import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'terminal.dart';

/// The outcome of a write that can fail on a duplicate serial number.
///
/// Mirrors `TerminalRepository.kt`. The Android example uses Room, which
/// enforces the primary key for it; here the check is explicit, which is the
/// only difference.
sealed class SaveOutcome {
  const SaveOutcome();
}

/// The terminal was stored.
final class SaveSucceeded extends SaveOutcome {
  const SaveSucceeded();
}

/// Another terminal already uses that serial number.
final class SaveRejected extends SaveOutcome {
  const SaveRejected(this.reason);

  final String reason;
}

/// Registered terminals, kept between launches.
class TerminalRepository {
  static const String _key = 'terminals';

  final StreamController<List<Terminal>> _terminals =
      StreamController<List<Terminal>>.broadcast();

  List<Terminal> _cache = const <Terminal>[];

  /// Every registered terminal, newest state first published on subscribe.
  Stream<List<Terminal>> observeAll() async* {
    yield await _load();
    yield* _terminals.stream;
  }

  Future<List<Terminal>> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> stored = prefs.getStringList(_key) ?? const <String>[];
    _cache = stored
        .map((String json) =>
            Terminal.fromJson(jsonDecode(json) as Map<String, Object?>))
        .toList();
    return _cache;
  }

  Future<void> _store(List<Terminal> terminals) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      terminals.map((Terminal t) => jsonEncode(t.toJson())).toList(),
    );
    _cache = terminals;
    _terminals.add(terminals);
  }

  Future<Terminal?> findBySerial(String serialNumber) async {
    final List<Terminal> terminals = await _load();
    for (final Terminal terminal in terminals) {
      if (terminal.serialNumber == serialNumber) return terminal;
    }
    return null;
  }

  /// Adds [terminal], or replaces the one registered under [originalSerial].
  ///
  /// A serial number already in use is refused rather than silently
  /// overwriting: two entries for one terminal, or one entry pointing at the
  /// wrong address, is worse than a save that did not happen.
  Future<SaveOutcome> save(Terminal terminal, {String? originalSerial}) async {
    final List<Terminal> terminals = List<Terminal>.of(await _load());

    final bool taken = terminals.any((Terminal existing) =>
        existing.serialNumber == terminal.serialNumber &&
        existing.serialNumber != originalSerial);
    if (taken) {
      return SaveRejected('Serial number ${terminal.serialNumber} is already registered');
    }

    if (originalSerial != null) {
      terminals.removeWhere((Terminal t) => t.serialNumber == originalSerial);
    }
    terminals
      ..removeWhere((Terminal t) => t.serialNumber == terminal.serialNumber)
      ..add(terminal);

    await _store(terminals);
    return const SaveSucceeded();
  }

  Future<void> delete(Terminal terminal) async {
    final List<Terminal> terminals = List<Terminal>.of(await _load())
      ..removeWhere((Terminal t) => t.serialNumber == terminal.serialNumber);
    await _store(terminals);
  }

  void dispose() => _terminals.close();
}
