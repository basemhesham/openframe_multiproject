<div align="center">

# TraceGuard-X

### Programmable Sequence-Based Anomaly Detection ASIC

**AUC Silicon Sprint — Open-Source ASIC Design**

[![Process](https://img.shields.io/badge/Process-SKY130%20Open%20PDK-blue?style=flat-square)](https://github.com/google/skywater-pdk)
[![Area](https://img.shields.io/badge/Die%20Area-0.908%20mm²-green?style=flat-square)](#physical-design-results)
[![DRC](https://img.shields.io/badge/DRC%20Errors-0-brightgreen?style=flat-square)](#physical-design-results)
[![LVS](https://img.shields.io/badge/LVS%20Errors-0-brightgreen?style=flat-square)](#physical-design-results)
[![Setup](https://img.shields.io/badge/Setup%20Violations-0-brightgreen?style=flat-square)](#timing-summary)
[![Hold](https://img.shields.io/badge/Hold%20Violations-0-brightgreen?style=flat-square)](#timing-summary)
[![Language](https://img.shields.io/badge/RTL-Verilog-orange?style=flat-square)](rtl/)
[![Flow](https://img.shields.io/badge/Flow-OpenLane%20%2F%20LibreLane-purple?style=flat-square)](pnr/)

---

> **"Teach it. Watch it. Trust it."**  
> Adaptive Pattern Learning · Real-Time Anomaly Protection · Hardware Security in Silicon

[**Omar Ahmed Fouad**](https://github.com/omar3363)  
[**Ahmed Tawfiq**](https://github.com/tawfeek202)  
[**Omar Ahmed Abdelaty**](https://github.com/OmarAhmed2772004)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Problem Statement](#problem-statement)
- [Proposed Solution](#proposed-solution)
- [Architecture Overview](#architecture-overview)
- [Module Inventory](#module-inventory)
- [Chip Interface (GPIO Map)](#chip-interface-gpio-map)
- [UART Command Protocol](#uart-command-protocol)
- [Key Features](#key-features)
- [Optimization Techniques](#optimization-techniques)
- [Example Workflow](#example-workflow)
- [Real-World Applications](#real-world-applications)
- [Physical Design Results](#physical-design-results)
- [Timing Summary](#timing-summary)
- [Power Analysis](#power-analysis)
- [Verification Summary](#verification-summary)
- [Repository Structure](#repository-structure)

---

## Overview

**TraceGuard-X** is a compact, field-programmable anomaly-detection ASIC designed to provide hardware-level security for industrial control networks and embedded edge devices. The chip sits inline between a serial data source and a host controller, continuously examining the byte-stream against a user-taught reference pattern and producing a real-time normalcy score (0–255) alongside dedicated hardware alert and match pins.

Unlike rule-based detectors compiled into fixed logic, TraceGuard-X is **runtime-programmable**: the reference pattern, detection threshold, and sliding-window size can all be reconfigured over UART without reflashing or restarting the system — making it fully field-upgradable.

The design is implemented in **Verilog**, verified with a comprehensive **SystemVerilog** testbench, and successfully taken through a complete RTL-to-GDSII physical design flow using **OpenLane / LibreLane** on the **SKY130 Open PDK**.

---

## Problem Statement

Industrial PLCs, wearable medical monitors, and IoT edge nodes share a critical vulnerability: they communicate over simple serial links using well-defined command sequences, but rely entirely on host-CPU software to detect anomalous traffic. This creates three fundamental problems:

1. **Power penalty** — An MCU must remain fully powered (milliwatts) to poll and analyze a continuous data stream, drastically reducing battery life in portable devices.
2. **CPU overhead** — Continuous pattern-matching interrupts starve the processor of cycles needed for critical control tasks.
3. **Attack surface** — Software-based intrusion detection can itself be compromised; a dedicated hardware sentinel operating below the OS layer cannot be tampered with via software.

---

## Proposed Solution

TraceGuard-X introduces a **hardware offload model** for anomaly detection:

- The host MCU performs a one-time calibration to capture the "normal" byte pattern, then programs it into TraceGuard-X over UART.
- The MCU enters deep sleep. TraceGuard-X remains awake 24/7, snooping the raw serial stream in hardware using **only micro-watts** of leakage power.
- The moment an anomaly is detected, the chip fires a hardware interrupt pin to wake the MCU — consuming full power only when there is something actionable to report.

The result: the same real-time anomaly detection coverage, at a fraction of the energy cost, with zero CPU overhead during normal operation.

---

## Architecture Overview

TraceGuard-X is organized as a **three-lane pipeline** coordinated by a central control FSM:

```
                         ┌──────────────────────────────────────────────┐
                         │              TraceGuard-X ASIC               │
                         │                                              │
 UART RX ──────────────► │  ┌──────────┐   ┌───────────┐   ┌─────────┐  │
                         │  │ uart_trx │──►│cmd_decoder│──►│ctrl_fsm │  │
 UART TX ◄───────────────│  └──────────┘   └─────┬─────┘   └────┬────┘  │
                         │                        │ (tokens)     │(mode)│
                         │              ┌─────────▼──────┐       │      │
                         │              │ sliding_window │◄──────┘      │
                         │              └───────┬────────┘              │
                         │                      │                       │
                         │              ┌───────▼────────┐              │
                         │              │ token_decoder  │ ◄─ learn_en  │
                         │              └───────┬────────┘              │
                         │                      │ (4-bit token)         │
                         │  ┌────────────┐  ┌───▼──────────┐            │
                         │  │ sram_ctrl  │  │  ac_engine   │            │
                         │  │(table build│◄─┤(match engine)│            │
                         │  │    MUX)    │  └───┬──────────┘            │
                         │  └──────┬─────┘      │ (match_count)         │
                         │         │        ┌────▼──────┐               │
                         │     ┌───▼────┐   │score_unit │               │
                         │     │  SRAM  │   └────┬──────┘               │
                         │     │256 × 8 │        │ score[7:0] + alert   │
                         │     └────────┘   ┌────▼──────┐               │
                         │                  │output_reg │──► GPIOs      │
                         │                  └───────────┘               │
                         └──────────────────────────────────────────────┘
```

All three lanes (command, training, detection) are clock-gated by the control FSM. A single top-level MUX arbitrates shared SRAM ownership between the table-builder and the match engine, eliminating the need for separate memories.

---

## Module Inventory

| Module | Role | Key Detail |
|--------|------|-----------|
| `traceguard_x` | Top-Level Wrapper | Integrates all blocks; routes shared SRAM via MUX |
| `uart_trx` | Host Gateway | Full-duplex UART · 16-deep RX/TX FIFOs · 115,200 baud |
| `cmd_decoder` | Protocol Parser | Parses 10 opcodes (0xA0–0xA9); routes commands |
| `ctrl_fsm` | Mode Controller | 4-state FSM (Idle/Learn/Detect/Building) · 16-bit PIN · watchdog |
| `sliding_window` | Pipeline Stage | Registered token hand-off; flushable on mode change |
| `token_decoder` | Compression Gate | Learns 4-bit dictionary from pattern alphabet (256→16 compression) |
| `ac_engine` | Recognition Core | Aho-Corasick walk on compiled goto-table; outputs match_count |
| `sram_ctrl` | Table Compiler | 3-phase AC build (clear → tree → BFS failure links) |
| `score_unit` | Decision Normalizer | Reciprocal-LUT scoring (0–255); threshold comparator |
| `output_reg` | GPIO Driver | 4-cycle match hold; 5-byte UART response formatter |
| `pattern_sram` | Pattern Memory | 17-word register file (valid + length + 15 chars) |
| `ram_wrapper` | Lookup Memory | 256×8 shared SRAM (goto-table during detect mode) |
| `ram_rtl` | SRAM Model | RTL model of SRAM · 1-cycle read latency |

---

## Chip Interface (GPIO Map)

### Left Edge — Clock & Reset

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `clk` | IN | 1 | System clock — 25 MHz nominal |
| `reset_n` | IN | 1 | Active-low synchronous reset |

### Bottom Edge — 15 GPIOs (Control & Status)

| Pin | Signal | Dir | Width | Description |
|-----|--------|-----|-------|-------------|
| [0] | `uart_rx` | IN | 1 | Serial data input — commands & streaming tokens |
| [1] | `uart_tx` | OUT | 1 | Serial data output — status & result frames |
| [2] | `gpio_alert` | OUT | 1 | Anomaly alert — fires when score < threshold |
| [3] | `gpio_match` | OUT | 1 | Pattern match — held 4 cycles for visibility |
| [4] | `gpio_busy` | OUT | 1 | AC engine activity indicator |
| [5] | `gpio_ready` | OUT | 1 | Detection-ready handshake |
| [6] | `gpio_overflow` | OUT | 1 | Pattern exceeds 16-state capacity |
| [7] | `gpio_wd_alert` | OUT | 1 | Watchdog timeout (255-cycle pulse) |
| [9:8] | `gpio_mode` | OUT | 2 | `00`=Idle · `01`=Learn · `10`=Detect · `11`=Building |
| [14:10] | *(reserved)* | IN | 5 | Tied off — reserved for future expansion |

### Right Edge — 9 GPIOs (Score Bus)

| Pins | Signal | Dir | Width | Description |
|------|--------|-----|-------|-------------|
| [7:0] | `gpio_score` | OUT | 8 | Live normalcy score · 255 = perfect match · 0 = anomaly |
| [8] | *(reserved)* | IN | 1 | Tied off |

### Top Edge — 14 GPIOs

All 14 pins reserved for future revisions; tied off as inputs.

---

## UART Command Protocol

All host communication follows an **opcode → length → payload** frame format. TraceGuard-X recognizes 10 opcodes in the range `0xA0`–`0xA9`. Any byte outside this range while the decoder is idle is forwarded directly to the detection pipeline as a live streaming token.

| Opcode | Mnemonic | Payload | Description |
|--------|----------|---------|-------------|
| `0xA0` | `SET_MODE` | 1 byte | `0x00` Idle · `0x01` Learn · `0x02` Detect |
| `0xA1` | `WRITE_PATTERN` | ID + N chars (≤15) | Store reference pattern in pattern memory |
| `0xA2` | `DELETE_PATTERN` | — | Invalidate the currently stored pattern |
| `0xA3` | `READ_PATTERN` | — | Read stored pattern back to host for verification |
| `0xA4` | `SET_THRESHOLD` | 1 byte (0–255) | Set anomaly threshold; default = 200 |
| `0xA5` | `SUBMIT_SEQ` | N bytes | Batch detection; returns 5-byte result frame |
| `0xA6` | `SET_PIN` | 2 bytes | Update the 16-bit unlock PIN (chip must be unlocked) |
| `0xA7` | `UNLOCK` | 2 bytes | Attempt chip unlock; factory PIN = `0xDEAD` |
| `0xA8` | `SET_WINDOW` | 1 byte (1–31) | Set sliding-window size; `0x00` → default 32 |
| `0xA9` | `GET_STATUS` | — | 5-byte status: score · mode · flags |

---

## Key Features

- **Runtime-Programmable** — Pattern, threshold, and window size all configurable over UART without silicon re-spin.
- **8-bit Normalcy Score** — Continuous 0–255 score output on dedicated GPIO bus; readable in a single parallel cycle.
- **Hardware Alert Pins** — Immediate `gpio_alert` and `gpio_match` without software in the loop.
- **XOR-Obfuscated PIN Lock** — 16-bit security lock (`0xDEAD` factory default) protects pattern writes and mode changes.
- **Watchdog Protection** — 1-second UART inactivity timeout returns chip to Idle; prevents runaway detection.
- **Field-Upgradable** — Pattern replacement is atomic; previous pattern is invalidated in a single transition.
- **Open-Source Flow** — Full RTL-to-GDSII via OpenLane/LibreLane on SKY130 PDK.

---

## Optimization Techniques

### 1 · Learnable Alphabet Compression — 93% Memory Reduction

The `token_decoder` observes every `WRITE_PATTERN` transaction and automatically assigns each unique character in the pattern a 4-bit dictionary ID. During detection, all incoming bytes are first compressed from 8 bits (256 possible symbols) to 4 bits (up to 16 unique symbols) before entering the AC engine.

| Dimension | Without Compression | With Compression | Savings |
|-----------|--------------------|-----------------:|:-------:|
| Goto-table columns | 256 | 16 | **–93.75 %** |
| SRAM depth needed | 256 × 16 = 4,096 | 16 × 16 = 256 | **–93.75 %** |

This single optimization is what makes the design viable within the 1 mm² silicon budget.

### 2 · Shared Dual-Purpose SRAM

Rather than instantiating two separate memories (one scratchpad for table build, one for runtime lookup), a single 256×8 SRAM is multiplexed at the top level. During the brief table-build phase it is owned by `sram_ctrl`; during steady-state detection it is owned by `ac_engine`. The two phases are mutually exclusive by FSM construction — zero functional penalty, half the memory area.

### 3 · Division-Free Scoring

The `score_unit` normalizes the raw match count to a 0–255 score without a hardware divider (which would cost significant area and timing margin on SKY130). A 64-entry reciprocal lookup table performs the equivalent of `score = (match_count / window_size) × 255` using only a multiply and a table read.

### 4 · FSM Clock-Gating

The control FSM issues per-block clock-enable signals (`en_sliding_win`, `en_ac_engine`, `en_score_unit`, `en_output_reg`). Unused blocks are clock-gated in every non-applicable mode, directly reducing dynamic power.

---

## Example Workflow

Below is the complete lifecycle for a typical deployment, from bench setup to real-time anomaly detection.

```
Step 1 — Unlock the chip
  Host → [0xA7][0x02][0xDE][0xAD]
  Chip ← ACK (gpio_mode transitions from locked Idle to unlocked Idle)

Step 2 — Configure detection parameters
  Host → [0xA4][0x01][0xC8]       # SET_THRESHOLD = 200/255
  Host → [0xA8][0x01][0x08]       # SET_WINDOW    = 8 tokens

Step 3 — Enter Learn mode and upload pattern
  Host → [0xA0][0x01][0x01]       # SET_MODE = LEARN
  Host → [0xA1][0x07][0x00]       # WRITE_PATTERN, ID=0, 6 chars follow
         [0x44][0x41][0x4E][0x47][0x45][0x52]  # "DANGER"
  gpio_mode → 01 (Learn)

Step 4 — Switch to Detect mode (triggers automatic table build)
  Host → [0xA0][0x01][0x02]       # SET_MODE = DETECT
  gpio_mode → 11 (Building) → 10 (Detect, gpio_ready asserts HIGH)

Step 5 — Stream live data; observe real-time response
  Host streams: D A N G E R D A N G E R ...
  → gpio_match HIGH, gpio_score = 0xFF (255), gpio_alert LOW  ✓ MATCH

  Host streams: D A X X X X ...
  → gpio_match LOW, gpio_score drops (e.g. 33), gpio_alert HIGH ✗ ANOMALY

Step 6 — Query status at any time
  Host → [0xA9][0x00]
  Chip ← [score][mode][alert][match][overflow]  (5-byte frame)

Step 7 — Re-train in the field (pattern replacement is atomic)
  Host → [0xA0][0x01][0x01]       # Back to LEARN
  Host → [0xA1] ...               # Upload new 10-character pattern
  Host → [0xA0][0x01][0x02]       # DETECT — old pattern atomically replaced
```

---

## Real-World Applications

### Industrial Predictive Maintenance
A vibration sensor on a factory motor produces a continuous raw byte stream. During commissioning, the host MCU samples a healthy vibration pattern and writes it to TraceGuard-X. The MCU then enters deep sleep. TraceGuard-X monitors the raw sensor bytes 24/7 in hardware. When a bearing begins to degrade, the pattern drifts below the threshold and `gpio_alert` fires — waking the MCU only when human intervention is required.

### Wearable ECG Monitoring
A smartwatch records a user's QRS complex (healthy heartbeat shape) during setup. This baseline is programmed into TraceGuard-X. The application MCU sleeps between alerts. TraceGuard-X performs continuous arrhythmia detection in micro-watts, extending battery life from days to weeks compared to an MCU-based polling loop.

### Post-Fabrication Validation (HIL Strategy)
Physical hardware validation will be performed via **Hardware-in-the-Loop data injection**:
- **Data sources:** MIT-BIH Arrhythmia Database (ECG) · CWRU Bearing Dataset (motor vibration)
- **Bench setup:** Python script on a laptop reads dataset CSV → converts to UART byte frames → streams to TraceGuard-X via USB-to-TTL adapter
- **Verification:** Logic analyzer on `gpio_alert` confirms correct anomaly/normal classification against known dataset ground truth

---

## Physical Design Results

Full RTL-to-GDSII flow executed with **OpenLane / LibreLane** on the **SKY130 Open PDK** (`sky130_fd_sc_hd` standard cell library).

### Die & Area

| Metric | Value |
|--------|-------|
| Die Bounding Box | 880.0 × 1031.66 µm |
| Die Area | **907,861 µm² (0.908 mm²)** |
| Core Area | 876,865 µm² |
| Core Utilization | **27.98 %** |
| Total Standard Cells | 43,531 |
| Buffers Inserted | 3,599 |
| Clock Buffers | 683 |
| Timing-Repair Buffers | 785 |
| Total Instances (incl. fill) | 222,140 |

### Signoff Checks

| Check | Result |
|-------|--------|
| DRC Errors (Magic) | **0** ✅ |
| DRC Errors (KLayout) | **0** ✅ |
| LVS Errors | **0** ✅ |
| LVS Device Mismatches | 0 |
| LVS Net Mismatches | 0 |
| GDS XOR Differences | **0** ✅ |
| Power Grid Violations (VDD) | **0** ✅ |
| Power Grid Violations (VSS) | **0** ✅ |
| Antenna Violations | **0** ✅ |
| Routing DRC Errors (final) | **0** ✅ |

---

## Timing Summary

Multi-corner STA across 9 PVT corners (nom/min/max · TT/SS/FF).

| Corner | Hold WS (ns) | Setup WS (ns) | Hold Vio | Setup Vio |
|--------|:------------:|:-------------:|:--------:|:---------:|
| **Overall Worst** | **0.064** | **8.997** | **0** ✅ | **0** ✅ |
| nom_tt_025C_1v80 | 0.243 | 11.309 | 0 | 0 |
| nom_ss_100C_1v60 | 0.157 | 9.159 | 0 | 0 |
| nom_ff_n40C_1v95 | 0.121 | 12.245 | 0 | 0 |
| min_tt_025C_1v80 | 0.243 | 11.401 | 0 | 0 |
| min_ss_100C_1v60 | 0.239 | 9.315 | 0 | 0 |
| min_ff_n40C_1v95 | 0.120 | 12.310 | 0 | 0 |
| max_tt_025C_1v80 | 0.244 | 11.207 | 0 | 0 |
| max_ss_100C_1v60 | 0.064 | 8.997 | 0 | 0 |
| max_ff_n40C_1v95 | 0.122 | 12.171 | 0 | 0 |

> **Zero setup violations and zero hold violations across all 9 PVT corners.**  
> Worst-case hold slack of **+64 ps** on the max_ss corner is positive and timing-clean.

---

## Power Analysis

Analyzed at the nominal TT / 25°C / 1.80V corner.

| Component | Power |
|-----------|------:|
| Internal (cell switching) | 4.512 mW |
| Switching (net toggling) | 1.580 mW |
| Leakage | **0.820 µW** |
| **Total** | **6.093 mW** |

IR drop (worst VDD droop): **0.115 mV** — well within PDK guidelines.

---

## Verification Summary

| Metric | Count |
|--------|------:|
| Directed test cases | **42** |
| Functional coverage groups | **14** |
| SystemVerilog Assertions (SVA) | **5** |
| Lint errors | 0 |
| Inferred latches | 0 |
| Synthesis check errors | 0 |

Key verification scenarios:
- Full unlock → learn → detect lifecycle with correct and corrupted pattern streams
- Watchdog timeout and automatic Idle recovery
- Pattern replacement atomicity (old pattern correctly invalidated)
- Overflow flag assertion on >16-state patterns
- UART frame error injection and FIFO overflow handling

---

## Repository Structure

```
traceguard-x/
│
├── README.md                          ← This file
├── .gitignore
│
├── docs/
│   ├── report/
│   │   └── TraceGuard_X_Specification_Report.pdf
│   ├── poster/
│   │   └── TraceGuard_X_Poster.png
│   └── application/
│       └── TraceGuard_X_Application_Notes.pdf
│
├── rtl/                               ← Synthesizable Verilog
│   ├── traceguard_x.v                 # Top-level integration
│   ├── uart_trx.v                     # UART transceiver
│   ├── cmd_decoder.v                  # Command parser
│   ├── ctrl_fsm.v                     # Control FSM
│   ├── sliding_window.v               # Token buffer
│   ├── token_decoder.v                # Alphabet compressor
│   ├── ac_engine.v                    # Aho-Corasick match engine
│   ├── sram_ctrl.v                    # Table builder
│   ├── score_unit.v                   # Scoring & threshold
│   ├── output_reg.v                   # GPIO driver & UART formatter
│   └── pattern_sram.v                 # Pattern register file
│   ├── ram_wrapper.v                  # RAM256_Banked wrapper (256×8, 1-bit byte-enable)
│   └── ram_rtl.v                      # SRAM model (1-cycle read latency)
│
├── tb/
│   └── tb_top_full.sv                 # Full SystemVerilog testbench
│
├── do_file/
│   └── sim_run.do                     # QuestaSim simulation script
│
│
└── pnr/
    ├── final_run/                     # OpenLane run outputs (GDS, netlists, etc.)
    └── reports/
        ├── sta_summary.rpt            # Multi-corner STA summary table
        ├── drc_magic.rpt              # Magic DRC report  (0 errors)
        ├── lvs_netgen.rpt             # Netgen LVS report (0 errors)
        └── metrics.csv                # Full OpenLane metrics (all checks)
```


<div align="center">

**TraceGuard-X · AUC Silicon Sprint · SKY130 Open PDK**

*Secure What Matters. TraceGuard-X Has Your Back.*

</div>
