# Caravel OpenFrame Multi-Project Chip (MP-SoC) Architecture Specification

## 1. Overview

A configurable **COLS x ROWS** grid of user projects inside an eFabless OpenFrame wrapper. The OpenFrame provides **44 Caravel GPIOs** arranged around 3 chip edges (right, top, left). Of these, **38 are routable** to projects through a scan-chain-configurable MUX tree network, and **6 are dedicated** to system signals. **Exactly one project is active at a time.**

**Convention:** Grid configurations are specified as **COLS x ROWS** (e.g., 4x5 = 4 columns, 5 rows = 20 projects).

Valid grid configurations: **3x3** (9), **3x4** (12), **3x5** (15), **4x4** (16), **4x5** (20 projects).

Target process: **Sky130** (via technology abstraction wrappers for portability).

## 2. Pad Allocation

### 2.1 System Pads (6 dedicated)

| Pad | Direction | Function                          |
|-----|-----------|-----------------------------------|
| 37  | Input     | POR (Power-On Reset from PCB)     |
| 38  | Input     | sys_clk                           |
| 39  | Input     | sys_reset_n                       |
| 40  | Input     | scan_clk                          |
| 41  | Input     | scan_din                          |
| 42  | Input     | scan_latch                        |
| 43  | Output    | scan_dout                         |

### 2.2 Project-Routable Pads (38)

| Caravel Edge | Pads      | Count | Reached Via                                       |
|--------------|-----------|-------|---------------------------------------------------|
| Right        | [14:0]    | 15    | Right Purple <-- bottom orange row chains (L->R)  |
| Top          | [23:15]   | 9     | Top Purple <-- right orange column chains (B->T)  |
| Left         | [37:24]   | 14    | Left Purple <-- top orange row chains (R->L)      |

## 3. Project Cell Architecture

Every grid position `[r][c]` contains a cluster of **4 macros + 1 user project**:

```
                       ┌──────────────────┐
                       │   Top Orange      │ ─── row chain R->L ───> Left Purple
                       │   PADS=15         │
                       │   (1 scan bit)    │
                       │   M1 pins (horiz) │
  ┌──────────┐        ├──────────────────┤        ┌──────────────────┐
  │  Green    │──clk──>│                  │───────>│  Right Orange     │
  │           │──rst──>│    PROJECT       │        │  PADS=15          │
  │ (1 scan   │        │    MACRO         │        │  (1 scan bit)     │ ─── col chain B->T
  │  bit)     │        │                  │        │  M2 pins (vert)   │       ──> Top Purple
  └──────────┘        ├──────────────────┤        └──────────────────┘
                       │  Bottom Orange    │ ─── row chain L->R ───> Right Purple
                       │  PADS=15          │
                       │  (1 scan bit)     │
                       │  M1 pins (horiz)  │
                       └──────────────────┘
```

### 3.1 Macro Count Summary

| Module               | Instances         | Contains scan_macro_node | Scan Bits per Instance   |
|----------------------|-------------------|--------------------------|--------------------------|
| scan_controller_macro| 1                 | No (has own FSM)         | --                       |
| green_macro          | COLS x ROWS       | Yes, WIDTH=1             | 1 (proj_en)              |
| orange_macro         | 3 x COLS x ROWS   | Yes, WIDTH=1             | 1 (sel_local)            |
| purple_macro         | 3                 | Yes, WIDTH=1+ceil(log2(PORTS)) | 1+ceil(log2(PORTS)) |
| project_macro        | COLS x ROWS       | No                       | --                       |
| scan_macro_node      | (inside green, orange, purple) | --            | WIDTH (parameter)        |

## 4. Module Specifications

### 4.1 scan_macro_node (Internal to green, orange, purple)

Never instantiated standalone. Always inside a host macro.

**Function:**
- WIDTH-bit shift register clocked by `scan_clk_in`.
- Shifts in from `scan_in`; MSB exits as `scan_out`.
- Shadow register captures shift_reg on `scan_latch_in` assertion, providing glitch-free `ctrl_out[WIDTH-1:0]`.
- Physical repeater buffers on `scan_clk` and `scan_latch` for signal integrity across the chip (using `tech_clkbuf` and `tech_buf`).
- Shadow register reset by `por_n` only (not sys_reset_n) to guarantee safe power-up state while preserving scan configuration across system resets.
- Shift register does not require reset (chain is locked on POR; no clocks or latches can reach it).

**WIDTH by host macro:**

| Host          | WIDTH                    | ctrl_out Meaning           |
|---------------|--------------------------|----------------------------|
| green_macro   | 1                        | proj_en                    |
| orange_macro  | 1                        | sel_local                  |
| purple_macro  | 1 + ceil(log2(PORTS))    | {master_en, port_sel}      |

**WIDTH=1 handling:** Uses a generate block to avoid illegal `shift_reg[-1:0]`:

```verilog
generate
    if (WIDTH == 1) begin : gen_w1
        always @(posedge scan_clk_in or negedge por_n) begin
            if (!por_n) shift_reg <= 1'b0;
            else        shift_reg <= scan_in;
        end
    end else begin : gen_wn
        always @(posedge scan_clk_in or negedge por_n) begin
            if (!por_n) shift_reg <= {WIDTH{1'b0}};
            else        shift_reg <= {shift_reg[WIDTH-2:0], scan_in};
        end
    end
endgenerate
```

**Ports:**

| Port           | Dir    | Width  | Description                                    |
|----------------|--------|--------|------------------------------------------------|
| por_n          | input  | 1      | Power-on reset (active low), resets shadow reg  |
| scan_clk_in    | input  | 1      | Scan clock from predecessor                    |
| scan_latch_in  | input  | 1      | Latch pulse from predecessor                   |
| scan_in        | input  | 1      | Serial data from predecessor                   |
| scan_clk_out   | output | 1      | Buffered scan clock to successor               |
| scan_latch_out | output | 1      | Buffered latch to successor                    |
| scan_out       | output | 1      | Serial data to successor (shift_reg MSB)       |
| ctrl_out       | output | WIDTH  | Latched configuration output                   |

