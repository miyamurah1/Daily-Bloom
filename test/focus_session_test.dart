import 'dart:convert';

import 'package:daily_bloom/data/ambient_sound.dart';
import 'package:daily_bloom/data/focus_quotes.dart';
import 'package:daily_bloom/data/session_sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('quote is stable within a day and rotates across days', () {
    final day = DateTime(2026, 9, 30);
    expect(focusQuoteFor(day, 'focus'),
        focusQuoteFor(DateTime(2026, 9, 30, 23, 59), 'focus'));
    // 8 focus lines: 8 days later it repeats, 1 day later it differs.
    expect(focusQuoteFor(day, 'focus'),
        isNot(focusQuoteFor(day.add(const Duration(days: 1)), 'focus')));
    expect(
        focusQuoteFor(day, 'focus'),
        focusQuoteFor(
            day.add(const Duration(days: 8)), 'focus'));
  });

  test('break shelf differs from focus shelf', () {
    final day = DateTime(2026, 9, 30);
    expect(focusQuoteFor(day, 'break'), isNotEmpty);
  });

  test('chime never throws without platform channels', () async {
    await SessionSound.chime();
  });

  test('ambient wash is headless-safe and persists its toggle', () async {
    await AmbientSound.load();
    expect(AmbientSound.enabled, isFalse);
    await AmbientSound.setEnabled(true);
    expect(AmbientSound.enabled, isTrue);
    // No binding, no player: sync/stop degrade to no-ops, never throw.
    await AmbientSound.sync(playing: true);
    await AmbientSound.sync(playing: false);
    await AmbientSound.stop();
    await AmbientSound.setEnabled(false);
    expect(AmbientSound.enabled, isFalse);
  });

  test('fetchRandomQuote returns the API line on success', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'quote': 'Ship it.', 'author': 'Bloom'}),
        200));
    expect(await fetchRandomQuote(client: client),
        'Ship it. — Bloom');
  });

  test('fetchRandomQuote falls back locally when offline', () async {
    final failing = MockClient((_) async => http.Response('nope', 500));
    final q = await fetchRandomQuote(
        client: failing, notEqualTo: 'One task, fully here.');
    expect(q, isNotEmpty);
    expect(q, isNot('One task, fully here.'));
  });
}
