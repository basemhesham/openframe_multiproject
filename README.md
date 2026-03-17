# OpenFrame Multi-Project Chip (MP-SoC)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A configurable **multi-project wrapper** for the eFabless OpenFrame, hosting up to 20 independent user designs in a single chip. A scan-chain-configurable MUX tree routes 38 GPIOs to the selected project at runtime.

## Key Features

- **Parameterizable grid**: COLS x ROWS project slots (default 3x4 = 12 projects)
- **38 routable GPIOs** across 3 chip edges (15 right, 9 top, 14 left)
- **Scan chain security**: 8-bit magic word (0xA5) locks/unlocks configuration
- **Per-project clock gating and reset isolation** via ICG cells
- **Technology-portable**: all PDK cells behind 3 abstraction wrappers
- **Target process**: Sky130 (via OpenLane)

## Architecture Overview

```
                        ┌──────────────────┐
                        │   Top Orange     │ ── R→L ──> Left Purple ──> gpio[37:24]
                        └──────────────────┘
   ┌──────────┐         ┌──────────────────┐         ┌──────────────────┐
   │  Green   │──clk──> │                  │ ──────> │  Right Orange    │
   │  (gate/  │──rst──> │  PROJECT MACRO   │         │                  │ ── B→T ──> Top Purple ──> gpio[23:15]
   │   reset) │──por──> │  (user design)   │         │                  │ 
   └──────────┘         └──────────────────┘         └──────────────────┘ 
                        ┌──────────────────┐
                        │  Bottom Orange   │ ── L→R ──> Right Purple ──> gpio[14:0]
                        └──────────────────┘
```

Each grid cell contains: 1 Green (clock/reset gate) + 3 Oranges (GPIO MUX) + 1 Project macro.

Three Purple aggregators at chip edges select which row/column reaches the pads.

## Project Structure

```
verilog/rtl/
  tech_lib/                     # Technology abstraction (buf, clkbuf, clkgate)
  scan_macro_node.v             # Parameterized shift register + shadow latch
  green_macro.v                 # Per-project clock gating and reset isolation
  orange_macro.v                # 15-wide GPIO MUX (chain/local select)
  purple_macro.v                # Edge aggregator (port select + master enable)
  scan_controller_macro.v       # Magic-word security gate
  project_macro.v               # User design sandbox (replace with your logic)
  openframe_project_wrapper.v   # Top-level wrapper (grid + scan chain + purples)

openlane/
  green_macro/                  # OpenLane config + pin_order for each macro
  orange_macro_h/               # Horizontal orange (bottom & top, dual-sided scan)
  orange_macro_v/               # Vertical orange (right, dual-sided scan)
  purple_macro_p3/              # Purple with PORTS=3 (Top Purple for 3-column grid)
  purple_macro_p4/              # Purple with PORTS=4 (Left/Right Purple for 4-row grid)
  project_macro/                # User project macro
  scan_controller_macro/        # Scan controller
  openframe_project_wrapper/    # Top-level wrapper hardening

verilog/dv/
  common/scan_tasks.vh          # Shared verification tasks
  unit/                         # 5 unit tests (scan_node, scan_ctrl, green, orange, purple)
  integration/                  # 5 integration tests (scan_chain, project_select, gpio_routing, ...)
  regression/                   # Makefile to run all tests

scripts/
  bitstream_gen.py              # Compute scan chain bitstream for a target project

Caravel_OF_MPC.md              # Full architecture specification
```

## Scan Chain

Single 57-bit chain (for 3x4 grid), row-major serpentine order:

```
Scan Controller ──> Purple_Left (3b) ──> Purple_Top (3b) ──> Purple_Right (3b)
  ──> Row 3 R→L: [3,2] [3,1] [3,0]
  ──> Row 2 L→R: [2,0] [2,1] [2,2]
  ──> Row 1 R→L: [1,2] [1,1] [1,0]
  ──> Row 0 L→R: [0,0] [0,1] [0,2] ──> Scan Controller (readback)
```

Within each cell: Green (1b) → Bottom Orange (1b) → Right Orange (1b) → Top Orange (1b).

## Selecting a Project

```python
# Generate the bitstream to enable project at row 2, column 1:
python3 scripts/bitstream_gen.py --rows 4 --cols 3 --row 2 --col 1
```

The external controller:
1. Shifts in magic word (0xA5) to unlock the chain
2. Shifts in 57 configuration bits (project enables + orange selects + purple port selects)
3. Pulses latch — shadow registers capture, chain auto-locks

## Running Verification

```bash
# Run all 10 tests (5 unit + 5 integration):
make -C verilog/dv/regression all

# Run unit tests only:
make -C verilog/dv/unit all

# Run integration tests only:
make -C verilog/dv/integration all

# Run a single test:
make -C verilog/dv/unit tb_green
```

Requires **Icarus Verilog** (`iverilog`) and **VVP**.

## Hardening (OpenLane)

Harden macros bottom-up, then the wrapper:

```bash
# 1. Harden leaf macros (order doesn't matter among these):
cf harden green_macro
cf harden orange_macro_h
cf harden orange_macro_v
cf harden purple_macro_p3
cf harden purple_macro_p4
cf harden scan_controller_macro
cf harden project_macro

# 2. Harden the top-level wrapper:
cf harden openframe_project_wrapper
```

## User Project Development

1. Replace the tie-offs in `verilog/rtl/project_macro.v` with your design logic
2. Your module receives: `clk`, `reset_n`, `por_n`, and 38 GPIOs (15 bottom + 9 right + 14 top)
3. Each GPIO has: `_in` (input from pad), `_out` (output to pad), `_oeb` (output enable bar), `_dm` (3-bit drive mode)
4. Default drive mode `3'b110` = strong digital push-pull

## GPIO Drive Modes

| dm[2:0] | Mode |
|---------|------|
| 3'b000  | High-Z / Analog |
| 3'b001  | Input only |
| 3'b010  | Input with pull-down |
| 3'b011  | Input with pull-up |
| 3'b110  | Strong push-pull output (default) |
| 3'b101  | Open-drain output |

## Documentation

See **[Caravel_OF_MPC.md](Caravel_OF_MPC.md)** for the full architecture specification including:
- Detailed module port tables
- Scan chain bit position map
- Floorplan analysis and macro dimensions
- GPIO MUX tree data flow
- Reset behavior (POR vs sys_reset_n)

## License

Apache 2.0
