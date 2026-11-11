"""Print a simple brace-depth trace for a Dart file."""
from __future__ import annotations

import sys

PATH = "lib/screens/habits_screen.dart"


def main() -> None:
    with open(PATH, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    depth = 0
    for i, line in enumerate(lines, start=1):
        for ch in line:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
        if depth < 0:
            print(f"line {i}: UNDERFLOW {depth} -> {line!r}")
            depth = 0
        # Print a compact trace for notable braces
        stripped = line.strip()
        if stripped.startswith("class ") or stripped.startswith("Widget ") or stripped.startswith("Future<") or stripped.endswith(":") or stripped == "{" or stripped == "}":
            print(f"line {i:4d} depth={depth:3d} {stripped[:60]!r}")

    print(f"final depth: {depth}")


if __name__ == "__main__":
    main()
