p = "lib/screens/goals_screen.dart"
s = open(p, encoding="utf-8").read()
old = "_GoalEditorSheetState extends State<_GoalEditorSheet>"
new = "class _GoalEditorSheetState extends State<_GoalEditorSheet>"
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("fixed")
