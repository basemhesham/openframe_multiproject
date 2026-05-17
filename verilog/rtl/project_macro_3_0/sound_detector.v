// ============================================================
// Project      : AegisDSP - Mixed Signal Security ASIC
// Module       : sound_detector
// Author       : Haya Shalaby
// Date         : April 10th, 2026 — revised for I2C sensor input
//
// Description  : Adaptive threshold sound event detector.
//                Reads a 16-bit sound-level register from a
//                digital I2C microphone/acoustic sensor, then
//                applies the same adaptive EMA background
//                comparison as the original ADC-based version.
//
// Target sensor : Any I2C acoustic sensor that exposes a
//                 16-bit sound-level register, e.g.:
//                   - INMP441 breakout with I2C bridge
//                   - ICS-43434 with I2C interface board
//                   - Generic SPL (sound pressure level) sensor
//                   - IM69D130 with I2C configuration
//                 Default 7-bit I2C address : 0x4A (configurable)
//                 Default register address  : 0x00 (16-bit level)
//
// I2C protocol  : Standard mode 100 kHz or fast mode 400 kHz
//                 Transaction: START | ADDR+W | REG | RSTART
//                              | ADDR+R | DATA_H | DATA_L | STOP
//
// Clocking      : clk = 50 MHz system clock
//                 I2C SCL = clk / CLK_DIV
//                   CLK_DIV = 500 → SCL = 100 kHz (standard)
//                   CLK_DIV = 125 → SCL = 400 kHz (fast mode)
//
// Poll rate     : One I2C read every POLL_CYCLES clk cycles
//                   POLL_CYCLES = 50_000_000/8000 = 6250
//                   → 8 kHz effective sample rate, matching
//                     original ADC-based version exactly
//
// Frame/EMA     : Identical to original sound_detector:
//                   Frame size  = 256 samples (~32 ms)
//                   Background  = EMA with N=6 (alpha=1/64)
//                   Threshold   = 2x background energy
//
// Assumptions   : clk = 50 MHz
//                 Sensor level register = unsigned 16-bit,
//                 mid-scale silence = 32768 (same as ADC path)
//                 Active-low async reset
// ============================================================

module sound_detector #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter I2C_FREQ_HZ   = 100_000,          // 100 kHz standard mode
    parameter SENSOR_ADDR   = 7'h4A,            // 7-bit I2C device address
    parameter SENSOR_REG    = 8'h00,            // register to read (16-bit level)
    parameter POLL_RATE_HZ  = 8_000             // how often to poll sensor
) (
    input  wire        clk,          // 50 MHz system clock
    input  wire        rst_n,        // active-low async reset

    // I2C bus pins (connect to chip pads)
    output wire        scl_out,      // I2C clock  — open-drain, needs pull-up
    input  wire        scl_in,       // I2C clock  — read-back for clock stretch
    output wire        sda_out,      // I2C data   — open-drain, needs pull-up
    input  wire        sda_in,       // I2C data   — read-back for arbitration

    output reg         sound_flag,   // goes high when sound event detected
    output reg         i2c_error     // goes high if sensor NAKs or bus stuck
);

// ============================================================
// SECTION 1 — Derived parameters
// ============================================================
localparam CLK_DIV    = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4); // quarter-period ticks
localparam POLL_CYCLES = CLK_FREQ_HZ / POLL_RATE_HZ;      // clk cycles between polls

// ============================================================
// SECTION 2 — I2C bit-clock generator
// Divides clk into quarter-period ticks for SCL generation.
// Quarter periods allow precise SDA setup/hold timing:
//   tick 0: SCL low  first  half  — SDA changes here
//   tick 1: SCL low  second half  — SDA stable setup
//   tick 2: SCL high first  half  — SDA sampled here
//   tick 3: SCL high second half  — SDA hold
// ============================================================
reg [$clog2(CLK_DIV)-1:0] clk_cnt;
reg [1:0] tick;           // 0..3 quarter-period index
reg       tick_pulse;     // single-cycle strobe at each quarter period

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_cnt    <= 0;
        tick       <= 2'd0;
        tick_pulse <= 1'b0;
    end else begin
        tick_pulse <= 1'b0;
        if (clk_cnt >= CLK_DIV - 1) begin
            clk_cnt    <= 0;
            tick       <= tick + 1;
            tick_pulse <= 1'b1;
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end
end

