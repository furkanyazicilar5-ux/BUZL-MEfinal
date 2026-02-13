import 'dart:collection';

/// Basit ring-buffer log. Sahada arıza teşhisi için.
///
/// - maxLines kadar satır tutar.
/// - add() ile eklenir.
/// - snapshot() ile kopya list alınır.
class LogBuffer {
  LogBuffer._();

  static final LogBuffer I = LogBuffer._();

  final int maxLines = 500;
  final ListQueue<String> _lines = ListQueue();

  void add(String line) {
    final ts = DateTime.now().toIso8601String();
    final full = '[$ts] $line';
    _lines.addLast(full);
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
  }

  List<String> snapshot() => List<String>.from(_lines);

  void clear() => _lines.clear();
}
