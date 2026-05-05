# NeuralTram: SPI-Controlled Systolic Array on OpenFrame

**Target**: SkyWater 130nm (sky130), OpenFrame multi-project
**Clock**: 20 MHz (50 ns period)
**Array**: 4x4 weight-stationary systolic array, INT8 multiply-accumulate
**Interface**: SPI slave over GPIO pins

---

## Overview

NeuralTram is a complete matrix multiplication accelerator hardened for the OpenFrame chip flow. It receives data and weights over SPI, stores them in DFFRAM memories, runs a 4x4 systolic array computation, and makes results available for SPI readout -- all controlled through a simple command protocol.

The top-level module (`project_macro`) conforms to the OpenFrame project_macro template, mapping SPI signals to the top GPIO edge and leaving bottom/right GPIOs as safe defaults.

---

## Quick Start

### Simulation

```bash
# Compile and run the full top-level testbench
iverilog -g2005-sv -o project_macro_tb.vvp \
  src/project_macro.v src/simple_spi.v src/systolic_wrapper.v \
  src/systolic.v src/pe.v src/dffram_rtl.v src/fixedpoint_simple.v \
  test/project_macro_tb.v

vvp project_macro_tb.vvp
```

The testbench (`test/project_macro_tb.v`) demonstrates the complete flow:

1. Load a 4x4 data matrix via SPI write commands (cmd 0x01)
2. Load a 4x4 weight matrix via SPI write commands (cmd 0x02)
3. Start computation via SPI start command (cmd 0x04)
4. Read results via SPI read commands (cmd 0x03)

### Hardware Test (Arduino)

After fabrication, an Arduino can communicate with the chip over SPI. See `arduino/` for the test sketch and wiring instructions.

### Unit Testbenches

The testbench (`test/project_macro_tb.v`) demonstrates the complete flow:

| Testbench                    | What it tests                                                      |
| ---------------------------- | ------------------------------------------------------------------ |
| `test/pe_tb.v`               | Single PE: MAC, weight loading, switching, overflow, disabled mode |
| `test/systolic_tb.v`         | Systolic array: weight loading, activation streaming, dataflow     |
| `test/systolic_wrapper_tb.v` | Wrapper: memory MUX, FSM, skew/deskew, output collection           |
| `test/project_macro_tb.v`    | Full system: SPI -> memories -> systolic -> output readback        |

---

## SPI Protocol

All communication happens through 4 GPIO pins on the top edge:

| GPIO       | Signal | Direction          |
| ---------- | ------ | ------------------ |
| top_in[0]  | CS_N   | Input (active low) |
| top_in[1]  | SCLK   | Input              |
| top_in[2]  | MOSI   | Input              |
| top_out[3] | MISO   | Output             |

### Commands

All commands are MSB-first, bit-serial over SPI.

