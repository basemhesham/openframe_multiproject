# NeuralTram Architecture

## System Hierarchy

```
project_macro (top-level, OpenFrame wrapper)
|-- SPI signals mapped to top GPIOs [0:3]
|   |-- simple_spi
|   |   |-- Synchronizes SCLK, CS_N, MOSI (2-bit shift regs)
|   |   |-- Decodes 5 commands into control pulses
|   |   +-- Generates: addr[7:0], din[63:0], data_we[7:0],
|   |                   weight_we[7:0], start, data_len[15:0], col_mask[3:0]
|   |
|   +-- systolic_wrapper
|       |-- 6-state FSM: IDLE -> LOAD_WEIGHTS -> SWITCH_WEIGHTS
|       |                -> PROCESS_DATA -> WAIT_OUTPUT -> DONE
|       |-- DFFRAM x3: data_mem, weight_mem, output_mem
|       |   |-- 32 words x 8 bytes each
|       |   +-- 1-cycle read latency
|       |-- Input skewing: delays row 1 by 1 cycle, row 2 by 2, row 3 by 3
|       +-- Output deskewing: delays col 0 by 3 cycles, col 1 by 2, col 2 by 1
|           |
|           +-- systolic (4x4 PE grid)
|               |-- Start signal skewed per row (wavefront)
|               +-- pe x16
|                   |-- Dual-buffer weights (shadow + active)
|                   |-- MAC: psum = activation * weight + psum_in
|                   +-- Overflow detection (sticky)
```

## Module Details

### project_macro

OpenFrame-compliant top-level. Maps SPI to GPIO pins:

| GPIO               | Signal   | Function                     |
| ------------------ | -------- | ---------------------------- |
| top_in[0]          | spi_cs_n | SPI chip select (active low) |
| top_in[1]          | spi_sclk | SPI clock                    |
| top_in[2]          | spi_mosi | SPI data in                  |
| top_out[3]         | spi_miso | SPI data out                 |
| top_in[13:4]       | unused   | Tied as inputs               |
| bot[14:0], rt[8:0] | unused   | All outputs Hi-Z             |

