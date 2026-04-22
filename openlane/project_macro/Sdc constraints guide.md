# Project Macro SDC Constraints Guide

**Chip:** OpenFrame 3 × 4 Multi-Project Chip — SKY130  
**Audience:** Each student assigned a `project_macro` slot in the grid

---

## Table of Contents

1. [How the Chip Is Organised](#1-how-the-chip-is-organised)
2. [The Three Infrastructure Macros](#2-the-three-infrastructure-macros)
3. [Full Signal Paths — Where Every Delay Comes From](#3-full-signal-paths--where-every-delay-comes-from)
4. [Your Location in the Grid](#4-your-location-in-the-grid)
5. [Constraint Values](#5-constraint-values)
6. [SDC Templates](#6-sdc-templates)
7. [PnR vs. Signoff — What Changes and Why](#7-pnr-vs-signoff--what-changes-and-why)
8. [Step-by-Step Instructions](#8-step-by-step-instructions)
9. [Quick Reference Summary](#9-quick-reference-summary)

---

## 1. How the Chip Is Organised

Your design — the `project_macro` — sits inside the `openframe_project_wrapper`, which is itself the top-level chip design. Signals must travel through the wrapper's external boundary **and** through the internal infrastructure macros before they reach (or leave) your design. The constraints in your project-level SDC must account for both layers.

The chip is a **3-column × 4-row grid**. Row 0 is the bottom row, closest to the clock pad. Row 3 is the top row, farthest from the clock pad.

```
         COL 0          COL 1          COL 2
       ┌──────────┐  ┌──────────┐  ┌──────────┐
ROW 3  │ project  │  │ project  │  │ project  │   ← farthest from clock pad
       └──────────┘  └──────────┘  └──────────┘
       ┌──────────┐  ┌──────────┐  ┌──────────┐
ROW 2  │ project  │  │ project  │  │ project  │
       └──────────┘  └──────────┘  └──────────┘
       ┌──────────┐  ┌──────────┐  ┌──────────┐
ROW 1  │ project  │  │ project  │  │ project  │
       └──────────┘  └──────────┘  └──────────┘
       ┌──────────┐  ┌──────────┐  ┌──────────┐
ROW 0  │ project  │  │ project  │  │ project  │   ← closest to clock pad
       └──────────┘  └──────────┘  └──────────┘

        gpio_in[38] (sys_clk) enters from the bottom
```

---

## 2. The Three Infrastructure Macros

### 2.1 Green Macro — Clock Distribution

One green macro sits to the left of each project cell. Green macros form **independent vertical chains**, one chain per column. The bottom green macro in each column receives the system clock from `gpio_in[38]`, buffers it upward row by row, and the green macro at your row gates it through an ICG cell before delivering it to your `clk` port.

```
   gpio_in[38]   (sys_clk)
        │
        ▼  [pad input buffer, ~5.57 ns slow / 4.65 ns fast]
        │
        ▼  [Green Row 0 — clkbuf_4]        ← always traversed
        │
        ▼  [Green Row 1 — clkbuf_4]        ← traversed if row ≥ 1
        │
        ▼  [Green Row 2 — clkbuf_4]        ← traversed if row ≥ 2
        │
        ▼  [Green Row 3 — clkbuf_4 + ICG]  ← traversed if row = 3
        │
        ▼  YOUR macro   clk   port
```

Because higher rows add more buffer stages, the clock arrives later at macros in higher rows. This is why `set_clock_latency` is the **only constraint that differs between students**.

---

### 2.2 Orange Macro — GPIO Routing (3 per project cell)

Each project cell has three orange macros: one on the bottom edge, one on the right edge, and one on the top edge.

**Input direction (pad → your project):**

The orange macro receives the GPIO data from the purple macro and drives it onto your `gpio_*_in` port via a local buffer. Because the purple macro *broadcasts* the pad signal to all orange macros simultaneously, all project locations receive the signal at approximately the same absolute time — the input data does not travel through a sequential chain.

```
   Purple broadcast
        │
        ├──► [orange local buf → project_row0_col0.gpio_*_in]
        ├──► [orange local buf → project_row0_col1.gpio_*_in]
        ├──►  ...
        └──► [orange local buf → project_row3_col2.gpio_*_in]
                ↑ broadcast: all ports receive the signal at ~the same time
```

**Output direction (your project → pad):**

Your output drives an AND gate inside the orange macro that places it into a MUX chain. This chain passes through **all orange macros in the column or row** before reaching the purple macro at the chip edge, regardless of your position.

```
   YOUR gpio_*_out
        │
        ▼  [Orange sel-gate (AND2)]
        ▼  [Orange stage 0 — MUX + buf]
        ▼  [Orange stage 1 — MUX + buf]
        ▼  [Orange stage 2 — MUX + buf]
        ▼  [Purple row/col-select MUX]
        ▼  [Output buffers → wrapper gpio_out port]
```

Every output traverses the same fixed-length chain, so the output infrastructure delay is the same for all 12 project locations.

---

### 2.3 Purple Macro — Pad-to-Chip Boundary (3 on chip edges)

Three purple macros sit at the chip edges (Left, Top, Right). For inputs, the purple macro receives a raw pad signal and fans it out to all orange macros simultaneously. For outputs, it selects which project's data drives the pad.

| Caravel pad edge | GPIO range | Purple macro | Orange macro | Project port |
|:---|:---:|:---:|:---:|:---:|
| Right pads | `gpio_in[0:14]` | Right Purple | Bottom Orange | `gpio_bot_in/out` |
| Top pads | `gpio_in[15:23]` | Top Purple | Right Orange | `gpio_rt_in/out` |
| Left pads | `gpio_in[24:37]` | Left Purple | Top Orange | `gpio_top_in/out` |

---

## 3. Full Signal Paths — Where Every Delay Comes From

### 3.1 Clock Path → `set_clock_latency`

```
 ┌──────────────────────────────────────────────────────────────────┐
 │  External clock source                                t = 0 ns   │
 │       │                                                          │
 │       ▼  Board + chip pad input buffer (source latency)          │
 │       │  max = 5.57 ns  /  min = 4.65 ns                         │
 │       ▼  gpio_in[38] port (OpenFrame boundary)                   │
 │       │                                                          │
 │       ▼  Green chain (1 to 4 buffer stages)       + 1.8–5.9 ns   │
 │       │         ↑ grows with your row number                     │
 │       ▼  ICG cell in green macro                  + ~1.9 ns      │
 │                                                                  │
 │  ─────────────────────────────────────────────────────────────   │
 │       ▼  YOUR macro  clk  port         total = 7.4–11.5 ns       │
 └──────────────────────────────────────────────────────────────────┘

   set_clock_latency -source -max / -min = full measured propagation
   from the external clock source to your macro's clk port.

   → Depends on your row and column. Find your values in Section 5.1.
```

---

### 3.2 Input Data Path → `set_input_delay`

Your project macro sits inside the OpenFrame wrapper. A data signal must travel through the wrapper's external boundary **and** through the internal purple and orange infrastructure before arriving at your input port. Both layers must be reflected in `set_input_delay`.

```
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                                                                          │
 │  LAYER 1 — OpenFrame external boundary (from wrapper SDC):               │
 │                                                                          │
 │  External clock source edge (t = 0)                                      │
 │       │  [data travels a parallel path from the same reference:]         │
 │  gpio_in[N] data pad                                                     │
 │       │                                                                  │
 │       ▼  External board / PCB delay                    + 4.00 ns         │
 │       ▼  Caravel pad cell + input buffer               + 4.55 ns max     │
 │       │                                                + 1.26 ns min     │
 │       ▼  gpio_in[N] port at OpenFrame boundary         = 8.55 ns max     │
 │                                                        = 5.26 ns min     │
 │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
 │                                                                          │
 │  LAYER 2 — Internal infrastructure (measured from wrapper STA):          │
 │                                                                          │
 │       ▼  Purple macro input buffer (broadcast to all projects)           │
 │       ▼  Orange local buffer                                             │
 │                                                                          │
 │       Bottom edge (Right Purple → Bot Orange): + 6.57 ns / + 1.82 ns     │
 │       Right  edge (Top Purple  → Rt  Orange):  + 6.50 ns / + 1.94 ns     │
 │       Top    edge (Left Purple → Top Orange):  + 5.70 ns / + 0.96 ns     │
 │                                                                          │
 │  ─────────────────────────────────────────────────────────────────────── │
 │       ▼  YOUR macro  gpio_*_in  port                                     │
 │                                                                          │
 │   Total set_input_delay = Layer 1 + Layer 2  (see Section 5.2)           │
 └───────────────────────────────────────────────────────────────────────── ┘
```

> **Why does input delay not vary by row or column?**
> The data path from the external source to your input port passes through the OpenFrame boundary, then through the purple broadcast buffer, and finally through the orange local buffer. The purple macro fans out to all cells simultaneously — it is not a sequential chain. Every project cell on the same purple macro receives the signal at the same time regardless of row or column. The green chain clock latency is a completely separate parallel path and plays no part in the input delay calculation.
>
> The three edges of your project macro (bottom, right, top) connect through different purple macros at different routing distances from the chip pads, so the values differ slightly per edge, but they are the same for all 12 locations on each edge.

---

### 3.3 Output Data Path → `set_output_delay`

Data leaving your project macro must travel through the internal orange and purple infrastructure and then through the OpenFrame external boundary to reach the receiving end. Both layers are included in `set_output_delay`.

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                                                                         │
 │  YOUR macro  gpio_*_out  port                                           │
 │                                                                         │
 │  LAYER 1 — Internal infrastructure (measured from wrapper STA):         │
 │                                                                         │
 │       ▼  Orange sel-gate (AND2)                        + 0.6 ns         │
 │       ▼  Orange MUX chain (full chain traversal)       + 3.9 ns         │
 │       │  (every project traverses the same complete chain)              │
 │       ▼  Purple row/col-select MUX                     + 1.6 ns         │
 │       ▼  Output routing buffers                        + 2.7 ns         │
 │                                                       ──────────        │
 │       Subtotal (max/slow):                            ≈ 9.61 ns         │
 │       Subtotal (min/fast):                            ≈ 2.92 ns         │
 │                                                                         │
 │       ▼  gpio_out[N] port at OpenFrame boundary                         │
 │                                                                         │
 │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
 │                                                                         │
 │  LAYER 2 — OpenFrame external boundary (from wrapper SDC):              │
 │                                                                         │
 │       ▼  External board / PCB delay                    + 4.00 ns        │
 │       ▼  Receiving device setup time requirement       + 9.12 ns max    │
 │                                                         + 3.90 ns min   │
 │       ▼  External receiving end                        = 13.12 ns max   │
 │                                                          =  7.90 ns min │
 │                                                                         │
 │  ─────────────────────────────────────────────────────────────────────  │
 │   Total set_output_delay = Layer 1 + Layer 2  (see Section 5.3)         │
 └─────────────────────────────────────────────────────────────────────────┘
```

> **Why is output delay the same for all locations?**
> The orange MUX chain traversal is the same length for every project — all outputs pass through the complete chain before reaching the purple mux. The external delay at the OpenFrame boundary is also fixed. Neither depends on which row or column your project occupies.

---

## 4. Your Location in the Grid

Find your project instance name in the wrapper `config.json`. The naming convention directly tells you your row and column:

```
gen_row[0].gen_col[0].u_proj  →  Row 0, Col 0
gen_row[0].gen_col[1].u_proj  →  Row 0, Col 1
gen_row[0].gen_col[2].u_proj  →  Row 0, Col 2
gen_row[1].gen_col[0].u_proj  →  Row 1, Col 0
gen_row[1].gen_col[1].u_proj  →  Row 1, Col 1
gen_row[1].gen_col[2].u_proj  →  Row 1, Col 2
gen_row[2].gen_col[0].u_proj  →  Row 2, Col 0
gen_row[2].gen_col[1].u_proj  →  Row 2, Col 1
gen_row[2].gen_col[2].u_proj  →  Row 2, Col 2
gen_row[3].gen_col[0].u_proj  →  Row 3, Col 0
gen_row[3].gen_col[1].u_proj  →  Row 3, Col 1
gen_row[3].gen_col[2].u_proj  →  Row 3, Col 2
```

Row 0 is the bottom row, closest to `gpio_in[38]`. Row 3 is the top row.

---

## 5. Constraint Values

### 5.1 Clock Source Latency — location-specific

This is the **only constraint that differs between project macros.** The values below are the measured propagated delays from the external clock source edge to your macro's `clk` port, covering the board, the Caravel pad input buffer, the green chain, and the ICG cell.

| Grid Position | `clk_latency_max` (ns) | `clk_latency_min` (ns) |
|:---|:---:|:---:|
| Row 0, Col 0 | 7.951 | 5.501 |
| Row 0, Col 1 | 7.438 | 5.304 | 
| Row 0, Col 2 | 7.818 | 5.456 | 
| Row 1, Col 0 | 9.769 | 6.133 |
| Row 1, Col 1 | 10.268 | 6.348 | 
| Row 1, Col 2 | 10.692 | 6.490 | 
| Row 2, Col 0 | 10.305 | 6.200 |
| Row 2, Col 1 | 9.552 | 7.085 | 
| Row 2, Col 2 | 9.903 | 7.194 |
| Row 3, Col 0 | 11.267 | 6.557 | 
| Row 3, Col 1 | 10.668 | 6.408 |
| Row 3, Col 2 | 11.535 | 6.720 |

`max` = slow-slow corner, 100 °C, 1.60 V — used with `-max` in the SDC.  
`min` = fast-fast corner, −40 °C, 1.95 V — used with `-min` in the SDC.

---

### 5.2 GPIO Input Delay — same for all 12 locations, per edge

Each value is the sum of the OpenFrame external boundary delay (from the wrapper SDC) and the internal infrastructure delay (measured from the wrapper-level STA). The values are the same for all 12 project locations because the purple broadcast path is identical for every cell on the same purple macro.

**Derivation:**

| Layer | Component | Max | Min |
|:---|:---|:---:|:---:|
| OpenFrame boundary | External board | 4.00 ns | 4.00 ns |
| OpenFrame boundary | Caravel pad + buffer | 4.55 ns | 1.26 ns |
| **OpenFrame total** | | **8.55 ns** | **5.26 ns** |
| Internal infra | Purple broadcast + orange buf (bottom edge) | 6.57 ns | 1.82 ns |
| Internal infra | Purple broadcast + orange buf (right edge) | 6.50 ns | 1.94 ns |
| Internal infra | Purple broadcast + orange buf (top edge) | 5.70 ns | 0.96 ns |

**Final values to use in the SDC:**

| Project macro edge | Port | `input_delay_max` | `input_delay_min` |
|:---|:---|:---:|:---:|
| Bottom (→ Caravel right pads) | `gpio_bot_in[*]` | **15.12 ns** | **7.08 ns** |
| Right (→ Caravel top pads) | `gpio_rt_in[*]` | **15.05 ns** | **7.20 ns** |
| Top (→ Caravel left pads) | `gpio_top_in[*]` | **14.25 ns** | **6.22 ns** |

These values are the same in both `pnr.sdc` and `signoff.sdc` because the OpenFrame wrapper SDC uses the same external delay (4 ns) in both files.

---

### 5.3 GPIO Output Delay — same for all 12 locations and all edges

Each value is the sum of the internal infrastructure delay (from the project macro output port to the wrapper boundary) and the OpenFrame external boundary delay (from the wrapper SDC).

**Derivation:**

| Layer | Component | Max | Min |
|:---|:---|:---:|:---:|
| Internal infra | Orange + purple chain (all ports) | 9.61 ns | 2.92 ns |
| Internal infra | Orange + purple (oeb, +0.2 ns margin) | 9.81 ns | 2.92 ns |
| OpenFrame boundary | External board | 4.00 ns | 4.00 ns |
| OpenFrame boundary | Receiving device setup (gpio_out) | 9.12 ns | 3.90 ns |
| OpenFrame boundary | Receiving device setup (gpio_oeb) | 9.32 ns | 2.34 ns |
| **OpenFrame total (out)** | | **13.12 ns** | **7.90 ns** |
| **OpenFrame total (oeb)** | | **13.32 ns** | **6.34 ns** |

**Final values to use in the SDC:**

| Port group | `output_delay_max` | `output_delay_min` |
|:---|:---:|:---:|
| `gpio_*_out[*]` | **22.73 ns** | **10.82 ns** |
| `gpio_*_oeb[*]` | **23.13 ns** | **9.26 ns** |
| `gpio_*_dm[*]`  | **22.73 ns** | **10.82 ns** |

These values are also the same in both `pnr.sdc` and `signoff.sdc` for the same reason as the input delays.

---

## 6. SDC Templates

Copy these templates as your `pnr.sdc` and `signoff.sdc`. The **only values you need to replace** are the two `<<...>>` clock latency placeholders. All input and output delay values are already filled in and are the same for every student.

### 6.1 `pnr.sdc`

```tcl
#=============================================================
# project_macro — PnR Constraints
#
# Applies during: Synthesis → Placement → CTS → Routing
#
# All I/O delays account for two layers:
#   1. OpenFrame wrapper external boundary (board + pad delays
#      from the wrapper-level SDC, ext_delay = 4 ns)
#   2. Internal infrastructure (purple + orange macros, measured
#      from wrapper-level post-PnR STA)
#
# HOW TO USE THIS FILE:
#   1. Find your grid position in the wrapper config.json
#      (e.g. gen_row[2].gen_col[1].u_proj = Row 2, Col 1)
#   2. Look up your clock latency in Section 5.1 of the guide.
#   3. Replace the two <<...>> placeholders below.
#   4. Leave everything else unchanged.
#=============================================================

set clk_port clk

create_clock [get_ports $clk_port] \
    -name clk \
    -period $::env(CLOCK_PERIOD)

set_propagated_clock [get_clocks {clk}]

# ── Clock non-idealities (PnR — pessimistic) ──────────────
set_clock_uncertainty 0.15 [get_clocks {clk}]
set_max_transition    0.75 [current_design]
set_max_fanout        16   [current_design]

set_timing_derate -early [expr {1 - 0.07}]
set_timing_derate -late  [expr {1 + 0.07}]

# ── Clock source latency ──────────────────────────────────
# Measured propagation from the external clock source to your
# macro's clk port. Includes: board + Caravel pad buffer +
# green column chain + ICG cell.
#
# *** REPLACE WITH YOUR VALUES FROM SECTION 5.1 ***
set_clock_latency -source -max <<clk_latency_max>> [get_clocks {clk}]
set_clock_latency -source -min <<clk_latency_min>> [get_clocks {clk}]

set_input_transition 0.80 [get_ports $clk_port]

# ── Reset and POR ─────────────────────────────────────────
set_input_delay [expr {$::env(CLOCK_PERIOD) * 0.5}] \
    -clock [get_clocks {clk}] [get_ports {reset_n por_n}]

# ── GPIO input delays ─────────────────────────────────────
# Total path: external board (4 ns) + Caravel pad buffer
# (4.55/1.26 ns) + purple broadcast buffer + orange local
# buffer → YOUR gpio_*_in port.
# Values differ per edge (different purple macro distance).
# They are the same for all 12 project locations.
#
# Bottom edge (gpio_bot_in) → via Right Purple + Bottom Orange
#   max = 8.55 + 6.57 = 15.12 ns  (slow corner)
#   min = 5.26 + 1.82 =  7.08 ns  (fast corner)
set_input_delay -max 15.12 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]
set_input_delay -min 7.08 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]

# Right edge (gpio_rt_in) → via Top Purple + Right Orange
#   max = 8.55 + 6.50 = 15.05 ns
#   min = 5.26 + 1.94 =  7.20 ns
set_input_delay -max 15.05 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]
set_input_delay -min 7.20 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]

# Top edge (gpio_top_in) → via Left Purple + Top Orange
#   max = 8.55 + 5.70 = 14.25 ns
#   min = 5.26 + 0.96 =  6.22 ns
set_input_delay -max 14.25 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]
set_input_delay -min 6.22 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]

set_input_transition -max 0.38 [get_ports {gpio_bot_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_bot_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_rt_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_rt_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_top_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_top_in[*]}]

# ── GPIO output delays ────────────────────────────────────
# Total path: YOUR gpio_*_out → orange sel-gate + orange MUX
# chain (9.61 ns) + purple mux → OpenFrame gpio_out port →
# external board (4 ns) + receiving device setup (9.12 ns).
# The same for all 12 project locations and all three edges.
#
#   gpio_*_out: max = 9.61 + 13.12 = 22.73 ns
#               min = 2.92 +  7.90 = 10.82 ns
#   gpio_*_oeb: max = 9.81 + 13.32 = 23.13 ns  (+0.2 ns margin)
#               min = 2.92 +  6.34 =  9.26 ns
set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]

set_output_delay -max 23.13 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]
set_output_delay -min 9.26 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]

