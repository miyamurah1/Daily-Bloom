"""Print the brace depth after every line (implies stack balance)."""
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
            print(f"line {i}: UNDERFLOW depth={depth} {line!r}")
            depth = 0
        print(f"{i:4d}: {depth:3d} {line}")

    print(f"final depth: {depth}")


if __name__ == "__main__":
    main()
