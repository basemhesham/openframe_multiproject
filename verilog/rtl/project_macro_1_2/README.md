# Cryptic: BLAKE2s-256 hardware hash accelerator — submission bundle v1

This folder is a **frozen package** for course / repository submission. It contains the **signoff run** `blake2s_grt_ant10_20260503_2314`, **RTL and constraints** used for that build, **tapeout views** (GDS/LEF and related artifacts under `final/`), and **cocotb** verification sources.

A single-block, unkeyed **BLAKE2s-256** cryptographic hash accelerator for the OpenFrame `project_macro` slot. The design accepts a **64-byte** message and produces a **32-byte** digest, controlled via a **4-wire SPI** register interface.

The core is **iterative**: a **single G-function unit** is reused for all **80** mixing operations (8 per round × 10 rounds), favoring **area** over throughput. Datapath operations map to Sky130 standard cells with **no lookup tables or SRAM**.

## What is in this directory

| Path | Contents |
| --- | --- |
| `design_source/` | `config.json`, `pnr.sdc`, `signoff.sdc`, `pin_order.cfg`, `fixed_dont_change/project_macro.def`, and `verilog_rtl/` (BLAKE2s RTL + `project_macro.v` + power tie cells). |
| `run_blake2s_grt_ant10_20260503_2314/` | `error.log`, `warning.log`, `flow.log`, `resolved.json`, timing/antenna summary reports, `signoff_reports/` (DRC/LVS/manufacturability), and full **`final/`** (GDS, LEF, DEF, ODB, SPEF, SDF, `.lib`, extracted spice, metrics, etc.). |
| `verification/` | cocotb test (`cocotb/blake2s_openframe/`), `setup-cocotb.py`, Verilog benches (`tb_*.v`), and DV `README.md`. |
| `project_macro.gds`, `project_macro.lef` | Copies of the Magic-streamed GDS and macro LEF from `final/` for quick access. |

**Note:** The packaged OpenLane/LibreLane run is a **continuation** from post-global-route antenna work through signoff (upstream steps were skipped in that invocation); `flow.log` documents which steps ran. Signoff metrics in `final/metrics.json` report **zero** setup/hold violation counts, **zero** route antenna violations, and **zero** Magic/KLayout DRC and LVS error counts for that run.

## Parameters (as implemented for this submission)

| Parameter | Value | Rationale |
| --- | --- | --- |
| Algorithm | BLAKE2s (32-bit variant) | Smaller datapath than BLAKE2b |
| Output length | Fixed 256-bit (32 bytes) | No configurable `nn` |
| Key mode | None (unkeyed, `kk=0`) | No key path |
| Input | Single 512-bit block (64 bytes) | Single-block only |
| Rounds | 10 | Per BLAKE2s spec |
| Datapath | Iterative: 1 G-function unit, 80 uses | Area-efficient |
| Interface | 4-wire SPI (42-bit frame) | OpenFrame register style |
| Clock | 50 ns period in `config.json` (20 MHz) for this build | See `design_source/config.json` |
| Die | 880 × 1031.66 µm² (from `DIE_AREA` in config) | OpenFrame macro contract |
| Process | SkyWater 130 nm (Sky130A) | Workshop PDK |
| Metal layers | Up to met4 (`RT_MAX_LAYER`) | OpenFrame met5 reserved for top-level |
| Verification | cocotb vs Python `hashlib.blake2s` | Sources under `verification/` |

## Repository

[ASIC-hub/si-sprint26-project-cryptic-shazli-and-malak](https://github.com/ASIC-hub/si-sprint26-project-cryptic-shazli-and-malak)