set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]

set_load 0.19 [all_outputs]
```

---

### 6.2 `signoff.sdc`

```tcl
#=============================================================
# project_macro — Signoff Constraints
#
# Applies at: OpenROAD.STAPostPNR (after SPEF extraction)
#
# I/O delays are identical to pnr.sdc because both the OpenFrame
# wrapper SDC and the internal infrastructure measurements use
# the same external delay value (4 ns) in both files.
#
# What changes vs. pnr.sdc:
#   - clock_uncertainty  0.10 ns  (pnr: 0.15 ns)
#   - timing_derate      ±5 %     (pnr: ±7 %)
#   - max_transition     1.50 ns  (pnr: 0.75 ns)
#
# HOW TO USE: replace only the two <<...>> clock latency
# placeholders with your values from Section 5.1.
#=============================================================

set clk_port clk

create_clock [get_ports $clk_port] \
    -name clk \
    -period $::env(CLOCK_PERIOD)

set_propagated_clock [get_clocks {clk}]

# ── Clock non-idealities (signoff — relaxed) ──────────────
set_clock_uncertainty 0.10 [get_clocks {clk}]
set_max_transition    1.50 [current_design]
set_max_fanout        16   [current_design]

set_timing_derate -early [expr {1 - 0.05}]
set_timing_derate -late  [expr {1 + 0.05}]

