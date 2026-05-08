# AUC OpenFrame — Participant Project Integration & Block Diagrams

> This document summarizes how individual designs are mapped to the `project_macro` GPIO ports and provides the functional block diagram for each.

## Project Overview

| Slot | Project | Repository | Description | Used I/Os |
| :---: | :--- | :--- | :--- | :--- |
| **[0,0]** | [Q-PULSE](https://github.com/ASIC-hub/si-sprint26-project-q-pulse) | si-sprint26-project-q-pulse | 1D CNN ECG arrhythmia classifier | `bot_in[1]`, `bot_out[0]` |
| **[0,1]** | [ProxCore](https://github.com/ASIC-hub/si-sprint26-project-visiontram) | si-sprint26-project-visiontram | LiDAR-based obstacle detection & emergency braking co-processor | `bot_in[3:0]`, `bot_out[5:4]` |
| **[0,2]** | [TraceGuard-X](https://github.com/ASIC-hub/si-sprint26-project-traceguard-x) | si-sprint26-project-traceguard-x | Field-programmable anomaly-detection ASIC for industrial networks | `bot_in[0]`, `bot_out[9:1]`, `rt_out[7:0]` |
| **[1,0]** | [NTT-Engine](https://github.com/ASIC-hub/si-sprint26-project-digitrons/) | si-sprint26-project-digitrons | NTT hardware accelerator for post-quantum cryptography | `bot_in[1:0]`, `bot_out[3]` |
| **[1,1]** | [NeuralTram](https://github.com/ASIC-hub/si-sprint26-project-neuraltram) | si-sprint26-project-neuraltram | 4×4 systolic array INT8 matrix multiplier | `top_in[2:0]`, `top_out[3]` |
| **[1,2]** | [Cryptic](https://github.com/ASIC-hub/si-sprint26-project-cryptic-shazli-and-malak) | si-sprint26-project-cryptic | BLAKE2s-256 single-block hash accelerator via SPI | `bot_in[2:0]`, `bot_out[3]` |
| **[2,0]** | [XtraRandom](https://github.com/ASIC-hub/si-sprint26-project-aast-26-27) | si-sprint26-project-aast-26-27 | Thermal-jitter True Random Number Generator (TRNG) | `bot_out[2:0]` |
| **[2,1]** | [I2C-UART](https://github.com/ASIC-hub/si-sprint26-project-I2C_controller) | si-sprint26-project-I2C_controller | PID temperature controller with I²C master/slave and UART | `top_in/out[0:1]`, `top_in[2]`, `top_in/out[3]`, `top_out[4]` |

---

## Table of Contents

- [Reset Architecture & Hierarchy](#reset-architecture--hierarchy)
  - [Signal Provenance & Logic Flow](#1-signal-provenance--logic-flow)
  - [Unified Reset Handling](#2-unified-reset-handling)
- [Project Slots](#project-slots)
  - [\[0,0\] Q-PULSE — ECG Arrhythmia Classifier](#00-q-pulse-ecg-arrhythmia-classifier)
  - [\[0,1\] ProxCore — Proximity Safety Co-Processor](#01-proxcore-proximity-safety-co-processor)
  - [\[0,2\] TraceGuard-X — Anomaly Detection ASIC](#02-traceguard-x-anomaly-detection-asic)
  - [\[1,0\] NTT-Engine — Number Theoretic Transform Accelerator](#10-ntt-engine-number-theoretic-transform-accelerator)
  - [\[1,1\] NeuralTram — Systolic Array](#11-neuraltram-systolic-array)
  - [\[1,2\] Cryptic — BLAKE2s Hash Accelerator](#12-cryptic-blake2s-hash-accelerator)
  - [\[2,0\] XtraRandom — Stochastic Entropy Primitive](#20-xtrarandom-stochastic-entropy-primitive)
  - [\[2,1\] I2C-UART Controller — Dual-I2C Bridge](#21-i2c-uart-controller-dual-i2c-bridge)
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

The design uses a UART-based communication bridge to feed a 1D CNN inference engine. It focuses on minimal pin usage to handle complex data (187 samples per window).

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | UART (13-bit CSR Packet Protocol) |
| `gpio_bot_in[1]` | `rx` — Input |
| `gpio_bot_out[0]` | `uart_tx_w` — Output |

#### Reset Behavior

The participant handles the reset by logically ANDing the gated `reset_n` and the global `por_n` into the core's `arst_n` signal. Additionally, a **Soft Reset** is implemented via Bit [12] of the UART packet for remote core recovery.

```verilog
// project_macro.v
.arst_n(reset_n & por_n), // Asynchronous reset for the core
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_out[0]` (TX) | `1'b0` (Output) | `3'b110` Strong push-pull | Reliable serial TX |
| `gpio_bot_in[1]` (RX) | `1'b1` (Input) | `3'b001` Input only | Serial RX |
| All unused GPIOs | — | `3'b001` Input only | Explicitly set by participant |

#### Block Diagram

> *`reset_n` is the gated system reset. `por_n` is the raw power-on reset.*

```text
           PROJECT MACRO [0,0]
        ┌──────────────────────────────────────────────────┐
        │      ┌──────────┐      ┌──────────────┐          │
bot_in[1]─────►│ UART RX  │─────►│ UART-to-AXIS │          │
        │      │ Receiver │      │    Bridge    │          │
        │      └──────────┘      └──────┬───────┘          │
        │                               │ (ECG Samples)    │
        │      ┌──────────┐      ┌──────▼───────┐          │
        │      │ UART TX  │◄─────│   TinyECG    │          │
bot_out[0]◄────┤  Bridge  │◄─────│ (1D CNN Core)│          │
        │      └──────────┘      └──────────────┘          │
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

### [1,0] NTT-Engine — Number Theoretic Transform Accelerator

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
           PROJECT MACRO [1,0]
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

### [1,1] NeuralTram — Systolic Array

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
           PROJECT MACRO [1,1]
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

### [2,0] XtraRandom — Stochastic Entropy Primitive

A True Random Number Generator (TRNG) utilizing thermal jitter to produce a multi-bit stochastic stream. The design is protocol-less and configured for continuous operation.

#### Interface & GPIO Mapping

| Property | Value |
| :--- | :--- |
| **Interface** | Clock-driven synchronous (Protocol-Less) |
| `gpio_bot_out[0]` | `q1` — Output (Entropy bit 0) |
| `gpio_bot_out[1]` | `q2` — Output (Entropy bit 1) |
| `gpio_bot_out[2]` | `q3` — Output (Entropy bit 2) |

#### Reset Behavior

In the current RTL implementation, the TRNG core is "always ON" (`en=1'b1`) and does not utilize the gated `reset_n` or `por_n` signals for its internal logic.

```verilog
// project_macro.v
wire en = 1'b1; // Always enabled
u_trng (.clk(clk), .en(en), ...);
```

#### Drive Modes & OEB Control

| Signal | OEB | Drive Mode | Notes |
| :--- | :--- | :--- | :--- |
| `gpio_bot_oeb[2:0]` | `3'b000` (All outputs) | `3'b110` Strong push-pull | Ensures clear signal transitions and stochastic integrity |
| All other bottom GPIOs | High-impedance | — | — |

#### Block Diagram

```text
           PROJECT MACRO [2,0]
        ┌──────────────────────────────────────────────────────────────┐
        │                                                              │
        │                        ┌──────────────────┐                  │
        │                        │     trng_top     │                  │
        │                        │     (u_trng)     │                  │
  CLK ──┼───────────────────────►│                  ├───► bot_out[0] (q1)
        │                        │                  ├───► bot_out[1] (q2)
        │         1'b1 (en) ────►│                  ├───► bot_out[2] (q3)
        │                        └──────────────────┘                  │
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

## Summary Table for Integration

| Project Slot | Logic Type | Primary Bank | Communication | Key Feature |
| :---: | :--- | :---: | :--- | :--- |
| **[0,0]** | 1D CNN | Bottom | UART | ECG Arrhythmia Classifier |
| **[0,1]** | FIR Filter | Bottom | UART + SPI | Proximity Safety Co-Processor |
| **[0,2]** | Aho-Corasick | Bottom + Right | UART + Parallel | Anomaly Detection ASIC |
| **[1,0]** | NTT Engine | Bottom | SPI Slave | Lattice-Based Cryptography |
| **[1,1]** | Systolic Array | Top | SPI Slave | INT8 Matrix Multiplier |
| **[1,2]** | BLAKE2s Hash | Bottom | SPI Slave | Cryptographic Accelerator |
| **[2,0]** | TRNG | Bottom | Protocol-Less | Stochastic Entropy Primitive |
| **[2,1]** | I2C Bridge | Top | I2C + UART | Dual-I2C Controller |
