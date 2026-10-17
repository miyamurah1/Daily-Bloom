import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/goal_store.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_dialog.dart';
import '../widgets/motion.dart';

/// Goals tab — real long-term project goals with target dates and
/// milestone checklists. Local-first ([GoalStore]): fully offline, no
/// backend table yet. Tapping a milestone toggles it and moves the
/// goal's progress bar.
class GoalsScreen extends StatefulWidget {
  final bool embedded;
  const GoalsScreen({super.key, this.embedded = false});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    GoalStore.instance.load();
  }

  Future<void> _newGoal() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: SakuraColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: _GoalEditorSheet(),
        ),
      ),
    );
    if (created == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmDelete(ProjectGoal goal) async {
    final yes = await showBloomConfirm(
      context,
      title: 'Delete "${goal.title}"?',
      message:
          'Its ${goal.milestones.length} milestone${goal.milestones.length == 1 ? '' : 's'} go with it. This cannot be undone.',
      cancelLabel: 'Keep',
    );
    if (!yes || !mounted) return;
    await GoalStore.instance.removeGoal(goal.id);
  }

  String _dueLabel(ProjectGoal goal) {
    final remaining = goal.daysRemaining();
    if (remaining == null) return 'No target date';
    if (remaining < 0) {
      return 'Overdue by ${-remaining}d';
    }
    if (remaining == 0) return 'Due today';
    if (remaining == 1) return 'Due tomorrow';
    return '$remaining days left';
  }

  @override
  Widget build(BuildContext context) {
    final content = RefreshIndicator(
      color: SakuraColors.primary,
      backgroundColor: SakuraColors.surface,
      onRefresh: () => GoalStore.instance.load(),
      child: ListenableBuilder(
        listenable: GoalStore.instance,
        builder: (context, _) {
          final goals = GoalStore.instance.goals;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _header(),
              const SizedBox(height: 18),
              if (goals.isEmpty)
                _EmptyGoals(onCreate: _newGoal)
              else ...[
                for (var i = 0; i < goals.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Entrance(
                    delayMs: (i * 60).clamp(0, 300),
                    child: _GoalCard(
                      goal: goals[i],
                      dueLabel: _dueLabel(goals[i]),
                      onToggle: (m) => GoalStore.instance
                          .toggleMilestone(goals[i].id, m.id),
                      onDelete: () => _confirmDelete(goals[i]),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SakuraColors.primary,
                      side: BorderSide(color: SakuraColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _newGoal,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('+ New Goal',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        bottom: false,
        child: content,
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目標',
          style: SakuraTheme.display(
            fontSize: 30,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: SakuraColors.primary,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              'GOALS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w600,
                color: SakuraColors.inkFaint,
              ),
            ),
            const Spacer(),
            Text(
              '● on this device',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: SakuraColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One project goal: title, target date + countdown, progress bar from
/// checked milestones, tappable checklist, delete affordance.
class _GoalCard extends StatelessWidget {
  final ProjectGoal goal;
  final String dueLabel;
  final ValueChanged<GoalMilestone> onToggle;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.dueLabel,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal.progress;
    final remaining = goal.daysRemaining();
    final overdue = remaining != null && remaining < 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: SakuraColors.ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  label: 'Delete',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                LucideIcons.calendarDays,
                size: 12,
                color: overdue
                    ? SakuraColors.primary
                    : SakuraColors.inkFaint,
              ),
              const SizedBox(width: 5),
              Text(
                goal.targetDate == null
                    ? dueLabel
                    : 'Target: ${DateFormat('MMM d, y').format(goal.targetDate!.toLocal())} · $dueLabel',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: overdue
                      ? SakuraColors.primary
                      : SakuraColors.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: SakuraColors.primarySoft,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        SakuraColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(100 * progress).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${goal.doneCount}/${goal.milestones.length} milestones',
            style: TextStyle(fontSize: 11, color: SakuraColors.inkSoft),
          ),
          const SizedBox(height: 8),
          for (final m in goal.milestones)
            GestureDetector(
              onTap: () => onToggle(m),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: m.done
                            ? SakuraColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: m.done
                              ? SakuraColors.primary
                              : SakuraColors.inkFaint,
                          width: 1.5,
                        ),
                      ),
                      child: m.done
                          ? const Icon(Icons.check,
                              size: 13, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: m.done
                              ? SakuraColors.inkFaint
                              : SakuraColors.ink,
                          decoration: m.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyGoals({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SakuraColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.target,
                size: 22, color: SakuraColors.primary),
          ),
          const SizedBox(height: 12),
          Text('No long-term goals yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink)),
          const SizedBox(height: 6),
          Text(
            'Name a mountain — a date and a few steps turn it into a plan.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.55, color: SakuraColors.inkSoft),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SakuraColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onCreate,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('+ New Goal',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// New-goal sheet: title + optional target date + 1–5 milestone steps.
class _GoalEditorSheet extends StatefulWidget {
  const _GoalEditorSheet();

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  final _title = TextEditingController();
  final _steps = [TextEditingController(), TextEditingController(), TextEditingController()];
  DateTime? _target;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    for (final c in _steps) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _target ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) setState(() => _target = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final steps =
        _steps.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (title.isEmpty || steps.isEmpty || !mounted) return;
    setState(() => _saving = true);
    await GoalStore.instance
        .addGoal(title: title, targetDate: _target, steps: steps);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('New goal',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: SakuraColors.ink)),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: Icon(Icons.close,
                    size: 18, color: SakuraColors.inkSoft),
                style: IconButton.styleFrom(
                  backgroundColor: SakuraColors.background,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration:
                BloomDialog.fieldDecoration('e.g. Launch V1 Beta'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickDate,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: SakuraColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SakuraColors.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.calendarDays,
                      size: 15, color: SakuraColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    _target == null
                        ? 'Target date (optional)'
                        : 'Target: ${DateFormat('MMM d, y').format(_target!.toLocal())}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _target == null
                          ? SakuraColors.inkFaint
                          : SakuraColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (_target != null)
                    GestureDetector(
                      onTap: () => setState(() => _target = null),
                      child: Semantics(
                        button: true,
                        label: 'Clear target',
                        child: Icon(LucideIcons.x,
                            size: 14,
                            color: SakuraColors.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MILESTONES (${_steps.length}/5)',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: SakuraColors.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _steps[i],
                      textCapitalization: TextCapitalization.sentences,
                      decoration: BloomDialog.fieldDecoration(
                          'Step ${i + 1}'),
                    ),
                  ),
                  if (_steps.length > 1)
                    IconButton(
                      tooltip: 'Remove step',
                      onPressed: () => setState(() {
                        _steps.removeAt(i).dispose();
                      }),
                      icon: Icon(LucideIcons.trash2,
                          size: 15,
                          color: SakuraColors.inkFaint),
                    ),
                ],
              ),
            ),
          if (_steps.length < 5)
            TextButton.icon(
              onPressed: () => setState(() {
                if (_steps.length < 5) {
                  _steps.add(TextEditingController());
                }
              }),
              icon: Icon(LucideIcons.plus,
                  size: 14, color: SakuraColors.primary),
              label: Text('Add step',
                  style: TextStyle(color: SakuraColors.primary)),
            ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: SakuraColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Planting…' : 'Plant goal',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