### 4.2 green_macro

**Placement:** Left side of each project cell.

**Function:**
- Contains `scan_macro_node #(.WIDTH(1))` producing `proj_en` (1 = project active, 0 = gated).
- Receives `sys_clk_in` and `sys_reset_n_in` from the green macro below in the same column (or from the grid input for the bottom row).
- Buffers clock/reset upward via `sys_clk_out`, `sys_reset_n_out` to the next green in the column.
- ICG cell (`tech_clkgate`) gates sys_clk: project receives clock only when `proj_en=1`.
- AND gate (`tech_and2`): `proj_reset_n_out = sys_reset_n_in & proj_en`. Project reset is held low when disabled.
- Buffers `por_n` through to the project macro (`proj_por_n_out`) so user designs can use POR for internal initialization without relying on sys_reset_n.
- All outputs buffered for drive strength using `tech_buf`/`tech_clkbuf`.

**Ports:**

| Port              | Dir    | Width | Description                                |
|-------------------|--------|-------|--------------------------------------------|
| sys_clk_in        | input  | 1     | System clock from green below              |
| sys_clk_out       | output | 1     | Buffered system clock to green above       |
| sys_reset_n_in    | input  | 1     | System reset from green below              |
| sys_reset_n_out   | output | 1     | Buffered system reset to green above       |
| proj_clk_out      | output | 1     | Gated clock to project (left edge)         |
| proj_reset_n_out  | output | 1     | Gated reset to project (left edge)         |
| proj_por_n_out    | output | 1     | Buffered POR to project (left edge)        |
| por_n             | input  | 1     | POR for internal scan_macro_node           |
| scan_clk_in       | input  | 1     | Scan chain feedthrough                     |
| scan_clk_out      | output | 1     | Scan chain feedthrough                     |
| scan_latch_in     | input  | 1     | Scan chain feedthrough                     |
| scan_latch_out    | output | 1     | Scan chain feedthrough                     |
| scan_in           | input  | 1     | Scan chain feedthrough                     |
| scan_out          | output | 1     | Scan chain feedthrough                     |

**Clock/Reset distribution:** Green macros form vertical column chains, bottom to top. For a COLS x ROWS grid, there are COLS independent clock/reset columns, each ROWS deep.

### 4.3 orange_macro

**Placement:** Bottom, right, and top sides of each project cell. Always `PADS=15`. All three instances per project cell are identical RTL; physical differences (orientation, pin metal layer) are handled by LEF/DEF and placement constraints.

**Function:**
- Contains `scan_macro_node #(.WIDTH(1))` producing `sel_local` (1 = route local project, 0 = pass through chain).
- 2x1 MUX for 15 bidirectional GPIOs.
- **Inbound** (pad -> project): broadcasts `pad_side_gpio_in` to both `local_proj_gpio_in` and `chain_side_gpio_in` (buffered via `tech_buf`).
- **Outbound** (project -> pad): when `sel_local=1`, routes `local_proj_gpio_out/oeb/dm` toward pads; when `sel_local=0`, passes through `chain_side_gpio_out/oeb/dm`.
- `gpio_dm` is 3 bits per pad (45 bits total for 15 pads), controlling pad drive mode.
- Scan signals feedthrough via the internal scan_macro_node.

**Ports:**

| Port                  | Dir    | Width  | Description                                   |
|-----------------------|--------|--------|-----------------------------------------------|
| por_n                 | input  | 1      | POR for internal scan_macro_node              |
| scan_clk_in           | input  | 1      | Scan chain feedthrough                        |
| scan_clk_out          | output | 1      | Scan chain feedthrough                        |
| scan_latch_in         | input  | 1      | Scan chain feedthrough                        |
| scan_latch_out        | output | 1      | Scan chain feedthrough                        |
| scan_in               | input  | 1      | Scan chain feedthrough                        |
| scan_out              | output | 1      | Scan chain feedthrough                        |
| pad_side_gpio_in      | input  | 15     | From pad/successor (closer to Caravel)        |
| pad_side_gpio_out     | output | 15     | To pad/successor                              |
| pad_side_gpio_oeb     | output | 15     | To pad/successor                              |
| pad_side_gpio_dm      | output | 45     | To pad/successor (3 bits per pad)             |
| chain_side_gpio_in    | output | 15     | Broadcast to chain predecessor                |
| chain_side_gpio_out   | input  | 15     | From chain predecessor                        |
| chain_side_gpio_oeb   | input  | 15     | From chain predecessor                        |
| chain_side_gpio_dm    | input  | 45     | From chain predecessor                        |
| local_proj_gpio_in    | output | 15     | Broadcast to local project                    |
| local_proj_gpio_out   | input  | 15     | From local project                            |
| local_proj_gpio_oeb   | input  | 15     | From local project                            |
| local_proj_gpio_dm    | input  | 45     | From local project                            |

**Chain topology (3x3 example):**

Bottom oranges per row, L->R toward Right Purple:
```
tie-off -> [Bot_r,0] -> [Bot_r,1] -> [Bot_r,2] -> Right Purple port r
```

Right oranges per column, B->T toward Top Purple:
```
tie-off -> [Rt_R-1,c] -> [Rt_R-2,c] -> ... -> [Rt_0,c] -> Top Purple port c
```

Top oranges per row, R->L toward Left Purple:
```
tie-off -> [Top_r,C-1] -> [Top_r,C-2] -> ... -> [Top_r,0] -> Left Purple port r
```

