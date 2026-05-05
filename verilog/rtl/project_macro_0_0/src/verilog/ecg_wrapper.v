//==============================================================================
//  Module      : ecg_wrapper
//  Description : Top-level wrapper for tiny_ecg_no_activ inference accelerator.
//
//  RX Packet (2 UART bytes, byte-0 first / LSB):
//    [15:10] = 6 bits for Control
//    [15] ---> soft reset
//    [14] ---> start
//    [13] ---> Mode (0 == UART INPUT , 1 == ADC INPUT, not implemented)
//    [12] ---> CSR select (0 = data, 1 = control)
//    [9:0]   = 10-bit input sample  (ap_fixed<10,5>, zero-padded to 16 bits)
//
//  TX Byte (1 UART byte):
//    [4:0]   = one-hot argmax class (class 0..4 from dense layer output)
//
//  AXI-S note:
//    The HLS core packs each ap_fixed<10,5> sample into a 16-bit slot [N*16+9:N*16].
//    Input:  1 sample  per beat → TDATA[15:0],  [9:0] used, [15:10] = 0
//    Output: 5 classes per beat → TDATA[79:0],  class N at [N*16+9:N*16]
//
//  Parameters:
//    BAUDIV — clock cycles per baud period.  100 MHz / 115200 ≈ 868.
//             Adjust for different system clocks or baud rates.
//==============================================================================

