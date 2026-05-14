// =============================================================================
// tpm_top.v — Micro-TPM Top Level (Open-Frame Tapeout)
// =============================================================================
// This is a standalone chip. There is NO embedded CPU, NO Wishbone bus,
// NO Caravel harness. The only interface to the outside world is SPI.
//
// External pins:
//   clk       — system clock (e.g. from crystal oscillator on PCB)
//   rstn      — active-low reset
//   spi_csn   — SPI chip-select, active-low
//   spi_sck   — SPI clock (mode 0)
//   spi_mosi  — host to chip data
//   spi_miso  — chip to host data
//   irq       — interrupt: goes high when response is ready
//
// Internal data path:
//   spi_csn/sck/mosi/miso → tpm_spi_slave ─┐
//                                           │ byte stream
//                                      tpm_mem (256B)
//                                           │ byte access
//                                      tpm_cmd_proc (main FSM)
//                                        ├─ tpm_sha256_wrap → sha256_core
//                                        ├─ tpm_trng
//                                        └─ tpm_pcr_bank
//
// The SPI slave and command processor share tpm_mem through two independent
// byte-wide ports. Phase separation is guaranteed by the protocol:
//   • SPI slave writes CMD_BUF while proc is idle
//   • proc_busy=1 → SPI slave cannot trigger a new cmd_start
//   • SPI slave reads RSP_BUF only after IRQ is asserted (proc done)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tpm_top (
    input  wire clk,
    input  wire rstn,

    // SPI interface (5 GPIO pins total)
    input  wire spi_csn,
    input  wire spi_sck,
    input  wire spi_mosi,
    output wire spi_miso,
    output wire irq
);

// ─────────────────────────────────────────────────────────────────────────────
// Internal wires
// ─────────────────────────────────────────────────────────────────────────────

// SPI slave ↔ memory (port A)
wire [7:0] pa_addr, pa_wdata, pa_rdata;
wire       pa_we;

// Command processor ↔ memory (port B)
wire [7:0] pb_addr, pb_wdata, pb_rdata;
wire       pb_we;

// Control: SPI slave ↔ command processor
wire       cmd_start;
wire       proc_busy, proc_done, proc_err;

// SHA-256 engine wires
wire         sha_start, sha_first, sha_last, sha_done, sha_ready;
wire [8:0]   sha_last_len;
wire [511:0] sha_block;
wire [63:0]  sha_tbits;
wire [255:0] sha_digest;

// TRNG wires
wire       trng_en, trng_valid;
wire [7:0] trng_data;

// PCR bank wires
wire [1:0]   pcr_ext_sel, pcr_rd_sel;
wire [255:0] pcr_ext_digest, pcr_rd_value;
wire         pcr_ext_valid;
wire [255:0] pcr0, pcr1, pcr2, pcr3;

// ─────────────────────────────────────────────────────────────────────────────
// Module instances
// ─────────────────────────────────────────────────────────────────────────────

tpm_spi_slave u_spi (
    .clk        (clk),
    .rstn       (rstn),
    .spi_csn    (spi_csn),
    .spi_sck    (spi_sck),
    .spi_mosi   (spi_mosi),
    .spi_miso   (spi_miso),
    .pa_addr    (pa_addr),
    .pa_wdata   (pa_wdata),
    .pa_we      (pa_we),
    .pa_rdata   (pa_rdata),
    .cmd_start  (cmd_start),
    .proc_busy  (proc_busy),
    .proc_done  (proc_done),
    .irq        (irq)
);

tpm_mem u_mem (
    .clk      (clk),
    .pa_addr  (pa_addr),
    .pa_wdata (pa_wdata),
    .pa_we    (pa_we),
    .pa_rdata (pa_rdata),
    .pb_addr  (pb_addr),
    .pb_wdata (pb_wdata),
    .pb_we    (pb_we),
    .pb_rdata (pb_rdata)
);

tpm_cmd_proc u_proc (
    .clk          (clk),
    .rstn         (rstn),
    .start        (cmd_start),
    .busy         (proc_busy),
    .done         (proc_done),
    .err          (proc_err),
    .mem_addr     (pb_addr),
    .mem_wdata    (pb_wdata),
    .mem_we       (pb_we),
    .mem_rdata    (pb_rdata),
    .sha_start    (sha_start),
    .sha_first    (sha_first),
    .sha_last     (sha_last),
    .sha_last_len (sha_last_len),
    .sha_block    (sha_block),
    .sha_tbits    (sha_tbits),
    .sha_ready    (sha_ready),
    .sha_done     (sha_done),
    .sha_digest   (sha_digest),
    .trng_en      (trng_en),
    .trng_data    (trng_data),
    .trng_valid   (trng_valid),
    .pcr_ext_sel    (pcr_ext_sel),
    .pcr_ext_digest (pcr_ext_digest),
    .pcr_ext_valid  (pcr_ext_valid),
    .pcr_rd_sel     (pcr_rd_sel),
    .pcr_rd_value   (pcr_rd_value)
);

tpm_sha256_wrap u_sha (
    .clk         (clk),
    .rstn        (rstn),
    .sha_start   (sha_start),
    .sha_first   (sha_first),
    .sha_last    (sha_last),
    .sha_last_len(sha_last_len),
    .sha_block   (sha_block),
    .sha_tbits   (sha_tbits),
    .sha_ready   (sha_ready),
    .sha_done    (sha_done),
    .sha_digest  (sha_digest)
);

tpm_trng #(.DECIM(16)) u_trng (
    .clk    (clk),
    .rstn   (rstn),
    .enable (trng_en),
    .data   (trng_data),
    .valid  (trng_valid)
);

tpm_pcr_bank u_pcr (
    .clk          (clk),
    .rstn         (rstn),
    .ext_sel      (pcr_ext_sel),
    .ext_digest   (pcr_ext_digest),
    .ext_valid    (pcr_ext_valid),
    .rd_sel       (pcr_rd_sel),
    .rd_value     (pcr_rd_value),
    .pcr0         (pcr0),
    .pcr1         (pcr1),
    .pcr2         (pcr2),
    .pcr3         (pcr3)
);

endmodule
`default_nettype wire
