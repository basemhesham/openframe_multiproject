// i2c_master_seq.v — corrected to match exact alexforencich i2c_master.v ports
// s_axis = data INTO the master (write to slave)
// m_axis = data OUT of the master (read from slave)

`default_nettype none
`timescale 1ns/1ps
module i2c_master_seq #(
    parameter CLK_FREQ      = 50_000_000,
    parameter I2C_FREQ      = 400_000,
    parameter SENSOR_ADDR   = 7'h48,
    parameter ACTUATOR_ADDR = 7'h40
)(
    input  wire        clk,
    input  wire        rst,

    // I2C bus pads
    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_t,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_t,

    // To data_proc_fsm
    output reg  [15:0] sensor_data,
    output reg         sensor_valid,

    // From data_proc_fsm
    input  wire [7:0]  actuator_cmd,
    input  wire        actuator_valid
);

    // prescale is a RUNTIME PORT on this core, not a parameter
    localparam [15:0] PRESCALE = CLK_FREQ / (I2C_FREQ * 4);

    // ── Command channel ───────────────────────────────────────────────────
    reg  [6:0]  s_axis_cmd_address;
    reg         s_axis_cmd_start;
    reg         s_axis_cmd_read;
    reg         s_axis_cmd_write;
    reg         s_axis_cmd_write_multiple;
    reg         s_axis_cmd_stop;
    reg         s_axis_cmd_valid;
    wire        s_axis_cmd_ready;

    // ── Write data channel: our logic → i2c master → slave device ────────
    reg  [7:0]  s_axis_data_tdata;
    reg         s_axis_data_tvalid;
    reg         s_axis_data_tlast;
    wire        s_axis_data_tready;

    // ── Read data channel: slave device → i2c master → our logic ─────────
    wire [7:0]  m_axis_data_tdata;
    wire        m_axis_data_tvalid;
    wire        m_axis_data_tlast;
    reg         m_axis_data_tready;

    // ── Instantiate alexforencich i2c_master ──────────────────────────────
    i2c_master #(
        .DEFAULT_PRESCALE(PRESCALE),
        .FIXED_PRESCALE(1),
        .CMD_FIFO(0),
        .WRITE_FIFO(0),
        .READ_FIFO(0)
    ) u_master (
        .clk(clk),
        .rst(rst),

        // I2C pads
        .scl_i(scl_i), .scl_o(scl_o), .scl_t(scl_t),
        .sda_i(sda_i), .sda_o(sda_o), .sda_t(sda_t),

        // Command channel
        .s_axis_cmd_address(s_axis_cmd_address),
        .s_axis_cmd_start(s_axis_cmd_start),
        .s_axis_cmd_read(s_axis_cmd_read),
        .s_axis_cmd_write(s_axis_cmd_write),
        .s_axis_cmd_write_multiple(s_axis_cmd_write_multiple),
        .s_axis_cmd_stop(s_axis_cmd_stop),
        .s_axis_cmd_valid(s_axis_cmd_valid),
        .s_axis_cmd_ready(s_axis_cmd_ready),

        // Write data (our FSM → slave device)
        .s_axis_data_tdata(s_axis_data_tdata),
        .s_axis_data_tvalid(s_axis_data_tvalid),
        .s_axis_data_tready(s_axis_data_tready),
        .s_axis_data_tlast(s_axis_data_tlast),

        // Read data (slave device → our FSM)
        .m_axis_data_tdata(m_axis_data_tdata),
        .m_axis_data_tvalid(m_axis_data_tvalid),
        .m_axis_data_tready(m_axis_data_tready),
        .m_axis_data_tlast(m_axis_data_tlast),

        // Runtime prescale — driven from our localparam
        .prescale(PRESCALE),
        .stop_on_idle(1'b1),

        // Unused status — leave open
        .busy(),
        .bus_control(),
        .bus_active(),
        .missed_ack()
    );

    // ── Sequencer FSM ─────────────────────────────────────────────────────
    localparam S_IDLE     = 4'd0,
               S_SENS_CMD = 4'd1,
               S_SENS_RD0 = 4'd2,
               S_SENS_RD1 = 4'd3,
               S_ACT_CMD  = 4'd4,
               S_ACT_WR   = 4'd5,
               S_WAIT     = 4'd6;

    reg [3:0]  state;
    reg [7:0]  rx_hi;
    reg [23:0] wait_cnt;
    localparam [23:0] WAIT_CYCLES = CLK_FREQ / 100; // 10 ms

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                     <= S_IDLE;
            sensor_valid              <= 1'b0;
            sensor_data               <= 16'h0;
            s_axis_cmd_valid          <= 1'b0;
            s_axis_cmd_address        <= 7'h0;
            s_axis_cmd_start          <= 1'b0;
            s_axis_cmd_read           <= 1'b0;
            s_axis_cmd_write          <= 1'b0;
            s_axis_cmd_write_multiple <= 1'b0;
            s_axis_cmd_stop           <= 1'b0;
            s_axis_data_tvalid        <= 1'b0;
            s_axis_data_tdata         <= 8'h0;
            s_axis_data_tlast         <= 1'b0;
            m_axis_data_tready        <= 1'b1;
            wait_cnt                  <= 24'h0;
            rx_hi                     <= 8'h0;
        end else begin
            sensor_valid <= 1'b0;

            case (state)
                // ── 10 ms inter-transaction gap ──────────────────────────
                S_IDLE: begin
                    if (wait_cnt < WAIT_CYCLES)
                        wait_cnt <= wait_cnt + 24'd1;
                    else begin
                        wait_cnt <= 24'h0;
                        state    <= S_SENS_CMD;
                    end
                end

                // ── Issue READ to temperature sensor ─────────────────────
                S_SENS_CMD: begin
                    s_axis_cmd_address        <= SENSOR_ADDR;
                    s_axis_cmd_start          <= 1'b1;
                    s_axis_cmd_read           <= 1'b1;
                    s_axis_cmd_write          <= 1'b0;
                    s_axis_cmd_write_multiple <= 1'b0;
                    s_axis_cmd_stop           <= 1'b1;
                    s_axis_cmd_valid          <= 1'b1;
                    m_axis_data_tready        <= 1'b1;
                    if (s_axis_cmd_ready) begin
                        s_axis_cmd_valid <= 1'b0;
                        state            <= S_SENS_RD0;
                    end
                end

                // ── Capture MSB of sensor reading ─────────────────────────
                S_SENS_RD0: begin
                    if (m_axis_data_tvalid) begin
                        rx_hi <= m_axis_data_tdata;
                        state <= S_SENS_RD1;
                    end
                end

                // ── Capture LSB, assert sensor_valid ─────────────────────
                S_SENS_RD1: begin
                    if (m_axis_data_tvalid && m_axis_data_tlast) begin
                        sensor_data  <= {rx_hi, m_axis_data_tdata};
                        sensor_valid <= 1'b1;
                        state        <= actuator_valid ? S_ACT_CMD : S_WAIT;
                    end
                end

                // ── Issue WRITE to actuator ───────────────────────────────
                S_ACT_CMD: begin
                    s_axis_cmd_address        <= ACTUATOR_ADDR;
                    s_axis_cmd_start          <= 1'b1;
                    s_axis_cmd_write          <= 1'b1;
                    s_axis_cmd_read           <= 1'b0;
                    s_axis_cmd_write_multiple <= 1'b0;
                    s_axis_cmd_stop           <= 1'b1;
                    s_axis_cmd_valid          <= 1'b1;
                    if (s_axis_cmd_ready) begin
                        s_axis_cmd_valid <= 1'b0;
                        state            <= S_ACT_WR;
                    end
                end

                // ── Send actuator command byte ────────────────────────────
                S_ACT_WR: begin
                    s_axis_data_tdata  <= actuator_cmd;
                    s_axis_data_tvalid <= 1'b1;
                    s_axis_data_tlast  <= 1'b1;
                    if (s_axis_data_tready) begin
                        s_axis_data_tvalid <= 1'b0;
                        s_axis_data_tlast  <= 1'b0;
                        state              <= S_WAIT;
                    end
                end

                S_WAIT: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
