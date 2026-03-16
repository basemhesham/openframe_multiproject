#!/usr/bin/env python3
"""
Bitstream Generator for Multi-Project OpenFrame Chip

Computes the scan chain bitstream needed to:
  1. Unlock the security controller (magic word)
  2. Enable a specific project in the ROWS x COLS grid

Usage:
    python3 bitstream_gen.py --rows 3 --cols 3 --project 4
    python3 bitstream_gen.py --rows 4 --cols 4 --row 2 --col 1
    python3 bitstream_gen.py --rows 3 --cols 3 --project 4 --format verilog
"""

import argparse
import sys


def serpentine_index(row: int, col: int, cols: int) -> int:
    """Convert (row, col) grid position to serpentine scan chain index."""
    if row % 2 == 0:
        return row * cols + col           # left to right
    else:
        return row * cols + (cols - 1 - col)  # right to left


def grid_position(scan_idx: int, rows: int, cols: int) -> tuple:
    """Convert scan chain index back to (row, col) grid position."""
    row = scan_idx // cols
    col_in_row = scan_idx % cols
    if row % 2 == 0:
        col = col_in_row
    else:
        col = cols - 1 - col_in_row
    return (row, col)


def generate_bitstream(rows: int, cols: int, target_project: int,
                       magic_word: int = 0xA5) -> list:
    """
    Generate the complete bitstream to unlock and enable a project.

    The scan chain structure is:
      [Magic Word (8 bits)] [Project 0 enable] [Project 1 enable] ... [Project N-1 enable]

    Bits are shifted in MSB-first (magic word bit 7 first).
    The entire bitstream is shifted through scan_din, then scan_latch is pulsed.

    Returns:
        List of bit values (0/1) in shift order (first shifted = first element).
    """
    num_projects = rows * cols

    if target_project < 0 or target_project >= num_projects:
        raise ValueError(
            f"Project index {target_project} out of range [0, {num_projects-1}]"
        )

    # Magic word bits: MSB first
    magic_bits = [(magic_word >> (7 - i)) & 1 for i in range(8)]

    # Project enable bits: project 0 is shifted first (closest to controller)
    # so it ends up at the far end of the chain. We need the target bit
    # at position `target_project` in the enable vector.
    enable_bits = [0] * num_projects
    enable_bits[target_project] = 1

    # Complete bitstream: magic word first, then enables
    # Since bits shift through, the first bit shifted ends up at the far end.
    # The scan chain is: controller -> green[0] -> green[1] -> ... -> green[N-1]
    # So we need to shift enables in reverse order (last project first),
    # then the magic word.
    bitstream = enable_bits[::-1] + magic_bits

    return bitstream


def format_hex(bits: list) -> str:
    """Format bitstream as hex string."""
    # Pad to multiple of 4
    padded = bits + [0] * ((4 - len(bits) % 4) % 4)
    hex_str = ""
    for i in range(0, len(padded), 4):
        nibble = (padded[i] << 3) | (padded[i+1] << 2) | (padded[i+2] << 1) | padded[i+3]
        hex_str += f"{nibble:X}"
    return hex_str


def format_binary(bits: list) -> str:
    """Format bitstream as binary string with separators."""
    return "".join(str(b) for b in bits)


def print_timing_diagram(bits: list, label: str = "scan_din"):
    """Print a simple ASCII timing diagram."""
    print(f"\n{'='*60}")
    print("Timing Diagram")
    print(f"{'='*60}")
    print(f"Total bits to shift: {len(bits)}")
    print()

    # Show bit indices
    idx_line = "Bit#:    "
    for i in range(len(bits)):
        idx_line += f"{i:>3}"
    print(idx_line)

    # Show data line
    dat_line = f"{label}: "
    for b in bits:
        dat_line += f"  {b}"
    print(dat_line)

    # Show clock edges
    clk_line = "scan_clk: "
    for _ in bits:
        clk_line += " /\\"
    print(clk_line)

    print()
    print("After all bits shifted, pulse scan_latch HIGH for 1 clock cycle.")
    print(f"{'='*60}")


