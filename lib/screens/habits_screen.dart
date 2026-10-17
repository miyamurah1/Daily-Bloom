import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/habit_store.dart';
import '../game/bloom_game_colors.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_dialog.dart';

/// Icon choices shared by the habit + goal sheets.
const _habitIcons = [
  LucideIcons.sprout,
  LucideIcons.dumbbell,
  LucideIcons.droplets,
  LucideIcons.footprints,
  LucideIcons.brain,
  LucideIcons.bookOpen,
  LucideIcons.moon,
  LucideIcons.flower2,
];

/// Accent choices - theme-relative, never hard neon.
Color _accentFor(int i) {
  switch (i % 4) {
    case 1:
      return const Color(0xFF4CAF7D);
    case 2:
      return const Color(0xFF4A9ED5);
    default:
      return SakuraColors.primary;
  }
}
IconData _iconFor(int i) => _habitIcons[i % _habitIcons.length];
String _fmtTarget(num t) => t == t.roundToDouble() ? '${t.round()}' : '$t';
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}
class _HabitsScreenState extends State<HabitsScreen> {
  final _store = HabitStore.instance;
  @override
  void initState() {
    super.initState();
    _store.load();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final best = _store.bestStreak;
            return RefreshIndicator(
              color: SakuraColors.primary,
              onRefresh: () => _store.load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                children: [
                  _header(best),
                  const SizedBox(height: 14),
                  _todayCard(),
                  const SizedBox(height: 12),
                  _journeyCard(best),
                  const SizedBox(height: 16),
                  _addRow(),
                  const SizedBox(height: 12),
                  for (final g in _store.goals) ...[
                    _GoalGroup(goal: g, key: ValueKey('goal-${g.id}')),
                    const SizedBox(height: 12),
                  ],
                  if (_store.ungrouped.isNotEmpty) ...[
                    const _UngroupedGroup(key: ValueKey('goal-ungrouped')),
                    const SizedBox(height: 12),
                  ],
                  if (_store.habits.isEmpty) _emptyState(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  Widget _header(int best) {
    final today = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final date = '${months[today.month - 1]} ${today.day}';
    final sub = best <= 0 ? 'Small steps, daily - $date' : 'Best run: $best day${best == 1 ? '' : 's'} - $date';
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Habits', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: SakuraColors.ink)), const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 12, color: SakuraColors.inkSoft))])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: SakuraColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SakuraColors.cardBorder)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.flame, size: 15, color: SakuraColors.primary), const SizedBox(width: 6), Text('$best', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SakuraColors.ink, fontFeatures: const [FontFeature.tabularFigures()]))])),
    ]);
  }
  Widget _todayCard() {
    final done = _store.doneTodayCount;
    final total = _store.activeTodayCount;
    final p = _store.todayProgress;
    final label = total == 0 ? 'No habits yet - add your first below.' : done == total ? 'All done. Savour it.' : done == 0 ? 'A gentle start counts.' : 'Keep tending - $done of $total.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('TODAY', style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: SakuraColors.inkFaint)), const Spacer(), Text('$done/$total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SakuraColors.ink, fontFeatures: const [FontFeature.tabularFigures()]))]),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: p), duration: AppMotion.progress, curve: AppMotion.progressCurve, builder: (context, v, _) => ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: total == 0 ? 0 : v, minHeight: 8, backgroundColor: SakuraColors.primarySoft, valueColor: AlwaysStoppedAnimation<Color>(SakuraColors.primary)))),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12.5, height: 1.45, color: SakuraColors.inkSoft)),
      ]),
    );
  }
  Widget _addRow() {
    return Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: () => showHabitSheet(context), icon: const Icon(LucideIcons.plus, size: 16), label: const Text('Habit'), style: OutlinedButton.styleFrom(foregroundColor: SakuraColors.ink, side: BorderSide(color: SakuraColors.cardBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: () => showGoalSheet(context), icon: const Icon(LucideIcons.target, size: 16), label: const Text('Goal', style: TextStyle(fontWeight: FontWeight.w700)), style: FilledButton.styleFrom(backgroundColor: SakuraColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)))),
    ]);
  }
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: SakuraColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(LucideIcons.sprout, size: 22, color: SakuraColors.primary)),
        const SizedBox(height: 12),
        Text('Begin with one small promise', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SakuraColors.ink)),
        const SizedBox(height: 6),
        Text('Write a goal (Calm mornings), then hang a tiny daily habit under it. Two minutes a day beats a perfect plan.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.55, color: SakuraColors.inkSoft)),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: () => showGoalSheet(context), icon: const Icon(LucideIcons.target, size: 16), label: const Text('Write your first goal'), style: FilledButton.styleFrom(backgroundColor: SakuraColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
        const SizedBox(height: 14),
        Text('OR START FROM A RITUAL', style: TextStyle(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: SakuraColors.inkFaint)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in RitualPresets.presets)
              GestureDetector(
                onTap: () async {
                  final n = await HabitStore.instance.applyPreset(p);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n > 0
                          ? 'Planted ${p.goalName} ($n new).'
                          : 'Already growing.')));
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: SakuraColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SakuraColors.cardBorder),
                  ),
                  child: Text(
                    p.goalName,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
  Widget _journeyCard(int best) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('THE JOURNEY', style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: SakuraColors.inkFaint)),
        const SizedBox(height: 12),
        Row(children: [_node(day: 3, name: 'Sprout', icon: LucideIcons.sprout, best: best), _line(from: 0, to: 3, best: best), _node(day: 7, name: 'Rooted', icon: LucideIcons.leaf, best: best), _line(from: 3, to: 7, best: best), _node(day: 21, name: 'Bloom', icon: LucideIcons.flower2, best: best), _line(from: 7, to: 21, best: best), _node(day: 30, name: 'Ritual', icon: LucideIcons.crown, best: best)]),
        const SizedBox(height: 10),
        Text(_journeyText(best), style: TextStyle(fontSize: 12, height: 1.5, color: SakuraColors.inkSoft)),
      ]),
    );
  }
  String _journeyText(int best) {
    if (best <= 0) return 'Day one is the hardest - check in a single habit to plant your streak.';
    if (best < 3) return '${3 - best} day${3 - best == 1 ? '' : 's'} to Sprout. Protect the next sunrise.';
    if (best < 7) return '${7 - best} day${7 - best == 1 ? '' : 's'} to Rooted. Same time, same breath.';
    if (best < 21) return '${21 - best} days to Bloom. Past willpower now - this is rhythm.';
    if (best < 30) return '${30 - best} days to Ritual. Tend it gently; mastery is quiet.';
    return '$best-day ritual - mastered, not finished.';
  }
  Widget _node({required int day, required String name, required IconData icon, required int best}) {
    final hit = best >= day;
    return SizedBox(
      width: 44,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(duration: AppMotion.toggle, curve: AppMotion.toggleCurve, width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: hit ? SakuraColors.primary.withValues(alpha: 0.12) : SakuraColors.surface, border: Border.all(color: hit ? SakuraColors.primary.withValues(alpha: 0.55) : SakuraColors.cardBorder, width: hit ? 1.6 : 1)), child: Icon(icon, size: 18, color: hit ? SakuraColors.primary : SakuraColors.inkFaint)),
        const SizedBox(height: 6),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: hit ? SakuraColors.ink : SakuraColors.inkFaint)),
        Text('${day}d', style: TextStyle(fontSize: 10, color: SakuraColors.inkFaint, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
  Widget _line({required int from, required int to, required int best}) {
    final frac = ((best - from) / (to - from)).clamp(0.0, 1.0);
    return Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 30, left: 4, right: 4), child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: frac), duration: AppMotion.progress, curve: AppMotion.progressCurve, builder: (context, v, _) => ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: SakuraColors.primarySoft, valueColor: AlwaysStoppedAnimation<Color>(SakuraColors.primary.withValues(alpha: 0.85)))))));
  }
}
/// One goal section: header + its habits.
class _GoalGroup extends StatelessWidget {
  final HabitGoal goal;
  const _GoalGroup({super.key, required this.goal});
  @override
  Widget build(BuildContext context) {
    final store = HabitStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final habits = store.habitsFor(goal.id);
        final active = habits.where((h) => !h.paused).toList();
        final done = active.where((h) => h.doneToday).length;
        final accent = _accentFor(goal.accentIndex);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: SakuraTheme.cardDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withValues(alpha: 0.3))), child: Icon(_iconFor(goal.iconIndex), size: 19, color: accent)),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                // The name IS the edit affordance — no hunting in ⋯.
                onTap: () => showGoalSheet(context, goal: goal),
                behavior: HitTestBehavior.opaque,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GOAL', style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: accent)), const SizedBox(height: 2), Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SakuraColors.ink))]),
              )),
              if (active.isNotEmpty) Text('$done/${active.length}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SakuraColors.inkSoft, fontFeatures: const [FontFeature.tabularFigures()])),
              PopupMenuButton<String>(icon: Icon(LucideIcons.ellipsis, size: 17, color: SakuraColors.inkFaint), color: SakuraColors.surface, onSelected: (v) {
                if (v == 'add') {
                  showHabitSheet(context, goalId: goal.id);
                } else if (v == 'edit') {
                  showGoalSheet(context, goal: goal);
                } else if (v == 'delete') {
                  _confirmDeleteGoal(context, goal);
                }
              }, itemBuilder: (_) => const [PopupMenuItem(value: 'add', child: Text('Add habit here')), PopupMenuItem(value: 'edit', child: Text('Edit goal')), PopupMenuItem(value: 'delete', child: Text('Delete goal'))]),
            ]),
            if (goal.intention.isNotEmpty) ...[const SizedBox(height: 6), Text(goal.intention, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.5, color: SakuraColors.inkSoft))],
            const SizedBox(height: 12),
            if (habits.isEmpty)
              GestureDetector(
                onTap: () => showHabitSheet(context, goalId: goal.id),
                behavior: HitTestBehavior.opaque,
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13), decoration: BoxDecoration(color: SakuraColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: SakuraColors.primary.withValues(alpha: 0.25))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(LucideIcons.plus, size: 14, color: SakuraColors.primary), const SizedBox(width: 6), Text('Add the first habit', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: SakuraColors.primary))])),
              )
            else
              for (var i = 0; i < habits.length; i++) ...[
                HabitRow(habit: habits[i], key: ValueKey('habit-${habits[i].id}')),
                if (i < habits.length - 1) const SizedBox(height: 8),
              ],
          ]),
        );
      },
    );
  }
  Future<void> _confirmDeleteGoal(BuildContext context, HabitGoal goal) async {
    final n = HabitStore.instance.habitsFor(goal.id).length;
    final msg = n == 0 ? 'This cannot be undone.' : 'Its $n habit${n == 1 ? '' : 's'} move to Ungrouped - nothing is lost.';
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(backgroundColor: SakuraColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: Text('Delete "${goal.name}"?', style: TextStyle(color: SakuraColors.ink, fontWeight: FontWeight.w800)), content: Text(msg, style: TextStyle(color: SakuraColors.inkSoft)), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: SakuraColors.primary), child: const Text('Delete'))]));
    if (yes == true) {
      await HabitStore.instance.removeGoal(goal.id);
    }
  }
}
/// Habits without a goal.
class _UngroupedGroup extends StatelessWidget {
  const _UngroupedGroup({super.key});
  @override
  Widget build(BuildContext context) {
    final store = HabitStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final habits = store.ungrouped;
        if (habits.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: SakuraTheme.cardDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: SakuraColors.inkFaint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: SakuraColors.cardBorder)), child: Icon(LucideIcons.inbox, size: 19, color: SakuraColors.inkSoft)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('STANDALONE', style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: SakuraColors.inkFaint)), const SizedBox(height: 2), Text('Ungrouped', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SakuraColors.ink))])),
              GestureDetector(onTap: () => showHabitSheet(context), behavior: HitTestBehavior.opaque, child: Semantics(button: true, label: 'Add habit', child: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: SakuraColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(LucideIcons.plus, size: 15, color: SakuraColors.primary)))),
            ]),
            const SizedBox(height: 12),
            for (var i = 0; i < habits.length; i++) ...[
              HabitRow(habit: habits[i], key: ValueKey('habit-${habits[i].id}')),
              if (i < habits.length - 1) const SizedBox(height: 8),
            ],
          ]),
        );
      },
    );
  }
}