Chain start tie-offs: `gpio_out=0`, `gpio_oeb={15{1'b1}}` (Hi-Z), `gpio_dm=0`.

### 4.4 purple_macro

**Placement:** 3 instances at chip edges. Always `PADS=15`.

**Function:**
- Contains `scan_macro_node #(.WIDTH(1 + ceil(log2(PORTS))))` producing `{master_en, port_sel}`.
- `port_sel` selects which of PORTS incoming orange chain endpoints reaches the pads.
- `master_en` safety bit: when 0, forces `gpio_out=0`, `gpio_oeb={15{1'b1}}` (Hi-Z), `gpio_dm=0`. Isolates the chip from all pads.
- **Inbound:** buffers `pad_gpio_in` and broadcasts to all PORTS chain endpoints.
- **Outbound:** indexed MUX selects one port's `gpio_out/oeb/dm`, gated by `master_en`.
- Scan signals feedthrough via the internal scan_macro_node.

**Instances:**

| Instance     | PORTS  | port_sel bits     | Total scan bits       | Caravel Connection             |
|--------------|--------|-------------------|-----------------------|--------------------------------|
| Right Purple | ROWS   | ceil(log2(ROWS))  | 1 + ceil(log2(ROWS))  | All 15 bits -> gpio[14:0]      |
| Top Purple   | COLS   | ceil(log2(COLS))  | 1 + ceil(log2(COLS))  | Lower 9 of 15 -> gpio[23:15]   |
| Left Purple  | ROWS   | ceil(log2(ROWS))  | 1 + ceil(log2(ROWS))  | Lower 14 of 15 -> gpio[37:24]  |

**Ports:**

| Port              | Dir    | Width           | Description                              |
|-------------------|--------|-----------------|------------------------------------------|
| por_n             | input  | 1               | POR for internal scan_macro_node         |
| scan_clk_in       | input  | 1               | Scan chain feedthrough                   |
| scan_clk_out      | output | 1               | Scan chain feedthrough                   |
| scan_latch_in     | input  | 1               | Scan chain feedthrough                   |
| scan_latch_out    | output | 1               | Scan chain feedthrough                   |
| scan_in           | input  | 1               | Scan chain feedthrough                   |
| scan_out          | output | 1               | Scan chain feedthrough                   |
| pad_gpio_in       | input  | 15              | From Caravel pads                        |
| pad_gpio_out      | output | 15              | To Caravel pads                          |
| pad_gpio_oeb      | output | 15              | To Caravel pads                          |
| pad_gpio_dm       | output | 45              | To Caravel pads                          |
| tree_gpio_in      | output | PORTS x 15      | Broadcast to all orange chain endpoints  |
| tree_gpio_out     | input  | PORTS x 15      | From orange chain endpoints              |
| tree_gpio_oeb     | input  | PORTS x 15      | From orange chain endpoints              |
| tree_gpio_dm      | input  | PORTS x 45      | From orange chain endpoints              |

### 4.5 project_macro

**Placement:** Center of each project cell.

**Function:** User design sandbox. All outputs have safe default tie-offs. Users replace the tie-offs with their logic.

**Port mapping by physical edge:**

| Physical Edge | Signal Group       | Width          | Connects To                        |
|---------------|--------------------|----------------|------------------------------------|
| Left          | clk                | 1              | Green macro proj_clk_out           |
| Left          | reset_n            | 1              | Green macro proj_reset_n_out       |
| Left          | por_n              | 1              | Green macro proj_por_n_out         |
| Bottom        | gpio_bot_in        | 15             | Bottom orange local_proj_gpio_in   |
| Bottom        | gpio_bot_out       | 15             | Bottom orange local_proj_gpio_out  |
| Bottom        | gpio_bot_oeb       | 15             | Bottom orange local_proj_gpio_oeb  |
| Bottom        | gpio_bot_dm        | 45             | Bottom orange local_proj_gpio_dm   |
| Right         | gpio_rt_in         | 9              | Right orange local_proj_gpio_in [8:0]  |
| Right         | gpio_rt_out        | 9              | Right orange local_proj_gpio_out [8:0] |
| Right         | gpio_rt_oeb        | 9              | Right orange local_proj_gpio_oeb [8:0] |
| Right         | gpio_rt_dm         | 27             | Right orange local_proj_gpio_dm [26:0] |
| Top           | gpio_top_in        | 14             | Top orange local_proj_gpio_in [13:0]   |
| Top           | gpio_top_out       | 14             | Top orange local_proj_gpio_out [13:0]  |
| Top           | gpio_top_oeb       | 14             | Top orange local_proj_gpio_oeb [13:0]  |
| Top           | gpio_top_dm        | 42             | Top orange local_proj_gpio_dm [41:0]   |

Total usable GPIOs: 15 + 9 + 14 = **38**.

The right and top orange macros are always 15-wide internally. The unused bits (6 for right, 1 for top) are tied off at the top-level connection between the project macro and the orange macro:
- Right orange: `local_proj_gpio_out[14:9] = 0`, `local_proj_gpio_oeb[14:9] = 1`, `local_proj_gpio_dm[44:27] = 0`
- Top orange: `local_proj_gpio_out[14] = 0`, `local_proj_gpio_oeb[14] = 1`, `local_proj_gpio_dm[44:42] = 0`

**Default tie-offs (user replaces these):**
- All `gpio_*_out` = 0
- All `gpio_*_oeb` = 1 (Hi-Z, prevents shorts)
- All `gpio_*_dm` = `3'b110` per pad (strong digital push-pull)

### 4.6 scan_controller_macro

**Placement:** Near system pads (bottom edge of chip).

**Function:** Secure serial bridge between external scan pins and the internal scan chain.

