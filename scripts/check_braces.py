p = "lib/screens/goals_screen.dart"
lines = open(p, encoding="utf-8").read().split("\n")

start = next(i for i, l in enumerate(lines) if l.startswith("class _GoalsScreenState"))
end = next(i for i, l in enumerate(lines) if i > start and l.startswith("_GoalEditorSheetState"))
print("start", start + 1, "end", end + 1)

open_count = 0
for i in range(start, len(lines)):
    for ch in lines[i]:
        if ch == "{":
            open_count += 1
        elif ch == "}":
            open_count -= 1
    if open_count < 0:
        print("UNBALANCED below line", i + 1)
        break
print("brace depth after end:", open_count)