def print_grid_map(rows: int, cols: int, target: int):
    """Print the physical grid with serpentine scan indices."""
    print(f"\n{'='*60}")
    print(f"Grid Layout ({rows}x{cols}) — Serpentine Scan Chain Order")
    print(f"{'='*60}")
    print()
    for r in range(rows):
        row_str = "  "
        for c in range(cols):
            idx = serpentine_index(r, c, cols)
            marker = " *" if idx == target else "  "
            row_str += f"[{idx:>2}{marker}] "
        # Show scan direction arrow
        if r % 2 == 0:
            row_str += " →"
        else:
            row_str += " ←"
        print(row_str)
        if r < rows - 1:
            # Show vertical connection
            if r % 2 == 0:
                print(" " * (4 * cols + 2) + "↓")
            else:
                print("  ↓")
    print()
    print(f"  * = Target project (scan index {target})")
    tgt_row, tgt_col = grid_position(target, rows, cols)
    print(f"    Grid position: row={tgt_row}, col={tgt_col}")


def format_verilog_task(bits: list, rows: int, cols: int, target: int,
                        magic_word: int) -> str:
    """Generate a Verilog task for shifting in the bitstream."""
    lines = []
    lines.append(f"// Bitstream for {rows}x{cols} grid, project {target}, magic=0x{magic_word:02X}")
    lines.append(f"// Total bits: {len(bits)}")
    lines.append("task automatic scan_load_project;")
    lines.append("  integer i;")
    lines.append(f"  reg [{len(bits)-1}:0] bitstream;")
    lines.append("  begin")
    hex_val = format_hex(bits)
    lines.append(f"    bitstream = {len(bits)}'b{format_binary(bits)};")
    lines.append(f"    for (i = {len(bits)-1}; i >= 0; i = i - 1) begin")
    lines.append("      scan_din = bitstream[i];")
    lines.append("      @(posedge scan_clk);")
    lines.append("    end")
    lines.append("    // Latch configuration")
    lines.append("    scan_latch = 1'b1;")
    lines.append("    @(posedge scan_clk);")
    lines.append("    scan_latch = 1'b0;")
    lines.append("  end")
    lines.append("endtask")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate scan chain bitstream for multi-project OpenFrame chip"
    )
    parser.add_argument("--rows", type=int, required=True, help="Number of grid rows")
    parser.add_argument("--cols", type=int, required=True, help="Number of grid columns")

    # Project selection: either by index or by row/col
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--project", type=int, help="Project scan chain index")
    group.add_argument("--row", type=int, help="Project grid row (use with --col)")

    parser.add_argument("--col", type=int, help="Project grid column (use with --row)")
    parser.add_argument("--magic", type=lambda x: int(x, 0), default=0xA5,
                        help="Magic word (default: 0xA5)")
    parser.add_argument("--format", choices=["text", "hex", "binary", "verilog"],
                        default="text", help="Output format")

    args = parser.parse_args()

    if args.row is not None:
        if args.col is None:
            parser.error("--col is required when using --row")
        if args.row >= args.rows or args.col >= args.cols:
            parser.error(f"Position ({args.row},{args.col}) out of range for {args.rows}x{args.cols} grid")
        target = serpentine_index(args.row, args.col, args.cols)
    else:
        target = args.project

    num_projects = args.rows * args.cols
    if target < 0 or target >= num_projects:
        print(f"Error: project index {target} out of range [0, {num_projects-1}]",
              file=sys.stderr)
        sys.exit(1)

    bitstream = generate_bitstream(args.rows, args.cols, target, args.magic)

    if args.format == "hex":
        print(format_hex(bitstream))
    elif args.format == "binary":
        print(format_binary(bitstream))
    elif args.format == "verilog":
        print(format_verilog_task(bitstream, args.rows, args.cols, target, args.magic))
    else:
        # Full text report
        print(f"\nMulti-Project OpenFrame Bitstream Generator")
        print(f"{'='*60}")
        print(f"Grid:         {args.rows} x {args.cols} ({num_projects} projects)")
        print(f"Target:       Project {target}")
        tgt_row, tgt_col = grid_position(target, args.rows, args.cols)
        print(f"Grid pos:     row={tgt_row}, col={tgt_col}")
        print(f"Magic word:   0x{args.magic:02X}")
        print(f"Total bits:   {len(bitstream)}")
        print(f"Hex:          0x{format_hex(bitstream)}")
        print(f"Binary:       {format_binary(bitstream)}")

        print_grid_map(args.rows, args.cols, target)
        print_timing_diagram(bitstream)


if __name__ == "__main__":
    main()