/// One habit row: tap to check in, stepper for counted, streak chip.
class HabitRow extends StatelessWidget {
  final Habit habit;
  const HabitRow({super.key, required this.habit});
  @override
  Widget build(BuildContext context) {
    final store = HabitStore.instance;
    final accent = _accentFor(habit.accentIndex);
    final done = habit.doneToday;
    final streak = habit.streak;
    final todayKey = HabitStore.dayKey(DateTime.now());
    final amount = habit.amountOn(todayKey);
    final frac = habit.counted ? (amount / (habit.target <= 0 ? 1 : habit.target)).clamp(0.0, 1.0).toDouble() : (done ? 1.0 : 0.0);
    final sub = habit.counted ? '${_fmtTarget(amount)} / ${_fmtTarget(habit.target)}${habit.unit.isEmpty ? '' : ' ${habit.unit}'}' : null;
    return Dismissible(
      key: ValueKey('dismiss-${habit.id}'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 18), decoration: BoxDecoration(color: const Color(0xFFD92B4B).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)), child: const Icon(LucideIcons.trash2, size: 17, color: Color(0xFFD92B4B))),
      confirmDismiss: (_) async {
        final removed = await HabitStore.instance.removeHabit(habit.id);
        if (removed != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "${removed.name}"'), action: SnackBarAction(label: 'Undo', onPressed: () => HabitStore.instance.restoreHabit(removed))));
        }
        return false;
      },
      child: AnimatedOpacity(
        duration: AppMotion.toggle,
        curve: AppMotion.toggleCurve,
        opacity: habit.paused ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SakuraColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: habit.frozen ? BloomGameColors.icyBlue.withValues(alpha: 0.45) : done ? accent.withValues(alpha: 0.45) : SakuraColors.cardBorder, width: done || habit.frozen ? 1.3 : 1)),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: habit.paused || habit.counted ? null : () => store.toggleToday(habit.id),
                behavior: HitTestBehavior.opaque,
                child: Tooltip(
                  message: done ? 'Done today' : 'Check in today',
                  child: AnimatedContainer(duration: AppMotion.toggle, curve: AppMotion.toggleCurve, width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: done ? accent : Colors.transparent, border: Border.all(color: done ? accent : SakuraColors.inkFaint.withValues(alpha: 0.5), width: 1.6)), child: done ? const Icon(LucideIcons.check, size: 15, color: Colors.white) : Icon(_iconFor(habit.iconIndex), size: 14, color: SakuraColors.inkFaint)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(onTap: () => showHabitSheet(context, habit: habit), behavior: HitTestBehavior.opaque, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(habit.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: SakuraColors.ink, decoration: done && !habit.counted ? TextDecoration.lineThrough : null)), if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 11.5, color: done ? accent : SakuraColors.inkSoft, fontWeight: FontWeight.w600))], if (habit.intention.isNotEmpty) ...[const SizedBox(height: 1), Text(habit.intention, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: SakuraColors.inkFaint))]]))),
              if (habit.frozen)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => unfreezeHabitFlow(context, habit),
                    behavior: HitTestBehavior.opaque,
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: BloomGameColors.icyBlue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: BloomGameColors.icyBlue.withValues(alpha: 0.45), width: 0.9)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(LucideIcons.snowflake, size: 11, color: BloomGameColors.icyBlue), const SizedBox(width: 3), Text('$streak', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: BloomGameColors.icyBlue, fontFeatures: [FontFeature.tabularFigures()]))])),
                  ),
                )
              else if (streak >= 2) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.flame, size: 11, color: accent), const SizedBox(width: 3), Text('$streak', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent, fontFeatures: const [FontFeature.tabularFigures()]))])),
            ]),
            if (habit.counted && !habit.paused) ...[
              const SizedBox(height: 10),
              Row(children: [
                _stepBtn(icon: LucideIcons.minus, label: 'Log less today', onTap: () => store.logToday(habit.id, -1)),
                const SizedBox(width: 8),
                Expanded(child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: frac), duration: AppMotion.progress, curve: AppMotion.progressCurve, builder: (context, v, _) => ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: SakuraColors.primarySoft, valueColor: AlwaysStoppedAnimation<Color>(done ? accent : SakuraColors.primary))))),
                const SizedBox(width: 8),
                _stepBtn(icon: LucideIcons.plus, primary: true, label: 'Log more today', onTap: () => store.logToday(habit.id, 1)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
  Widget _stepBtn({required IconData icon, required VoidCallback onTap, bool primary = false, required String label}) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Semantics(button: true, label: label, child: Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: primary ? SakuraColors.primary : SakuraColors.surface, shape: BoxShape.circle, border: Border.all(color: primary ? SakuraColors.primary : SakuraColors.cardBorder)), child: Icon(icon, size: 14, color: primary ? Colors.white : SakuraColors.inkSoft))));
  }
}
/// Thaw flow shared by the row pill and the edit sheet: confirm, spend,
/// report. Returns true when the habit actually thawed.
Future<bool> unfreezeHabitFlow(BuildContext context, Habit habit) async {
  final yes = await showBloomConfirm(
    context,
    title: 'Unfreeze "${habit.name}"?',
    message:
        'Thawing costs ${HabitStore.unfreezeTokens} tokens. Your streak recomputes from your log from here.',
    confirmLabel: 'Unfreeze',
  );
  if (!yes || !context.mounted) return false;
  final ok = await HabitStore.instance.unfreezeHabit(habit.id);
  if (!context.mounted) return ok;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Thawed — your streak is live again.'
          : 'Not enough tokens — thaw costs ${HabitStore.unfreezeTokens}.')));
  return ok;
}