// ============================================================
// SECTION 3 — I2C master FSM
//
// State machine handles:
//   IDLE       - wait for poll trigger
//   START      - generate START condition
//   ADDR_W     - send 7-bit address + W bit (register write phase)
//   SEND_REG   - send register address byte
//   RSTART     - generate repeated START
//   ADDR_R     - send 7-bit address + R bit
//   READ_HIGH  - read data byte high (MSB first)
//   READ_LOW   - read data byte low, send NAK to end transfer
//   STOP       - generate STOP condition
//   DONE       - latch result, return to IDLE
//   ERROR      - NAK received or bus error
// ============================================================
localparam ST_IDLE      = 4'd0;
localparam ST_START     = 4'd1;
localparam ST_ADDR_W    = 4'd2;
localparam ST_ACK_AW    = 4'd3;
localparam ST_SEND_REG  = 4'd4;
localparam ST_ACK_REG   = 4'd5;
localparam ST_RSTART    = 4'd6;
localparam ST_ADDR_R    = 4'd7;
localparam ST_ACK_AR    = 4'd8;
localparam ST_READ_H    = 4'd9;
localparam ST_ACK_H     = 4'd10;
localparam ST_READ_L    = 4'd11;
localparam ST_NAK_L     = 4'd12;
localparam ST_STOP      = 4'd13;
localparam ST_DONE      = 4'd14;
localparam ST_ERROR     = 4'd15;

reg [3:0]  i2c_state;
reg [2:0]  bit_idx;        // counts bits 7 downto 0 within each byte
reg [7:0]  shift_out;      // byte being transmitted
reg [7:0]  rx_high;        // received high byte
reg [7:0]  rx_low;         // received low byte
reg        scl_r;          // SCL register (open-drain: 0=drive low, 1=release)
reg        sda_r;          // SDA register (open-drain: 0=drive low, 1=release)
reg        result_valid;   // pulses high for one cycle when new reading is ready
reg [15:0] i2c_result;     // latched 16-bit sensor reading

// Open-drain outputs: only drive low, release high (pull-up handles it)
assign scl_out = scl_r;
assign sda_out = sda_r;

// Poll interval counter
reg [$clog2(POLL_CYCLES)-1:0] poll_cnt;
reg poll_trigger;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        poll_cnt     <= 0;
        poll_trigger <= 1'b0;
    end else begin
        poll_trigger <= 1'b0;
        if (poll_cnt >= POLL_CYCLES - 1) begin
            poll_cnt     <= 0;
            poll_trigger <= 1'b1;
        end else begin
            poll_cnt <= poll_cnt + 1;
        end
    end
end