**Security protocol:**
1. **LOCKED** on reset (POR or sys_reset_n). Chain scan clock is gated off, latch is gated off. No configuration data can reach the chain.
2. External controller shifts in magic word (**0xA5**) on `pad_scan_din`/`pad_scan_clk`. Chain **UNLOCKS**.
3. Scan clock and data now propagate to the internal chain. Shift in all configuration bits.
4. Assert `pad_scan_latch` (rising edge). Shadow registers capture throughout the chain. Chain **immediately re-locks**.
5. Must unlock again for any subsequent reconfiguration.

`pad_scan_dout` always passes `chain_scan_dout` back to the external controller for readback, even when locked.

**Ports:**

| Port             | Dir    | Width | Description                               |
|------------------|--------|-------|-------------------------------------------|
| por_n            | input  | 1     | Power-on reset (active low)               |
| sys_reset_n      | input  | 1     | System reset (active low)                 |
| pad_scan_clk     | input  | 1     | External scan clock (pad 40)              |
| pad_scan_din     | input  | 1     | External scan data in (pad 41)            |
| pad_scan_latch   | input  | 1     | External latch pulse (pad 42)             |
| pad_scan_dout    | output | 1     | Scan data readback (pad 43)               |
| chain_scan_clk   | output | 1     | Gated clock to internal chain             |
| chain_scan_din   | output | 1     | Buffered data to internal chain           |
| chain_scan_latch | output | 1     | Gated latch to internal chain             |
| chain_scan_dout  | input  | 1     | Data from last node in chain (readback)   |

**Internal logic:**
- Combined reset: `combined_reset_n = por_n & sys_reset_n` (both must be deasserted).
- 8-bit shift register monitors incoming data for the magic word.
- When `{shift_reg[6:0], pad_scan_din} == 8'hA5`, `unlocked` flips to 1.
- `chain_scan_clk` is gated by `unlocked` via `tech_clkgate`.
- `chain_scan_latch` is gated: `safe_latch = unlocked & pad_scan_latch`.
- On latch assertion while unlocked: `unlocked` returns to 0 (auto re-lock).

### 4.7 openframe_project_wrapper (Top Level)

**Parameters:** `ROWS`, `COLS`

**Responsibilities:**
1. OpenFrame mandatory pad tie-offs (44 GPIOs x ~12 configuration signals each).
2. System pad assignments (clk, rst, POR, scan interface).
3. Scan controller instantiation.
4. 2D grid generation via `generate`:
   - COLS x ROWS project cells, each containing 1 green + 3 oranges + 1 project_macro.
5. Green macro column chains: clock/reset distribution bottom -> top, COLS independent columns.
6. Orange chain wiring:
   - Bottom oranges: L->R per row (ROWS chains), endpoints to Right Purple.
   - Right oranges: B->T per column (COLS chains), endpoints to Top Purple.
   - Top oranges: R->L per row (ROWS chains), endpoints to Left Purple.
7. Chain start tie-offs (safe defaults at each chain origin).
8. 3 purple macro instantiations at chip edges.
9. Pad output trimming (15->9 for Top Purple to Caravel, 15->14 for Left Purple to Caravel).
10. Scan chain stitching in row-major serpentine order.
11. POR distribution to all scan_macro_node instances (via their host macros) and to all project macros (via green macros).

## 5. Scan Chain

### 5.1 Topology

Single global scan chain, **row-major serpentine**. Within each cell, 4 macros are visited in physical traversal order (all are feedthrough with repeater buffers).

![Scan Chain Stitching](scanchain_3x4.svg)

```
Scan Controller (pad_scan_din)
  -> Purple_Left -> Purple_Top -> Purple_Right
  -> Row R-1 (R->L): cell[R-1,C-1] -> ... -> cell[R-1,0]       (top row, first)
  -> Row R-2 (L->R): cell[R-2,0] -> cell[R-2,1] -> ...
  -> ...alternating...
  -> Row 0:          cell[0,0] -> ... -> cell[0,C-1]            (bottom row, last)
  -> back to Scan Controller (pad_scan_dout)
```

Purples are scanned **first** (closest to the scan port), then the grid is traversed **top-down** in a serpentine pattern. This routes naturally: scan controller (bottom center) → left edge → top edge → right edge → grid entry at top-right → serpentine down → bottom row exit → back to scan controller.

### 5.1.1 Intra-Cell Scan Order

Within each cell, the 4 scan nodes are visited in a fixed order:

```
Green -> Bottom Orange -> Right Orange -> Top Orange
```

This order follows the physical placement: green on the left, then the three oranges counter-clockwise (bottom, right, top). All macros are feedthrough — the scan chain passes through them regardless of their functional state.

**Full scan order example (3x4, 12 projects, 57 bits):**

```
Scan Controller (pad_scan_din) ->
  Purple_Left (3 bits) -> Purple_Top (3 bits) -> Purple_Right (3 bits) ->
  Row 3 (R->L): [3,2]:G->B->R->T -> [3,1]:G->B->R->T -> [3,0]:G->B->R->T ->
  Row 2 (L->R): [2,0]:G->B->R->T -> [2,1]:G->B->R->T -> [2,2]:G->B->R->T ->
  Row 1 (R->L): [1,2]:G->B->R->T -> [1,1]:G->B->R->T -> [1,0]:G->B->R->T ->
  Row 0 (L->R): [0,0]:G->B->R->T -> [0,1]:G->B->R->T -> [0,2]:G->B->R->T ->
-> Scan Controller (pad_scan_dout)
```

Where G=green (1 bit), B=bottom orange (1 bit), R=right orange (1 bit), T=top orange (1 bit).

### 5.1.2 Complete Bit Position Map (3x4 Default, 57 bits)

Origin: row 0 = bottom, column 0 = left.

**Purple nodes (bits 0–8):**