/// Bottom sheet: create or edit a goal (name + why + icon + accent).
Future<void> showGoalSheet(BuildContext context, {HabitGoal? goal}) async {
  final nameCtrl = TextEditingController(text: goal?.name ?? '');
  final whyCtrl = TextEditingController(text: goal?.intention ?? '');
  var icon = goal?.iconIndex ?? 0;
  var accent = goal?.accentIndex ?? 0;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SakuraColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 12),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: SakuraColors.cardBorder, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 14),
          Text(goal == null ? 'New goal' : 'Edit goal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: SakuraColors.ink)),
          const SizedBox(height: 4),
          Text('Name the life you are growing toward.', style: TextStyle(fontSize: 12.5, color: SakuraColors.inkSoft)),
          const SizedBox(height: 14),
          _sheetLabel('GOAL NAME'),
          TextField(controller: nameCtrl, autofocus: goal == null, textCapitalization: TextCapitalization.sentences, maxLength: 40, onChanged: (_) => setSheet(() {}), decoration: _sheetField(hint: 'e.g. Calm mornings')),
          const SizedBox(height: 12),
          _sheetLabel('WHY IT MATTERS - OPTIONAL'),
          TextField(controller: whyCtrl, textCapitalization: TextCapitalization.sentences, maxLines: 2, maxLength: 120, decoration: _sheetField(hint: 'e.g. Start steady instead of reactive')),
          const SizedBox(height: 12),
          _sheetLabel('ICON'),
          Wrap(spacing: 8, runSpacing: 8, children: List.generate(_habitIcons.length, (i) {
            final sel = i == icon;
            return GestureDetector(onTap: () => setSheet(() => icon = i), behavior: HitTestBehavior.opaque, child: Semantics(button: true, label: 'Choose icon ${i + 1}', child: Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: sel ? SakuraColors.primary.withValues(alpha: 0.12) : SakuraColors.background, borderRadius: BorderRadius.circular(13), border: Border.all(color: sel ? SakuraColors.primary : SakuraColors.cardBorder, width: sel ? 1.6 : 1)), child: Icon(_habitIcons[i], size: 18, color: sel ? SakuraColors.primary : SakuraColors.inkSoft))));
          })),
          const SizedBox(height: 12),
          _sheetLabel('ACCENT'),
          Wrap(spacing: 8, children: List.generate(4, (i) {
            final sel = i == accent;
            final c = i == 0 ? SakuraColors.primary : i == 1 ? const Color(0xFF4CAF7D) : i == 2 ? const Color(0xFF4A9ED5) : const Color(0xFFE8A33D);
            return GestureDetector(onTap: () => setSheet(() => accent = i), behavior: HitTestBehavior.opaque, child: Semantics(button: true, label: 'Accent color ${i + 1}', child: Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: c.withValues(alpha: sel ? 0.2 : 0.1), shape: BoxShape.circle, border: Border.all(color: sel ? c : Colors.transparent, width: 2)), child: Container(width: 16, height: 16, decoration: BoxDecoration(color: c, shape: BoxShape.circle)))));
          })),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: nameCtrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: SakuraColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(goal == null ? 'Create goal' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w700)))),
          const SizedBox(height: 20),
        ]),
      ),
    )),
  );
  if (saved != true) return;
  if (goal == null) {
    await HabitStore.instance.addGoal(name: nameCtrl.text, intention: whyCtrl.text, iconIndex: icon, accentIndex: accent);
  } else {
    await HabitStore.instance.updateGoal(goal.id, name: nameCtrl.text, intention: whyCtrl.text, iconIndex: icon, accentIndex: accent);
  }
}
/// Bottom sheet: create or edit a habit.
Future<void> showHabitSheet(BuildContext context, {Habit? habit, String? goalId}) async {
  final store = HabitStore.instance;
  final nameCtrl = TextEditingController(text: habit?.name ?? '');
  final whyCtrl = TextEditingController(text: habit?.intention ?? '');
  final t0 = habit != null && habit.counted ? _fmtTarget(habit.target) : '8';
  final targetCtrl = TextEditingController(text: t0);
  final unitCtrl = TextEditingController(text: habit?.unit ?? '');
  var counted = habit?.counted ?? false;
  var goal = habit?.goalId ?? goalId;
  var icon = habit?.iconIndex ?? 0;
  var frozenNow = habit?.frozen ?? false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SakuraColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: SakuraColors.cardBorder, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 14),
            Text(habit == null ? 'New habit' : 'Edit habit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: SakuraColors.ink)),
            const SizedBox(height: 14),
            _sheetLabel('HABIT NAME'),
            TextField(controller: nameCtrl, autofocus: habit == null, textCapitalization: TextCapitalization.sentences, maxLength: 40, onChanged: (_) => setSheet(() {}), decoration: _sheetField(hint: 'e.g. Read 10 pages')),
            const SizedBox(height: 12),
            _sheetLabel('WHY - OPTIONAL'),
            TextField(controller: whyCtrl, textCapitalization: TextCapitalization.sentences, maxLines: 2, maxLength: 120, decoration: _sheetField(hint: 'e.g. Wind down without screens')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: GestureDetector(onTap: () => setSheet(() => counted = false), child: Container(padding: const EdgeInsets.symmetric(vertical: 11), alignment: Alignment.center, decoration: BoxDecoration(color: !counted ? SakuraColors.primary.withValues(alpha: 0.12) : SakuraColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: !counted ? SakuraColors.primary : SakuraColors.cardBorder)), child: Text('Yes / No', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: !counted ? SakuraColors.primary : SakuraColors.inkSoft))))),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(onTap: () => setSheet(() => counted = true), child: Container(padding: const EdgeInsets.symmetric(vertical: 11), alignment: Alignment.center, decoration: BoxDecoration(color: counted ? SakuraColors.primary.withValues(alpha: 0.12) : SakuraColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: counted ? SakuraColors.primary : SakuraColors.cardBorder)), child: Text('Counted', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: counted ? SakuraColors.primary : SakuraColors.inkSoft))))),
            ]),
            if (counted) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('DAILY TARGET'), TextField(controller: targetCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setSheet(() {}), decoration: _sheetField(hint: '8'))])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sheetLabel('UNIT'), TextField(controller: unitCtrl, maxLength: 12, decoration: _sheetField(hint: 'glasses'))])),
              ]),
            ],
            const SizedBox(height: 12),
            _sheetLabel('GOAL'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: SakuraColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: SakuraColors.cardBorder)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String?>(value: store.goalById(goal) == null ? null : goal, isExpanded: true, dropdownColor: SakuraColors.surface, style: TextStyle(color: SakuraColors.ink, fontSize: 13.5), hint: Text('Ungrouped', style: TextStyle(color: SakuraColors.inkFaint)), items: [const DropdownMenuItem<String?>(value: null, child: Text('Ungrouped')), for (final g in store.goals) DropdownMenuItem<String?>(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis))], onChanged: (v) => setSheet(() => goal = v))),
            ),
            const SizedBox(height: 12),
            if (habit != null) ...[
              _sheetLabel('STREAK FREEZE'),
              GestureDetector(
                onTap: () async {
                  if (frozenNow) {
                    final ok = await unfreezeHabitFlow(ctx, store.habitById(habit.id) ?? habit);
                    if (ok) setSheet(() => frozenNow = false);
                  } else {
                    final ok = await store.freezeHabit(habit.id);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ok ? 'Frozen — your streak is shielded.' : 'Already frozen.')));
                      if (ok) setSheet(() => frozenNow = true);
                    }
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: frozenNow ? BloomGameColors.icyBlue.withValues(alpha: 0.12) : SakuraColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: frozenNow ? BloomGameColors.icyBlue : SakuraColors.cardBorder),
                  ),
                  child: Row(children: [
                    Icon(LucideIcons.snowflake, size: 18, color: frozenNow ? BloomGameColors.icyBlue : SakuraColors.inkSoft),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(frozenNow ? 'Frozen · shielded' : 'Freeze streak', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: frozenNow ? BloomGameColors.icyBlue : SakuraColors.ink)),
                      const SizedBox(height: 2),
                      Text(frozenNow ? 'Thaw for ${HabitStore.unfreezeTokens} tokens' : 'Free to freeze · thaw costs ${HabitStore.unfreezeTokens}', style: TextStyle(fontSize: 11.5, color: SakuraColors.inkSoft)),
                    ])),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _sheetLabel('ICON'),
            Wrap(spacing: 8, runSpacing: 8, children: List.generate(_habitIcons.length, (i) {
              final sel = i == icon;
              return GestureDetector(onTap: () => setSheet(() => icon = i), child: Semantics(button: true, label: 'Choose icon ${i + 1}', child: Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: sel ? SakuraColors.primary.withValues(alpha: 0.12) : SakuraColors.background, borderRadius: BorderRadius.circular(13), border: Border.all(color: sel ? SakuraColors.primary : SakuraColors.cardBorder)), child: Icon(_habitIcons[i], size: 18, color: sel ? SakuraColors.primary : SakuraColors.inkSoft))));
            })),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: nameCtrl.text.trim().isNotEmpty ? () => Navigator.pop(ctx, true) : null, style: FilledButton.styleFrom(backgroundColor: SakuraColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(habit == null ? 'Create habit' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w700)))),
            const SizedBox(height: 20),
          ]),
        ),
      );
    }),
  );
  if (saved != true) return;
  num target = 1;
  if (counted) {
    target = num.tryParse(targetCtrl.text.trim()) ?? 1;
    if (target <= 0) target = 1;
  }
  if (habit == null) {
    await store.addHabit(name: nameCtrl.text, intention: whyCtrl.text, counted: counted, target: target, unit: unitCtrl.text, goalId: goal, iconIndex: icon, accentIndex: icon % 4);
  } else {
    await store.updateHabit(habit.id, name: nameCtrl.text, intention: whyCtrl.text, counted: counted, target: target, unit: unitCtrl.text, goalId: () => goal, iconIndex: icon, accentIndex: icon % 4);
  }
}
Widget _sheetLabel(String t) {
  return Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(t, style: TextStyle(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: SakuraColors.inkFaint)));
}
InputDecoration _sheetField({required String hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: SakuraColors.inkFaint, fontSize: 13.5),
    filled: true,
    fillColor: SakuraColors.background,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: SakuraColors.cardBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: SakuraColors.cardBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: SakuraColors.primary, width: 1.5)),
  );
}

/// Bottom sheet: create or edit a habit.