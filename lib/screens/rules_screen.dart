import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_sheet.dart';
import '../widgets/motion.dart';
import 'activity_screen.dart';
import 'flow_canvas_screen.dart';
import 'rule_runs_screen.dart';

/// Flows tab — automations (WHEN trigger → THEN actions) plus the
/// task-chain view. Toggle a rule, inspect its run log, or open the
/// chain: every task with subtasks below and its timer beside.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final _api = BloomApi();
  List<FlowRule> _rules = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await _api.fetchRules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = 'API offline — flows need the backend.';
        _rules = [];
      });
    }
  }

  Future<void> _toggle(FlowRule r, bool v) async {
    try {
      await _api.updateRule(r.id, enabled: v);
      await _load();
    } catch (e) {
      if (e is AuthExpiredException || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update flow.')),
      );
    }
  }

  Future<void> _delete(FlowRule r) async {
    try {
      await _api.deleteRule(r.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${r.name}".')),
        );
      }
    } catch (e) {
      if (e is AuthExpiredException || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete flow.')),
      );
    }
  }

  void _openChain() {
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => const FlowCanvasScreen()),
    );
  }

  IconData _triggerIcon(String t) {
    switch (t) {
      case 'task_created':
        return LucideIcons.plus;
      case 'task_moved':
        return LucideIcons.moveRight;
      case 'task_done':
        return LucideIcons.check;
      case 'note_added':
        return LucideIcons.messageSquare;
      case 'subtasks_complete':
        return LucideIcons.listChecks;
      case 'focus_done':
        return LucideIcons.timer;
      default:
        return LucideIcons.zap;
    }
  }

  InputDecoration _sheetField({
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    final radius = BorderRadius.circular(14);
    final side = BorderSide(color: SakuraColors.cardBorder);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: SakuraColors.inkFaint),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: SakuraColors.background,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: side),
      enabledBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: side),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: SakuraColors.primary, width: 1.6),
      ),
    );
  }

  Widget _sheetLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
          color: SakuraColors.inkFaint,
        ),
      ),
    );
  }

  /// Quick-create keeps rule creation alive without the old node
  /// editor: name + trigger + optional tag + tokens + inbox note.
  Future<void> _quickCreate() async {
    final nameCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    final tokensCtrl = TextEditingController(text: '10');
    var trigger = 'task_done';
    var withInbox = false;
    var saving = false;
    const triggers = [
      'task_created',
      'task_moved',
      'task_done',
      'note_added',
      'subtasks_complete',
      'focus_done',
    ];
    try {
      final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: SakuraColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) {
            final name = nameCtrl.text.trim();
            final tag = tagCtrl.text.trim();
            final amount =
                (int.tryParse(tokensCtrl.text.trim()) ?? 10)
                    .clamp(1, 500);
            final canSave = name.isNotEmpty && !saving;
            final summary =
                'WHEN ${triggerLabel(trigger).toLowerCase()} → +$amount ◆'
                '${tag.isEmpty ? '' : ' · $tag'}'
                '${withInbox ? ' · inbox note' : ''}';
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom:
                      MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('New flow',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: SakuraColors.ink)),
                            const SizedBox(height: 2),
                            Text(
                              'Automations run themselves',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      SakuraColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () =>
                            Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close,
                            size: 18,
                            color: SakuraColors.inkSoft),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              SakuraColors.background,
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sheetLabel('NAME'),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization:
                        TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setSheet(() {}),
                    decoration: _sheetField(
                      hint: 'e.g. Done → party',
                      prefix: Icon(
                          LucideIcons.sparkles,
                          size: 16,
                          color: SakuraColors.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sheetLabel('TRIGGER'),
                  DropdownButtonFormField<String>(
                    initialValue: trigger,
                    decoration: _sheetField(),
                    borderRadius: BorderRadius.circular(14),
                    items: triggers
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Row(
                                children: [
                                  Icon(_triggerIcon(t),
                                      size: 15,
                                      color:
                                          SakuraColors.primary),
                                  const SizedBox(width: 10),
                                  Text(triggerLabel(t),
                                      style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              SakuraColors.ink)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setSheet(
                        () => trigger = v ?? 'task_done'),
                  ),
                  const SizedBox(height: 14),
                  _sheetLabel('ONLY THIS TAG · OPTIONAL'),
                  TextField(
                    controller: tagCtrl,
                    textCapitalization:
                        TextCapitalization.none,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setSheet(() {}),
                    decoration: _sheetField(
                      hint: 'e.g. Design',
                      prefix: Icon(LucideIcons.tag,
                          size: 16,
                          color: SakuraColors.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sheetLabel('REWARD TOKENS'),
                  TextField(
                    controller: tokensCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    onChanged: (_) => setSheet(() {}),
                    decoration: _sheetField(
                      hint: '10',
                      prefix: Icon(LucideIcons.diamond,
                          size: 16,
                          color: SakuraColors.primary),
                      suffix: Padding(
                        padding: const EdgeInsets.only(
                            right: 14),
                        child: Text('1–500',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    SakuraColors.inkFaint)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(LucideIcons.inbox,
                          size: 15,
                          color: SakuraColors.inkSoft),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Also send inbox note',
                            style: TextStyle(
                                fontSize: 13,
                                color: SakuraColors.ink)),
                      ),
                      Switch(
                        value: withInbox,
                        activeThumbColor:
                            SakuraColors.primary,
                        onChanged: (v) => setSheet(
                            () => withInbox = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Live preview of the automation being built.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: SakuraColors.primary
                          .withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.zap,
                            size: 13,
                            color: SakuraColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(summary,
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      SakuraColors.primary)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor:
                            SakuraColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            SakuraColors.cardBorder,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    16))),
                    onPressed: canSave
                        ? () async {
                            setSheet(
                                () => saving = true);
                            try {
                              await _api.createRule(
                                name: name,
                                trigger: trigger,
                                condition: tag.isEmpty
                                    ? {}
                                    : {
                                        'field': 'tag',
                                        'op': 'contains',
                                        'value': tag
                                      },
                                actions: [
                                  {
                                    'type': 'award_tokens',
                                    'amount': amount
                                  },
                                  if (withInbox)
                                    {
                                      'type': 'inbox',
                                      'title': name,
                                      'body':
                                          'Fired by your "$name" flow.',
                                    },
                                ],
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setSheet(
                                  () => saving = false);
                              ScaffoldMessenger.of(ctx)
                                  .showSnackBar(
                                SnackBar(
                                    content: Text(e
                                            is AuthException
                                        ? e.message
                                        : 'Save failed: $e')),
                              );
                            }
                          }
                        : null,
                    icon: saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Icon(
                            LucideIcons.sparkles,
                            size: 15),
                    label: Text(
                        saving ? 'Creating…' : 'Create flow',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (created == true) await _load();
    } finally {
      nameCtrl.dispose();
      tagCtrl.dispose();
      tokensCtrl.dispose();
    }
  }

  void _openRuns(FlowRule r) {
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => RuleRunsScreen(rule: r)),
    );
  }

  String _conditionLabel(FlowRule r) {
    final c = r.condition;
    if (c.isEmpty) return 'Any task';
    if (c.containsKey('all') || c.containsKey('any')) {
      return c.toString();
    }
    final field = '${c['field'] ?? 'tag'}';
    final op = '${c['op'] ?? 'contains'}';
    final value = '${c['value'] ?? ''}';
    if (value.isEmpty) return 'Any task';
    return '$field $op "$value"';
  }

  /// Tapping a flow card opens its detail — previously the card itself
  /// did nothing (only Runs / Switch / Delete responded).
  void _openDetail(FlowRule r) {
    showBloomSheet(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.name,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: SakuraColors.ink)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.enabled
                        ? SakuraColors.primary.withValues(alpha: 0.12)
                        : SakuraColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SakuraColors.cardBorder),
                  ),
                  child: Text(r.enabled ? 'ON' : 'OFF',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: r.enabled
                              ? SakuraColors.primary
                              : SakuraColors.inkFaint)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow('WHEN', triggerLabel(r.trigger)),
            const SizedBox(height: 6),
            _detailRow('IF', _conditionLabel(r)),
            const SizedBox(height: 6),
            _detailRow(
                'THEN',
                r.actions.isEmpty
                    ? '—'
                    : r.actions.map(actionLabel).join(' + ')),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openRuns(r);
                    },
                    icon: const Icon(LucideIcons.history, size: 15),
                    label: const Text('Runs'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openChain();
                    },
                    icon: const Icon(LucideIcons.gitBranch, size: 15),
                    label: const Text('Chain'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: SakuraColors.primary),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _toggle(r, !r.enabled);
                    },
                    child: Text(r.enabled ? 'Disable' : 'Enable'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(k,
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.inkFaint)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: SakuraColors.ink)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自動',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'FLOWS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 3.2,
                            fontWeight: FontWeight.w600,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openChain,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.gitBranch,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        SakuraPageRoute(
                            builder: (_) =>
                                const ActivityScreen()),
                      );
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Icon(
                        LucideIcons.activity,
                        size: 18,
                        color: SakuraColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _quickCreate,
                    behavior: HitTestBehavior.opaque,
                      child: Semantics(
                        button: true,
                        label: 'Create rule',
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SakuraColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: SakuraColors.cardBorder),
                          ),
                          child: Icon(
                            LucideIcons.plus,
                            size: 18,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Automations fire on their own — toggle, Runs, or + a quick flow. The branch icon opens your task chains.',
                style: TextStyle(
                    fontSize: 12, color: SakuraColors.inkSoft),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 11,
                          color: SakuraColors.inkSoft)),
                ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_rules.isEmpty && _error == null)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: SakuraTheme.cardDecoration(),
                  child: Text(
                    'No flows yet — tap + to automate your first one.\nTry: WHEN task completed THEN +10 tokens.',
                    style: TextStyle(
                        height: 1.5, color: SakuraColors.inkSoft),
                  ),
                )
              else
                ..._rules.asMap().entries.map(
                  (entry) {
                    final i = entry.key;
                    final r = entry.value;
                    return Entrance(
                      key: ValueKey('rule-entrance-${r.id}'),
                      onceKey: 'rule-${r.id}',
                      delayMs: (i * 70).clamp(0, 350),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(20),
                          onTap: () => _openDetail(r),
                          child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: SakuraTheme.cardDecoration(),
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: r.enabled
                                      ? SakuraColors.ink
                                      : SakuraColors.inkFaint,
                                ),
                              ),
                            ),
                            Icon(
                                LucideIcons.chevronRight,
                                size: 15,
                                color: SakuraColors.inkFaint),
                            const SizedBox(width: 2),
                            Switch(
                              value: r.enabled,
                              activeThumbColor: SakuraColors.primary,
                              onChanged: (v) => _toggle(r, v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'WHEN ${triggerLabel(r.trigger).toLowerCase()}'
                          '${r.actions.map((a) => ' → ${actionLabel(a)}').join()}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: SakuraColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _openRuns(r),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7),
                                decoration: BoxDecoration(
                                  color: SakuraColors.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(
                                          10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.history,
                                        size: 13,
                                        color:
                                            SakuraColors.primary),
                                    const SizedBox(width: 5),
                                    Text('Runs',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w700,
                                            color: SakuraColors
                                                .primary)),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Delete rule',
                              onPressed: () => _delete(r),
                              icon: Icon(
                                  LucideIcons.trash2,
                                  size: 16,
                                  color: SakuraColors.inkFaint),
                              padding:
                                  const EdgeInsets.all(8),
                              constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                      ),
                    ),
                    ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
