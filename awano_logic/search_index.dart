const searchSeparator = '\u0000';
const searchResultLimit = 100000;

class SearchIndex {
  List<String> texts = [];
  List<int> entryStarts = [0];
  List<String>? folded;
  final haystacks = <bool, String>{};
  bool stale = true;

  SearchIndex() {
    invalidate();
  }

  void rebuild(Iterable<List<String>> entryTexts) {
    final newTexts = <String>[];
    final starts = <int>[];
    for (final fieldTexts in entryTexts) {
      starts.add(newTexts.length);
      newTexts.addAll(fieldTexts);
    }
    starts.add(newTexts.length);
    texts = newTexts;
    entryStarts = starts;
    folded = null;
    haystacks.clear();
    stale = false;
  }

  void invalidate() {
    texts = [];
    entryStarts = [0];
    folded = null;
    haystacks.clear();
    stale = true;
  }

  void update(int entryIndex, int fieldIndex, String text) {
    if (stale) return;
    if (entryIndex + 1 >= entryStarts.length) {
      invalidate();
      return;
    }
    final record = entryStarts[entryIndex] + fieldIndex;
    if (record >= entryStarts[entryIndex + 1]) {
      invalidate();
      return;
    }
    if (texts[record] == text) return;
    texts[record] = text;
    folded?[record] = text.toLowerCase();
    haystacks.clear();
  }

  (int, int) locate(int record) {
    var low = 0;
    var high = entryStarts.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (entryStarts[mid] <= record) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final entryIndex = low - 1;
    return (entryIndex, record - entryStarts[entryIndex]);
  }

  String textAt(int record) => texts[record];

  String haystack(bool caseSensitive) {
    final cached = haystacks[caseSensitive];
    if (cached != null) return cached;
    final source = caseSensitive ? texts : (folded ??= [for (final text in texts) text.toLowerCase()]);
    final buffer = StringBuffer(searchSeparator);
    for (final text in source) {
      buffer.write(text.replaceAll(searchSeparator, ''));
      buffer.write(searchSeparator);
    }
    final built = buffer.toString();
    haystacks[caseSensitive] = built;
    return built;
  }

  (List<int>, bool) search(String query, {bool exact = false, bool caseSensitive = false, int limit = searchResultLimit}) {
    final cleanQuery = query.replaceAll(searchSeparator, '');
    final matches = <int>[];
    if (stale || cleanQuery.isEmpty || texts.isEmpty) return (matches, false);

    final hay = haystack(caseSensitive);
    var needle = caseSensitive ? cleanQuery : cleanQuery.toLowerCase();
    var lead = 0;
    if (exact) {
      needle = '$searchSeparator$needle$searchSeparator';
      lead = 1;
    }

    var separatorsSeen = 0;
    var scannedTo = 0;
    var position = hay.indexOf(needle);
    while (position != -1) {
      final core = position + lead;
      for (var i = scannedTo; i < core; i++) {
        if (hay.codeUnitAt(i) == 0) separatorsSeen++;
      }
      scannedTo = core;
      matches.add(separatorsSeen - 1);
      if (matches.length >= limit) return (matches, true);
      final recordEnd = hay.indexOf(searchSeparator, core);
      if (recordEnd == -1) break;
      position = hay.indexOf(needle, recordEnd + 1 - lead);
    }
    return (matches, false);
  }
}