`default_nettype none

module ecg_wrapper #(
    parameter [31:0] BAUDIV = 32'd868   // 100 MHz / 115200 baud
) (
    input  wire clk,     // system clock (matches BAUDIV)
    input  wire arst_n,  // async reset, active low
    input  wire rx,      // UART RX pin (connect to host TX)
    output wire tx       // UART TX pin (connect to host RX)
);

    // -------------------------------------------------------------------------
    // UART RX → 16-bit AXI-S bridge
    // Assembles two consecutive UART bytes into one 16-bit beat.
    // -------------------------------------------------------------------------
    wire [15:0] brx_tdata;
    wire        brx_tvalid;
    wire        brx_tready;

    uart_rx_axis_bridge #(.BAUDIV(BAUDIV)) u_rx_bridge (
        .clk     (clk),
        .arst_n  (arst_n),
        .rx      (rx),
        .m_tdata (brx_tdata),
        .m_tvalid(brx_tvalid),
        .m_tready(brx_tready)
    );
    localparam ADC_MODE = 1'b1;
    // -------------------------------------------------------------------------
    // 8-bit AXI-S → UART TX bridge
    // Serialises one byte per AXI-S beat.
    // -------------------------------------------------------------------------
    reg  [7:0] btx_tdata;
    reg        btx_tvalid;
    wire       btx_tready;

    axis_uart_tx_bridge #(.BAUDIV(BAUDIV)) u_tx_bridge (
        .clk     (clk),
        .arst_n  (arst_n),
        .s_tdata (btx_tdata),
        .s_tvalid(btx_tvalid),
        .s_tready(btx_tready),
        .tx      (tx)
    );

    // -------------------------------------------------------------------------
    // ECG accelerator AXI-S signals
    //
    // RX packet decode (combinational): bits [9:0] of the 16-bit bridge word
    // carry the 10-bit input sample; upper 6 bits are zero-padded.
    // Flow control passes straight through: the bridge holds TVALID/TDATA
    // until in_tready is asserted by the HLS core.
    // -------------------------------------------------------------------------
    reg [15:0] in_tdata;
    reg        in_tvalid;
    reg        in_tready;
    assign brx_tready = brx_tdata[12] ? 1'b1 : in_tready;

    wire [79:0] out_tdata;
    wire        out_tvalid;
    wire        out_tready;

    wire       engine_soft_reset /* verilator public_flat */;
    wire       engine_start      /* verilator public_flat */;
    wire       engine_mode       /* verilator public_flat */;
    reg  [2:0] ctrl_reg;

    // Control register write selector: bit[12]==1 means this word updates control bits [15:13].
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            ctrl_reg <= 3'b000;
        end else if (brx_tvalid && brx_tready && brx_tdata[12]) begin
            ctrl_reg <= brx_tdata[15:13];
        end
    end

    assign engine_soft_reset = ctrl_reg[2];   // saved from bit[15]
    assign engine_start      = ctrl_reg[1];   // saved from bit[14]
    assign engine_mode       = ctrl_reg[0];   // saved from bit[13]

    // -------------------------------------------------------------------------
    // ECG accelerator
    // -------------------------------------------------------------------------
    wire ap_done_w, ap_ready_w, ap_idle_w;
    always @(*) begin
        if (engine_mode == ADC_MODE) begin
            in_tdata  = 16'h0;    // ADC mode not implemented, tie off input
            in_tvalid = 1'b0;    // No valid input data in ADC mode

        end else begin
            in_tdata  = {6'b0, brx_tdata[9:0]};  // UART mode: input sample from RX bridge
            in_tvalid = brx_tvalid & !engine_soft_reset & !brx_tdata[12]; // Ignore control-register writes on data path
        end
    end
    tiny_ecg_no_activ u_ecg (
        .ap_clk              (clk),
        .ap_rst_n            (!engine_soft_reset & arst_n),                //sync reset inside HLS core, not exposed to wrapper
        .ap_start            (engine_start),                           //start signal from UART bridge, not exposed to wrapper
        .ap_done             (ap_done_w),
        .ap_ready            (ap_ready_w),
        .ap_idle             (ap_idle_w),
        .input_layer_3_TDATA (in_tdata),
        .input_layer_3_TVALID(in_tvalid),
        .input_layer_3_TREADY(in_tready),
        .layer11_out_TDATA   (out_tdata),
        .layer11_out_TVALID  (out_tvalid),
        .layer11_out_TREADY  (out_tready)
    );

    // -------------------------------------------------------------------------
    // Argmax over 5 signed ap_fixed<10,5> output scores → one-hot 5-bit
    //   Score N lives in out_tdata[N*16 +: 10] (bits [9:0] of each 16-bit slot)
    // Argmax candidate is computed from cap_data and consumed in TS_LATCH.
    // -------------------------------------------------------------------------
    reg [79:0] cap_data;     // latched at AXI-S handshake
    reg [2:0]  cap_status;   // {ap_idle, ap_ready, ap_done} at handshake

    reg  [4:0] argmax_oh_c;
    reg  [2:0] win_idx;
    reg signed [9:0] win_val;
    reg        out_hs_d;
    integer k;

    always @(*) begin
        win_val   = $signed(cap_data[9:0]);
        win_idx   = 3'd0;
        for (k = 1; k < 5; k = k + 1) begin
            if ($signed(cap_data[k*16 +: 10]) > win_val) begin
                win_val = $signed(cap_data[k*16 +: 10]);
                win_idx = k[2:0];
            end
        end
        argmax_oh_c = 5'b00001 << win_idx;   // one-hot, classes 0..4
    end

    // Only accept a new engine output when the UART side has no pending byte.
    assign out_tready = ~btx_tvalid;

    //  1) On engine handshake, capture output/status and raise delayed pulse.
    //  2) One cycle later, present argmax-packed byte to UART bridge.
    //  3) Hold TVALID until UART bridge asserts TREADY.
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            cap_data   <= 80'h0;
            cap_status <= 3'b000;
            out_hs_d   <= 1'b0;
            btx_tdata  <= 8'hFF;
            btx_tvalid <= 1'b0;
        end else begin
            out_hs_d <= out_tvalid & out_tready;

            if (out_tvalid & out_tready) begin
                cap_data   <= out_tdata;
                //cap_status <= {ap_idle_w, ap_ready_w, ap_done_w};
            end

            if (out_hs_d) begin
                btx_tdata  <= {cap_status, argmax_oh_c};
                btx_tvalid <= 1'b1;
            end else if (btx_tvalid & btx_tready) begin
                btx_tvalid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