| Bit | Node | Function |
|-----|------|----------|
| 0 | Purple_Left [0] | port_sel[0] |
| 1 | Purple_Left [1] | port_sel[1] |
| 2 | Purple_Left [2] | master_en |
| 3 | Purple_Top [0] | port_sel[0] |
| 4 | Purple_Top [1] | port_sel[1] |
| 5 | Purple_Top [2] | master_en |
| 6 | Purple_Right [0] | port_sel[0] |
| 7 | Purple_Right [1] | port_sel[1] |
| 8 | Purple_Right [2] | master_en |

**Grid nodes (bits 9–56), top-down serpentine:**

| Bit | Node | Row | Col | Direction |
|-----|------|-----|-----|-----------|
| 9  | G_3_2  | 3 | 2 | Row 3 R→L |
| 10 | O_3_2_bot | 3 | 2 | |
| 11 | O_3_2_rt  | 3 | 2 | |
| 12 | O_3_2_top | 3 | 2 | |
| 13 | G_3_1  | 3 | 1 | |
| 14 | O_3_1_bot | 3 | 1 | |
| 15 | O_3_1_rt  | 3 | 1 | |
| 16 | O_3_1_top | 3 | 1 | |
| 17 | G_3_0  | 3 | 0 | |
| 18 | O_3_0_bot | 3 | 0 | |
| 19 | O_3_0_rt  | 3 | 0 | |
| 20 | O_3_0_top | 3 | 0 | |
| 21 | G_2_0  | 2 | 0 | Row 2 L→R |
| 22 | O_2_0_bot | 2 | 0 | |
| 23 | O_2_0_rt  | 2 | 0 | |
| 24 | O_2_0_top | 2 | 0 | |
| 25 | G_2_1  | 2 | 1 | |
| 26 | O_2_1_bot | 2 | 1 | |
| 27 | O_2_1_rt  | 2 | 1 | |
| 28 | O_2_1_top | 2 | 1 | |
| 29 | G_2_2  | 2 | 2 | |
| 30 | O_2_2_bot | 2 | 2 | |
| 31 | O_2_2_rt  | 2 | 2 | |
| 32 | O_2_2_top | 2 | 2 | |
| 33 | G_1_2  | 1 | 2 | Row 1 R→L |
| 34 | O_1_2_bot | 1 | 2 | |
| 35 | O_1_2_rt  | 1 | 2 | |
| 36 | O_1_2_top | 1 | 2 | |
| 37 | G_1_1  | 1 | 1 | |
| 38 | O_1_1_bot | 1 | 1 | |
| 39 | O_1_1_rt  | 1 | 1 | |
| 40 | O_1_1_top | 1 | 1 | |
| 41 | G_1_0  | 1 | 0 | |
| 42 | O_1_0_bot | 1 | 0 | |
| 43 | O_1_0_rt  | 1 | 0 | |
| 44 | O_1_0_top | 1 | 0 | |
| 45 | G_0_0  | 0 | 0 | Row 0 L→R |
| 46 | O_0_0_bot | 0 | 0 | |
| 47 | O_0_0_rt  | 0 | 0 | |
| 48 | O_0_0_top | 0 | 0 | |
| 49 | G_0_1  | 0 | 1 | |
| 50 | O_0_1_bot | 0 | 1 | |
| 51 | O_0_1_rt  | 0 | 1 | |
| 52 | O_0_1_top | 0 | 1 | |
| 53 | G_0_2  | 0 | 2 | |
| 54 | O_0_2_bot | 0 | 2 | |
| 55 | O_0_2_rt  | 0 | 2 | |
| 56 | O_0_2_top | 0 | 2 | |

**Naming convention:** `G_r_c` = green at (row, col), `O_r_c_bot` = bottom orange, `O_r_c_rt` = right orange, `O_r_c_top` = top orange.

**Serpentine rule (generalized):**
- `ROW_FROM_TOP = ROWS - 1 - r`
- Even `ROW_FROM_TOP` (0, 2, ...): R→L (column order `C-1, C-2, ..., 0`)
- Odd `ROW_FROM_TOP` (1, 3, ...): L→R (column order `0, 1, ..., C-1`)
- `PROJ_IDX = ROW_FROM_TOP * COLS + SERP_C`
- `SC_BASE = SC_GRID_BASE + PROJ_IDX * 4`

### 5.2 Bit Count

| Component              | Bits per Instance         | Count         | Total                   |
|------------------------|---------------------------|---------------|-------------------------|
| Green (proj_en)        | 1                         | COLS x ROWS   | COLS x ROWS             |
| Bottom Orange (sel)    | 1                         | COLS x ROWS   | COLS x ROWS             |
| Right Orange (sel)     | 1                         | COLS x ROWS   | COLS x ROWS             |
| Top Orange (sel)       | 1                         | COLS x ROWS   | COLS x ROWS             |
| Right Purple           | 1 + ceil(log2(ROWS))      | 1             | 1 + ceil(log2(ROWS))    |
| Top Purple             | 1 + ceil(log2(COLS))      | 1             | 1 + ceil(log2(COLS))    |
| Left Purple            | 1 + ceil(log2(ROWS))      | 1             | 1 + ceil(log2(ROWS))    |

**Examples (COLS x ROWS):**

| Config | Projects | Project bits | Purple bits (R+T+L) | Total |
|--------|----------|-------------|----------------------|-------|
| 3x3    | 9        | 36          | 3+3+3 = 9           | 45    |
| 3x4    | 12       | 48          | 3+3+3 = 9           | 57    |
| 3x5    | 15       | 60          | 4+3+4 = 11          | 71    |
| 4x4    | 16       | 64          | 3+3+3 = 9           | 73    |
| 4x5    | 20       | 80          | 4+3+4 = 11          | 91    |

