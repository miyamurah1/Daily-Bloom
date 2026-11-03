import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_store.dart';
import 'privacy_preferences.dart';
import '../data/energy_store.dart';
import 'mock_data.dart';

/// True when text is mostly Latin-script / ASCII — the only script the
/// LLM + heuristics handle well today. Anything else (Hindi, Arabic,
/// Japanese…) skips the AI call entirely, returning 0 or receiving a
/// neutral prompt untouched.
bool isAiSupportedScript(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  var latin = 0;
  for (final u in t.runes) {
    if (u <= 0x7F) latin++;
  }
  return latin / t.runes.length >= 0.65;
}

/// AI client — Gemini 2.5 Flash-Lite via the server proxy, Groq fallback
/// server-side, local heuristics when offline or uncapped.
///
/// Offline-first: every method returns local-heuristic data on any failure,
/// so the UI never blocks on the network. Server results only upgrade the
/// suggestion quality.
class AiParse {
  final String title;
  final String tag;
  final String folder;
  final String priority;
  final DateTime? dueAt;
  final bool fromAi;

  const AiParse({
    required this.title,
    this.tag = 'General',
    this.folder = 'Productivity',
    this.priority = 'none',
    this.dueAt,
    this.fromAi = false,
  });

  factory AiParse.fromJson(Map<String, dynamic> j, {bool fromAi = true}) {
    return AiParse(
      title: '${j['title'] ?? ''}',
      tag: '${j['tag'] ?? 'General'}',
      folder: '${j['folder'] ?? 'Productivity'}',
      priority: '${j['priority']}' == 'high' ? 'high' : 'none',
      dueAt: j['due_at'] == null ? null : DateTime.tryParse('${j['due_at']}'),
      fromAi: fromAi,
    );
  }
}

class AiStep {
  final String title;
  final int minutes;

  const AiStep(this.title, [this.minutes = 15]);
}

class AiPick {
  final String id;
  final String title;
  final String reason;

  const AiPick({required this.id, required this.title, required this.reason});
}

class GroomGroup {
  final String kind;
  final String title;
  final List<String> ids;
  final String action;
  final String note;

  const GroomGroup({
    required this.kind,
    required this.title,
    required this.ids,
    required this.action,
    required this.note,
  });
}

class AiAnswer {
  final String text;
  final List<String> ids;

  const AiAnswer(this.text, [this.ids = const []]);
}