# ── Clock source latency ──────────────────────────────────
# Identical to pnr.sdc — physical measurement, not estimate.
#
# *** REPLACE WITH YOUR VALUES FROM SECTION 5.1 ***
set_clock_latency -source -max <<clk_latency_max>> [get_clocks {clk}]
set_clock_latency -source -min <<clk_latency_min>> [get_clocks {clk}]

set_input_transition 0.80 [get_ports $clk_port]

# ── Reset and POR ─────────────────────────────────────────
set_input_delay [expr {$::env(CLOCK_PERIOD) * 0.5}] \
    -clock [get_clocks {clk}] [get_ports {reset_n por_n}]

# ── GPIO input delays ─────────────────────────────────────
# Same values as pnr.sdc. The wrapper SDC uses ext_delay = 4
# in both PnR and signoff, so these constraints do not change.
#
# Bottom edge (gpio_bot_in) → Right Purple + Bottom Orange
set_input_delay -max 15.12 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]
set_input_delay -min 7.08 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]

# Right edge (gpio_rt_in) → Top Purple + Right Orange
set_input_delay -max 15.05 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]
set_input_delay -min 7.20 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]

# Top edge (gpio_top_in) → Left Purple + Top Orange
set_input_delay -max 14.25 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]
set_input_delay -min 6.22 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]