Note: Purple scan bits = 1 (master_en) + ceil(log2(PORTS)). Right/Left Purple PORTS=ROWS, Top Purple PORTS=COLS. For ROWS=3: 1+ceil(log2(3))=1+2=3. For ROWS=5: 1+ceil(log2(5))=1+3=4. For COLS=4: 1+ceil(log2(4))=1+2=3 (not 4, since log2(4)=2 exactly).

### 5.3 Reset Behavior

- **POR** resets all shadow registers to 0. This guarantees:
  - All `proj_en` = 0 (no project clocked)
  - All `sel_local` = 0 (all oranges pass through, delivering tie-off zeros)
  - All `master_en` = 0 (all purples force Hi-Z on all pads)
- **sys_reset_n** does NOT reset shadow registers. Scan configuration survives system resets. Only the active project is reset via its green macro.
- Shift registers do not require reset. The scan chain is locked on POR; no clocks or latches can reach the chain until the magic word is provided.

## 6. Clock and Reset Distribution

- System clock and reset enter from the **bottom of the grid** (pads 38 and 39).
- Green macros form **vertical column chains**, bottom to top.
- For a COLS x ROWS grid: COLS independent clock/reset columns, each ROWS deep.
- Each green macro:
  - Buffers `sys_clk` and `sys_reset_n` upward to the next green (`tech_clkbuf` / `tech_buf`).
  - Gates `sys_clk` via `tech_clkgate` using `proj_en` -> `proj_clk_out`.
  - ANDs `sys_reset_n` with `proj_en` via `tech_and2` -> `proj_reset_n_out`.
  - Buffers `por_n` through to the project macro (`proj_por_n_out`) for user-design initialization.
- Maximum buffer chain depth: ROWS green macros per column.

## 7. GPIO MUX Tree Data Flow

### 7.1 Outbound (Project -> Caravel Pads)

For active project at `[r][c]`:

```
Project [r][c] bottom gpio_out -> Bot Orange [r][c] (sel_local=1)
  -> passes through Bot Oranges [r][c+1..C-1] (sel_local=0)
  -> Right Purple (port_sel=r, master_en=1)
  -> Caravel Right Pads [14:0]

Project [r][c] right gpio_out -> Rt Orange [r][c] (sel_local=1)
  -> passes through Rt Oranges [r-1..0][c] (sel_local=0)
  -> Top Purple (port_sel=c, master_en=1)
  -> Caravel Top Pads [23:15] (9 of 15 used)

Project [r][c] top gpio_out -> Top Orange [r][c] (sel_local=1)
  -> passes through Top Oranges [r][c-1..0] (sel_local=0)
  -> Left Purple (port_sel=r, master_en=1)
  -> Caravel Left Pads [37:24] (14 of 15 used)
```

### 7.2 Inbound (Caravel Pads -> Project)

Each purple broadcasts its pad_gpio_in to all chain ports. Each orange broadcasts pad_side_gpio_in to both its local project and the chain predecessor. All projects receive the pad input simultaneously; only the enabled project's clock is active to sample it.

## 8. Selecting Project [r][c]

The external controller performs the following sequence:

1. Shift in magic word (0xA5) to unlock the scan chain.
2. Shift in configuration bits (first-in = Purple Left, last-in = Row 0 cell):
   - `purple_left: master_en=1, port_sel=r`
   - `purple_top: master_en=1, port_sel=c`
   - `purple_right: master_en=1, port_sel=r`
   - Grid cells (top-down serpentine): for each cell, set:
     - `green[r][c].proj_en = 1` (all others 0)
     - `bottom_orange[r][c].sel_local = 1` (all others in row r = 0)
     - `right_orange[r][c].sel_local = 1` (all others in col c = 0)
     - `top_orange[r][c].sel_local = 1` (all others in row r = 0)
3. Pulse `scan_latch`. Shadow registers capture. Chain auto-locks.
4. Project [r][c] is now active with all 38 GPIOs routed to Caravel pads.

## 9. Technology Abstraction Layer

No direct PDK cell instantiation anywhere in the RTL. Three wrapper modules abstract the technology-specific cells that must be preserved as physical instances (buffers for signal integrity, clock gates for glitch-free gating). Simple combinational logic (AND, OR, etc.) is left as inferrable RTL for the synthesis tool.

| Wrapper        | Wraps                        | Ports              | Used In                          |
|----------------|------------------------------|--------------------|---------------------------------|
| `tech_buf`     | Generic drive buffer         | `A -> X`           | All modules (signal repeaters)  |
| `tech_clkbuf`  | Clock tree buffer (CTS-aware)| `A -> X`           | scan_macro_node, green_macro    |
| `tech_clkgate` | Integrated clock gating cell | `CLK, GATE -> GCLK`| green_macro, scan_controller    |

Each wrapper contains a single PDK cell instantiation with `(* dont_touch = "true" *)` attributes to prevent synthesis optimization. Porting to a different PDK (GF180, TSMC, etc.) means swapping only these 3 files.

### 9.1 Sky130 Mapping (Default)

| Wrapper        | Sky130 Cell                  |
|----------------|------------------------------|
| `tech_buf`     | `sky130_fd_sc_hd__buf_4`     |
| `tech_clkbuf`  | `sky130_fd_sc_hd__clkbuf_4`  |
| `tech_clkgate` | `sky130_fd_sc_hd__dlclkp_1`  |

## 10. Macro Physical Constraints

### 10.1 Shape

Orange macros are rectangular with:
- **Long side:** matches the project macro edge it connects to.
- **Short side:** 55 um.

Green macros are rectangular with:
- **Long side:** matches the project macro height.
- **Short side:** 45 um.

### 10.2 Pin Metal Layers

| Orientation | Position       | Pin Metal | Routing Direction |
|-------------|----------------|-----------|-------------------|
| Horizontal  | Bottom, Top    | Metal 1   | Horizontal        |
| Vertical    | Right          | Metal 2   | Vertical          |