| Command | Name         | Sequence                    | Response                            |
| ------- | ------------ | --------------------------- | ----------------------------------- |
| `0x01`  | Write Data   | CMD(8) + ADDR(8) + DATA(64) | None                                |
| `0x02`  | Write Weight | CMD(8) + ADDR(8) + DATA(64) | None                                |
| `0x03`  | Read Output  | CMD(8) + ADDR(8)            | 64-bit data on MISO                 |
| `0x04`  | Start        | CMD(8)                      | None (triggers computation)         |
| `0x05`  | Read Status  | CMD(8)                      | {busy[63], done[62], 62'b0} on MISO |

Write enable (`data_we`, `weight_we`) and `start` signals are generated as single-cycle pulses and auto-cleared. The wrapper ignores external writes while `busy=1`.

---

## Usage Flow

A complete multiply-accumulate operation: load data, load weights, start computation, read results. All communication is SPI byte sequences.

### SPI Helpers

Two primitives cover all interaction:

```
write_spi(cmd, addr, data64)
  → Pulls CS_N low, sends 10 bytes (cmd + addr + 8-byte data), releases CS_N

read_spi(cmd, addr) → data64
  → Pulls CS_N low, sends 2 bytes (cmd + addr), clocks out 8 bytes on MISO, releases CS_N

start_spi()
  → Pulls CS_N low, sends 1 byte (0x04), releases CS_N
```

### Example: 4x4 Identity Multiplication

**Input data** (row-major, each 64-bit word packs four 16-bit sign-extended values):

```
Row 0: [1, 2, 3, 4]  →  0x0001_0002_0003_0004
Row 1: [2, 3, 4, 5]  →  0x0002_0003_0004_0005
Row 2: [3, 4, 5, 6]  →  0x0003_0004_0005_0006
Row 3: [4, 5, 6, 7]  →  0x0004_0005_0006_0007
```

**Weights** (identity matrix, loaded in reverse order -- address 0 reaches PE row 3):

```
Addr 0 → PE row 3: [1, 0, 0, 0]  →  0x0001_0000_0000_0000
Addr 1 → PE row 2: [0, 1, 0, 0]  →  0x0000_0001_0000_0000
Addr 2 → PE row 1: [0, 0, 1, 0]  →  0x0000_0000_0001_0000
Addr 3 → PE row 0: [0, 0, 0, 1]  →  0x0000_0000_0000_0001
```

**Expected result** (A x I = A):

```
Out[0] = 0x0001_0002_0003_0004
Out[1] = 0x0002_0003_0004_0005
Out[2] = 0x0003_0004_0005_0006
Out[3] = 0x0004_0005_0006_0007
```

### Operation Trace

```
# 1. Load data matrix into data_mem
write_spi(0x01, 0x00, 0x0001000200030004)   # data_mem[0] ← Row 0
write_spi(0x01, 0x01, 0x0002000300040005)   # data_mem[1] ← Row 1
write_spi(0x01, 0x02, 0x0003000400050006)   # data_mem[2] ← Row 2
write_spi(0x01, 0x03, 0x0004000500060007)   # data_mem[3] ← Row 3

# 2. Load weight matrix into weight_mem
write_spi(0x02, 0x00, 0x0001000000000000)   # weight_mem[0] → PE row 3
write_spi(0x02, 0x01, 0x0000000100000000)   # weight_mem[1] → PE row 2
write_spi(0x02, 0x02, 0x0000000000010000)   # weight_mem[2] → PE row 1
write_spi(0x02, 0x03, 0x0000000000000001)   # weight_mem[3] → PE row 0

# 3. Start computation
#    FSM runs: LOAD_WEIGHTS(6) → SWITCH_WEIGHTS(1) → PROCESS_DATA(10)
#              → WAIT_OUTPUT(21) → DONE(1) = 39 cycles minimum
start_spi()
#    Wait ≥ 60 clock cycles after CS_N release

# 4. Read output matrix from output_mem
read_spi(0x03, 0x00)   # → 0x0001000200030004  ✓
read_spi(0x03, 0x01)   # → 0x0002000300040005  ✓
read_spi(0x03, 0x02)   # → 0x0003000400050006  ✓
read_spi(0x03, 0x03)   # → 0x0004000500060007  ✓
```

### Byte-Level Wire Traces

**Write** (`write_spi(0x01, 0x00, 0x0001000200030004)`):

```
CS_N ↓ | 01 00 00 01 00 02 00 03 00 04 | CS_N ↑
         ^  ^  ^-------------------^
         |  |  64-bit data: {8'b0, 0x01, 8'b0, 0x02, 8'b0, 0x03, 8'b0, 0x04}
         |  8-bit address: 0x00
         8-bit command: 0x01  (write data)
```

**Read** (`read_spi(0x03, 0x00)`):

```
CS_N ↓ | 03 00 | XX XX XX XX XX XX XX XX | CS_N ↑
         ^  ^    ^-------------------^
         |  |    64-bit result shifted out on MISO (MSB first)
         |  address: 0x00
         command: 0x03  (read output)
```

### Timing

SPI timing depends on the ratio between the chip's internal clock (20 MHz, 50 ns period) and the external SPI master's SCLK rate. Define **K** as the number of chip clock cycles per SCLK bit:

```
K = ceil(SCLK_period / 50 ns)
```

| Phase               | SPI cost (clock cycles) | FSM cost (cycles) | Notes             |
| ------------------- | ----------------------- | ----------------- | ----------------- |
| Write 4 data rows   | 320 × K                 | --                | 80 bits per write |
| Write 4 weight rows | 320 × K                 | --                | Same              |
| Start command       | 8 × K                   | --                | 8 bits            |
| --                  | --                      | 39                | FSM execution     |
| Read 4 output rows  | 320 × K                 | --                | 80 bits per read  |
| **Total**           | **968 × K**             | **39**            |                   |

**Example**: at 10 MHz SPI (100 ns/bit) on the hardened chip, K=2. Total: 1936 + 39 = 1975 cycles = 98.8 µs. In the testbench (100 MHz internal, 25 MHz SCLK), K=4 and the total is ~3911 cycles. The FSM compute itself takes 39 cycles (~2 µs); SPI transfer dominates.

---

## Directory Structure

```
NeuralTram/
|-- src/
|   |-- project_macro.v        # OpenFrame top-level wrapper
|   |-- simple_spi.v           # SPI slave command decoder
|   |-- systolic_wrapper.v     # FSM controller + DFFRAM + skew logic
|   |-- systolic.v             # 4x4 systolic array
|   |-- pe.v                   # Processing element (MAC cell)
|   |-- dffram_rtl.v           # Behavioral DFFRAM model
|   |-- fixedpoint_simple.v    # Fixed-point primitives (reference)
|   +-- openlane/
|       |-- config.json        # OpenLane configuration
|       |-- summary.rpt        # Timing summary report
|       +-- constraints/       # SDC timing constraints
+-- test/
    |-- project_macro_tb.v     # Full system testbench
    |-- systolic_wrapper_tb.v  # Wrapper integration test
    |-- systolic_tb.v          # Systolic array test
    |-- systolic_comprehensive_tb.v
    |-- systolic_complex_tb.v
    +-- pe_tb.v                # PE unit test
```

---

## OpenLane Results

Hardened as `project_macro` on sky130, 50 ns clock, 880x1032 um die area.

| Metric            | Value                   |
| ----------------- | ----------------------- |
| Worst setup slack | 9.84 ns (ss/100C/1.60V) |
| Worst hold slack  | 0.26 ns (ss/100C/1.60V) |
| Setup violations  | 0 (all 9 corners)       |
| Hold violations   | 0 (all 9 corners)       |

See `ARCHITECTURE.md` for full timing breakdown across all corners.

---

## Attribution

This project builds on two upstream open-source repositories, both under Apache License 2.0:

| Source            | Repository                                   | Files Used                                              |
| ----------------- | -------------------------------------------- | ------------------------------------------------------- |
| tiny-tpu          | https://github.com/tiny-tpu-v2/tiny-tpu      | `src/pe.v`, `src/systolic.v`, `src/fixedpoint_simple.v` |
| sky130_gen_dffram | https://github.com/shalan/sky130_gen_dffram/ | `src/dffram_rtl.v`                                      |

NeuralTram adds: `src/project_macro.v`, `src/simple_spi.v`, `src/systolic_wrapper.v`, all testbenches, and the OpenLane hardening configuration.

See `NOTICE` for full license details.