set_input_transition -max 0.38 [get_ports {gpio_bot_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_bot_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_rt_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_rt_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_top_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_top_in[*]}]

# ── GPIO output delays ────────────────────────────────────
# Same values as pnr.sdc for the same reason.
set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]

set_output_delay -max 23.13 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]
set_output_delay -min 9.26 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]

set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]

set_load 0.19 [all_outputs]
```

---

## 7. PnR vs. Signoff — What Changes and Why

| Constraint | `pnr.sdc` | `signoff.sdc` | Reason |
|:---|:---:|:---:|:---|
| `clock_uncertainty` | 0.15 ns | 0.10 ns | CTS has balanced the clock tree; pre-CTS pessimism is removed |
| `timing_derate` | ±7 % | ±5 % | SPEF extraction replaces estimated wire parasitics with real values |
| `max_transition` | 0.75 ns | 1.50 ns | Tight slew forces buffer insertion during routing; relaxed at signoff |
| `set_clock_latency` | same | same | Physical measurement — does not change |
| `set_input_delay` | **same** | **same** | The OpenFrame wrapper uses the same external delay (4 ns) in both its PnR and signoff SDC files |
| `set_output_delay` | **same** | **same** | Same reason as input delays |

---

## 8. Step-by-Step Instructions

**Step 1 — Find your position.**  
Open the wrapper `config.json` and locate your project instance name. The format `gen_row[R].gen_col[C]` tells you: `R` is your row, `C` is your column.

**Step 2 — Look up your clock latency.**  
From the table in Section 5.1, find your grid position and note the `clk_latency_max` and `clk_latency_min` values.

**Step 3 — Fill in the templates.**  
Copy Sections 6.1 and 6.2 as your `pnr.sdc` and `signoff.sdc`. Replace the two `<<clk_latency_max>>` and `<<clk_latency_min>>` placeholders in each file.

**Step 4 — Leave everything else unchanged.**  
All input delays, output delays, derate, uncertainty, and transition values are the same for every project location. They are already filled in.

**Step 5 — Set your clock period.**  
The templates use `$::env(CLOCK_PERIOD)`. Set this variable in your `config.json` to your target clock period in nanoseconds (for example, `25` for a 40 MHz clock).

---

## 9. Quick Reference Summary

```
WHAT CHANGES BY LOCATION:
  ✅ set_clock_latency -source -max / -min   →  Section 5.1 table

