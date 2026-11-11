"""Remove the unused private helper _confirmDeleteGoal from habits_screen.dart."""
from __future__ import annotations

import sys

PATH = "lib/screens/habits_screen.dart"


def main() -> None:
    with open(PATH, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    start = None
    for i, line in enumerate(lines):
        if line.strip().startswith("Future<void> _confirmDeleteGoal"):
            start = i
            break

    if start is None:
        print("Could not find _confirmDeleteGoal")
        sys.exit(1)

    # Locate the closing brace of the `if (yes == true) { ... }` block.
    if_close = None
    for i in range(start + 1, len(lines)):
        if lines[i].strip() == "}":
            if_close = i
            break

    if if_close is None:
        print("Could not locate the closing brace of the confirm dialog")
        sys.exit(1)

    # if_close is the `}` for `if (yes == true) {`; the method itself closes
    # on the next line.
    method_close = if_close + 1
    del lines[start:method_close + 1]

    with open(PATH, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
        fh.write("\n")


if __name__ == "__main__":
    main()