### 10.3 Pin Density

Sky130 Metal 1/2 track pitch: **460nm**.

Short side (55um): 55000nm / 460nm = **~119 available tracks**.

Signals per short edge:

| Signal         | Width |
|----------------|-------|
| gpio_in        | 15    |
| gpio_out       | 15    |
| gpio_oeb       | 15    |
| gpio_dm        | 45    |
| scan_clk       | 1     |
| scan_latch     | 1     |
| scan_in or out | 1     |
| por_n          | 1     |
| **Total**      | **94**|

94 signals on 119 tracks leaves **25 spare tracks** for VDD/VSS and spacing.

### 10.4 Pin Placement by Edge

**Bottom orange (horizontal, L->R chain):**

| Edge          | Connects To                  | Signals                              |
|---------------|------------------------------|--------------------------------------|
| Top (long)    | Project bottom edge          | local_proj_* (GPIO + power)          |
| Left (short)  | Chain predecessor            | chain_side_* + scan_in/clk_in/lat_in + por_n |
| Right (short) | Chain successor / Purple     | pad_side_* + scan_out/clk_out/lat_out|

**Right orange (vertical, B->T chain):**

| Edge           | Connects To                  | Signals                              |
|----------------|------------------------------|--------------------------------------|
| Left (long)    | Project right edge           | local_proj_* (GPIO + power)          |
| Bottom (short) | Chain predecessor            | chain_side_* + scan_in/clk_in/lat_in + por_n |
| Top (short)    | Chain successor / Purple     | pad_side_* + scan_out/clk_out/lat_out|

**Top orange (horizontal, R->L chain) — `orange_macro_h_top`:**

| Edge            | Connects To                  | Signals                              |
|-----------------|------------------------------|--------------------------------------|
| Bottom (long)   | Project top edge             | local_proj_* (GPIO + power)          |
| Right (short)   | Chain predecessor + scan I/O | chain_side_* + scan_in/clk_in/lat_in + scan_out/clk_out/lat_out + por_n |
| Left (short)    | Chain successor / Purple     | pad_side_*                           |

