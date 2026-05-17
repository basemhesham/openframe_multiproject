//==============================================================================
//  Module      : ecg_wrapper
//  Description : Top-level wrapper for tiny_ecg_no_activ inference accelerator.
//
//  RX Packet (2 UART bytes, byte-0 first / LSB):
//    [15:12] = 4 bits for Control
//    [15]    ---> CSR Address Space Select (0 = data, 1 = control)
//    [14:12] ---> Register Address 
//    [11:0]  ---> CSR Data OR Input sample (ap_fixed<10,5>, zero-padded to 12 bits)
//
//  TX Byte (1 UART byte):
//    [4:0]   = one-hot argmax class (class 0..4 from dense layer output)
//
//  Register Map:
//    0xxx = Data Register
//    1000 = CSR Register [Soft Reset, Start, Mode]
//    1001 = Slope Threshold Register
//    1010 = RS Threshold Register
//    1011 = Max Window Threshold Register
//    1100 = Tolerance Threshold Register
//    1101 = Floor Offset Register
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
`define ASIC
module ecg_wrapper #(
    parameter [31:0] BAUDIV = 32'd35, // 4 MHz / 115200 baud
    parameter DATA_W = 8
) (
    input  wire clk,     // system clock (matches BAUDIV)
    input  wire arst_n,  // async reset, active low
    (* mark_debug = "true", keep = "true" *)    input  wire rx,      // UART RX pin (connect to host TX)
    (* mark_debug = "true", keep = "true" *)    output wire tx,       // UART TX pin (connect to host RX)
    (* mark_debug = "true", keep = "true" *)    input   wire          adc_valid,
    (* mark_debug = "true", keep = "true" *)    input   wire [7:0]    adc_data,
    output  wire          adc_ready
);

    assign adc_ready = 1'b1;  // always ready; ADC has no backpressure
    // -------------------------------------------------------------------------
    // UART RX → 16-bit AXI-S bridge
    // Assembles two consecutive UART bytes into one 16-bit beat.
    // -------------------------------------------------------------------------
    (* mark_debug = "true", keep = "true" *) wire [15:0] brx_tdata;
    (* mark_debug = "true", keep = "true" *) wire        brx_tvalid;
    (* mark_debug = "true", keep = "true" *) wire        brx_tready;

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
    (* mark_debug = "true", keep = "true" *) reg  [7:0] btx_tdata;
    (* mark_debug = "true", keep = "true" *) reg        btx_tvalid;
    (* mark_debug = "true", keep = "true" *) wire       btx_tready;

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
    (* mark_debug = "true", keep = "true" *) reg [15:0] in_tdata;
    (* mark_debug = "true", keep = "true" *) reg         in_tvalid;
    (* mark_debug = "true", keep = "true" *) wire        in_tready;
    assign brx_tready = brx_tdata[15] ? 1'b1 : in_tready;

    (* mark_debug = "true", keep = "true" *) wire [79:0] out_tdata;
    (* mark_debug = "true", keep = "true" *) wire        out_tvalid;
    (* mark_debug = "true", keep = "true" *) wire        out_tready;

    (* mark_debug = "true", keep = "true" *) wire       engine_soft_reset /* verilator public_flat */;
    (* mark_debug = "true", keep = "true" *) wire       engine_start      /* verilator public_flat */;
    (* mark_debug = "true", keep = "true" *) wire       engine_mode       /* verilator public_flat */;

    wire        clear;
    wire [4:0]  sample_out;
    wire        sample_valid;

    (* mark_debug = "true", keep = "true" *) reg  [11:0] csr_regs [0:5];
    integer i;

    // Control register write selector: bit[15]==1 means this word updates control bits [15:13].
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            for (i = 0; i < 6; i = i + 1) begin
                csr_regs[i] <= 12'b0; // Add Default Values
            end
        end else if (brx_tvalid && brx_tready && brx_tdata[15]) begin
            csr_regs[brx_tdata[14:12]] <= brx_tdata[11:0];
        end
    end

    assign engine_soft_reset = csr_regs[0][2];
    assign engine_start      = csr_regs[0][1];
    assign engine_mode       = csr_regs[0][0];

    // -------------------------------------------------------------------------
    // ADC Wrapper
    // -------------------------------------------------------------------------
    ADC_Big_Wrap # (
        .DATA_W(DATA_W)
    )
    ADC_Big_Wrap_inst (
        .clk(clk),
        .rst_n(arst_n),

        .slope_thresh(csr_regs[1][DATA_W-1 : 0]),
        .rs_window(csr_regs[2][DATA_W-1 : 0]),
        .max_window(csr_regs[3][DATA_W-1 : 0]),
        .tolerance(csr_regs[4][DATA_W-1 : 0]),
        .floor_offset(csr_regs[5][DATA_W-1 : 0]),
        .command_ready(1'b1),        
        
        // ADC I/O
        .adc_valid(adc_valid),
        .adc_in_data(adc_data),

        // Engine Outputs
        .clear(clear),
        .sample_out(sample_out),
        .sample_valid(sample_valid)


    );

    // -------------------------------------------------------------------------
    // ECG accelerator
    // -------------------------------------------------------------------------
    wire ap_done_w, ap_ready_w, ap_idle_w;
    always @(*) begin
        if (engine_mode == ADC_MODE) begin
            in_tdata  = {11'b0, sample_out};    // ADC mode: Input sample from ECG Sensor
            in_tvalid = sample_valid;                   // ADC mode: Input Valid

        end else begin
            in_tdata  = {6'b0, brx_tdata[9:0]};  // UART mode: input sample from RX bridge
            in_tvalid = brx_tvalid & !engine_soft_reset & !brx_tdata[15]; // Ignore control-register writes on data path
        end
    end
    
    tiny_ecg_no_activ u_ecg (
        .ap_clk              (clk),
        .ap_rst_n            (arst_n & !engine_soft_reset & !clear),   //sync reset inside HLS core, not exposed to wrapper
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

    (* mark_debug = "true", keep = "true" *) reg  [4:0] argmax_oh_c;
    (* mark_debug = "true", keep = "true" *) reg  [2:0] win_idx;
    (* mark_debug = "true", keep = "true" *) reg signed [9:0] win_val;
    (* mark_debug = "true", keep = "true" *) reg        out_hs_d;
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