/// Pure local parser — mirrors `server/src/ai.js` so offline suggestions
/// match capped-mode server output. Test-covered, no network.
AiParse parseQuickAddLocal(String raw) {
  var title = raw.trim();
  var tag = 'General';
  const folder = 'Productivity';
  var priority = 'none';
  DateTime? due;

  final hash = RegExp(r'#([A-Za-z0-9_-]+)').firstMatch(title);
  if (hash != null) {
    final t = hash.group(1)!;
    tag = t[0].toUpperCase() + t.substring(1);
    title = title.replaceFirst(hash.group(0)!, ' ').trim();
  } else {
    const hints = [
      ['Work', r'work|meeting|report|email|deploy|review'],
      ['Home', r'home|family|mom|dad|kids|grocery|clean'],
      ['Health', r'health|gym|run|doctor|sleep|walk'],
      ['Learning', r'learn|study|read|course|practice'],
      ['Idea', r'idea|brainstorm|draft|write'],
    ];
    for (final h in hints) {
      if (RegExp(h[1], caseSensitive: false).hasMatch(title)) {
        tag = h[0];
        break;
      }
    }
  }

  if (RegExp(r'!!!|\burgent\b|\bhigh[\s-]?priority\b|\bp1\b', caseSensitive: false)
      .hasMatch(title)) {
    priority = 'high';
    title = title
        .replaceAll(
            RegExp(r'!!!|\burgent\b|\bhigh[\s-]?priority\b|\bp1\b',
                caseSensitive: false),
            ' ')
        .trim();
  }

  DateTime midnight(DateTime d) => DateTime(d.year, d.month, d.day);
  final now = DateTime.now();
  final lower = title.toLowerCase();
  if (lower.contains('tomorrow')) {
    due = midnight(now).add(const Duration(days: 1));
    title = title.replaceAll(RegExp('tomorrow', caseSensitive: false), ' ').trim();
  } else if (lower.contains('today')) {
    due = midnight(now);
    title = title.replaceAll(RegExp('today', caseSensitive: false), ' ').trim();
  } else if (lower.contains('next week')) {
    due = midnight(now).add(const Duration(days: 7));
    title = title.replaceAll(RegExp('next week', caseSensitive: false), ' ').trim();
  }

  final time = RegExp(r'(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false)
      .firstMatch(title);
  if (time != null) {
    var h = int.parse(time.group(1)!);
    final m = int.parse(time.group(2) ?? '0');
    final ap = time.group(3)!.toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    final base = due ?? midnight(now);
    due = DateTime(base.year, base.month, base.day, h, m);
    title = title.replaceFirst(time.group(0)!, ' ').trim();
  }

  title = title.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return AiParse(
    title: title.isEmpty ? raw.trim() : title,
    tag: tag,
    folder: folder,
    priority: priority,
    dueAt: due,
  );
}

/// Template breakdown — same shape as the server fallback.
List<AiStep> breakdownLocal(String rawTitle) {
  final t = rawTitle.trim();
  final lower = t.toLowerCase();
  if (RegExp(r'report|essay|doc|proposal').hasMatch(lower)) {
    return const [
      AiStep('Outline the sections', 15),
      AiStep('Draft the core content', 25),
      AiStep('Edit + tighten', 15),
      AiStep('Proofread + ship', 10),
    ];
  }
  if (RegExp(r'clean|tidy|organize|garage|room').hasMatch(lower)) {
    return const [
      AiStep('Pick one small zone', 5),
      AiStep('Sort into keep / toss', 20),
      AiStep('Put away + wipe down', 15),
    ];
  }
  return [
    AiStep('Clarify done for: ${t.length > 60 ? '${t.substring(0, 60)}…' : t}', 5),
    const AiStep('Smallest first step', 15),
    const AiStep('Main work block', 25),
    const AiStep('Review + close out', 10),
  ];
}

/// Local day planner — mirrors `server/src/ai.js` so offline still
/// suggests overdue / due-soon / high-priority / in-progress first.
List<AiPick> planDayLocal(List<Task> tasks) {
  final now = DateTime.now();
  final scored = <({Task task, int score, String reason})>[];
  for (final t in tasks) {
    if (t.status == 'done') continue;
    var score = 0;
    var reason = 'small win';
    if (t.dueAt != null) {
      if (t.dueAt!.isBefore(now)) {
        score += 50;
        reason = 'overdue';
      } else if (t.dueAt!.isBefore(now.add(const Duration(days: 1)))) {
        score += 30;
        reason = 'due soon';
      }
    }
    if (t.priority == 'high') {
      score += 20;
      reason = reason == 'small win' ? 'high priority' : reason;
    }
    if (t.status == 'in_progress') {
      score += 10;
      reason = reason == 'small win' ? 'already started' : reason;
    }
    scored.add((task: t, score: score, reason: reason));
  }
  // Tiebreak: demanding work first while fresh (unset counts as medium).
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return _energyRank(EnergyStore.instance.levelFor(b.task.id))
        .compareTo(_energyRank(EnergyStore.instance.levelFor(a.task.id)));
  });
  return scored
      .take(3)
      .map((s) => AiPick(id: s.task.id, title: s.task.title, reason: s.reason))
      .toList();
}

