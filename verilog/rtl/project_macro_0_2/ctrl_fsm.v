// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : ctrl_fsm
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module ctrl_fsm #(
    parameter FSM_CLK_FREQ        = 25_000_000,
    parameter FSM_WATCHDOG_CYCLES = 25_000_000
) (
    input  wire        clk,
    input  wire        rst_n,

    // from Command Decoder
    input  wire [1:0]  mode_cmd,
    input  wire        mode_cmd_valid,
    input  wire        lock_cmd,
    input  wire [15:0] pin_data,

    // from SRAM Controller
    input  wire        table_ready,

    // from UART transceiver
    input  wire        uart_activity,

    // mode output
    output reg  [1:0]  mode,

    // clock enables
    output wire        en_sliding_win,
    output wire        en_ac_engine,
    output wire        en_score_unit,
    output wire        en_output_reg,

    // SRAM & AC control
    output wire        sram_wr_allow,
    output wire        ac_reset_n,
    output reg         build_table,
    output wire        pipeline_en,

    // lock interface
    output reg         lock_granted,
    output wire        chip_locked,

    // watchdog & status
    output reg         watchdog_alert,
    output wire [1:0]  mode_out,
    output wire [7:0]  transition_log
);

    // Mode Encoding
    localparam [1:0] FSM_MODE_IDLE     = 2'b00;
    localparam [1:0] FSM_MODE_LEARN    = 2'b01;
    localparam [1:0] FSM_MODE_DETECT   = 2'b10;
    localparam [1:0] FSM_MODE_BUILDING = 2'b11; 

    // Lock Obfuscation
    localparam [15:0] PIN_XOR     = 16'hA5A5;
    localparam [15:0] PIN_DEFAULT = 16'hDEAD ^ 16'hA5A5;

    // Internal Registers
    reg [1:0]  mode_r;
    reg        locked_r;
    reg [15:0] stored_pin_r;
    reg        table_ready_r;
    reg [7:0]  transition_log_r;
    reg [25:0] watchdog_counter;
    reg [7:0]  wd_alert_timer;

    // Combinatorial Logic
    assign mode_out       = mode_r;
    assign transition_log = transition_log_r;
    assign chip_locked    = locked_r;

    assign en_sliding_win = (mode_r == FSM_MODE_DETECT);
    assign en_ac_engine   = (mode_r == FSM_MODE_DETECT) && table_ready_r;
    assign en_score_unit  = (mode_r == FSM_MODE_DETECT) && table_ready_r;
    assign en_output_reg  = 1'b1; 

    assign sram_wr_allow  = ((mode_r == FSM_MODE_LEARN) || (mode_r == FSM_MODE_BUILDING)) && !locked_r;
    assign ac_reset_n     = table_ready_r || (mode_r == FSM_MODE_BUILDING);
    assign pipeline_en    = (mode_r == FSM_MODE_DETECT) && table_ready_r;

    wire bld_done_cond = (mode_r == FSM_MODE_BUILDING) && table_ready;

    // Synchronous Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {mode_r, mode} <= 4'd0;
            locked_r       <= 1'b1;
            stored_pin_r   <= PIN_DEFAULT;
            table_ready_r  <= 1'b0;
            transition_log_r <= 8'd0;
            watchdog_counter <= FSM_WATCHDOG_CYCLES[25:0];
            watchdog_alert   <= 1'b0;
            wd_alert_timer   <= 8'd0;
            {build_table, lock_granted} <= 2'b00;
        end else begin
            {build_table, lock_granted} <= 2'b00;

            if (wd_alert_timer != 0) begin
                wd_alert_timer <= wd_alert_timer - 1'b1;
                if (wd_alert_timer == 1) watchdog_alert <= 1'b0;
            end

            if (lock_cmd) begin
                if (locked_r) begin
                    if ((pin_data ^ PIN_XOR) == stored_pin_r) begin
                        locked_r     <= 1'b0;
                        lock_granted <= 1'b1;
                    end
                end else begin
                    stored_pin_r <= pin_data ^ PIN_XOR;
                    lock_granted <= 1'b1;
                end
            end

            if (mode_cmd_valid) begin
                case (mode_cmd)
                    FSM_MODE_IDLE: begin
                        if (mode_r != FSM_MODE_IDLE) transition_log_r <= {transition_log_r[3:0], mode_r, FSM_MODE_IDLE};
                        mode_r <= FSM_MODE_IDLE;
                        mode   <= FSM_MODE_IDLE;
                    end
                    FSM_MODE_LEARN: begin
                        if (mode_r != FSM_MODE_LEARN) transition_log_r <= {transition_log_r[3:0], mode_r, FSM_MODE_LEARN};
                        mode_r <= FSM_MODE_LEARN;
                        mode   <= FSM_MODE_LEARN;
                        table_ready_r <= 1'b0;
                    end
                    FSM_MODE_DETECT: begin
                        if (mode_r == FSM_MODE_IDLE && table_ready_r) begin
                            transition_log_r <= {transition_log_r[3:0], mode_r, FSM_MODE_DETECT};
                            mode_r <= FSM_MODE_DETECT;
                            mode   <= FSM_MODE_DETECT;
                        end else if (mode_r == FSM_MODE_LEARN) begin
                            transition_log_r <= {transition_log_r[3:0], mode_r, FSM_MODE_DETECT};
                            mode_r      <= FSM_MODE_BUILDING;
                            build_table <= 1'b1;
                        end
                    end
                    default: mode_r <= mode_r; 
                endcase
            end else if (bld_done_cond) begin
                mode_r        <= FSM_MODE_DETECT;
                mode          <= FSM_MODE_DETECT;
                table_ready_r <= 1'b1;
            end else if (mode_r == FSM_MODE_DETECT) begin
                if (uart_activity) begin
                    watchdog_counter <= FSM_WATCHDOG_CYCLES[25:0];
                end else if (watchdog_counter == 0) begin
                    mode_r           <= FSM_MODE_IDLE;
                    mode             <= FSM_MODE_IDLE;
                    watchdog_alert   <= 1'b1;
                    wd_alert_timer   <= 8'd255;
                    transition_log_r <= {transition_log_r[3:0], mode_r, FSM_MODE_IDLE};
                    watchdog_counter <= FSM_WATCHDOG_CYCLES[25:0];
                end else begin
                    watchdog_counter <= watchdog_counter - 1'b1;
                end
            end else begin
                watchdog_counter <= FSM_WATCHDOG_CYCLES[25:0];
            end
        end
    end
endmodule