// I2C state machine — advances on tick_pulse (quarter-period boundary)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i2c_state    <= ST_IDLE;
        scl_r        <= 1'b1;
        sda_r        <= 1'b1;
        bit_idx      <= 3'd7;
        shift_out    <= 8'd0;
        rx_high      <= 8'd0;
        rx_low       <= 8'd0;
        i2c_result   <= 16'd0;
        result_valid <= 1'b0;
        i2c_error    <= 1'b0;
    end else begin
        result_valid <= 1'b0;  // default clear

        if (tick_pulse) begin
            case (i2c_state)

                // ── IDLE: wait for poll trigger ──────────────────
                ST_IDLE: begin
                    scl_r <= 1'b1;
                    sda_r <= 1'b1;
                    i2c_error <= 1'b0;
                    if (poll_trigger) begin
                        i2c_state <= ST_START;
                    end
                end

                // ── START: SDA falls while SCL high ─────────────
                // Uses 4 ticks: release both, pull SDA low,
                // pull SCL low to begin first bit
                ST_START: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b1; sda_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; sda_r <= 1'b0; end // SDA falls
                        2'd2: begin scl_r <= 1'b0; sda_r <= 1'b0; end // SCL falls
                        2'd3: begin
                            // load ADDR + W (write = 0)
                            shift_out <= {SENSOR_ADDR, 1'b0};
                            bit_idx   <= 3'd7;
                            i2c_state <= ST_ADDR_W;
                        end
                    endcase
                end

                // ── ADDR_W: clock out 8 bits (7-bit addr + W) ───
                ST_ADDR_W: begin
                    case (tick)
                        2'd0: begin
                            sda_r <= shift_out[bit_idx];
                            scl_r <= 1'b0;
                        end
                        2'd1: begin scl_r <= 1'b0; end   // setup hold
                        2'd2: begin scl_r <= 1'b1; end   // SCL rises — sensor samples
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_idx == 3'd0) begin
                                sda_r     <= 1'b1;        // release SDA for ACK
                                i2c_state <= ST_ACK_AW;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                    endcase
                end

                // ── ACK_AW: sample ACK from sensor ──────────────
                ST_ACK_AW: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin
                            // sensor pulls SDA low for ACK
                            if (sda_in != 1'b0) begin
                                i2c_state <= ST_ERROR;
                            end
                        end
                        2'd3: begin
                            scl_r     <= 1'b0;
                            shift_out <= SENSOR_REG;
                            bit_idx   <= 3'd7;
                            i2c_state <= ST_SEND_REG;
                        end
                    endcase
                end

                // ── SEND_REG: send register address byte ────────
                ST_SEND_REG: begin
                    case (tick)
                        2'd0: begin
                            sda_r <= shift_out[bit_idx];
                            scl_r <= 1'b0;
                        end
                        2'd1: begin scl_r <= 1'b0; end
                        2'd2: begin scl_r <= 1'b1; end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_idx == 3'd0) begin
                                sda_r     <= 1'b1;
                                i2c_state <= ST_ACK_REG;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                    endcase
                end

                // ── ACK_REG: sample ACK after register byte ─────
                ST_ACK_REG: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin
                            if (sda_in != 1'b0)
                                i2c_state <= ST_ERROR;
                        end
                        2'd3: begin
                            scl_r     <= 1'b0;
                            i2c_state <= ST_RSTART;
                        end
                    endcase
                end

                // ── RSTART: repeated START before read phase ────
                ST_RSTART: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; sda_r <= 1'b1; end // SCL high
                        2'd2: begin scl_r <= 1'b1; sda_r <= 1'b0; end // SDA falls
                        2'd3: begin
                            scl_r     <= 1'b0;
                            shift_out <= {SENSOR_ADDR, 1'b1};         // ADDR + R
                            bit_idx   <= 3'd7;
                            i2c_state <= ST_ADDR_R;
                        end
                    endcase
                end

                // ── ADDR_R: clock out address + read bit ────────
                ST_ADDR_R: begin
                    case (tick)
                        2'd0: begin sda_r <= shift_out[bit_idx]; scl_r <= 1'b0; end
                        2'd1: begin scl_r <= 1'b0; end
                        2'd2: begin scl_r <= 1'b1; end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_idx == 3'd0) begin
                                sda_r     <= 1'b1;
                                i2c_state <= ST_ACK_AR;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                    endcase
                end

                // ── ACK_AR: sample ACK after read address ───────
                ST_ACK_AR: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin
                            if (sda_in != 1'b0)
                                i2c_state <= ST_ERROR;
                        end
                        2'd3: begin
                            scl_r     <= 1'b0;
                            bit_idx   <= 3'd7;
                            rx_high   <= 8'd0;
                            i2c_state <= ST_READ_H;
                        end
                    endcase
                end

                // ── READ_H: receive high byte MSB first ─────────
                ST_READ_H: begin
                    case (tick)
                        2'd0: begin sda_r <= 1'b1; scl_r <= 1'b0; end // release SDA
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin
                            // sample SDA on SCL high
                            rx_high[bit_idx] <= sda_in;
                        end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_idx == 3'd0) begin
                                i2c_state <= ST_ACK_H;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                    endcase
                end

                // ── ACK_H: send ACK after high byte (continue) ──
                ST_ACK_H: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b0; end // master ACK
                        2'd1: begin scl_r <= 1'b0; end
                        2'd2: begin scl_r <= 1'b1; end
                        2'd3: begin
                            scl_r     <= 1'b0;
                            sda_r     <= 1'b1;
                            bit_idx   <= 3'd7;
                            rx_low    <= 8'd0;
                            i2c_state <= ST_READ_L;
                        end
                    endcase
                end

                // ── READ_L: receive low byte MSB first ──────────
                ST_READ_L: begin
                    case (tick)
                        2'd0: begin sda_r <= 1'b1; scl_r <= 1'b0; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin
                            rx_low[bit_idx] <= sda_in;
                        end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_idx == 3'd0) begin
                                i2c_state <= ST_NAK_L;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                    endcase
                end

                // ── NAK_L: send NAK after low byte (end read) ───
                ST_NAK_L: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end // master NAK
                        2'd1: begin scl_r <= 1'b0; end
                        2'd2: begin scl_r <= 1'b1; end
                        2'd3: begin
                            scl_r     <= 1'b0;
                            i2c_state <= ST_STOP;
                        end
                    endcase
                end

                // ── STOP: SDA rises while SCL high ──────────────
                ST_STOP: begin
                    case (tick)
                        2'd0: begin scl_r <= 1'b0; sda_r <= 1'b0; end
                        2'd1: begin scl_r <= 1'b1; sda_r <= 1'b0; end // SCL rises
                        2'd2: begin scl_r <= 1'b1; sda_r <= 1'b1; end // SDA rises
                        2'd3: begin
                            i2c_state <= ST_DONE;
                        end
                    endcase
                end

                // ── DONE: latch result, return to IDLE ──────────
                ST_DONE: begin
                    i2c_result   <= {rx_high, rx_low};
                    result_valid <= 1'b1;
                    i2c_state    <= ST_IDLE;
                end

                // ── ERROR: NAK or bus fault — release bus ───────
                ST_ERROR: begin
                    scl_r     <= 1'b1;
                    sda_r     <= 1'b1;
                    i2c_error <= 1'b1;
                    i2c_state <= ST_IDLE;
                end

                default: i2c_state <= ST_IDLE;

            endcase
        end // tick_pulse
    end
end

// ============================================================
// SECTION 4 — Adaptive EMA sound detection
// Identical algorithm to original sound_detector:
//   Frame size  = 256 samples
//   Background  = EMA alpha = 1 - 1/64
//   Threshold   = 2x background energy
//   DC removal  = subtract 32768 (sensor mid-scale = silence)
//
// result_valid pulses once per I2C read (8 kHz poll rate)
// ============================================================
reg signed [39:0] frame_energy;
reg signed [47:0] background;
reg [7:0]         sample_count;
reg signed [39:0] current_energy;
reg               frame_ready;

// Signed DC-removed sample: sensor mid-scale 32768 = silence
wire signed [15:0] sample_dc =
    $signed({1'b0, i2c_result}) - $signed(17'd32768);

// Squared energy contribution (always positive)
wire signed [31:0] sample_sq = sample_dc * sample_dc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_energy   <= 40'd0;
        sample_count   <= 8'd0;
        current_energy <= 40'd0;
        frame_ready    <= 1'b0;
    end else begin
        frame_ready <= 1'b0;

        if (result_valid) begin
            if (sample_count == 8'd255) begin
                current_energy <= frame_energy + sample_sq;
                frame_energy   <= 40'd0;
                sample_count   <= 8'd0;
                frame_ready    <= 1'b1;
            end else begin
                frame_energy <= frame_energy + sample_sq;
                sample_count <= sample_count + 1;
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        background <= 48'd0;
        sound_flag <= 1'b0;
    end else begin
        if (frame_ready) begin
            if ($signed(current_energy) > ($signed(background) << 1))
                sound_flag <= 1'b1;
            else
                sound_flag <= 1'b0;

            // EMA background update: bg += (current - bg) >> 6
            background <= $signed(background) +
                         (($signed(current_energy) -
                           $signed(background)) >>> 6);
        end
    end
end

endmodule
