p = "lib/screens/goals_screen.dart"
s = open(p, encoding="utf-8").read()

marker = "_GoalEditorSheetState extends State<_GoalEditorSheet> {"
index = s.find(marker)
assert index != -1, "marker not found"

widget_class = """class _GoalEditorSheet extends StatefulWidget {
  const _GoalEditorSheet({super.key});

  @override
  _GoalEditorSheetState createState() => _GoalEditorSheetState();
}

"""

s = s[:index] + widget_class + s[index:]
open(p, "w", encoding="utf-8").write(s)
print("inserted _GoalEditorSheet widget")
