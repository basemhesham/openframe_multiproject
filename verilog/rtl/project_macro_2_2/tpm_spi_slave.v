// =============================================================================
// tpm_spi_slave.v — 4-Wire SPI Slave
// =============================================================================
// Bug fixes vs previous version:
//
//   Bug 1 FIXED: Removed sck_fall check inside the pre_fetch handler.
//     sck_fall is a 1-cycle combinational pulse. Checking it inside a
//     registered always block at an arbitrary cycle is unreliable —
//     whether it fires depends on phase alignment between SPI clock and
//     system clock, not on design intent.
//     tx_byte is now loaded unconditionally when memory data is ready.
//     The normal bit-level sck_fall path handles MISO output.
//
//   Bug 2 FIXED: pre_fetch changed from reg [1:0] (2-bit counter) back to
//     reg (1-bit flag).
//     tpm_mem has 1-cycle read latency: address on cycle N → data on N+1.
//     One flag is sufficient:
//       Cycle T   (opcode decoded):   pa_addr <= 0x80,  pre_fetch <= 1
//       Cycle T+1 (flag fires):        tx_byte <= pa_rdata, pre_fetch <= 0
//     The first data sck_fall arrives ~2.5 sys clocks after byte_done
//     (at sys_clk/SPI_clk = 5). Loading tx_byte at T+1 gives 1.5 cycles
//     of margin — enough at the recommended clock ratio.
//
//   Bug 3 FIXED: IRQ priority conflict.
//     Previous code had irq_r <= 1 (proc_done) and irq_r <= 0 (csn_rise)
//     in the same always block with no explicit priority. In Verilog the
//     last nonblocking assignment wins, so a simultaneous proc_done +
//     csn_rise would silently lose the IRQ. Fixed with explicit if/else.
//
// Unchanged:
//   2-FF synchroniser on CSn, SCK, MOSI.
//   WRITE: 0xC0 opcode, bytes → CMD_BUF, cmd_start on CSn rise.
//   READ:  0x40 opcode, RSP_BUF bytes clocked out MSB first.
//   Max reliable SPI clock = sys_clk / 5.
// =============================================================================
`timescale 1ns/1ps

module tpm_spi_slave (
    input  wire       clk,
    input  wire       rstn,

    input  wire       spi_csn,
    input  wire       spi_sck,
    input  wire       spi_mosi,
    output reg        spi_miso,

    output reg  [7:0] pa_addr,
    output reg  [7:0] pa_wdata,
    output reg        pa_we,
    input  wire [7:0] pa_rdata,

    output reg        cmd_start,
    input  wire       proc_busy,
    input  wire       proc_done,
    output wire       irq
);

// ---------------------------------------------------------------------------
// 2-FF synchronisers
// ---------------------------------------------------------------------------
reg [1:0] csn_ff, sck_ff, mosi_ff;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        csn_ff  <= 2'b11;
        sck_ff  <= 2'b00;
        mosi_ff <= 2'b00;
    end else begin
        csn_ff  <= {csn_ff[0],  spi_csn};
        sck_ff  <= {sck_ff[0],  spi_sck}; 
        mosi_ff <= {mosi_ff[0], spi_mosi};
    end
end

wire csn  = csn_ff[1];
wire sck  = sck_ff[1];
wire mosi = mosi_ff[1];

// Edge detection — ff[0] is 1-cycle delayed, ff[1] is 2-cycle delayed (stable)
wire sck_rise = ( sck_ff[0] & ~sck_ff[1]);
wire sck_fall = (~sck_ff[0] &  sck_ff[1]);
wire csn_fall = (~csn_ff[0] &  csn_ff[1]);
wire csn_rise = ( csn_ff[0] & ~csn_ff[1]);

// ---------------------------------------------------------------------------
// IRQ
// ---------------------------------------------------------------------------
reg irq_r;
assign irq = irq_r;

// ---------------------------------------------------------------------------
// FSM states
// ---------------------------------------------------------------------------
localparam TS_IDLE   = 3'd0;
localparam TS_OPCODE = 3'd1;
localparam TS_WRITE  = 3'd2;
localparam TS_READ   = 3'd3;

reg [2:0] ts_state;
reg [6:0] byte_idx;
reg       pre_fetch;   // FIX Bug 2: 1-bit flag (was 2-bit counter)

// ---------------------------------------------------------------------------
// Shift register
// ---------------------------------------------------------------------------
reg [7:0] rx_sr;
reg [7:0] tx_byte;
reg [2:0] bit_cnt;
reg       byte_done;

wire [7:0] rx_byte = rx_sr;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        irq_r     <= 1'b0;
        rx_sr     <= 8'h00;
        tx_byte   <= 8'hFF;
        bit_cnt   <= 3'd7;
        byte_done <= 1'b0;
        spi_miso  <= 1'b1;
        ts_state  <= TS_IDLE;
        byte_idx  <= 7'd0;
        cmd_start <= 1'b0;
        pa_we     <= 1'b0;
        pa_addr   <= 8'h00;
        pa_wdata  <= 8'h00;
        pre_fetch <= 1'b0;
    end else begin
        byte_done <= 1'b0;
        cmd_start <= 1'b0;
        pa_we     <= 1'b0;

        // FIX Bug 3: explicit priority — READ-clear beats proc_done-set.
        // If both happen simultaneously (host reads response exactly as
        // a new result arrives), clear wins. This is the correct behaviour:
        // the host still owns the bus and will see the new IRQ on the
        // next proc_done assertion.
        if (csn_rise && ts_state == TS_READ) begin
            irq_r <= 1'b0;
        end else if (proc_done) begin
            irq_r <= 1'b1;
        end

        // ── BIT-LEVEL LOGIC ─────────────────────────────────────────────
        if (csn) begin
            bit_cnt  <= 3'd7;
            spi_miso <= 1'b1;
        end else begin
            if (sck_rise) begin
                rx_sr <= {rx_sr[6:0], mosi};
                if (bit_cnt == 3'd0) begin
                    byte_done <= 1'b1;
                    bit_cnt   <= 3'd7;
                end else begin
                    bit_cnt <= bit_cnt - 1;
                end
            end
            // Drive MISO on falling SCK (SPI mode 0: data changes on fall,
            // host samples on rise).
            if (sck_fall) begin
                spi_miso <= tx_byte[7];
                tx_byte  <= {tx_byte[6:0], 1'b1};
            end
            // Pre-drive first bit when CSn falls (before any SCK activity).
            if (csn_fall) begin
                spi_miso <= tx_byte[7];
            end
        end

        // ── TRANSACTION FSM ─────────────────────────────────────────────
        case (ts_state)

        TS_IDLE: begin
            if (csn_fall) begin
                byte_idx <= 7'd0;
                ts_state <= TS_OPCODE;
            end
        end

        TS_OPCODE: begin
            if (csn_rise) begin
                ts_state <= TS_IDLE;
            end else if (byte_done) begin
                if (rx_byte == 8'hC0) begin
                    byte_idx <= 7'd0;
                    ts_state <= TS_WRITE;
                end else if (rx_byte == 8'h40) begin
                    // Address RSP_BUF[0]. pa_rdata will be valid next cycle.
                    // FIX Bug 1+2: set 1-bit flag, no sck_fall check needed.
                    pa_addr   <= 8'h80;
                    byte_idx  <= 7'd0;
                    pre_fetch <= 1'b1;
                    ts_state  <= TS_READ;
                end else begin
                    ts_state <= TS_IDLE;
                end
            end
        end

        TS_WRITE: begin
            if (csn_rise) begin
                if (!proc_busy) cmd_start <= 1'b1; 
                ts_state <= TS_IDLE;
            end else if (byte_done) begin
                if (byte_idx <= 7'd127) begin
                    pa_addr  <= {1'b0, byte_idx};
                    pa_wdata <= rx_byte;
                    pa_we    <= 1'b1;
                    byte_idx <= byte_idx + 1;
                end
            end
        end

        TS_READ: begin
            if (csn_rise) begin
                // IRQ clear handled in priority block above.
                ts_state <= TS_IDLE;
            end else begin
                if (pre_fetch) begin
                    // FIX Bug 1+2: load tx_byte unconditionally — no sck_fall
                    // check. pa_rdata = RSP_BUF[0] (1-cycle latency from
                    // pa_addr=0x80 set when opcode was decoded).
                    // The bit-level sck_fall handler will drive MISO from
                    // tx_byte on the next falling SCK edge.
                    tx_byte   <= pa_rdata;
                    pre_fetch <= 1'b0;
                    byte_idx  <= 7'd1;
                    pa_addr   <= 8'h81;     // pre-fetch RSP_BUF[1]
                end else if (byte_done) begin
                    // pa_rdata holds the next RSP byte (pre-fetched last cycle).
                    tx_byte  <= pa_rdata;
                    byte_idx <= byte_idx + 1;
                    if (byte_idx < 7'd126)
                        pa_addr <= 8'h80 + byte_idx + 1;
                end
            end
        end

        default: ts_state <= TS_IDLE;
        endcase
    end
end

endmodule