Total 38 GPIOs (15 bottom + 9 right + 14 top). All drive modes set to strong push-pull (3'b110).

### simple_spi

SPI slave that runs entirely on the internal `clk` domain. Synchronizes all SPI signals with 2-bit shift registers. Detects SCLK rising edge for MOSI sampling, falling edge for MISO shifting.

Command decode:

- Bit counter tracks position within transaction
- Command byte captured at bit_cnt==7
- For write commands (0x01, 0x02): 80-bit transaction (cmd + addr + 64-bit data)
- For read command (0x03): loads dout into miso_shift at bit_cnt==16, shifts out on subsequent clocks
- For start command (0x04): single byte, sets start=1
- For status command (0x05): loads {busy, done, 62'b0} at bit_cnt==8

Control signal timing:

- `data_we`, `weight_we`: asserted for 1 cycle, auto-cleared next cycle
- `start`: asserted for 1 cycle, auto-cleared next cycle
- `addr` and `din` hold the last written values until overwritten

### systolic_wrapper

Central controller. Contains three DFFRAM instances and the systolic array.

**Memory MUX behavior:**

- When `busy=0`: external ports pass through to memories (host can read/write)
- When `busy=1`: external writes blocked, internal FSM drives memory reads

**FSM states:**

```
IDLE (state=0):
  - Wait for start=1
  - done=0, busy=0

LOAD_WEIGHTS (state=1, counter=0..5):
  - Cycles 1-4: read weight_mem_do, assert col_mask
  - Cycle 5: transition to SWITCH_WEIGHTS
  - Total: 6 cycles

SWITCH_WEIGHTS (state=2, 1 cycle):
  - Pulse sys_switch_in=1
  - Immediately transition to PROCESS_DATA

PROCESS_DATA (state=3, counter=0..data_len+5):
  - Cycles 0..data_len-1: sys_start=1, feed data_mem_do
  - Cycles data_len..data_len+5: sys_start=0, drain pipeline
  - Input skewing: cascade delay registers for rows 1-3
  - At counter==data_len+5: transition to WAIT_OUTPUT

WAIT_OUTPUT (state=4, counter=0..20):
  - Continue feeding zeros through skew registers
  - Deskewed valid signals trigger output_mem writes
  - output_counter increments on each deskewed_valid
  - At counter==20: transition to DONE

DONE (state=5, 1 cycle):
  - Set busy=0, done=1
  - Return to IDLE
```

**Input skewing registers:**

```
skewed_data_in[15:0]  = sys_data_in[15:0]       (no delay)
skewed_data_in[31:16] = data_skew_r1_0           (1 cycle delay)
skewed_data_in[47:32] = data_skew_r2_1           (2 cycle delay)
skewed_data_in[63:48] = data_skew_r3_2           (3 cycle delay)
```

**Output deskewing registers:**

```
deskewed_data_out[15:0]  = res_deskew_c0_2       (3 cycle delay)
deskewed_data_out[31:16] = res_deskew_c1_1       (2 cycle delay)
deskewed_data_out[47:32] = res_deskew_c2_0       (1 cycle delay)
deskewed_data_out[63:48] = sys_data_out[63:48]   (no delay)
```

### systolic

4x4 grid of PEs with wavefront control.

**Start signal skewing:**

```
sys_start_skewed[0] <= sys_start
sys_start_skewed[i] <= sys_start_skewed[i-1]  (for i=1,2,3)
```

This creates a diagonal wavefront where row i starts i cycles after row 0.

**Data routing:**

- Activations enter from the left (west). Row i gets sys_data_in[i*16 +: 16], sign-extended from 8-bit.
- Weights enter from the top (north). Column j gets sys_weight_in[j*16 +: 16], sign-extended from 8-bit.
- Partial sums flow downward (north to south).
- Activations flow rightward (west to east).
- Weights propagate downward through the array.

**Row 0**: psum_in = 0 (accumulation starts fresh)
**Column 0**: activation comes from sys_data_in (sign-extended to 16-bit)

### pe

Single MAC processing element.

**Core computation:**

```
mult_out  = activation_in * weight_active    (16-bit signed multiply)
mac_out   = mult_out + psum_in               (16-bit signed add)
psum_out  = mac_out (when valid_in=1)
```

**Dual-buffer weight system:**

- `weight_shadow`: loaded when accept_w_in=1
- `weight_active`: used in MAC, updated when switch_in=1 (copies from shadow)

**Passthrough behavior:**

- activation_out = activation_in (when valid_in=1, else 0)
- weight_out = weight_in (when accept_w_in=1, else 0)
- valid_out = valid_in (1 cycle delay)
- switch_out = switch_in (1 cycle delay)

**Overflow detection:**

- `mult_overflow`: sign mismatch on multiply result
- `add_overflow`: sign mismatch on add result
- `overflow_out`: sticky OR of both, never cleared except on reset

### dffram_rtl

Behavioral memory model matching the structural DFFRAM interface.

```
Parameters: WORDS=256 (default), WSIZE=1 (byte)
When EN0=1:
  - Writes bytes where WE0[i]=1
  - Reads: Do0 <= mem[A0] (1-cycle latency)
When EN0=0:
  - Do0 holds previous value
```

In systolic_wrapper, all three instances use WORDS=32, WSIZE=8 (32 words of 8 bytes = 256 bytes each).

---

## Timing Analysis

### End-to-end computation latency

For a matrix multiplication with data_len input vectors:

| Phase          | Cycles            | Description                                    |
| -------------- | ----------------- | ---------------------------------------------- |
| LOAD_WEIGHTS   | 6                 | Load 4 weight rows from memory                 |
| SWITCH_WEIGHTS | 1                 | Pulse weight switch                            |
| PROCESS_DATA   | data_len + 6      | Stream data_len inputs, drain 5-cycle pipeline |
| WAIT_OUTPUT    | 21                | Flush output pipeline                          |
| DONE           | 1                 | Set done flag                                  |
| **Total**      | **data_len + 35** | Excluding SPI transfer time                    |

### SPI transfer time

Each SPI transaction's duration in chip clock cycles depends on **K**, the ratio between the chip's internal clock period (50 ns, 20 MHz) and the external SCLK period:

```
K = ceil(SCLK_period / 50 ns)
```

| Transaction           | Bits | Clock cycles |
| --------------------- | ---- | ------------ |
| Write (data/weight)   | 80   | 80 × K       |
| Read (output/status)  | 80   | 80 × K       |
| Start                 | 8    | 8 × K        |

For example, with a 10 MHz SPI master (100 ns/bit) on the 20 MHz hardened chip, K=2. In the testbench (100 MHz internal, 25 MHz SCLK), K=4.
- Status command: 8 bits in + 64 bits out = 72 SCLK edges = 288 clk cycles

### Internal clock delays

| Signal                            | Delay (cycles) | Source                                 |
| --------------------------------- | -------------- | -------------------------------------- |
| SPI signal sync                   | 2              | simple_spi shift registers             |
| data_we / weight_we / start pulse | 1              | Auto-cleared next cycle                |
| DFFRAM read                       | 1              | EN0 + A0 to Do0                        |
| PE MAC                            | 1              | Combinational mult+add, registered out |
| Activation pass-through (per PE)  | 1              | Each PE adds 1 cycle                   |
| Psum pass-through (per PE)        | 1              | Each PE adds 1 cycle                   |
| Weight pass-through (per PE)      | 1              | Each PE adds 1 cycle                   |
| Systolic array diagonal latency   | 7              | 4 rows + 4 cols - 1                    |
| Input skewing (row 3)             | 3              | systolic_wrapper cascade               |
| Output deskewing (col 0)          | 3              | systolic_wrapper cascade               |

---

## OpenLane Hardening

### Configuration

```
Design: project_macro
Clock:  50 ns (20 MHz)
Die:    880 x 1031.66 um
PDK:    sky130
Corner: max_ss_100C_1v60 (default)
```

### Timing Summary (all corners)

| Corner           | Hold Slack | Setup Slack | Violations |
| ---------------- | ---------- | ----------- | ---------- |
| nom_tt_025C_1v80 | 0.4902     | 11.7779     | 0          |
| nom_ss_100C_1v60 | 0.3320     | 9.9435      | 0          |
| nom_ff_n40C_1v95 | 0.2855     | 12.5409     | 0          |
| min_tt_025C_1v80 | 0.5046     | 11.8354     | 0          |
| min_ss_100C_1v60 | 0.3882     | 10.0250     | 0          |
| min_ff_n40C_1v95 | 0.2842     | 12.5815     | 0          |
| max_tt_025C_1v80 | 0.4437     | 11.7071     | 0          |
| max_ss_100C_1v60 | 0.2645     | 9.8428      | 0          |
| max_ff_n40C_1v95 | 0.2809     | 12.4892     | 0          |

All corners: zero violations for hold, setup, max capacitance, and max slew.

### SDC Constraints

- Clock uncertainty: 0.1 ns
- Clock source latency: 0.32 ns (min) / 4.48 ns (max)
- Max transition: 0.75 ns
- Max fanout: 20
- Timing derates: 0.93 (early) / 1.07 (late) -- 7% PVT variation
- Input delay: 8.90 ns max / 5.20 ns min
- Output delay: 31.71 ns max / 24.72 ns min (includes 22.0 ns external delay)
- False path: reset_n, por_n

---

## Data Format

### Memory layout

Each memory word is 64 bits (8 bytes). The systolic wrapper packs four 16-bit values per word:

```
data_mem[r] = {row[r][3], row[r][2], row[r][1], row[r][0]}  // 4x16-bit
```

Each 16-bit value is sign-extended from 8-bit INT8:

```
16-bit = {8{byte[7]}, byte[7:0]}  // sign extension
```

### Weight loading order

Weights are loaded into weight_mem[0..3], then read sequentially during LOAD_WEIGHTS state. Due to the systolic array's vertical weight propagation:

- weight_mem[0] shifts down to PE row 3
- weight_mem[1] shifts down to PE row 2
- weight_mem[2] shifts down to PE row 1
- weight_mem[3] stays at PE row 0

### Example: Identity matrix multiplication

Data matrix A:

```
Row 0: [1, 2, 3, 4]
Row 1: [2, 3, 4, 5]
Row 2: [3, 4, 5, 6]
Row 3: [4, 5, 6, 7]
```

Weight matrix B (identity):

```
[1, 0, 0, 0]
[0, 1, 0, 0]
[0, 0, 1, 0]
[0, 0, 0, 1]
```

Expected result C = A \* B = A (identity property).

See `test/project_macro_tb.v` for the complete test sequence.

---

## Flaws and Limitations

### Remnants of an Older Design

These are artifacts inherited from previous design iterations that were never fully cleaned up.

#### Address Width Mismatch

The SPI protocol and wrapper interface use 8-bit addresses, but all three DFFRAM memories contain only 32 entries (requiring 5 bits). The wrapper silently slices the lower 5 bits (`ext_data_addr[4:0]`), meaning addresses 32-255 alias to 0-31. This is a workaround for LibreLane crashes when instantiating memories larger than 32 words, not an intentional design choice. It creates a silent bug risk: writing to address 0x20 will overwrite address 0x00 with no warning.

#### 16-Bit Wires Carrying 8-Bit Data

The systolic array interface uses 64-bit buses packed as four 16-bit values, but only the lower 8 bits of each lane carry meaningful data. In `systolic.v` line 45:

```verilog
assign pe_activation_in = {{8{sys_data_in[i*16+7]}}, sys_data_in[i*16 +: 8]};
```

This takes bit 7 (the MSB of the lower byte) and sign-extends it to fill the upper 8 bits, discarding whatever was already in bits 15:8 of the input. The same pattern applies to weights on line 54. This wastes 50% of bus bandwidth, 50% of register storage in the skew/deskew pipeline, and makes the 16-bit interface misleading -- the PE's `activation_in` and `weight_in` ports are declared as 16-bit but only carry 8-bit data. The upper byte is always sign-extension of the lower byte's MSB, so the effective precision is INT8 throughout despite the INT16 wire widths.

#### Hardcoded Dead Inputs

The systolic array declares `ub_rd_col_size_in[15:0]` and `ub_rd_col_size_valid_in` as inputs, but the wrapper hardwires them to `16'd4` and `1'b1` respectively. These ports serve no purpose in the current design; they were intentionally added to an older module design that was originally intended to support variable column sizing, which was never implemented in the wrapper.

#### Unused Overflow Detection

Each PE computes `mult_overflow` and `add_overflow` flags with a sticky `overflow_reg`, but the systolic array discards them entirely (`overflow_out()` tied to nothing). For a production design, accumulated overflow should be readable by the controller to detect saturation.

#### Unused Valid Deskewing Registers

The wrapper declares `valid_deskew_0` through `valid_deskew_3` as a 4-stage shift register chain, but only `sys_valid_out[3]` is used directly as `deskewed_valid`. The deskewed valid shift register chain is never read -- dead logic that consumes flops.

#### No Backpressure or Flow Control

The wrapper has no mechanism to signal when the output memory is full or when results are ready beyond the single-cycle `done` pulse. If the external controller misses the `done` signal, there is no way to detect completion. The `busy` signal only indicates the FSM is running, not that results are available.

### Active Design Limitations

Inherent to the current architecture and its implementation choices.

#### Excessive Control Overhead

The FSM introduces significant overhead relative to the actual computation. For a 4x4 multiply with `data_len=4`:

| Phase          | Cycles | Notes                            |
| -------------- | ------ | -------------------------------- |
| LOAD_WEIGHTS   | 6      | Reads 4 weight rows              |
| SWITCH_WEIGHTS | 1      | Pulse switch                     |
| PROCESS_DATA   | 10     | Stream 4 inputs + 6 drain cycles |
| WAIT_OUTPUT    | 21     | Fixed flush period               |
| DONE           | 1      | Set flag                         |
| **FSM total**  | **39** | For 16 MAC operations            |

Adding SPI transfer time (using K as defined above):

- 8 SPI writes (4 data + 4 weights) at 80 bits each: 640 × K cycles
- 1 SPI start at 8 bits: 8 × K cycles
- 4 SPI reads at 80 bits each: 320 × K cycles
- **SPI total**: 968 × K cycles

At 10 MHz SPI on the 20 MHz chip (K=2): 1936 + 39 = **~1975 clock cycles** (~99 µs). In the testbench (K=4): ~3911 cycles. The FSM overhead alone (39 cycles) exceeds the systolic array's actual compute time. The WAIT_OUTPUT state uses a hardcoded 21-cycle flush regardless of actual data volume, and the 6 drain cycles in PROCESS_DATA are also fixed.

Additionally, the `data_len` parameter (set in `simple_spi.v` at reset, hardcoded to 4) is never modified by any SPI command. This means the number of streamed rows cannot be configured at runtime, locking the design to a fixed matrix width despite the parameterized interface suggesting otherwise.

#### Significant Unused Timing Margin

The hardened macro has substantial positive slack across all PVT corners:

| Corner                   | Setup Slack | Implied Max Frequency |
| ------------------------ | ----------- | --------------------- |
| nom_tt_025C_1v80         | 11.78 ns    | ~26.5 MHz             |
| max_ss_100C_1v60 (worst) | 9.84 ns     | ~24.8 MHz             |
| nom_ff_n40C_1v95         | 12.54 ns    | ~27.3 MHz             |

The design runs at 20 MHz (50 ns period) but the worst-case critical path is only ~40 ns. This represents approximately 20% unused frequency headroom. The design could be retimed for 25 MHz, or pushed further with targeted pipelining of the PE multiply-add path.

#### Weight Passthrough Zeros on Non-Accept

In the PE, `weight_out` is set to `weight_in` only when `accept_w_in=1`, otherwise it is zeroed (line 111 of `pe.v`). This means weights cannot pass through a row without being loaded into its shadow register. This works for the current sequential loading pattern but prevents any form of weight bypass or partial loading.

#### Behavioral Memory Model

The DFFRAM uses a behavioral `reg` array (`reg [(WSIZE*8-1):0] mem [0:WORDS-1]`), which synthesizes to individual flip-flops. For 3 memories of 32 words x 8 bytes, this is 768 flip-flops -- substantial area that could be replaced with SRAM macros in a production flow. The behavioral model also means area and power estimates from synthesis may not reflect physical reality.

#### Insufficient Timing and Delay Verification in Testing

The testbenches exercise functional correctness but do not rigorously validate the timing relationships between modules. The skew/deskew pipeline, the FSM state transitions, and the SPI-to-wrapper handoff all depend on precise cycle counts, yet the tests use large fixed delays (`#15000` in `project_macro_tb.v`, `#200` in `systolic_wrapper_tb.v`) that mask timing-sensitive bugs. No test verifies:

- That the 3-cycle input skew and 3-cycle output deskew correctly realign data for different data lengths
- That the WAIT_OUTPUT 21-cycle flush is the minimum required (not too short or too long)
- That the 6 drain cycles in PROCESS_DATA are correctly sized for the systolic pipeline depth
- Boundary conditions where `data_len` is 1 or very large
- That results arrive in the correct output memory address when `data_len` does not match the array width

A comprehensive timing verification would sweep `data_len` across its full range, verify output alignment cycle-by-cycle, and use assertions or formal verification to validate timing relationships rather than fixed delays.
