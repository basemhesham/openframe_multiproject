# ProxCore

**A Runtime-Configurable Proximity Safety Co-Processor in SkyWater Sky130B**

Silicon Sprint SP26 — American University in Cairo, Cairo, Egypt

---

## Overview

ProxCore is a dedicated ASIC safety co-processor that receives distance
measurements from a UART-based LiDAR sensor, filters noise with a
16-tap symmetric FIR lowpass filter, and asserts a hardware brake
interrupt when an obstacle is detected within a configurable threshold
distance for three consecutive filtered samples.

All safety parameters — UART baud rate, braking threshold, and the
eight FIR filter coefficients — are runtime-programmable via SPI,
enabling the same silicon die to serve trams, automobiles, forklifts,
collaborative robots, industrial robot cells, and autonomous guided
vehicles without any hardware modification.

## Headline Results

| Metric | Value |
|---|---|
| Process | SkyWater Sky130 (130 nm) |
| Die area | 0.908 mm² (880 × 1031.66 µm) |
| Total power | 1.48 mW @ 25 MHz / 1.8 V |
| Standard cells | 39,480 |
| Verification | 45 directed tests, all passing |
| Signoff | Zero DRC, zero LVS, zero antenna, zero timing violations |

## Architecture

```
                                   ┌────────────────────┐
LiDAR ──► [ deserializer_gc ] ──► [ proxcore_fir_filter ] ──► [ threshold_fsm ] ──► brake_irq
              ▲                              ▲                        ▲
              │                              │                        │
              └──────────── [ config_regs_gc ] ◄──────────── SPI bus
                            baud_div    coeff0–7        threshold
```

| Module | Function |
|---|---|
| `deserializer_gc` | UART 8N1 receiver with runtime-configurable baud rate |
| `proxcore_fir_filter` | 16-tap symmetric FIR filter, 8 multipliers, 5-cycle pipeline |
| `threshold_fsm` | 3-consecutive-sample debounced threshold comparator |
| `config_regs_gc` | SPI write-only register file (10 registers, 24-bit frames) |
| `proxcore_top` | Top-level integration of all four processing blocks |
| `project_macro` | SP26 shuttle GPIO wrapper with pad configuration |

## Key Specifications

| Parameter | Value |
|---|---|
| Technology | SkyWater Sky130 (130 nm) |
| Clock frequency | 25 MHz (single domain) |
| Supply voltage | 1.8 V |
| Active GPIO pins | 6 inputs + 2 outputs (`clk`/`rst_n` provided by shuttle) |
| Baud rate range | 9,600 – 921,600 (runtime-configurable via SPI) |
| Distance range | 0 – 1023.98 m (Q10.6 unsigned, ~1.56 cm resolution) |
| FIR filter | 16-tap symmetric Hamming lowpass, Q1.15 signed coefficients |
| Filter latency | 5 clock cycles (200 ns at 25 MHz) |
| Braking decision | 3 consecutive sub-threshold filtered samples |
| Brake output | `brake_irq` held high while in BRAKING state |
| Configuration | 10 × 16-bit registers via SPI (24-bit frames, write-only) |

## SPI Register Map

| Address | Name | Default | Encoding | Description |
|---|---|---|---|---|
| 0x00 | threshold | 2,560 | Q10.6 unsigned | Braking distance threshold (40 m) |
| 0x01 | coeff0 | 112 | Q1.15 signed | FIR tap h[0], h[15] |
| 0x02 | coeff1 | 243 | Q1.15 signed | FIR tap h[1], h[14] |
| 0x03 | coeff2 | 618 | Q1.15 signed | FIR tap h[2], h[13] |
| 0x04 | coeff3 | 1,293 | Q1.15 signed | FIR tap h[3], h[12] |
| 0x05 | coeff4 | 2,217 | Q1.15 signed | FIR tap h[4], h[11] |
| 0x06 | coeff5 | 3,225 | Q1.15 signed | FIR tap h[5], h[10] |
| 0x07 | coeff6 | 4,089 | Q1.15 signed | FIR tap h[6], h[9] |
| 0x08 | coeff7 | 4,587 | Q1.15 signed | FIR tap h[7], h[8] |
| 0x09 | baud_div | 54 | Unsigned int | UART clock divider (default = 460,800 baud) |

**SPI frame format:** 24 bits, MSB first — `[addr 7:0][data 15:0]`. CPOL = 0, CPHA = 0.

## Baud Rate Configuration