Note: The top orange uses a separate hardened variant (`orange_macro_h_top`) with **swapped short edges** compared to `orange_macro_h`. Since the GPIO chain flows R→L (opposite to bottom orange's L→R), the chain predecessor is on the **right** and the successor (toward Left Purple) is on the **left**. The pin_order.cfg reflects this: `#E` = chain_side + scan I/O, `#W` = pad_side. After FN placement, `#E` stays right (= predecessor side) and `#W` stays left (= Purple side). Both scan_in and scan_out are co-located on `#E` so the scan_macro_node sits near the right edge with short internal wires. Same RTL as `orange_macro_h`, different pin placement only.

## 11. Floorplan Analysis

### 11.1 OpenFrame Core Area

From the OpenFrame LEF (`openframe_project_wrapper.lef`):

- **Core width:** 3166.630 um
- **Core height:** 4766.630 um
- **Core area:** 15.095 mm²

### 11.2 Floorplan Diagram (3x4 Default Configuration)

![Floorplan](floorplan_3x4.svg)

<details><summary>ASCII fallback (click to expand)</summary>

```
 3166.63 um
◄─────────────────────────────────────────────────────────────────────────────────────►
                                                                                       ▲
┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│                              Purple Top (p3)                                        │ 50
│                            3066.63 × 50 um                                          │ um
├──┬───┬──────────────────────┬──┬───┬──────────────────────┬──┬───┬──────────────────────┬──┤ ▼
│  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │ ▲
│  │   │  922.21 × 55         │  │   │  922.21 × 55         │  │   │  922.21 × 55         │  │ │55
│  │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │ ▼
│  │ G │                      │Or│ G │                      │Or│ G │                      │Or│
│  │ r │                      │an│ r │                      │an│ r │                      │an│
│P │ e │   Project [3,0]      │ge│ e │   Project [3,1]      │ge│ e │   Project [3,2]      │ge│
│u │ e │   922.21 × 1031.66   │ V│ e │   922.21 × 1031.66   │ V│ e │   922.21 × 1031.66   │ V│  P
│r │ n │                      │55│ n │                      │55│ n │                      │55│  u
│p │   │                      │x │   │                      │x │   │                      │x │  r
│l │ 45│                      │10│ 45│                      │10│ 45│                      │10│  p
│e │ x │                      │31│ x │                      │31│ x │                      │31│  l
│  │ 10│                      │  │ 10│                      │  │ 10│                      │  │  e
│L │ 31│                      │  │ 31│                      │  │ 31│                      │  │
│e │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │  R
│f │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │  i
│t ├───┼──────────────────────┼──┼───┼──────────────────────┼──┼───┼──────────────────────┼──┤  g
│  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │  h
│  │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │  t
│  │ G │                      │Or│ G │                      │Or│ G │                      │Or│
│  │ r │   Project [2,0]      │ V│ r │   Project [2,1]      │ V│ r │   Project [2,2]      │ V│
│( │ e │                      │  │ e │                      │  │ e │                      │  │
│p │ e │                      │  │ e │                      │  │ e │                      │  │  (
│4 │ n │                      │  │ n │                      │  │ n │                      │  │  p
│) │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │  4
│  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │  )
│  ├───┼──────────────────────┼──┼───┼──────────────────────┼──┼───┼──────────────────────┼──┤
│50│   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │50
│um│   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │um
│  │ G │                      │Or│ G │                      │Or│ G │                      │Or│
│  │ r │   Project [1,0]      │ V│ r │   Project [1,1]      │ V│ r │   Project [1,2]      │ V│ 4766.63
│  │ e │                      │  │ e │                      │  │ e │                      │  │ um
│  │ e │                      │  │ e │                      │  │ e │                      │  │
│  │ n │                      │  │ n │                      │  │ n │                      │  │
│  │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │
│  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │
│  ├───┼──────────────────────┼──┼───┼──────────────────────┼──┼───┼──────────────────────┼──┤
│  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │   │  Top Orange (H, FN)  │  │
│  │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │
│  │ G │                      │Or│ G │                      │Or│ G │                      │Or│
│  │ r │   Project [0,0]      │ V│ r │   Project [0,1]      │ V│ r │   Project [0,2]      │ V│
│  │ e │                      │  │ e │                      │  │ e │                      │  │
│  │ e │                      │  │ e │                      │  │ e │                      │  │
│  │ n │                      │  │ n │                      │  │ n │                      │  │
│  │   ├──────────────────────┤  │   ├──────────────────────┤  │   ├──────────────────────┤  │
│  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │   │  Bot Orange (H)      │  │
├──┴───┴──────────┬───────────┴──┴───┴──────────────────────┴──┴───┴──────────────────────┴──┤
│                 │  Scan Controller  │                                                      │ ▲
│   (margin)      │   200 × 100 um   │                (margin)                               │ 150 um
└─────────────────┴───────────────────┴──────────────────────────────────────────────────────┘ ▼

Legend:
  Green (G)        = Clock gate + reset isolation          45 × 1031.66 um
  Orange V (Or V)  = Orange Macro, vertical, M2 pins      55 × 1031.66 um
  Orange H         = Orange Macro, horizontal, M1 pins    922.21 × 55 um
  Top Orange FN    = Orange H, flipped (R→L chain)        922.21 × 55 um
  Project          = User project sandbox                  922.21 × 1031.66 um
  Purple Left/Right= Purple Macro p4 (PORTS=ROWS=4)       50 × 4566.63 um
  Purple Top       = Purple Macro p3 (PORTS=COLS=3)        3066.63 × 50 um
  Scan Controller  = Magic-word security gate              200 × 100 um

Cell [r,c] = row r, column c (r=0 is bottom row, c=0 is left column)

Instance count: 12 Green + 24 Orange H + 12 Orange V + 12 Project
              +  2 Purple p4 + 1 Purple p3 + 1 Scan Controller = 64 macro instances
```

</details>

### 11.3 Macro Dimensions

| Macro          | Short Side | Long Side              | Notes                           |
|----------------|-----------|------------------------|--------------------------------|
| Orange macro   | 55 um     | Matches project edge   | Pins on M1 (horiz) or M2 (vert) |
| Green macro    | 45 um     | Matches project height | Placed to the left of project  |
| Purple macro   | 50 um     | Along chip edge        | 3 instances at right/top/left  |
| Scan controller| ~150 um   | Along bottom edge      | Includes routing channels      |

### 11.4 Inter-Project Spacing

| Gap Direction | Between                      | Components in Gap        | Total Gap |
|---------------|------------------------------|--------------------------|-----------|
| Horizontal    | Adjacent columns             | Right orange (55) + Green (45) | **100 um** |
| Vertical      | Adjacent rows                | Bottom orange (55) + Top orange (55) | **110 um** |

### 11.5 Project Dimension Equations

```
Available grid width  = 3166.630 - 50 (left purple) - 50 (right purple) = 3066.630 um
Available grid height = 4766.630 - 50 (top purple) - 150 (scan ctrl)    = 4566.630 um

Cell width  = grid_width  / COLS
Cell height = grid_height / ROWS

Project width  = cell_width  - 45 (green) - 55 (right orange) = cell_width  - 100
Project height = cell_height - 55 (bottom orange) - 55 (top orange) = cell_height - 110
```

### 11.6 Configuration Comparison

| Config | COLS x ROWS | Project (um)    | Aspect Ratio | Project Area | Total Proj Area | Efficiency |
|--------|------------|-----------------|-------------|-------------|----------------|------------|
| 3x3    | 3C x 3R    | 922.2 x 1412.2 | 1 : 1.53    | **1.302 mm²** | **11.72 mm²** | **77.6%** |
| 3x4    | 3C x 4R    | 922.2 x 1031.7 | 1 : 1.12    | **0.951 mm²** | **11.41 mm²** | **75.6%** |
| 3x5    | 3C x 5R    | 922.2 x 803.3  | 1.15 : 1    | **0.741 mm²** | **11.11 mm²** | **73.6%** |
| 4x4    | 4C x 4R    | 666.7 x 1031.7 | 1 : 1.55    | **0.688 mm²** | **11.01 mm²** | **72.9%** |
| 4x5    | 4C x 5R    | 666.7 x 803.3  | 1 : 1.20    | **0.536 mm²** | **10.71 mm²** | **70.9%** |

### 11.7 Observations

- **3x4 has the best aspect ratio** (1:1.12, nearly square projects).
- **3-column configs have higher efficiency** than 4-column configs because the horizontal overhead (100 um green+orange) is a smaller fraction of the wider cells.
- **Efficiency ranges from 71% to 78%** — the orange macro overhead (55 um per edge x 3 sides) is the dominant area cost.
- **Per-project area decreases with grid size:** 1.302 mm² (3x3) down to 0.536 mm² (4x5). The 4x5 projects (~0.5 mm², ~50k gates in sky130) are suitable for small digital blocks; 3x3 projects (~1.3 mm², ~130k gates) can fit moderate designs.

## 12. File Structure

```
verilog/rtl/
  tech_lib/
    tech_buf.v
    tech_clkbuf.v
    tech_clkgate.v
  scan_macro_node.v
  green_macro.v
  orange_macro.v
  purple_macro.v
  project_macro.v
  scan_controller_macro.v
  openframe_project_wrapper.v
```