WHAT IS THE SAME FOR ALL 12 LOCATIONS:
  ✅ set_input_delay  (per edge, not per location)  →  Section 5.2
  ✅ set_output_delay (all edges identical)          →  Section 5.3

I/O DELAY COMPOSITION:
  Input delay  = OpenFrame external boundary  +  internal infrastructure
                = (board + pad buffer)         +  (purple + orange buf)
                = 8.55 ns max / 5.26 ns min   +  edge-specific values

  Output delay = internal infrastructure  +  OpenFrame external boundary
               = (orange + purple chain)  +  (board + receiver setup)
               = 9.61 ns max / 2.92 min  +  13.12 ns max / 7.90 ns min

WHY PnR AND SIGNOFF I/O DELAYS ARE IDENTICAL:
  The OpenFrame wrapper SDC uses the same external delay (4 ns) in both
  its PnR and signoff files. The internal infrastructure measurements
  are physical and do not change between tool stages. Only the timing
  analysis settings (uncertainty, derate, transition) differ.

CONSTRAINT VALUE TABLE:
  ┌──────────────────────────┬──────────────────────────────────────┐
  │ Constraint               │ Both pnr.sdc and signoff.sdc         │
  ├──────────────────────────┼──────────────────────────────────────┤
  │ clk_latency_max          │ from table 5.1 (your location)       │
  │ clk_latency_min          │ from table 5.1 (your location)       │
  │ input_delay_max (bot)    │ 15.12 ns                             │
  │ input_delay_min (bot)    │  7.08 ns                             │
  │ input_delay_max (rt)     │ 15.05 ns                             │
  │ input_delay_min (rt)     │  7.20 ns                             │
  │ input_delay_max (top)    │ 14.25 ns                             │
  │ input_delay_min (top)    │  6.22 ns                             │
  │ output_delay_max (out)   │ 22.73 ns                             │
  │ output_delay_min (out)   │ 10.82 ns                             │
  │ output_delay_max (oeb)   │ 23.13 ns                             │
  │ output_delay_min (oeb)   │  9.26 ns                             │
  ├──────────────────────────┼──────────────┬───────────────────────┤
  │                          │  pnr.sdc     │  signoff.sdc          │
  ├──────────────────────────┼──────────────┼───────────────────────┤
  │ clock_uncertainty        │  0.15 ns     │  0.10 ns              │
  │ timing_derate            │  ±7 %        │  ±5 %                 │
  │ max_transition           │  0.75 ns     │  1.50 ns              │
  └──────────────────────────┴──────────────┴───────────────────────┘
```

---

*Delay values sourced from: (1) OpenFrame wrapper `pnr.sdc` and `signoff.sdc` for the external boundary delays, and (2) post-PnR Static Timing Analysis of the full wrapper at `max_ss_100C_1v60` (slow/setup corner) and `min_ff_n40C_1v95` (fast/hold corner) for the internal infrastructure delays. Chip: OpenFrame 3×4 grid, SKY130 process node.*
