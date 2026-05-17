# AUC OpenFrame — Participant Project Integration & Block Diagrams

> This document summarizes how individual designs are mapped to the `project_macro` GPIO ports and provides the functional block diagram for each.

## Project Overview

| Slot | Project | Repository | Description | Used I/Os |
| :---: | :--- | :--- | :--- | :--- |
| **[0,0]** | [Q-PULSE](https://github.com/ASIC-hub/si-sprint26-project-q-pulse) | si-sprint26-project-q-pulse | 1D CNN ECG arrhythmia classifier with UART control/data path and ADC preprocessing mode | `bot_in[1]`, `bot_out[0]` |
| **[0,1]** | [ProxCore](https://github.com/ASIC-hub/si-sprint26-project-visiontram) | si-sprint26-project-visiontram | LiDAR-based obstacle detection & emergency braking co-processor | `bot_in[3:0]`, `bot_out[5:4]` |
| **[0,2]** | [TraceGuard-X](https://github.com/ASIC-hub/si-sprint26-project-traceguard-x) | si-sprint26-project-traceguard-x | Field-programmable anomaly-detection ASIC for industrial networks | `bot_in[0]`, `bot_out[9:1]`, `rt_out[7:0]` |
| **[1,0]** | [HARTS](https://github.com/yomnahisham/harts) | harts | Hardware real-time scheduler with UART/APB control, external IRQs, timer, queues, and scan debug | `rt_in[2:0]`, `rt_out[5:3]`, `bot_in[7:0]` |
| **[1,1]** | [NTT-Engine](https://github.com/ASIC-hub/si-sprint26-project-digitrons/) | si-sprint26-project-digitrons | NTT hardware accelerator for post-quantum cryptography | `bot_in[1:0]`, `bot_out[3]` |
| **[1,2]** | [Cryptic](https://github.com/ASIC-hub/si-sprint26-project-cryptic-shazli-and-malak) | si-sprint26-project-cryptic | BLAKE2s-256 single-block hash accelerator via SPI | `bot_in[2:0]`, `bot_out[3]` |
| **[2,0]** | [NeuralTram](https://github.com/ASIC-hub/si-sprint26-project-neuraltram) | si-sprint26-project-neuraltram | 4x4 systolic array INT8 matrix multiplier | `top_in[2:0]`, `top_out[3]` |
| **[2,1]** | [I2C-UART](https://github.com/ASIC-hub/si-sprint26-project-I2C_controller) | si-sprint26-project-I2C_controller | PID temperature controller with I²C master/slave and UART | `top_in/out[0:1]`, `top_in[2]`, `top_in/out[3]`, `top_out[4]` |
| **[2,2]** | [Micro-TPM](https://github.com/ASIC-hub/si-sprint26-project-custom_tpm) | si-sprint26-project-custom_tpm | SPI-accessible TPM-style security processor with TRNG, PCRs, SHA-256, and HMAC | `bot_in[2:0]`, `bot_out[4:3]` |
| **[3,0]** | [AegisDSP](https://github.com/ASIC-hub/si-sprint26-project-aegisdsp) | si-sprint26-project-aegisdsp | Mixed-signal access-control ASIC with IR motion detection, I2C microphone sound detection, SPI status readout, and alarm/status GPIOs | `rt_in[2:0]`, `rt_out[8:3]`, `top_in[1:0]`, `top_in/out[3:2]` |
| **[3,1]** | [NanoNPU](https://github.com/ASIC-hub/si-sprint26-project-nanonpu) | si-sprint26-project-nanonpu | UART/APB-controlled 4x4 systolic-array neural processing unit | `bot_in[0]`, `bot_out[4:1]` |
| **[3,2]** | [Silicon-Sprint-Proj-1](https://github.com/shalan/Silicon-Sprint-Proj-1) | Silicon-Sprint-Proj-1 | USB CDC, FLL/RC oscillator, nc_sercom, and ADPoR monitor test chip | `bot_in[0,2,11]`, `bot_in/out[3:4]`, `bot_out[1,5:10,12]`, `rt_in/out[7:2]` |

---

## Table of Contents

- [Reset Architecture & Hierarchy](#reset-architecture--hierarchy)
  - [Signal Provenance & Logic Flow](#1-signal-provenance--logic-flow)
  - [Unified Reset Handling](#2-unified-reset-handling)
- [Project Slots](#project-slots)
  - [\[0,0\] Q-PULSE — ECG Arrhythmia Classifier](#00-q-pulse-ecg-arrhythmia-classifier)
  - [\[0,1\] ProxCore — Proximity Safety Co-Processor](#01-proxcore-proximity-safety-co-processor)
  - [\[0,2\] TraceGuard-X — Anomaly Detection ASIC](#02-traceguard-x-anomaly-detection-asic)
  - [\[1,0\] HARTS — Hardware Real-Time Scheduler](#10-harts--hardware-real-time-scheduler)
  - [\[1,1\] NTT-Engine — Number Theoretic Transform Accelerator](#11-ntt-engine-number-theoretic-transform-accelerator)
  - [\[1,2\] Cryptic — BLAKE2s Hash Accelerator](#12-cryptic-blake2s-hash-accelerator)
  - [\[2,0\] NeuralTram — Systolic Array](#20-neuraltram-systolic-array)
  - [\[2,1\] I2C-UART Controller — Dual-I2C Bridge](#21-i2c-uart-controller-dual-i2c-bridge)
  - [\[2,2\] Micro-TPM — SPI Security Processor](#22-micro-tpm--spi-security-processor)
  - [\[3,0\] AegisDSP — Access-Control Sensor Fusion ASIC](#30-aegisdsp--access-control-sensor-fusion-asic)
  - [\[3,1\] NanoNPU — Neural Processing Unit](#31-nanonpu--neural-processing-unit)
  - [\[3,2\] Silicon-Sprint-Proj-1 — USB CDC, Clock, and Serial Test Chip](#32-silicon-sprint-proj-1--usb-cdc-clock-and-serial-test-chip)
- [Summary Table for Integration](#summary-table-for-integration)

---

## Reset Architecture & Hierarchy

The design utilizes a multi-stage reset strategy to ensure reliable system startup, stable project isolation, and remote recovery capabilities.

### 1. Signal Provenance & Logic Flow

The primary reset for the `project_macro` is generated within the **Green Macro**, which acts as a dedicated isolation and clock-gating tile. The local reset signal (`proj_reset_n`) is a logical combination of the global system state and the project's activation status:

```math
\text{proj\_reset\_n} = \text{sys\_reset\_n} \mathbin{\&} \text{proj\_en}
```

| Signal | Description |
| :--- | :--- |
| `sys_reset_n` | The global asynchronous system reset. |
| `proj_en` | A control bit stored in the Green Macro's **Shadow Register**. Automatically cleared to `0` whenever **`por_n`** (Power-On Reset) is asserted, ensuring the project starts in a disabled and reset state. |

### 2. Unified Reset Handling

By utilizing the gated reset from the Green Macro, a single `reset_n` input at the project level effectively handles two critical states:

1. **Hardware Reset** — When `sys_reset_n` is pulled low.
2. **Power-On Event** — When `por_n` clears `proj_en`, forcing the project into reset regardless of the system reset state.

---

## Project Slots

---

### [0,0] Q-PULSE — ECG Arrhythmia Classifier

Q-PULSE is an ECG arrhythmia classifier built around a TinyECG 1D CNN. The current `ecg_wrapper` supports two ingestion paths: a UART packet path for CSR writes and direct sample loading, and an ADC preprocessing path through `ADC_Big_Wrap` for filtered/conditioned ECG samples. At the OpenFrame project boundary, the current `project_macro.v` still exposes only the UART RX/TX pins; the ADC-side wrapper ports (`adc_valid`, `adc_data`, `adc_ready`) are internal to `ecg_wrapper` and are not mapped to project GPIOs in this slot wrapper.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **OpenFrame Interface** | UART packet interface on bottom GPIOs |
| **Core Modes** | UART sample mode or ADC preprocessing mode, selected by CSR control bit `[0]` |
| `gpio_bot_in[1]` | `rx` — Input, host UART to Q-PULSE |
| `gpio_bot_out[0]` | `uart_tx_w` — Output, Q-PULSE UART response |
| `ecg_wrapper.adc_valid` | Core-level ADC sample-valid input, not mapped to OpenFrame GPIO |
| `ecg_wrapper.adc_data[7:0]` | Core-level ADC sample input, not mapped to OpenFrame GPIO |
| `ecg_wrapper.adc_ready` | Core-level ADC ready output, not mapped to OpenFrame GPIO |

The UART RX bridge assembles two UART bytes into one 16-bit packet. Packets with bit `[15]=1` update CSR registers; packets with bit `[15]=0` feed sample data into the CNN when UART mode is selected.

#### Reset Behavior

The project wrapper logically ANDs the gated `reset_n` and raw `por_n` before driving `ecg_wrapper.arst_n`. Inside `ecg_wrapper`, CSR control bit `[2]` provides a soft reset for the HLS core, and the ADC preprocessing path can assert `clear` on threshold alarms. The TinyECG HLS core reset is therefore gated by wrapper reset, soft reset, and ADC-clear conditions.

```verilog
// project_macro.v
.arst_n(reset_n & por_n), // Asynchronous reset for the core
```

```verilog
// ecg_wrapper.v
.ap_rst_n(arst_n & !engine_soft_reset & !clear)
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_out[0]` (TX) | `1'b0` (Output) | `3'b110` Strong push-pull | Reliable serial TX |
| `gpio_bot_in[1]` (RX) | `1'b1` (Input) | `3'b001` Input only | Serial RX |
| Bottom `[14:1]`, Right, Top | OEB=1 (Hi-Z) | `3'b001` Input only | Unused/reserved at the OpenFrame boundary |

#### Block Diagram

> *`reset_n` is the gated system reset. `por_n` is the raw power-on reset.*

```text
           PROJECT MACRO [0,0]
        ┌──────────────────────────────────────────────────┐
        │      ┌──────────┐      ┌──────────────┐          │
bot_in[1]─────►│ UART RX  │─────►│ UART-to-AXIS │          │
        │      │ Receiver │      │    Bridge    │          │
        │      └──────────┘      └──────┬───────┘          │
        │                               │ (CSR/Data)       │
        │  adc_valid/data               │                  │
        │  (not GPIO mapped) ───►┌──────▼───────┐          │
        │                        │ ADC_Big_Wrap │          │
        │                        │ preprocessing│          │
        │      ┌──────────┐      └──────┬───────┘          │
        │      │ UART TX  │◄─────┌──────▼───────┐          │
bot_out[0]◄────┤  Bridge  │◄─────│   TinyECG    │          │
        │      └──────────┘      │ (1D CNN Core)│          │
        │                        └──────────────┘          │
        └──────────────────────────────────────────────────┘
```

---

### [0,1] ProxCore — Proximity Safety Co-Processor

This project implements a real-time FIR filter and threshold comparator for LiDAR sensors. It uses a combination of UART for sensor data and SPI for runtime configuration.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | UART (LiDAR Data) + SPI (Config) |
| `gpio_bot_in[0]` | `uart_rx` — Input (LiDAR samples) |
| `gpio_bot_in[1]` | `spi_sck` — Input |
| `gpio_bot_in[2]` | `spi_cs_n` — Input |
| `gpio_bot_in[3]` | `spi_mosi` — Input |
| `gpio_bot_out[4]` | `brake_irq` — Output (Interrupt) |
| `gpio_bot_out[5]` | `dbg_filtered_valid` — Output (Debug) |

#### Reset Behavior

The participant handles the reset by utilizing the gated `reset_n` directly for the core's `rst_n` signal. This clears the FIR filter pipeline and configuration registers.

```verilog
// project_macro.v
.rst_n(reset_n),
```

#### Drive Modes & OEB Control

| Pins | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[4]` (`brake_irq`) | `1'b0` (Output) | `3'b110` Strong push-pull | Digital output |
| `gpio_bot_oeb[5]` (`dbg_filtered_valid`) | `1'b0` (Output) | `3'b110` Strong push-pull | Digital output |
| Input signals `[3:0]` (UART/SPI) | `1'b1` (Hi-Z) | `3'b001` Input | — |
| Unused GPIOs | OEB=1 (Hi-Z) | `3'b110` | **Safe Mode** — prevents contention and protects the SoC |

#### Block Diagram

```text
           PROJECT MACRO [0,1]
        ┌─────────────────────────────────────────────────────────┐
        │  ┌─────────┐      ┌──────────────┐      ┌──────────┐    │
bot_in[0]─►│ UART RX │─────►│  FIR Filter  ├─────►│ Threshold│    │
        │  └─────────┘      │   (Q10.6)    │      │ Comp     ├───► bot_out[4]
        │  ┌─────────┐      └──────┬───────┘      └────┬─────┘    │
bot_in[1:3]►│ SPI Slv │─────────────┘                   │          │
        │  └─────────┘             (Coefficients)      │          │
        └──────────────────────────────────────────────┘          │
```

---

### [0,2] TraceGuard-X — Anomaly Detection ASIC

This design is the most comprehensive in terms of GPIO usage, utilizing the Bottom bank for control/status and the Right bank for a parallel data bus.

#### Interface & GPIO Mapping

**Bottom Edge (`gpio_bot`)**

| Signal | Direction | Description |
| :--- | :--- | :--- |
| `gpio_bot_in[0]` | In | `uart_rx` — Command/Token streaming |
| `gpio_bot_out[1]` | Out | `uart_tx` — Status responses |
| `gpio_bot_out[2]` | Out | `gpio_alert` — Real-time anomaly flag |
| `gpio_bot_out[3]` | Out | `gpio_match` — Pattern match indicator |
| `gpio_bot_out[4]` | Out | `gpio_busy` — Engine processing state |
| `gpio_bot_out[5]` | Out | `gpio_ready` — Detection handshake |
| `gpio_bot_out[6]` | Out | `gpio_overflow` — SRAM capacity alert |
| `gpio_bot_out[7]` | Out | `gpio_wd_alert` — Watchdog timeout |
| `[9:8]` | Out | `gpio_mode` — Current FSM state (Idle/Learn/Detect/Build) |

**Right Edge (`gpio_rt`)**

| Signal | Direction | Description |
| :--- | :--- | :--- |
| `gpio_rt_out[7:0]` | Out | `gpio_score` — 8-bit parallel normalcy score |

#### Reset Behavior

The core utilizes the gated `reset_n` signal from the Green Macro directly for its `rst_n` input. This signal initializes the Aho-Corasick match engine, the control FSM, and the shared SRAM arbitration logic.

```verilog
// project_macro.v
.rst_n(reset_n), // Gated system reset
```

#### Drive Modes & OEB Control

| Bank | OEB Setting | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb` | `15'b11111_00_0000000_1` | `3'b110` (default) | Bit 0 → Input (UART RX); Bits 1–9 → Outputs |
| `gpio_rt_oeb` | Bits `[7:0]` enabled as outputs | `3'b110` (default) | Parallel score bus |

All active pins across both banks use `3'b110` (Strong digital push-pull) to maintain signal integrity for the UART and high-speed parallel score bus.

#### Block Diagram

```text
           PROJECT MACRO [0,2]
        ┌─────────────────────────────────────────────────────────┐
        │  ┌─────────┐      ┌──────────────┐      ┌──────────┐    │
bot_in[0]─►│ UART RX │─────►│ CMD Decoder  ├─────►│ CTRL FSM │    │
        │  └─────────┘      └──────┬───────┘      └────┬─────┘    │
        │                          │ (Tokens)          │ (Mode)   │
        │  ┌─────────┐      ┌──────▼───────┐           │          │
bot_out[1]◄┤ uart_tx  │◄─────│  AC Engine   │◄──────────┘          │
        │  └─────────┘      │(Aho-Corasick)│          GPIO FLAGS  │
        │                   └──────┬───────┘      (bot_out[2:9]) ──►
        │        ┌────────┐        │                   ▲          │
        │        │ Shared │◄───────┘      ┌────────┐   │          │
        │        │ SRAM   │               │ Score  ├───┘          │
        │        └────────┘               │ Unit   ├────────────┐ │
        │                                 └────────┘            │ │
        └───────────────────────────────────────────────────────┼─┘
                                                                │
                                                        SCORE BUS rt_out[7:0]
```

---

### [1,0] HARTS — Hardware Real-Time Scheduler

HARTS is a hardware real-time scheduling coprocessor. The host configures and queries it through a UART-to-APB bridge, while the scheduler core manages a 16-task table, ready priority queue, sleep queue, tick timer, and external interrupt handling. A scan chain exposes selected internal scheduler status for debug.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | UART/APB control + external IRQ inputs + scan debug |
| `gpio_rt_in[0]` | `uart_rx` — Input (host command stream) |
| `gpio_rt_in[1]` | `scan_en` — Input |
| `gpio_rt_in[2]` | `scan_in` — Input |
| `gpio_rt_out[3]` | `uart_tx` — Output (host response stream) |
| `gpio_rt_out[4]` | `irq_n` — Output (active-low host interrupt) |
| `gpio_rt_out[5]` | `scan_out` — Output |
| `gpio_bot_in[7:0]` | `ext_irq[7:0]` — External interrupt inputs |

The RTL instantiates `hw_scheduler_top` with `UART_DIVISOR=16'd11`, matching the wrapper comment for a 20 MHz clock and 115200 baud with 16x oversampling. The UART bridge converts host frames into APB3 accesses, which feed the HARTS APB slave and scheduler control path.

#### Reset Behavior

The wrapper passes the gated OpenFrame reset directly into the scheduler as `rst_n`. This reset initializes the UART/APB bridge, APB slave response path, control unit, timer, priority queue, sleep queue, interrupt controller, task table, and scan chain. The `por_n` input is not used directly by this project wrapper.

```verilog
// project_macro.v
hw_scheduler_top #(
    .UART_DIVISOR(16'd11)
) u_harts (
    .clk   (clk),
    .rst_n (reset_n),
    ...
);
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_rt_oeb[2:0]` (`uart_rx`, `scan_en`, `scan_in`) | `3'b111` (Inputs) | `3'b110` (default) | Host UART and scan inputs |
| `gpio_rt_oeb[5:3]` (`uart_tx`, `irq_n`, `scan_out`) | `3'b000` (Outputs) | `3'b110` Strong push-pull | UART response, host interrupt, scan output |
| `gpio_rt_oeb[8:6]` | `3'b111` (Hi-Z) | `3'b110` (default) | Unused right GPIOs |
| `gpio_bot_oeb[14:0]` | All `1'b1` (Inputs/Hi-Z) | `3'b110` (default) | Bottom `[7:0]` are `ext_irq`; `[14:8]` unused |
| `gpio_top_oeb[13:0]` | All `1'b1` (Hi-Z) | `3'b110` (default) | Top GPIOs unused |

#### Block Diagram

```text
           PROJECT MACRO [1,0]
        +------------------------------------------------------------+
        |                                                            |
rt_in[0] uart_rx  ----> uart_apb_master ---- APB ---- harts_apb_slave|
rt_out[3] uart_tx <----        |                         |           |
        |                     locked                     v           |
        |                                           control_unit      |
bot_in[7:0] ext_irq ----> interrupt_ctrl                 |           |
        |                                                |           |
        |             +----------------------------------+----+      |
        |             |                  |                    |      |
        |        priority_queue     sleep_queue             timer    |
        |             |                  |                    |      |
rt_out[4] irq_n <-----+------------------+--------------------+      |
        |                                                            |
rt_in[1] scan_en  ----+                                            |
rt_in[2] scan_in  ----+--> scan_chain --> rt_out[5] scan_out        |
        |                                                            |
        | reset_n -> rst_n for UART/APB, queues, timer, IRQ, scan    |
        +------------------------------------------------------------+
```

---

### [1,1] NTT-Engine — Number Theoretic Transform Accelerator

This project implements a hardware accelerator for the Number Theoretic Transform (NTT), a critical primitive in lattice-based cryptography. It utilizes a simplified SPI interface mapped to the Bottom GPIO bank.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | SPI Slave |
| `gpio_bot_in[0]` | `cs_n` — Input (Active Low) |
| `gpio_bot_in[1]` | `mosi` — Input (Master Out Slave In) |
| `gpio_bot_out[3]` | `miso` — Output (Master In Slave Out) |

#### Reset Behavior

The core utilizes the gated `reset_n` signal from the Green Macro. This ensures the NTT transformation state machine and internal memory pointers are initialized only when the project is active and the system reset is deasserted.

```verilog
// project_macro.v
.rst_n(reset_n), // Gated system reset
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[3]` (`miso`) | `1'b0` (Output) | `3'b110` Strong push-pull | Timing closure across orange-purple MUX tree |
| All other GPIOs (bottom, right, top) | `oeb=1` (Input) | Digital input optimized | Default |

#### Block Diagram

> ✅ **Contention Resolved:** `miso` was moved from `gpio_bot_out[0]` (conflicting with `cs_n` input) to `gpio_bot_out[3]`, eliminating the shared-pad conflict.

```text
           PROJECT MACRO [1,1]
        ┌─────────────────────────────────────────────────────────┐
        │                                                         │
        │  ┌───────────┐        ┌──────────────────────────┐      │
bot_in[0]─►│           │        │                          │      │
        │  │ SPI Slave │───────►│      NTT-Engine Core     │      │
bot_in[1]─►│ Decoder   │        │   (Butterfly + Twiddle)  │      │
        │  │           │◄───────│                          │      │
        │  └─────┬─────┘        └────────────┬─────────────┘      │
        │        │                           │                    │
bot_out[3]◄──────┘               reset_n ────┘                    │
        │                                                         │
        └─────────────────────────────────────────────────────────┘
```

---

### [1,2] Cryptic — BLAKE2s Hash Accelerator

This project implements a BLAKE2s cryptographic hash accelerator, accessed via a 4-wire SPI interface that maps to a 32-bit register file. The core performs single-block hashing.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | 4-wire SPI Slave (MSB-first, 42-bit frame, CPOL=0 CPHA=0) |
| `gpio_bot_in[0]` | `spi_sclk` — Input (SPI Clock) |
| `gpio_bot_in[1]` | `spi_cs_n` — Input (SPI Chip Select, Active Low) |
| `gpio_bot_in[2]` | `spi_mosi` — Input (SPI Master Out Slave In) |
| `gpio_bot_out[3]` | `spi_miso` — Output (SPI Master In Slave Out) |

#### SPI Frame Format

| Bits | Field | Description |
| :--- | :--- | :--- |
| `Bit[41]` | `R/nW` | `1` = Read, `0` = Write |
| `Bit[40:33]` | `address[7:0]` | Register address |
| `Bit[32:1]` | `write_data[31:0]` | Write data (ignored on reads) |
| `Bit[0]` | — | Padding bit |

#### Reset Behavior

The core utilizes the gated `reset_n` signal from the Green Macro directly. This signal clears the internal SPI state machine and the BLAKE2s register file, ensuring a clean and predictable start for hash operations.

```verilog
// project_macro.v
.reset_n(reset_n), // Gated system reset for SPI and BLAKE2s core
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[3]` (`spi_miso`) | `1'b0` (Output) | `3'b110` Strong push-pull | Explicit output enable |
| All other GPIOs (bottom, right, top) | `1'b1` (Inputs) | `3'b110` (default) | — |

#### Block Diagram

> ✅ **Contention Resolved:** `spi_miso` was moved from `gpio_bot_out[0]` (conflicting with `spi_sclk` input) to `gpio_bot_out[3]`, eliminating the shared-pad conflict.

> *`reset_n` is the gated system reset.*

```text
           PROJECT MACRO [1,2]
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
bot_in[0] (SCLK)  ──┐                                             │
bot_in[1] (CS_N)  ──┼──────┐                                      │
bot_in[2] (MOSI)  ──┼──────┼──────┐                               │
        │           ▼      ▼      ▼                               │
        │     ┌─────────────────────────┐                         │
        │     │   SPI-to-Regfile Bridge │                         │
        │     │   (42-bit frame)        │──────────┐              │
        │     └────┬───────────────▲────┘          │              │
        │          │ (cs, we, addr,│ (rdata)       │              │
        │          │  wdata)      │                │              │
        │     ┌────▼───────────────┴────┐          │              │
        │     │     blake2s_regs        │          │              │
        │     │ (BLAKE2s Hash Core)     │          │              │
        │     └────────────┬────────────┘          │              │
        │                  │ reset_n               │              │
        │                  └───────────────────────┘              │
        │                                                         │
bot_out[3] (MISO) ◄───────────────────────────────────────────────┘
        └──────────────────────────────────────────────────────────┘
```

---

### [2,0] NeuralTram — Systolic Array

The participant opted for a standardized SPI interface to communicate with a 4×4 matrix multiplier. All connections are localized on the Top edge for easy wiring.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | SPI Slave (Top Edge) |
| `gpio_top_in[0]` | `CS_N` — Input (SPI Chip Select) |
| `gpio_top_in[1]` | `SCLK` — Input (SPI Clock) |
| `gpio_top_in[2]` | `MOSI` — Input (SPI Data In) |
| `gpio_top_out[3]` | `MISO` — Output (SPI Data Out) |

#### Reset Behavior

The core utilizes the gated `reset_n` signal from the Green Macro directly. This signal clears both the SPI decoder (`u_spi`) and the systolic FSM within the wrapper (`u_wrapper`), ensuring the transformation state machine and memory pointers are initialized only when the project is active. On reset deassertion, the internal MUX defaults to "SPI Access" mode to facilitate data and weight loading.

```verilog
// project_macro.v
.rst_n(reset_n), // Gated system reset for SPI and Wrapper
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_top_oeb[3]` (`miso`) | `1'b0` (Output) | `3'b110` Strong push-pull | Consistent timing and drive strength across chip |
| `gpio_top_oeb[2:0]` (SPI bus) | `1'b1` (Inputs) | `3'b110` (default) | All top bank pins |

#### Block Diagram

```text
           PROJECT MACRO [2,0]
        ┌──────────────────────────────────────────────────────────────┐
        │                                                              │
        │  top_in[0] (CS_N)  ──┐                                       │
        │  top_in[1] (SCLK)  ──┼──────┐                                │
        │  top_in[2] (MOSI)  ──┼──────┼──────┐                         │
        │                      ▼      ▼      ▼                         │
        │                ┌─────────────────────────┐                   │
        │                │       simple_spi        │                   │
        │                │         (u_spi)         │──────────┐        │
        │                └────┬───────────────▲────┘          │        │
        │   (addr, din, we,   │               │ (dout, busy,  │        │
        │    start, config)   │               │  done)        │        │
        │                ┌────▼───────────────┴────┐          │        │
        │                │     systolic_wrapper    │          │        │
        │                │       (u_wrapper)       │          │        │
        │                └────────────┬────────────┘          │        │
        │                             │ (4x4 Matrix Op)       │        │
        │                ┌────────────▼────────────┐          │        │
        │                │      systolic_array     │          │        │
        │                └─────────────────────────┘          │        │
        │                                                     │        │
        │  top_out[3] (MISO) ◄────────────────────────────────┘        │
        │                                                              │
        └──────────────────────────────────────────────────────────────┘
```

---

### [2,1] I2C-UART Controller — Dual-I2C Bridge

This project provides a versatile communication bridge featuring an I2C Master for controlling external sensors and an I2C Slave (factory set to Address `0x55`) for interface with a host controller. It also includes a UART transmitter for telemetry output.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | I2C (Master & Slave) + UART (TX Only) |
| `gpio_top_in/out[0]` | `mst_scl` — Inout |
| `gpio_top_in/out[1]` | `mst_sda` — Inout |
| `gpio_top_in[2]` | `slv_scl` — Input Only |
| `gpio_top_in/out[3]` | `slv_sda` — Inout |
| `gpio_top_out[4]` | `uart_tx` — Output |

#### Reset Behavior

The module is initialized using the gated `reset_n` signal. This ensures that the I2C state machines and the UART baud rate generator are held in reset until the project slot is enabled via the scan chain.

```verilog
// project_macro.v
.rst_n(reset_n), // Gated system reset
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `mst_scl_t`, `mst_sda_t`, `slv_sda_t` | Dynamic | `3'b110` (default) | Dynamic control for I2C bi-directionality |
| `gpio_top_oeb[4]` (`uart_tx`) | `1'b0` (Output) | `3'b110` (default) | Fixed output enable |

#### Block Diagram

```text
           PROJECT MACRO [2,1]
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
        │  ┌────────────┐        ┌──────────────┐                  │
top[0:1]◄─►│ I2C Master │◄──────►│              │                  │
        │  └────────────┘        │              │                  │
        │  ┌────────────┐        │   chip_top   │      ┌────────┐  │
top[2]──►│  │ I2C Slave  │◄──────►│              ├─────►│UART TX ├──► top[4]
top[3]◄─►│  │ (Addr 0x55)│        │              │      └────────┘  │
        │  └────────────┘        └──────────────┘                  │
        │  top[2]: slv_scl (Input Only)                            │
        │  top[3]: slv_sda (Inout)                                 │
        └──────────────────────────────────────────────────────────┘
```

---

### [2,2] Micro-TPM — SPI Security Processor

This project implements a compact TPM-style security block exposed through a 4-wire SPI slave plus an interrupt output. The host writes TPM2 no-session command packets into a command buffer, the internal command processor executes the request, and the host reads the response buffer after `irq` asserts.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | SPI Slave (Mode 0 byte stream) + IRQ |
| `gpio_bot_in[0]` | `spi_csn` — Input (Active Low Chip Select) |
| `gpio_bot_in[1]` | `spi_sck` — Input (SPI Clock) |
| `gpio_bot_in[2]` | `spi_mosi` — Input (Host-to-TPM Data) |
| `gpio_bot_out[3]` | `spi_miso` — Output (TPM-to-Host Data) |
| `gpio_bot_out[4]` | `irq` — Output (Response Ready Interrupt) |

The SPI transaction layer uses opcode `8'hC0` for host writes into `CMD_BUF` (`0x00`-`0x7F`) and opcode `8'h40` for host reads from `RSP_BUF` (`0x80`-`0xFF`). The command processor supports `CC_GET_RANDOM`, `CC_PCR_EXTEND`, `CC_PCR_READ`, and `CC_HMAC`.

#### Reset Behavior

The wrapper connects the gated OpenFrame project reset directly to the TPM top-level active-low reset. This reset is propagated into the SPI slave, command processor, SHA-256 wrapper, TRNG, and PCR bank. It clears the SPI FSM and IRQ, returns the command processor to idle, clears TRNG state, and resets all PCR registers to zero. The shared command/response memory is initialized to zero in RTL and has no separate reset input.

```verilog
// project_macro.v
tpm_top u_tpm (
    .clk  (clk),
    .rstn (reset_n),
    ...
);
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[2:0]` (`spi_csn`, `spi_sck`, `spi_mosi`) | `3'b111` (Inputs) | `3'b110` (default) | SPI command path from host |
| `gpio_bot_oeb[3]` (`spi_miso`) | `1'b0` (Output) | `3'b110` Strong push-pull | SPI response data |
| `gpio_bot_oeb[4]` (`irq`) | `1'b0` (Output) | `3'b110` Strong push-pull | Asserted when response is ready |
| Bottom `[14:5]`, Right, Top | OEB=1 (Hi-Z) | `3'b110` (default) | Unused GPIOs tied off as inputs |

#### Block Diagram

```text
           PROJECT MACRO [2,2]
        +------------------------------------------------------------+
        |                                                            |
bot_in[0] spi_csn  ----+                                            |
bot_in[1] spi_sck  ----+--> tpm_spi_slave ---- Port A ----+         |
bot_in[2] spi_mosi ----+          |                       |         |
bot_out[3] spi_miso <--+          |                       v         |
        |                         |                tpm_mem 256B      |
        |                         |          CMD_BUF / RSP_BUF       |
bot_out[4] irq <------------------+                       ^         |
        |                         |                       |         |
        |                         +---- cmd_start ---- tpm_cmd_proc  |
        |                                                |           |
        |                         tpm_cmd_proc controls:             |
        |                           - tpm_sha256_wrap                |
        |                           - tpm_trng                       |
        |                           - tpm_pcr_bank                   |
        |                                                            |
        | reset_n -> rstn for SPI, processor, SHA, TRNG, and PCRs    |
        +------------------------------------------------------------+
```

---

### [3,0] AegisDSP — Access-Control Sensor Fusion ASIC

AegisDSP combines a 1-bit IR motion path with an I2C microphone sound detector. Either motion or sound asserts the alarm and drives the internal two-state FSM into `ALARM` for a 5-second hold interval. A lightweight SPI status stream exposes the alarm and debug flags without consuming the bottom GPIO bank.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | SPI status slave + IR input + open-drain I2C microphone bus |
| `gpio_rt_in[0]` / Caravel `gpio[15]` | `spi_sclk` — Input |
| `gpio_rt_in[1]` / Caravel `gpio[16]` | `spi_cs_n` — Input, active low |
| `gpio_rt_in[2]` / Caravel `gpio[17]` | `spi_mosi` — Input |
| `gpio_rt_out[3]` / Caravel `gpio[18]` | `spi_miso` — Output while selected, Hi-Z when `spi_cs_n=1` |
| `gpio_rt_out[4]` / Caravel `gpio[19]` | `alarm` — Output |
| `gpio_rt_out[5]` / Caravel `gpio[20]` | `motion_active` — Output |
| `gpio_rt_out[6]` / Caravel `gpio[21]` | `sound_active` — Output |
| `gpio_rt_out[7]` / Caravel `gpio[22]` | `i2c_error` — Output |
| `gpio_rt_out[8]` / Caravel `gpio[23]` | `fsm_state` — Output, `0=IDLE`, `1=ALARM` |
| `gpio_top_in[0]` / Caravel `gpio[24]` | `ir_in` — Input, 1-bit digital IR sensor |
| `gpio_top_in[1]` / Caravel `gpio[25]` | `ir_sample_valid` — Input, one-cycle strobe per IR sample |
| `gpio_top_in/out[2]` / Caravel `gpio[26]` | `mic_i2c_scl` — Bidirectional open-drain I2C SCL |
| `gpio_top_in/out[3]` / Caravel `gpio[27]` | `mic_i2c_sda` — Bidirectional open-drain I2C SDA |
| `gpio_bot[14:0]` / Caravel `gpio[14:0]` | Unused, held as high-impedance inputs |

#### Reset Behavior

The wrapper combines the gated project reset with the raw power-on reset before feeding the access-control core. This reset clears the IR filter state, I2C controller, adaptive sound detector, alarm FSM, and SPI status shift registers.

```verilog
// project_macro.v
wire macro_rst_n = reset_n & por_n;

access_control_top u_access_control_top (
    .clk   (clk),
    .rst_n (macro_rst_n),
    ...
);
```

The SPI status byte is shifted MSB-first on `gpio_rt_out[3]` when `spi_cs_n` is low:

```verilog
{3'b000, fsm_state, i2c_error, sound_active, motion_active, alarm}
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_rt_oeb[2:0]` (`spi_sclk`, `spi_cs_n`, `spi_mosi`) | `3'b111` (Inputs) | `3'b001` Input only | Host-driven SPI inputs |
| `gpio_rt_oeb[3]` (`spi_miso`) | `spi_cs_n` | `3'b110` Strong push-pull | Drives only while the SPI slave is selected |
| `gpio_rt_oeb[8:4]` (`alarm`, status flags) | `5'b00000` (Outputs) | `3'b110` Strong push-pull | Direct debug/status outputs |
| `gpio_top_oeb[1:0]` (`ir_in`, `ir_sample_valid`) | `2'b11` (Inputs) | `3'b001` Input only | Digital IR sample path |
| `gpio_top_oeb[2]` (`mic_i2c_scl`) | `mic_scl_release` | `3'b101` Open-drain | Drive low or release to external pull-up |
| `gpio_top_oeb[3]` (`mic_i2c_sda`) | `mic_sda_release` | `3'b101` Open-drain | Drive low or release to external pull-up |
| Bottom `[14:0]`, Top `[13:4]` | OEB=1 (Hi-Z) | `3'b001` Input only | Unused/reserved GPIOs |

#### Block Diagram

```text
           PROJECT MACRO [3,0]
        +------------------------------------------------------------+
        |                                                            |
top_in[0] ir_in ----------> ir_dsp_core ---- motion_active --> rt[5]|
top_in[1] sample_valid --->       |                         |       |
        |                         |                         v       |
        |                         +----------------------> alarm -> rt[4]
        |                                                   ^       |
top[2] mic_i2c_scl <----> sound_detector / I2C master -----+       |
top[3] mic_i2c_sda <----> 16-bit sound level + EMA threshold        |
        |                         |                         |       |
        |                         +---- sound_active ------> rt[6]  |
        |                         +---- i2c_error ---------> rt[7]  |
        |                                                            |
rt[0] spi_sclk ----+                                             rt[8]
rt[1] spi_cs_n ----+--> SPI status shifter <-- fsm_state ----------+
rt[2] spi_mosi ----+       status byte -> rt[3] spi_miso            |
        |                                                            |
        | macro_rst_n = reset_n & por_n                              |
        +------------------------------------------------------------+
```

---

### [3,1] NanoNPU — Neural Processing Unit

NanoNPU is a UART-controlled neural processing unit built around a 4x4 systolic array. The host accesses the design through a UART-to-APB bridge, loads instructions and data through APB-visible IMEM/DMEM windows, starts execution through a control CSR, and observes completion through status outputs and APB status registers.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | UART/APB control with status GPIO outputs |
| `gpio_bot_in[0]` | `uart_rx` — Input (host UART to NPU) |
| `gpio_bot_out[1]` | `uart_tx` — Output (NPU UART response) |
| `gpio_bot_out[2]` | `locked` — Output (UART/APB lock status) |
| `gpio_bot_out[3]` | `npu_done` — Output (NPU reached HALT) |
| `gpio_bot_out[4]` | `done_processing` — Output (instruction processing complete) |

The APB decoder exposes control and memory windows through UART commands: `0x000` controls `start_npu`, `load_imem`, `load_dmem`, and `dmem_rd_host`; `0x004` reports `npu_done` and `done_processing`; `0x100..0x17C` loads 32 IMEM words; and `0x200..0x3FC` accesses the data-memory window.

#### Reset Behavior

The OpenFrame gated reset is passed directly into `npu_system_top` as `rst_n`. This reset initializes the UART/APB bridge, APB decoder control registers, NPU control unit, systolic-array control path, pipeline state, and status signals. The `por_n` input is present on the wrapper but is not used directly by the NanoNPU RTL.

```verilog
// npu_project_macro.sv
npu_system_top u_npu_sys (
    .clk   (clk),
    .rst_n (reset_n),
    ...
);
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[0]` (`uart_rx`) | `1'b1` (Input) | `3'b001` Input only | Host UART input |
| `gpio_bot_oeb[1]` (`uart_tx`) | `1'b0` (Output) | `3'b110` Strong push-pull | UART response output |
| `gpio_bot_oeb[2]` (`locked`) | `1'b0` (Output) | `3'b110` Strong push-pull | APB bridge lock indicator |
| `gpio_bot_oeb[3]` (`npu_done`) | `1'b0` (Output) | `3'b110` Strong push-pull | NPU halt/status output |
| `gpio_bot_oeb[4]` (`done_processing`) | `1'b0` (Output) | `3'b110` Strong push-pull | Processing-complete status |
| Bottom `[14:5]`, Right, Top | OEB=1 (Hi-Z) | `3'b001` Input only | Unused GPIOs |

#### Block Diagram

```text
           PROJECT MACRO [3,1]
        +------------------------------------------------------------+
        |                                                            |
bot_in[0] uart_rx  ----> uart_apb_sys ---- APB ---- npu_apb_decoder |
bot_out[1] uart_tx <----       |                         |           |
bot_out[2] locked  <-----------+                         |           |
        |                                                v           |
        |                                            npu_top         |
        |                                      +----------------+    |
        |                                      | IMEM / DMEM    |    |
        |                                      | Control Unit   |    |
        |                                      | 4x4 SA + ReLU  |    |
        |                                      | Store Engine   |    |
        |                                      +----------------+    |
bot_out[3] npu_done        <--------------------------+              |
bot_out[4] done_processing <--------------------------+              |
        |                                                            |
        | reset_n -> rst_n for UART/APB, decoder, and NPU core       |
        +------------------------------------------------------------+
```

---

### [3,2] Silicon-Sprint-Proj-1 — USB CDC, Clock, and Serial Test Chip

This project integrates a UART-to-APB debug bridge, USB CDC data path, fractional-N DLL/FLL clocking block, two RC oscillator monitor paths, an all-digital power-on-reset monitor, and an `nc_sercom` multi-protocol serial peripheral. The copied RTL source set is the project's synthesis source list: project glue, UART/APB bridge, USB CDC core, nc_sercom RTL, and black-box stubs for the hard macros.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | UART/APB control, USB CDC, clock monitor outputs, and nc_sercom USART/SPI/I2C pads |
| `gpio_bot_in[0]` | `uart_rx` — Input (host UART to APB bridge) |
| `gpio_bot_out[1]` | `uart_tx` — Output (APB bridge UART response) |
| `gpio_bot_in[2]` | `xclk` — Input (12 MHz APB/reference clock) |
| `gpio_bot_in/out[3]` | `usb_dp` — Bidirectional USB D+ |
| `gpio_bot_in/out[4]` | `usb_dm` — Bidirectional USB D- |
| `gpio_bot_out[5]` | `usb_pu` — Output (external USB D+ pull-up enable) |
| `gpio_bot_out[6]` | `fll_mon` — Output (FLL monitor clock) |
| `gpio_bot_out[7]` | `rc16m_mon` — Output (16 MHz RC oscillator monitor) |
| `gpio_bot_out[8]` | `rc500k_mon` — Output (500 kHz RC oscillator monitor) |
| `gpio_bot_out[9]` | `usb_configured` — Output (USB CDC configured status) |
| `gpio_bot_out[10]` | `clk48m_mon` — Output (48 MHz USB clock monitor) |
| `gpio_bot_in[11]` | `ext_rst_n` — Input (external active-low reset) |
| `gpio_bot_out[12]` | `adpor_mon` — Output (all-digital PoR monitor) |
| `gpio_rt_in/out[7:2]` | `sercom_pad[5:0]` — Bidirectional nc_sercom USART/SPI/I2C pads |

#### Reset Behavior

The wrapper first combines the OpenFrame gated reset with the raw power-on reset. The external reset input on `gpio_bot_in[11]` is then synchronized into the `xclk` domain and ANDed into the local reset used by the UART/APB bridge, USB CDC path, FLL control, status logic, and nc_sercom block.

```verilog
// project_macro.v
wire sys_rst_n = reset_n & por_n;
wire rst_n = sys_rst_n & ext_rst_sync;
```

The USB CDC block also observes the APB-controlled `usb_rst_n` bit. The `por_macro` instance is self-contained and exposes only its monitor output on `gpio_bot_out[12]`.

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[0]` (`uart_rx`) | `1'b1` (Input) | `3'b001` Input only | Host UART input |
| `gpio_bot_oeb[1]` (`uart_tx`) | `1'b0` (Output) | `3'b110` Strong push-pull | UART response output |
| `gpio_bot_oeb[2]` (`xclk`) | `1'b1` (Input) | `3'b001` Input only | External 12 MHz reference/APB clock |
| `gpio_bot_oeb[3:4]` (`usb_dp`, `usb_dm`) | `~tx_en` | APB-controlled USB drive mode | Bidirectional USB data pins |
| `gpio_bot_oeb[5]` (`usb_pu`) | `~dp_pu` | APB-controlled | Enables external USB pull-up |
| `gpio_bot_oeb[6:8]` (`fll_mon`, `rc16m_mon`, `rc500k_mon`) | Inverse monitor enables | `3'b110` Strong push-pull | Clock monitor outputs |
| `gpio_bot_oeb[9]` (`usb_configured`) | `1'b0` (Output) | `3'b110` Strong push-pull | USB configured status |
| `gpio_bot_oeb[10]` (`clk48m_mon`) | `~clk48m_mon_en` | `3'b110` Strong push-pull | 48 MHz monitor output |
| `gpio_bot_oeb[11]` (`ext_rst_n`) | `1'b1` (Input) | `3'b110` | External reset input |
| `gpio_bot_oeb[12]` (`adpor_mon`) | `1'b0` (Output) | `3'b110` Strong push-pull | ADPoR monitor |
| `gpio_rt_oeb[7:2]` (`sercom_pad[5:0]`) | `~sercom_pad_oe` | `3'b110` Strong digital | Runtime-configurable serial pads |
| Bottom `[14:13]`, Right `[1:0]`, Right `[8]`, Top | OEB=1 (Hi-Z) | `3'b110` | Spares/unused |

#### Block Diagram

```text
           PROJECT MACRO [3,2]
        +----------------------------------------------------------------+
        |                                                                |
bot_in[0] uart_rx  ----> uart_apb_sys ---- APB splitter ----+           |
bot_out[1] uart_tx <----       |                            |           |
        |                      |                            v           |
bot_in[2] xclk ----------------+----> clk_ctrl / status / usb_fifo      |
        |                      |                            |           |
        |                      |                            v           |
        |          fll_top + RC oscillators ---- monitors --> bot[6:10] |
        |                                                                |
bot[3:4] usb_dp/dm <---------- usb_cdc <---------- apb_usb_fifo         |
bot_out[5] usb_pu <------------+                                         |
        |                                                                |
rt[7:2] sercom_pad[5:0] <----> nc_sercom ---- irq/status over APB       |
        |                                                                |
bot_in[11] ext_rst_n -> xclk sync -> rst_n for APB/USB/FLL/nc_sercom    |
bot_out[12] adpor_mon <------- por_macro monitor                         |
        +----------------------------------------------------------------+
```

---

## Summary Table for Integration

| Project Slot | Logic Type | Primary Bank | Communication | Key Feature |
| :---: | :--- | :---: | :--- | :--- |
| **[0,0]** | 1D CNN + ADC preprocessing | Bottom | UART; ADC mode inside wrapper | ECG arrhythmia classifier with UART control and ADC-conditioned sample path |
| **[0,1]** | FIR Filter | Bottom | UART + SPI | Proximity Safety Co-Processor |
| **[0,2]** | Aho-Corasick | Bottom + Right | UART + Parallel | Anomaly Detection ASIC |
| **[1,0]** | HARTS Scheduler | Right + Bottom | UART/APB + IRQ + Scan | Hardware Real-Time Scheduling |
| **[1,1]** | NTT Engine | Bottom | SPI Slave | Lattice-Based Cryptography |
| **[1,2]** | BLAKE2s Hash | Bottom | SPI Slave | Cryptographic Accelerator |
| **[2,0]** | Systolic Array | Top | SPI Slave | INT8 Matrix Multiplier |
| **[2,1]** | I2C Bridge | Top | I2C + UART | Dual-I2C Controller |
| **[2,2]** | Micro-TPM | Bottom | SPI Slave + IRQ | TPM-style Random, PCR, and HMAC Services |
| **[3,0]** | Sensor fusion / FSM | Right + Top | SPI status + I2C + IR GPIO | IR/microphone access-control alarm with status readout |
| **[3,1]** | NanoNPU | Bottom | UART/APB | 4x4 Systolic-Array Neural Processing Unit |
| **[3,2]** | Mixed-signal test chip | Bottom + Right | UART/APB + USB CDC + USART/SPI/I2C | FLL/RC clock monitors and serial/USB test fabric |