| Baud Rate | baud_div @ 25 MHz | baud_div @ 50 MHz |
|---|---|---|
| 9,600 | 2,604 | 5,208 |
| 115,200 | 217 | 434 |
| 230,400 | 108 | 217 |
| 460,800 | 54 | 108 |
| 921,600 | 27 | 54 |

## Application Profiles

The same silicon serves multiple markets via SPI configuration at power-on:

| Application | Threshold | Baud Rate | baud_div @ 25 MHz | FIR Profile |
|---|---|---|---|---|
| Urban tram | 40 m (2,560) | 115,200 | 217 | Default |
| Car — city parking | 8 m (512) | 115,200 | 217 | Default |
| Car — highway FCW | 80 m (5,120) | 460,800 | 54 | Custom (light) |
| Warehouse forklift | 3 m (192) | 115,200 | 217 | Default |
| Collaborative robot | 0.5 m (32) | 460,800 | 54 | Custom (minimal) |
| Industrial robot cell | 1.5 m (96) | 230,400 | 108 | Default |
| AGV / AMR | 2 m (128) | 115,200 | 217 | Default |

> See `documentation/ProxCore Report.pdf` Section 6 for full SPI initialization sequences and custom FIR coefficient tables.

## Repository Structure

```
proxcore/
├── rtl/
│   ├── project_macro.sv           # SP26 shuttle GPIO wrapper
│   ├── proxcore_top.sv            # Top-level integration
│   ├── deserializer_gc.sv         # UART deserializer (runtime baud rate)
│   ├── proxcore_fir_filter.sv     # 16-tap symmetric FIR lowpass filter
│   ├── threshold_fsm.sv           # 3-sample debounced threshold FSM
│   └── config_regs_gc.sv          # SPI configuration registers (+baud_div)
│
├── tb/
│   ├── tb_proxcore_top.sv         # Integration testbench (7 tests)
│   ├── output_test_filter.sv      # FIR filter testbench (6 tests)
│   ├── config_regs_tb.sv          # SPI config registers testbench (14 tests)
│   ├── tb_threshold_fsm.sv        # Threshold FSM testbench (13 tests)
│   └── deserializer_tb.sv         # UART deserializer testbench (5 tests)
│
├── final/
│   ├── project_macro.gds          # Final signed-off GDSII layout
│   ├── project_macro.lef          # Abstract LEF for shuttle integration
│   └── project_macro.nl.v         # Post-synthesis gate-level netlist
│
├── metrics/
│   ├── metrics.json               # Complete OpenLane signoff metrics
│   ├── sta_summary.txt            # STA results across all PVT corners
│   ├── power_summary.txt          # Power breakdown (1.48 mW total)
│   ├── drc.magic.rpt              # Magic + KLayout DRC reports (0 errors)
│   └── lvs.netgen.rpt             # Netgen LVS report (0 mismatches)
│
├── openlane files/
│   ├── config.json                # Main OpenLane 2 flow configuration
│   ├── pnr.sdc                    # Place-and-route timing constraints
│   └── signoff.sdc                # Signoff timing constraints
│
├── documentation/
│   └── ProxCore Report.pdf        # Full design and signoff report
│
├── LICENSE                        # Apache 2.0
└── README.md                      # This file
```


## Verification Summary

**45 directed tests** across 5 testbenches covering every module
individually and the full system end-to-end.

### FIR Filter — `output_test_filter` (6 tests)

| # | Test | What It Proves |
|---|---|---|
| 1 | Edge cases (0x0000, 0x7FFF, 0x8000, 0xFFFF) | Boundary and signedness correctness |
| 2 | 200 random samples vs. golden model | Arithmetic correctness across full input range |
| 3 | DC flatness at 100 m | Unity DC gain — constant input passes through unchanged |
| 4 | Rainstorm spike rejection (alternating 2 m / 100 m) | Single-sample noise is attenuated by the lowpass response |
| 5 | Sustained 30 m input | Filter output settles to 30 m within filter latency |
| 6 | Recovery after sustained obstacle clears | Output rises back to clear-track value within filter latency |

### SPI Config Registers — `config_regs_tb` (14 tests)

| # | Test | What It Proves |
|---|---|---|
| 1 | Reset defaults | All registers initialize to correct power-on values |
| 2 | Single threshold write | Only target register changes, others untouched |
| 3 | First and last coefficient write | Address decode works at register boundaries |
| 4 | All middle coefficient writes | Full register file is writeable |
| 5 | Invalid address ignored | Out-of-range addresses silently dropped |
| 6 | Partial frame discarded by CSN | Incomplete SPI transfer does not corrupt registers |
| 7 | Full frame after partial | Receiver recovers cleanly after aborted transfer |
| 8 | Reset restores defaults after writes | Async reset overrides all SPI-written values |
| 9 | Back-to-back frames without CSN toggle | Bit counter wraps correctly at frame boundary |
| 10 | Overwrite same register twice | Last write wins — no write-once behavior |
| 11 | Maximum address 0xFF ignored | Upper address space safely rejected |
| 12 | All zeros to all registers | Zero pattern writes correctly |
| 13 | All ones to all registers | 0xFFFF pattern writes correctly |
| 14 | Final reset restores defaults | Confirms reset from all-ones state |

