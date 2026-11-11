p = "lib/screens/goals_screen.dart"
lines = open(p, encoding="utf-8").read().split("\n")
for i in range(388, 404):
    print(f"{i+1:4} | {lines[i]}")
