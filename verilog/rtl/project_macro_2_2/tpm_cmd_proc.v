// =============================================================================
// tpm_cmd_proc.v — TPM Command Processor (Main FSM)
// =============================================================================
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW THIS MODULE USES SHA-256
// ─────────────────────────────────────────────────────────────────────────────
// There is ONE sha256_core instance in the design (inside tpm_sha256_wrap).
// This processor calls it sequentially for every SHA-256 operation needed.
//
// PCR_Extend needs 1 SHA-256 call:
//   Block = PCR_old[255:0] || measurement[255:0]  (exactly 64 bytes = 1 block)
//   SHA256( block ) → new PCR value
//
// HMAC needs 4 SHA-256 block calls:
//   HMAC-SHA256(K, M) = SHA256( opad_K || SHA256( ipad_K || M ) )
//   where ipad = key XOR 0x363636..., opad = key XOR 0x5C5C5C...
//   key is 32 bytes, padded with zeros to 64 bytes.
//   message is fixed at 32 bytes.
//
//   Inner hash (SHA256 of ipad_K || M):
//     Block 1: ipad_key (64 bytes, sha_first=1, sha_last=0) → call 1
//     Block 2: message  (32 bytes, sha_first=0, sha_last=1) → call 2
//              total message = 96 bytes = 768 bits → inner_digest
//
//   Outer hash (SHA256 of opad_K || inner_digest):
//     Block 1: opad_key    (64 bytes, sha_first=1, sha_last=0) → call 3
//     Block 2: inner_digest (32 bytes, sha_first=0, sha_last=1) → call 4
//              total message = 96 bytes = 768 bits → final HMAC
//
// ─────────────────────────────────────────────────────────────────────────────
// SUPPORTED COMMANDS
// ─────────────────────────────────────────────────────────────────────────────
//   CC_GET_RANDOM  0x017B  → up to 32 TRNG bytes
//   CC_PCR_EXTEND  0x0182  → extend PCR[0..3] with 32-byte digest
//   CC_PCR_READ    0x017E  → read 32-byte PCR value
//   CC_HMAC        0x015D  → HMAC-SHA256(key32, msg32)
//
// ─────────────────────────────────────────────────────────────────────────────
// COMMAND WIRE FORMAT  (big-endian, TPM2 no-sessions)
// ─────────────────────────────────────────────────────────────────────────────
//   Bytes 0-1   tag       0x8001
//   Bytes 2-5   cmdSize   total length in bytes
//   Bytes 6-9   cmdCode   one of CC_* above
//   Bytes 10+   params    command-specific (see README)
//
// RESPONSE WIRE FORMAT
//   Bytes 0-1   tag       0x8001
//   Bytes 2-5   rspSize   total length in bytes
//   Bytes 6-9   rspCode   0x00000000 = success
//   Bytes 10+   output    command-specific
//
// ─────────────────────────────────────────────────────────────────────────────
// MEMORY MAP (tpm_mem)
// ─────────────────────────────────────────────────────────────────────────────
//   0x00-0x7F  CMD_BUF  (written by SPI slave, read by this module)
//   0x80-0xFF  RSP_BUF  (written by this module, read by SPI slave)
// =============================================================================
`timescale 1ns/1ps

module tpm_cmd_proc (
    input  wire         clk,
    input  wire         rstn,

    // Control
    input  wire         start,      // pulse: begin processing CMD_BUF
    output reg          busy,
    output reg          done,       // 1-cycle pulse: RSP_BUF ready
    output reg          err,

    // Memory port B (processor side)
    output reg  [7:0]   mem_addr,
    output reg  [7:0]   mem_wdata,
    output reg          mem_we,
    input  wire [7:0]   mem_rdata,  // valid one cycle after mem_addr

    // SHA-256 engine
    output reg          sha_start,
    output reg          sha_first,
    output reg          sha_last,
    output reg  [8:0]   sha_last_len,
    output reg  [511:0] sha_block,
    output reg  [63:0]  sha_tbits,
    input  wire         sha_ready,
    input  wire         sha_done,
    input  wire [255:0] sha_digest,

    // TRNG
    output reg          trng_en,
    input  wire [7:0]   trng_data,
    input  wire         trng_valid,

    // PCR bank
    output reg  [1:0]   pcr_ext_sel,
    output reg  [255:0] pcr_ext_digest,
    output reg          pcr_ext_valid,
    output reg  [1:0]   pcr_rd_sel,
    input  wire [255:0] pcr_rd_value
);

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
localparam [15:0] TAG      = 16'h8001;
localparam [31:0] CC_RAND  = 32'h0000_017B;
localparam [31:0] CC_EXT   = 32'h0000_0182;
localparam [31:0] CC_READ  = 32'h0000_017E;
localparam [31:0] CC_HMAC  = 32'h0000_015D;
localparam [31:0] RC_OK    = 32'h0000_0000;
localparam [31:0] RC_TAG   = 32'h0000_009C;
localparam [31:0] RC_CC    = 32'h0000_0143;

// Memory base addresses
localparam [7:0] CMD = 8'h00;
localparam [7:0] RSP = 8'h80;

// HMAC padding constants (32 bytes each)
localparam [255:0] IPAD = {32{8'h36}};
localparam [255:0] OPAD = {32{8'h5C}};

// ─────────────────────────────────────────────────────────────────────────────
// State encoding
// ─────────────────────────────────────────────────────────────────────────────
localparam [5:0]
    // Header parse (runs for every command)
    S_IDLE      = 6'd0,
    S_HDR_ADDR  = 6'd1,   // set memory address for next header byte
    S_HDR_READ  = 6'd2,   // latch header byte from mem_rdata
    S_DECODE    = 6'd3,   // decode command code and jump

    // GetRandom
    S_RND_WAIT  = 6'd4,   // wait for TRNG byte
    S_RND_WR    = 6'd5,   // write TRNG byte to RSP_BUF
    S_RND_DONE  = 6'd6,

    // PCR_Extend
    S_EXT_ADDR  = 6'd7,   // set mem address to read measurement bytes
    S_EXT_READ  = 6'd8,   // accumulate measurement into register
    S_EXT_SHA   = 6'd9,   // call SHA256(PCR||meas)
    S_EXT_WAIT  = 6'd10,  // wait for sha_done
    S_EXT_STORE = 6'd11,  // write new PCR value

    // PCR_Read
    S_RD_ADDR   = 6'd12,  // address PCR index byte
    S_RD_READ   = 6'd13,  // read PCR index
    S_RD_WR     = 6'd14,  // write 32 PCR bytes to RSP_BUF

    // HMAC — read phase
    S_HM_KEY_A  = 6'd15,  // address first key byte
    S_HM_KEY_R  = 6'd16,  // read key bytes
    S_HM_MSG_A  = 6'd17,  // address first msg byte
    S_HM_MSG_R  = 6'd18,  // read msg bytes

    // HMAC — inner hash (SHA256 of ipad_key || msg)
    S_HM_I1     = 6'd19,  // call SHA with ipad_key block (init)
    S_HM_I1W    = 6'd20,  // wait for SHA done (block 1)
    S_HM_I2     = 6'd21,  // call SHA with msg block (final)
    S_HM_I2W    = 6'd22,  // wait for SHA done (block 2) → inner_digest

    // HMAC — outer hash (SHA256 of opad_key || inner_digest)
    S_HM_O1     = 6'd23,  // call SHA with opad_key block (init)
    S_HM_O1W    = 6'd24,  // wait for SHA done (block 3)
    S_HM_O2     = 6'd25,  // call SHA with inner_digest block (final)
    S_HM_O2W    = 6'd26,  // wait for SHA done (block 4) → HMAC result

    // HMAC write result
    S_HM_WR     = 6'd27,

    // Common response header write
    S_RSP_WR    = 6'd28,

    // Done
    S_DONE      = 6'd29;

// ─────────────────────────────────────────────────────────────────────────────
// Registers
// ─────────────────────────────────────────────────────────────────────────────
reg [5:0]  state;

// Parsed command header
reg [15:0] h_tag;
reg [31:0] h_size, h_code;

// Response fields
reg [31:0] rsp_size, rsp_code;

// Header byte counter (reads bytes 0-9)
reg [3:0]  hdr_cnt;

// Generic read/write cursor within CMD_BUF or RSP_BUF
reg [7:0]  cmd_ptr;   // next byte to read from CMD_BUF
reg [7:0]  rsp_ptr;   // next byte to write to RSP_BUF

// GetRandom
reg [7:0]  rnd_n;     // bytes to generate (max 32)
reg [7:0]  rnd_done;

// PCR_Extend working registers
reg [255:0] ext_meas;   // 32-byte measurement digest
reg [5:0]   ext_bcnt;   // byte counter (0..31)
reg [1:0]   ext_pcr;    // PCR index from command

// PCR_Read
reg [5:0]  rd_bcnt;

// HMAC working registers
reg [255:0] hm_key;      // 32-byte key
reg [255:0] hm_msg;      // 32-byte message
reg [255:0] hm_inner;    // inner hash result
reg [5:0]   hm_bcnt;

// Write-32-bytes helper (shared between PCR_Read, HMAC result write)
reg [255:0] wr_data;
reg [5:0]   wr_cnt;

// Response header write counter
reg [3:0] rsp_hdr_cnt;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: build 512-bit HMAC block
// ipad_block = (key ^ IPAD32) [255:0] || IPAD32 [255:0]
// opad_block = (key ^ OPAD32) [255:0] || OPAD32 [255:0]
// The key is 32 bytes, padded to 64 by XORing the zero-padding with ipad/opad.
// ─────────────────────────────────────────────────────────────────────────────
function [511:0] mk_ipad_blk;
    input [255:0] k;
    begin mk_ipad_blk = {k ^ IPAD, IPAD}; end
endfunction

function [511:0] mk_opad_blk;
    input [255:0] k;
    begin mk_opad_blk = {k ^ OPAD, OPAD}; end
endfunction

// ─────────────────────────────────────────────────────────────────────────────
// Main FSM
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state    <= S_IDLE;
        busy     <= 0; done <= 0; err <= 0;
        mem_we   <= 0; sha_start <= 0;
        trng_en  <= 0; pcr_ext_valid <= 0;
        rsp_code <= RC_OK; rsp_size <= 0;
        cmd_ptr  <= 0; rsp_ptr <= RSP;
    end else begin
        // De-assert single-cycle pulses every cycle by default
        mem_we        <= 0;
        sha_start     <= 0;
        pcr_ext_valid <= 0;
        done          <= 0;

        case (state)

        // ═════════════════════════════════════════════════════════════════
        S_IDLE: begin
            busy <= 0; err <= 0;
            if (start) begin
                busy        <= 1;
                mem_addr    <= CMD + 0;    // FIX: pre-address byte 0 so pb_rdata is ready next cycle
                cmd_ptr     <= CMD + 1;    // FIX: next byte to pre-address
                rsp_ptr     <= RSP + 10;
                rsp_code    <= RC_OK;
                hdr_cnt     <= 0;
                rsp_hdr_cnt <= 0;
                state       <= S_HDR_ADDR; // wait one cycle for registered read to be valid
            end
        end

        // ═════════════════════════════════════════════════════════════════
        // Parse 10-byte command header
        // FIX: Registered read pipeline:
        //   Cycle N   (S_IDLE or S_HDR_READ): mem_addr <= next_addr
        //   Cycle N+1 (S_HDR_ADDR)          : pb_rdata = mem[next_addr]  (1-cycle latency)
        //   Cycle N+1 (S_HDR_ADDR)          : also pre-load address for next byte
        //   Cycle N+2 (S_HDR_READ)          : latch pb_rdata
        // ═════════════════════════════════════════════════════════════════
        S_HDR_ADDR: begin
            // pb_rdata is now valid (= mem[mem_addr set in prev cycle])
            // Pre-address the NEXT byte while we wait for HDR_READ to latch
            
                mem_addr <= cmd_ptr;
                cmd_ptr  <= cmd_ptr + 1;
            
            state <= S_HDR_READ;
        end

        S_HDR_READ: begin
            // Latch the byte that was addressed 2 cycles ago (via IDLE/HDR_ADDR)
            case (hdr_cnt)
              4'd0: h_tag[15:8]   <= mem_rdata;
              4'd1: h_tag[7:0]    <= mem_rdata;
              4'd2: h_size[31:24] <= mem_rdata;
              4'd3: h_size[23:16] <= mem_rdata;
              4'd4: h_size[15:8]  <= mem_rdata;
              4'd5: h_size[7:0]   <= mem_rdata;
              4'd6: h_code[31:24] <= mem_rdata;
              4'd7: h_code[23:16] <= mem_rdata;
              4'd8: h_code[15:8]  <= mem_rdata;
              4'd9: begin
                    h_code[7:0]   <= mem_rdata;
                    state         <= S_DECODE;
              end
            endcase
            hdr_cnt <= hdr_cnt + 1;
            if (hdr_cnt < 9) state <= S_HDR_ADDR;
        end

        // ═════════════════════════════════════════════════════════════════
        S_DECODE: begin
            if (h_tag != TAG) begin
                rsp_code <= RC_TAG;
                rsp_size <= 32'd10;
                state    <= S_RSP_WR;
            end else begin
                case (h_code[15:0])

                CC_RAND[15:0]: begin
                    // Bytes 10-11 = bytesRequested (we cap at 32)
                    // FIX: TRNG data starts at RSP+12 (RSP+10..11 reserved for outSize field)
                    rnd_n    <= 8'd32;
                    rnd_done <= 0;
                    rsp_ptr  <= RSP + 12;   // FIX: was RSP+10, overwrote outSize
                    trng_en  <= 1;
                    state    <= S_RND_WAIT;
                end

                CC_EXT[15:0]: begin
                    // Bytes 10-13 = PCR handle (only [1:0] used)
                    // Bytes 14-45 = 32-byte measurement digest
                    // Address byte 13 first (PCR index)
                    mem_addr <= CMD + 13;
                    cmd_ptr  <= CMD + 14;
                    ext_bcnt <= 0;
                    state    <= S_EXT_ADDR;
                end

                CC_READ[15:0]: begin
                    // Bytes 10-13 = PCR handle (only [1:0] used)
                    mem_addr <= CMD + 13;
                    state    <= S_RD_ADDR;
                end

                CC_HMAC[15:0]: begin
                    // Bytes 10-41 = 32-byte key
                    // Bytes 42-73 = 32-byte message
                    mem_addr <= CMD + 10;
                    cmd_ptr  <= CMD + 11;
                    hm_bcnt  <= 0;
                    state    <= S_HM_KEY_A;
                end

                default: begin
                    rsp_code <= RC_CC;
                    rsp_size <= 32'd10;
                    state    <= S_RSP_WR;
                end
                endcase
            end
        end

        // ═════════════════════════════════════════════════════════════════
        // GetRandom: pull bytes from TRNG, write to RSP_BUF[10..]
        // ═════════════════════════════════════════════════════════════════
        S_RND_WAIT: begin
            if (trng_valid) state <= S_RND_WR;
        end

        S_RND_WR: begin
            mem_addr  <= rsp_ptr;
            mem_wdata <= trng_data;
            mem_we    <= 1;
            rsp_ptr   <= rsp_ptr + 1;
            rnd_done  <= rnd_done + 1;
            if (rnd_done + 1 >= rnd_n) begin
                trng_en <= 0;
                state   <= S_RND_DONE;
            end else begin
                state <= S_RND_WAIT;
            end
        end

        S_RND_DONE: begin
            // Write 2-byte outSize field at RSP+10..11 (big-endian)
            // FIX: rnd_n bytes of random data were written to RSP+12..(12+rnd_n-1)
            // We now write outSize as a 2-byte big-endian at RSP+10..11.
            // Use rsp_hdr_cnt to sequence the two writes.
            mem_we <= 1;
            case (rsp_hdr_cnt)
              4'd0: begin
                mem_addr    <= RSP + 10;
                mem_wdata   <= 8'h00;        // outSize[15:8] = 0 (rnd_n <= 32)
                rsp_hdr_cnt <= 1;
              end
              default: begin
                mem_addr    <= RSP + 11;
                mem_wdata   <= rnd_n;        // outSize[7:0]
                rsp_hdr_cnt <= 0;
                rsp_size    <= 32'd12 + rnd_n;
                state       <= S_RSP_WR;
              end
            endcase
        end

        // ═════════════════════════════════════════════════════════════════
        // PCR_Extend
        // Step 1: read PCR index + 32-byte measurement from CMD_BUF
        // Step 2: SHA256( PCR_current || measurement ) — 1 block call
        // Step 3: write result to PCR bank
        // ═════════════════════════════════════════════════════════════════
        S_EXT_ADDR: begin
            // First time: mem_addr already set to CMD+13 in S_DECODE
            // Subsequent times: mem_addr set by S_EXT_READ below
            state <= S_EXT_READ;
        end

        S_EXT_READ: begin
            if (ext_bcnt == 0) begin
                // Byte 13 = PCR index
                ext_pcr  <= mem_rdata[1:0];
                mem_addr <= cmd_ptr;
                cmd_ptr  <= cmd_ptr + 1;
                ext_bcnt <= 1;
                state    <= S_EXT_ADDR;
            end else begin
                // Bytes 14-45: accumulate measurement MSB first
                ext_meas <= {ext_meas[247:0], mem_rdata};
                ext_bcnt <= ext_bcnt + 1;
                if (ext_bcnt < 32) begin
                    mem_addr <= cmd_ptr;
                    cmd_ptr  <= cmd_ptr + 1;
                    state    <= S_EXT_ADDR;
                end else begin
                    // All 32 bytes received
                    pcr_rd_sel <= ext_pcr;
                    state      <= S_EXT_SHA;
                end
            end
        end

        S_EXT_SHA: begin
            // Wait for SHA engine, then call it with 64-byte block
            // Block = pcr_rd_value[255:0] || ext_meas[255:0] = 64 bytes exactly
            // No padding needed because 64 bytes = 1 full SHA-256 block
            // sha_last_len = 64 (all bytes valid), sha_tbits = 512
            if (sha_ready) begin
                sha_block     <= {pcr_rd_value, ext_meas};
                sha_first     <= 1;
                sha_last      <= 1;
                sha_last_len  <= 9'd64;
                sha_tbits     <= 64'd512;
                sha_start     <= 1;
                state         <= S_EXT_WAIT;
            end
        end

        S_EXT_WAIT: begin
            if (sha_done) begin
                state <= S_EXT_STORE;
            end
        end

        S_EXT_STORE: begin
            pcr_ext_sel    <= ext_pcr;
            pcr_ext_digest <= sha_digest;
            pcr_ext_valid  <= 1;
            rsp_size       <= 32'd10;
            state          <= S_RSP_WR;
        end

        // ═════════════════════════════════════════════════════════════════
        // PCR_Read: return 32 bytes of PCR value in RSP_BUF[10..41]
        // ═════════════════════════════════════════════════════════════════
        S_RD_ADDR: begin
            state <= S_RD_READ;
        end

        S_RD_READ: begin
            pcr_rd_sel <= mem_rdata[1:0];
            rd_bcnt    <= 0;
            state      <= S_RD_WR;
        end

        S_RD_WR: begin
            // Write pcr_rd_value[255:0] MSB-first to RSP_BUF[10..41]
            // pcr_rd_value is combinational with 1-cycle latency from S_RD_READ
            mem_addr  <= RSP + 10 + rd_bcnt;
            mem_wdata <= pcr_rd_value[255 - (rd_bcnt * 8) -: 8];
            mem_we    <= 1;
            rd_bcnt   <= rd_bcnt + 1;
            if (rd_bcnt == 6'd31) begin
                rsp_size <= 32'd42;
                state    <= S_RSP_WR;
            end
        end

        // ═════════════════════════════════════════════════════════════════
        // HMAC-SHA256 — read key (32 bytes) and message (32 bytes)
        // ═════════════════════════════════════════════════════════════════
        S_HM_KEY_A: begin
            state <= S_HM_KEY_R;
        end

        S_HM_KEY_R: begin
            hm_key  <= {hm_key[247:0], mem_rdata};
            hm_bcnt <= hm_bcnt + 1;
            if (hm_bcnt < 31) begin
                mem_addr <= cmd_ptr;
                cmd_ptr  <= cmd_ptr + 1;
                state    <= S_HM_KEY_A;
            end else begin
                // Done reading key; start reading message
                mem_addr <= cmd_ptr;
                cmd_ptr  <= cmd_ptr + 1;
                hm_bcnt  <= 0;
                state    <= S_HM_MSG_A;
            end
        end

        S_HM_MSG_A: begin
            state <= S_HM_MSG_R;
        end

        S_HM_MSG_R: begin
            hm_msg  <= {hm_msg[247:0], mem_rdata};
            hm_bcnt <= hm_bcnt + 1;
            if (hm_bcnt < 31) begin
                mem_addr <= cmd_ptr;
                cmd_ptr  <= cmd_ptr + 1;
                state    <= S_HM_MSG_A;
            end else begin
                // Both key and message ready; start inner hash
                hm_bcnt <= 0;
                state   <= S_HM_I1;
            end
        end

        // ─────────────────────────────────────────────────────────────────
        // INNER HASH PASS
        // Call 1: SHA256 block = ipad_key  (64 bytes, first=1, last=0)
        // ─────────────────────────────────────────────────────────────────
        S_HM_I1: begin
            if (sha_ready) begin
                // ipad_block: (hm_key ^ IPAD)[255:0] || IPAD[255:0]
                // High 32 bytes = key XOR ipad; Low 32 bytes = 0 XOR ipad = ipad
                sha_block    <= mk_ipad_blk(hm_key);
                sha_first    <= 1;
                sha_last     <= 0;
                sha_last_len <= 0;
                sha_tbits    <= 0;
                sha_start    <= 1;
                state        <= S_HM_I1W;
            end
        end

        S_HM_I1W: begin
            // The core has stored the intermediate hash state internally.
            // We wait for sha_ready to come back (core becomes ready again).
            // sha_done is only asserted when sha_last=1 (final block).
            // So here we just wait for sha_ready (means block was absorbed).
            if (sha_ready && !sha_start) state <= S_HM_I2;
        end

        // Call 2: SHA256 block = message  (32 bytes, first=0, last=1)
        // Total inner message = 64 + 32 = 96 bytes = 768 bits
        S_HM_I2: begin
            if (sha_ready) begin
                sha_block    <= {hm_msg, 256'h0};  // 32 bytes msg + 32 bytes zero
                sha_first    <= 0;
                sha_last     <= 1;
                sha_last_len <= 9'd32;
                sha_tbits    <= 64'd768;
                sha_start    <= 1;
                state        <= S_HM_I2W;
            end
        end

        S_HM_I2W: begin
            if (sha_done) begin
                hm_inner <= sha_digest;   // save inner hash
                state    <= S_HM_O1;
            end
        end

        // ─────────────────────────────────────────────────────────────────
        // OUTER HASH PASS
        // Call 3: SHA256 block = opad_key  (64 bytes, first=1, last=0)
        // ─────────────────────────────────────────────────────────────────
        S_HM_O1: begin
            if (sha_ready) begin
                sha_block    <= mk_opad_blk(hm_key);
                sha_first    <= 1;
                sha_last     <= 0;
                sha_last_len <= 0;
                sha_tbits    <= 0;
                sha_start    <= 1;
                state        <= S_HM_O1W;
            end
        end

        S_HM_O1W: begin
            if (sha_ready && !sha_start) state <= S_HM_O2;
        end

        // Call 4: SHA256 block = inner_digest  (32 bytes, first=0, last=1)
        // Total outer message = 64 + 32 = 96 bytes = 768 bits
        S_HM_O2: begin
            if (sha_ready) begin
                sha_block    <= {hm_inner, 256'h0};
                sha_first    <= 0;
                sha_last     <= 1;
                sha_last_len <= 9'd32;
                sha_tbits    <= 64'd768;
                sha_start    <= 1;
                state        <= S_HM_O2W;
            end
        end

        S_HM_O2W: begin
            if (sha_done) begin
                // sha_digest = final HMAC result
                wr_data  <= sha_digest;
                wr_cnt   <= 0;
                state    <= S_HM_WR;
            end
        end

        S_HM_WR: begin
            // Write 32 bytes of HMAC result to RSP_BUF[10..41]
            mem_addr  <= RSP + 10 + wr_cnt;
            mem_wdata <= wr_data[255 - (wr_cnt * 8) -: 8];
            mem_we    <= 1;
            wr_cnt    <= wr_cnt + 1;
            if (wr_cnt == 6'd31) begin
                rsp_size <= 32'd42;
                state    <= S_RSP_WR;
            end
        end

        // ═════════════════════════════════════════════════════════════════
        // Write 10-byte response header to RSP_BUF[0..9]
        // tag(2) | rsp_size(4) | rsp_code(4)
        // ═════════════════════════════════════════════════════════════════
        S_RSP_WR: begin
            mem_we <= 1;
            case (rsp_hdr_cnt)
              4'd0:  begin mem_addr <= RSP+0; mem_wdata <= TAG[15:8];      rsp_hdr_cnt <= 1; end
              4'd1:  begin mem_addr <= RSP+1; mem_wdata <= TAG[7:0];       rsp_hdr_cnt <= 2; end
              4'd2:  begin mem_addr <= RSP+2; mem_wdata <= rsp_size[31:24]; rsp_hdr_cnt <= 3; end
              4'd3:  begin mem_addr <= RSP+3; mem_wdata <= rsp_size[23:16]; rsp_hdr_cnt <= 4; end
              4'd4:  begin mem_addr <= RSP+4; mem_wdata <= rsp_size[15:8];  rsp_hdr_cnt <= 5; end
              4'd5:  begin mem_addr <= RSP+5; mem_wdata <= rsp_size[7:0];   rsp_hdr_cnt <= 6; end
              4'd6:  begin mem_addr <= RSP+6; mem_wdata <= rsp_code[31:24]; rsp_hdr_cnt <= 7; end
              4'd7:  begin mem_addr <= RSP+7; mem_wdata <= rsp_code[23:16]; rsp_hdr_cnt <= 8; end
              4'd8:  begin mem_addr <= RSP+8; mem_wdata <= rsp_code[15:8];  rsp_hdr_cnt <= 9; end
              4'd9:  begin
                     mem_addr <= RSP+9; mem_wdata <= rsp_code[7:0];
                     rsp_hdr_cnt <= 0;
                     state <= S_DONE;
              end
              default: begin mem_we <= 0; state <= S_DONE; end
            endcase
        end

        // ═════════════════════════════════════════════════════════════════
        S_DONE: begin
            mem_we <= 0;
            done   <= 1;
            busy   <= 0;
            err    <= (rsp_code != RC_OK);
            state  <= S_IDLE;
        end

        default: state <= S_IDLE;
        endcase
    end
end

// Reset rsp_hdr_cnt when entering S_RSP_WR from outside
// (handled by always block above — initialized to 0 in reset,
// and forced to 0 again at S_DONE)

endmodule