/// Energy rank for planner tiebreaks: demanding work first while fresh.
/// Unset counts as medium (neutral) — only explicit low sinks.
int _energyRank(String? level) => switch (level) {
      EnergyStore.high => 2,
      EnergyStore.low => 0,
      _ => 1,
    };

/// Rough load per task: 15 min per open subtask, else one 25-min block.
/// Honest, not precise — the bar reads "about", never exact.
int estimatedMinutes(Task t) {
  final openSubs = t.subtasks?.where((s) => !s.done).length ?? 0;
  return openSubs > 0 ? openSubs * 15 : 25;
}

/// Total estimated load across the plan's picks.
int planDayTotalMinutes(List<Task> all, List<AiPick> picks) {
  final byId = {for (final t in all) t.id: t};
  var total = 0;
  for (final p in picks) {
    final t = byId[p.id];
    if (t != null) total += estimatedMinutes(t);
  }
  return total;
}

String fmtLoad(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Tasks worth repeating: an open task whose title was finished 2+ times
/// and isn't already recurring. Latest done count included for the ask.
List<({Task task, int times})> repeatCandidates(
  List<Task> open,
  List<Task> done, {
  int minTimes = 2,
}) {
  String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final doneCount = <String, int>{};
  for (final t in done) {
    final k = norm(t.title);
    if (k.isEmpty) continue;
    doneCount[k] = (doneCount[k] ?? 0) + 1;
  }
  final out = <({Task task, int times})>[];
  for (final t in open) {
    if (t.recurring != 'none') continue;
    final times = doneCount[norm(t.title)] ?? 0;
    if (times >= minTimes) out.add((task: t, times: times));
  }
  out.sort((a, b) => b.times.compareTo(a.times));
  return out.take(3).toList();
}

/// Local weekly narrative from numbers the app already has.
String narrativeLocal(List<String> tips, {int done = 0, int streak = 0, int focusMinutes = 0}) {
  final lines = <String>[];
  if (done > 0) {
    lines.add(
        'You closed $done task${done == 1 ? '' : 's'} this week${streak > 1 ? ' on a $streak-day streak' : ''} — the garden is visibly fuller.');
  } else {
    lines.add('A quiet week — the soil is rested and ready for one small planting.');
  }
  if (focusMinutes > 0) {
    lines.add('You banked $focusMinutes focused minutes; protect that hour like a ritual.');
  }
  if (tips.isNotEmpty) lines.add(tips.first);
  return lines.take(3).join(' ');
}

String _normTitle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Local backlog groom: duplicates, stale (30d+, no due), vague (<12 chars).
List<GroomGroup> groomLocal(List<Task> tasks) {
  final open = tasks.where((t) => t.status != 'done').toList();
  final groups = <GroomGroup>[];
  final byTitle = <String, List<Task>>{};
  for (final t in open) {
    final k = _normTitle(t.title);
    if (k.isEmpty) continue;
    (byTitle[k] ??= []).add(t);
  }
  for (final entry in byTitle.entries) {
    if (entry.value.length < 2) continue;
    final rows = [...entry.value]
      ..sort((a, b) => (a.createdAt?.toIso8601String() ?? '')
          .compareTo(b.createdAt?.toIso8601String() ?? ''));
    final keep = rows.last;
    groups.add(GroomGroup(
      kind: 'duplicates',
      title:
          '“${keep.title.length > 60 ? '${keep.title.substring(0, 60)}…' : keep.title}” appears ${rows.length}x',
      ids: rows.sublist(0, rows.length - 1).map((t) => t.id).toList(),
      action: 'delete-others',
      note: 'Keep the newest, clear the copies.',
    ));
  }
  final stale = open.where((t) {
    if (t.dueAt != null || t.createdAt == null) return false;
    return DateTime.now().difference(t.createdAt!).inDays > 30;
  }).toList();
  if (stale.isNotEmpty) {
    groups.add(GroomGroup(
      kind: 'stale',
      title: '${stale.length} untouched for 30+ days',
      ids: stale.take(20).map((t) => t.id).toList(),
      action: 'defer-week',
      note: 'Give them next week or let them go.',
    ));
  }
  final vague = open.where((t) => t.title.trim().length < 12).toList();
  if (vague.isNotEmpty) {
    groups.add(GroomGroup(
      kind: 'vague',
      title: '${vague.length} need sharpening',
      ids: vague.take(20).map((t) => t.id).toList(),
      action: 'review',
      note: 'Open each and say what done looks like.',
    ));
  }
  return groups.take(6).toList();
}

/// Local ask: keyword scoring over title (x3), tag/folder (x2), desc (x1).
AiAnswer askLocal(String question, List<Task> tasks) {
  const stop = {
    'what', 'when', 'where', 'which', 'with', 'how', 'the', 'and',
    'for', 'are', 'was', 'were', 'task', 'tasks', 'show', 'find',
    'give', 'list', 'any', 'all', 'about'
  };
  final words = question
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !stop.contains(w))
      .toList();
  if (words.isEmpty) {
    return const AiAnswer('Ask me about a tag, folder, or word in your tasks.');
  }
  final scored = <({Task task, int score})>[];
  for (final t in tasks) {
    final title = t.title.toLowerCase();
    final tag = t.tag.toLowerCase();
    final folder = t.folder.toLowerCase();
    final desc = t.description.toLowerCase();
    var score = 0;
    for (final w in words) {
      if (title.contains(w)) score += 3;
      if (tag.contains(w) || folder.contains(w)) score += 2;
      if (desc.contains(w)) score += 1;
    }
    if (score > 0) scored.add((task: t, score: score));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  final top = scored.take(5).toList();
  if (top.isEmpty) {
    final q = question.length > 60 ? '${question.substring(0, 60)}…' : question;
    return AiAnswer('Nothing matches “$q” yet.');
  }
  final openCount = top.where((s) => s.task.status != 'done').length;
  final first = top.first.task.title;
  final short = first.length > 80 ? '${first.substring(0, 80)}…' : first;
  return AiAnswer(
    '${top.length} match${top.length == 1 ? '' : 'es'}${openCount > 0 ? ', $openCount still open' : ', all done'} — top: “$short”.',
    top.map((s) => s.task.id).toList(),
  );
}

class AiClient {
  final http.Client _client;
  AiClient([http.Client? client]) : _client = client ?? http.Client();

  Future<Map<String, String>> get _headers => AuthStore.instance.authHeaders;

  Future<bool> get _externalAiAllowed async {
    await PrivacyPreferences.instance.load();
    return PrivacyPreferences.instance.externalAiAllowed;
  }

  Future<AiParse> parse(String text) async {
    final fallback = parseQuickAddLocal(text);
    // Non-Latin input: skip AI entirely (it would mangle the title).
    if (!isAiSupportedScript(text)) return fallback;
    if (!await _externalAiAllowed) return fallback;
    try {
      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/parse'),
            headers: await _headers,
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      if (d is! Map<String, dynamic>) return fallback;
      return AiParse.fromJson(d);
    } catch (_) {
      return fallback;
    }
  }

  Future<List<AiStep>> breakdown(String title) async {
    final fallback = breakdownLocal(title);
    if (!isAiSupportedScript(title)) return fallback;
    if (!await _externalAiAllowed) return fallback;
    try {
      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/breakdown'),
            headers: await _headers,
            body: jsonEncode({'title': title}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      final steps = d is Map<String, dynamic> ? d['steps'] : null;
      if (steps is! List || steps.isEmpty) return fallback;
      return steps
          .whereType<Map<String, dynamic>>()
          .map((s) => AiStep(
                '${s['title'] ?? ''}'.trim(),
                ((s['minutes'] as num?)?.toInt() ?? 15).clamp(5, 120),
              ))
          .where((s) => s.title.isNotEmpty)
          .take(6)
          .toList();
    } catch (_) {
      return fallback;
    }
  }

  Future<List<AiPick>> plan(List<Task> tasks) async {
    final fallback = planDayLocal(tasks);
    if (!await _externalAiAllowed) return fallback;
    try {      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/plan'),
            headers: await _headers,
            body: jsonEncode({
              'tasks': tasks.take(30).map(_taskJson).toList(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      final picks = d is Map<String, dynamic> ? d['picks'] : null;
      if (picks is! List || picks.isEmpty) return fallback;
      return picks
          .whereType<Map<String, dynamic>>()
          .map((p) => AiPick(
                id: '${p['id'] ?? ''}',
                title: '${p['title'] ?? ''}',
                reason: '${p['reason'] ?? 'suggested'}',
              ))
          .where((p) => p.id.isNotEmpty)
          .take(3)
          .toList();
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> _taskJson(Task t) => {
        'id': t.id,
        'title': t.title,
        'status': t.status,
        'priority': t.priority,
        'tag': t.tag,
        'folder': t.folder,
        'description': t.description,
        'due_at': t.dueAt?.toIso8601String(),
        'created_at': t.createdAt?.toIso8601String(),
        'energy': EnergyStore.instance.levelFor(t.id),
      };

  Future<String> narrative(
    List<String> tips, {
    int done = 0,
    int streak = 0,
    int focusMinutes = 0,
  }) async {
    final fallback =
        narrativeLocal(tips, done: done, streak: streak, focusMinutes: focusMinutes);
    if (!await _externalAiAllowed) return fallback;
    try {
      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/narrative'),
            headers: await _headers,
            body: jsonEncode({
              'tips': tips.take(10).toList(),
              'stats': {'done': done, 'streak': streak, 'focusMinutes': focusMinutes},
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      final text = d is Map<String, dynamic> ? '${d['text'] ?? ''}'.trim() : '';
      return text.isEmpty ? fallback : text;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<GroomGroup>> groom(List<Task> tasks) async {
    final fallback = groomLocal(tasks);
    if (!await _externalAiAllowed) return fallback;
    try {
      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/groom'),
            headers: await _headers,
            body: jsonEncode({'tasks': tasks.take(60).map(_taskJson).toList()}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      final groups = d is Map<String, dynamic> ? d['groups'] : null;
      if (groups is! List || groups.isEmpty) return fallback;
      return groups
          .whereType<Map<String, dynamic>>()
          .map((g) => GroomGroup(
                kind: '${g['kind'] ?? 'stale'}',
                title: '${g['title'] ?? ''}',
                ids: ((g['ids'] as List?) ?? [])
                    .map((id) => '$id')
                    .take(20)
                    .toList(),
                action: '${g['action'] ?? 'review'}',
                note: '${g['note'] ?? ''}',
              ))
          .where((g) => g.title.isNotEmpty && g.ids.isNotEmpty)
          .take(6)
          .toList();
    } catch (_) {
      return fallback;
    }
  }

  Future<AiAnswer> ask(String question, List<Task> tasks) async {
    final fallback = askLocal(question, tasks);
    if (!isAiSupportedScript(question)) return fallback;
    if (!await _externalAiAllowed) return fallback;
    try {
      final res = await _client
          .post(
            Uri.parse('${BloomApi.baseUrl}/api/ai/ask'),
            headers: await _headers,
            body: jsonEncode({
              'question': question,
              'tasks': tasks.take(60).map(_taskJson).toList(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return fallback;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final d = j['data'];
      if (d is! Map<String, dynamic>) return fallback;
      final answer = '${d['answer'] ?? ''}'.trim();
      final ids = ((d['ids'] as List?) ?? []).map((id) => '$id').take(5).toList();
      if (answer.isEmpty) return fallback;
      return AiAnswer(answer, ids);
    } catch (_) {
      return fallback;
    }
  }
}