### Threshold FSM — `tb_threshold_fsm` (13 tests)

| # | Test | What It Proves |
|---|---|---|
| 1 | Idle — no samples | No false IRQ when `data_valid` is low |
| 2 | Clear track (10 × 100 m) | No false brake on safe distances |
| 3 | Single sub-threshold sample | 1 reading alone does not trigger |
| 4 | Two sub-threshold samples | 2 readings alone do not trigger |
| 5 | Three consecutive — enters BRAKING | 3 consecutive sub-threshold readings assert `brake_irq` |
| 6 | Debounce reset at WARN1 | One safe reading resets the warning chain |
| 7 | Debounce reset at WARN2 | Two-deep warning chain still resets on safe reading |
| 8 | `brake_irq` held in BRAKING | Output stays high while obstacle persists; no toggling |
| 9 | Recovery and re-detection | System unsticks after obstacle clears, detects again |
| 10 | Exact threshold — no fire | Value == threshold is NOT sub-threshold (`<` only) |
| 11 | One below threshold — fires | Boundary value just below threshold triggers correctly |
| 12 | `data_valid` gating | FSM frozen when `data_valid` is deasserted |
| 13 | Runtime threshold change | Raising threshold mid-operation takes effect immediately |

### UART Deserializer — `deserializer_tb` (5 tests)

| # | Test | What It Proves |
|---|---|---|
| 1 | Idle after reset | No spurious output with `rx` held high |
| 2 | Single 16-bit word | Two bytes assembled correctly (low byte first) |
| 3 | Back-to-back words | Continuous reception without dropping words |
| 4 | Glitch rejection | Short `rx` pulse rejected by start-bit midpoint check |
| 5 | Reset during partial word | Partial byte discarded, clean recovery |

### System Integration — `tb_proxcore_top` (7 tests)

| # | Test | What It Proves |
|---|---|---|
| 1 | Clear track — 100 m | No false brakes through full pipeline |
| 2 | Rainstorm spike rejection | FIR + FSM together reject alternating noise |
| 3 | 30 m obstacle detection | Real obstacle triggers brake through full pipeline |
| 4 | Recovery + re-detection | System recovers from BRAKING, detects second obstacle |
| 5 | SPI threshold reconfiguration | Runtime threshold change works end-to-end |
| 6 | Reset recovery | Full pipeline clears cleanly after async reset |
| 7 | End-to-end baud rate change via SPI | Baud rate switch from 460,800 → 115,200 through full pipeline |

## Compatible Sensors

Any UART-based LiDAR sensor with 16-bit distance output:

| Sensor | Range | Default Baud | Notes |
|---|---|---|---|
| Benewake TFmini-S | 0.1 – 12 m | 115,200 | Compact, ideal for forklift/cobot/parking |
| Benewake TF-Luna | 0.2 – 8 m | 115,200 | Small form factor, low power |
| Benewake TFmini Plus | 0.1 – 12 m | 115,200 | IP65-rated variant available, AGV-friendly |
| Benewake TF02-Pro | 0.1 – 40 m | 115,200 | Medium range, industrial cells |
| Benewake TF03 | 0.1 – 180 m | 115,200 | Long range, automotive/tram |

> **Note:** Sky130 I/O operates at 1.8 V. A 3.3 V → 1.8 V level
> shifter (e.g., TI SN74LVC1T45) is required between the sensor UART
> TX line and the chip's `uart_rx` pad. See the design report for
> wiring diagrams.

## Tools

| Purpose | Tool |
|---|---|
| HDL | SystemVerilog (IEEE 1800-2017) |
| Synthesis & PnR | Yosys + LibreLane |
| Simulation | Icarus Verilog |
| Layout / DRC | Magic, KLayout |
| LVS | Netgen |
| Waveforms | GTKWave |
| PDK | SkyWater Sky130B (open-source) |

## Authors

**Ali Shawky · Karim Khaled · Farah Moataz**
Faculty of Engineering — Ain Shams University, Cairo, Egypt

## License

This project is released under the **Apache License 2.0**. See the
[`LICENSE`](LICENSE) file for the full text.
