import 'dart:ffi'; import 'dart:io'; import 'dart:math' as math; import 'dart:typed_data';
import 'bin_format.dart'; import 'codec.dart'; import 'd2d.dart'; import 'search_index.dart'; import 'shop_bin.dart';
import 'string_tbl.dart'; import 'ui.dart'; import 'win.dart';

const editorPanelWidth = 1000.0;
const editorPanelHeight = 680.0;
const editorPanelX = 540.0;
const editorPanelY = 40.0;
const searchDelayMs = 120;
const snippetContext = 32;
const snippetLimit = 140;
const highlightLimit = 2000;
const searchHitColor = 0xFF7A5C00;
const searchTimerId = 2;

String shortenPathSmart(String path) {
  final parts = path.split(Platform.pathSeparator);
  if (parts.length >= 2) return '${Platform.pathSeparator}${parts[parts.length - 2]}${Platform.pathSeparator}${parts.last}';
  return path;
}

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

String grouped(int n) {
  final digits = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (match) => ',');
  return n < 0 ? '-$digits' : digits;
}

String signedGrouped(int n) => n >= 0 ? '+${grouped(n)}' : grouped(n);

String buildSnippet(String text, String query, bool caseSensitive) {
  final haystack = caseSensitive ? text : text.toLowerCase();
  final found = haystack.indexOf(caseSensitive ? query : query.toLowerCase());
  final position = math.max(found, 0);
  final start = math.max(0, position - snippetContext);
  final end = math.min(text.length, start + snippetLimit);
  var snippet = text.substring(start, end).trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join(' ');
  if (start > 0) snippet = '...$snippet';
  if (end < text.length) snippet = '$snippet...';
  return snippet;
}

class EditorHost {
  final void Function(Panel panel) showExclusive;
  final int Function() fallbackOwner;
  final (int, int) Function() origin;
  final void Function() closeApp;
  final void Function() toggleTopmost;
  EditorHost(this.showExclusive, this.fallbackOwner, this.origin, this.closeApp, this.toggleTopmost);
}

abstract class EditorPanel extends Panel {
  final EditorHost host;
  String get titleNoun;
  String get documentNoun;
  String get entriesHeading => 'Entries';
  String get fieldsHeading => 'Fields';
  String get jumpHeading => 'Jump to Entry';
  int get jumpDigits => 3;
  String get errorTitle;
  String get emptyInfo;
  String get loadedStatus => 'File loaded.';
  String? get openTitle => null;
  List<FileFilter> get openFilters;
  String get saveExtension;
  List<FileFilter> get saveFilters => openFilters;
  String get fallbackName;
  bool get resetFieldOnEntryChange => true;
  bool get skipUnchangedOnApply => false;
  (double, double) get columnWidths;

  String? path;
  String? lastSavedPath;
  Object? document;
  Object? originalDocument;
  Uint8List? sourceBytes;
  int entryIndex = 0;
  int fieldIndex = 0;
  bool dirty = false;
  late String status;
  String loadedText = '';
  int? loadedBytes;
  final searchIndex = SearchIndex();
  List<int> searchMatches = [];
  bool searchTruncated = false;
  String searchQuery = '';
  bool searchPending = false;

  late final Label infoLabel = add(Label('', labelBoldStyle.copy(wrap: true, vAlign: vAlignNear), white));
  late final Label statusLabel = add(Label('', labelStyle.copy(wrap: true, vAlign: vAlignNear), mutedFg));
  late final Label searchLabel = add(Label('Search', labelBoldStyle, goldFg));
  late final Label jumpLabel = add(Label(jumpHeading, labelBoldStyle, goldFg));
  late final ToggleButton exactToggle = add(ToggleButton('Exact', () => runSearch()));
  late final ToggleButton caseToggle = add(ToggleButton('Aa', () => runSearch()));
  late final Label entriesHeadingLabel = add(Label(entriesHeading, labelBoldStyle, headingFg));
  late final Label fieldsHeadingLabel = add(Label(fieldsHeading, labelBoldStyle, headingFg));
  late final Label resultsHeadingLabel = add(Label('Results', labelBoldStyle, headingFg));
  late final VirtualList entriesList = add(VirtualList((index) => selectEntry(index)));
  late final VirtualList fieldsList = add(VirtualList(onFieldSelect));
  late final VirtualList resultsList = add(VirtualList(onResultSelect));
  late final Label valueLabel = add(Label('Value', labelBoldStyle, headingFg));
  late final Label lengthLabel = add(Label('', labelStyle, mutedFg));
  late final Sash columnSashA = add(Sash(true, (delta) => dragColumn(0, delta)));
  late final Sash columnSashB = add(Sash(true, (delta) => dragColumn(1, delta)));
  late final Sash splitSash = add(Sash(false, dragSplit));
  late final List<Button> valueButtons;
  late final TextBox searchBox;
  late final TextBox jumpBox;
  late final TextBox editor;
  late double columnA;
  late double columnB;
  double columnsHeight = 250;

  EditorPanel(String title, this.host)
      : super(title, editorPanelWidth, editorPanelHeight, editorPanelX, editorPanelY, host.origin, () {},
            minWidth: 560, minHeight: 400) {
    onClose = closeDocument;
    status = idleStatus();
    columnA = columnWidths.$1;
    columnB = columnWidths.$2;
    searchBox = TextBox(this, 101);
    jumpBox = TextBox(this, 102, center: true);
    editor = TextBox(this, 103, multiline: true, points: 10);
    valueButtons = [
      Button('S', applyValue, accent, accentActive, black),
      Button('RA', reloadAllValues, 0xFF6A4A4A, 0xFF8F6161),
      ...extraValueButtons(),
      Button('C', saveAs, 0xFF4D6D4F, 0xFF66956A),
      Button('R', restoreSelectedValue, 0xFF4D5C71, 0xFF6E83A1),
    ];
    for (final button in valueButtons) {
      add(button);
    }
    buildHeaderExtras();
    fitToScreen();
    refresh();
  }

  String idleStatus();
  Object parse(Uint8List data, String encoding, String? filePath);
  int fieldCount(int entryIndex);
  String entryLabel(int entryIndex);
  String fieldLabel(int entryIndex, int fieldIndex);
  String valueText(int entryIndex, int fieldIndex);
  Iterable<List<String>> searchTexts();
  void storeValue(int entryIndex, int fieldIndex, String rawValue);
  String updatedStatus(int entryIndex, int fieldIndex);
  String infoText();
  void restoreSelectedValue();
  int documentCount(Object doc);
  String documentEncoding(Object doc);
  String? documentPath(Object doc);
  Uint8List documentBytes(Object doc, String encoding);

  void buildHeaderExtras() {}
  void refreshHeaderExtras() {}
  List<Button> extraValueButtons() => [];
  void documentReplaced() {}
  String loadedMessage() => loadedStatus;
  String savedStatus(String outputPath, Uint8List outputBytes) =>
      'Created $documentNoun at ${shortenPathSmart(outputPath)}.';
  String resultEntryLabel(int entryIndex) => entryLabel(entryIndex);
  String resultFieldLabel(int entryIndex, int fieldIndex) => fieldLabel(entryIndex, fieldIndex);
  void valueChanged(int entryIndex, int fieldIndex) =>
      searchIndex.update(entryIndex, fieldIndex, valueText(entryIndex, fieldIndex));

  int entryCount() => document == null ? 0 : documentCount(document!);

  String displayName(String fallback) => fileNameOf(path ?? documentPath(document!) ?? fallback);
  String displayPath(String fallback) => shortenPathSmart(path ?? documentPath(document!) ?? fallback);
  String get dirtyMarker => dirty ? ' *' : '';
  String formatJump(int index) => index.toString().padLeft(jumpDigits, '0');
  int get dialogOwner => panelVisible ? hwnd : host.fallbackOwner();

  void showError(String title, String message) => messageBox(dialogOwner, message, title, MB_OK | MB_ICONERROR);
  bool askYesNo(String title, String message) =>
      messageBox(dialogOwner, message, title, MB_YESNO | MB_ICONQUESTION) == IDYES;

  String? askOpenPath([String? title]) => fileDialog(dialogOwner, title: title, filters: openFilters);

  bool confirmOpenDiscard() {
    if (!dirty) return true;
    return askYesNo('Open $titleNoun', 'Discard the current $documentNoun edits and open another file?');
  }

  void showPanel() {
    if (document != null) host.showExclusive(this);
  }

  bool openDocument() {
    final file = askOpenPath(openTitle);
    if (file == null || !confirmOpenDiscard()) return false;
    return loadDocument(file);
  }

  bool loadDocument(String filePath) {
    final Uint8List bytes;
    try {
      bytes = File(filePath).readAsBytesSync();
    } catch (error) {
      showError(errorTitle, describe(error));
      return false;
    }
    return loadDocumentBytes(filePath, bytes);
  }

  String describe(Object error) {
    if (error is FileSystemException) {
      final os = error.osError?.message.trim() ?? '';
      return os.isEmpty ? '${error.message}: ${error.path}' : '$os: ${error.path}';
    }
    if (error is RangeError) return 'The file ended before the data it describes.';
    return error.toString();
  }

  bool loadDocumentBytes(String filePath, Uint8List bytes) {
    final Object parsed;
    final Object original;
    try {
      parsed = parse(bytes, autoEncoding, filePath);
      original = parse(bytes, documentEncoding(parsed), filePath);
    } catch (error) {
      showError(errorTitle, describe(error));
      return false;
    }
    document = parsed;
    originalDocument = original;
    sourceBytes = bytes;
    path = filePath;
    lastSavedPath = null;
    dirty = false;
    entryIndex = 0;
    fieldIndex = 0;
    status = loadedMessage();
    documentReplaced();
    searchIndex.invalidate();
    refresh();
    host.showExclusive(this);
    return true;
  }

  void closeDocument() {
    if (dirty && !askYesNo('Close $titleNoun', 'Discard the current $documentNoun edits and close it?')) return;
    document = null;
    originalDocument = null;
    sourceBytes = null;
    path = null;
    lastSavedPath = null;
    dirty = false;
    entryIndex = 0;
    fieldIndex = 0;
    status = idleStatus();
    documentReplaced();
    searchIndex.invalidate();
    refresh();
    hide();
  }

  void reloadAllValues() {
    final bytes = sourceBytes;
    final original = originalDocument;
    if (bytes == null || original == null) return;
    if (dirty &&
        !askYesNo('Reload $titleNoun', 'Discard all current $documentNoun edits and reload the original values?')) {
      return;
    }
    try {
      document = parse(bytes, documentEncoding(original), path);
    } catch (error) {
      showError('Reload Failed', describe(error));
      return;
    }
    dirty = false;
    status = 'Reloaded the in-memory $documentNoun from the original file.';
    documentReplaced();
    searchIndex.invalidate();
    refresh();
  }

  void saveAs() {
    final doc = document;
    if (doc == null) return;
    if (!commitCurrentValue(false)) {
      showError('Save Failed', 'The current value couldnt be saved into memory. Fix it before saving the $documentNoun.');
      return;
    }
    final defaultName = fileNameOf(lastSavedPath ?? path ?? documentPath(doc) ?? fallbackName);
    final output = fileDialog(dialogOwner,
        save: true, filters: saveFilters, fileName: defaultName, defaultExtension: saveExtension.replaceFirst('.', ''));
    if (output == null) return;
    final Uint8List bytes;
    try {
      bytes = documentBytes(doc, documentEncoding(doc));
      File(output).writeAsBytesSync(bytes);
    } catch (error) {
      showError('Save Failed', describe(error));
      return;
    }
    lastSavedPath = output;
    dirty = false;
    status = savedStatus(output, bytes);
    refresh();
  }

  void applyValue() => commitCurrentValue(true);

  String editorValue() {
    final edited = editor.text;
    if (loadedText.contains('\r\n') && !loadedText.replaceAll('\r\n', '').contains(RegExp('[\r\n]'))) {
      return edited.replaceAll('\n', '\r\n');
    }
    if (loadedText.contains('\r') && !loadedText.contains('\n')) return edited.replaceAll('\n', '\r');
    return edited;
  }

  bool commitCurrentValue(bool showFeedback) {
    if (document == null) return false;
    final location = currentLocation();
    if (location == null) return true;
    final raw = editorValue();
    if (raw == loadedText && (!showFeedback || skipUnchangedOnApply)) return true;
    try {
      storeValue(location.$1, location.$2, raw);
    } catch (error) {
      if (showFeedback) showError(errorTitle, describe(error));
      return false;
    }
    dirty = true;
    if (showFeedback) status = updatedStatus(location.$1, location.$2);
    valueChanged(location.$1, location.$2);
    refresh();
    return true;
  }

  (int, int)? currentLocation() {
    if (entryCount() <= 0) return null;
    final count = fieldCount(entryIndex);
    if (count <= 0) return null;
    fieldIndex = math.min(fieldIndex, count - 1);
    return (entryIndex, fieldIndex);
  }

  void refresh() {
    refreshHeaderExtras();
    statusLabel.set(status);
    if (document == null) {
      infoLabel.set(emptyInfo);
      setJump('');
      entriesList.setItems(0, null);
      fieldsList.setItems(0, null);
    } else {
      final count = entryCount();
      entryIndex = math.max(0, math.min(entryIndex, count - 1));
      entriesList.setItems(count, entryLabel, count > 0 ? entryIndex : -1);
      if (count > 0) setJump(formatJump(entryIndex));
      populateFields();
      infoLabel.set(infoText());
    }
    loadSelectedValue();
    runSearch(keepPosition: true);
    layout();
  }

  void setJump(String value) {
    if (jumpBox.text != value) jumpBox.text = value;
  }

  void populateFields() {
    if (entryCount() <= 0) {
      fieldsList.setItems(0, null);
      return;
    }
    final entry = entryIndex;
    final count = fieldCount(entry);
    fieldIndex = math.max(0, math.min(fieldIndex, count - 1));
    fieldsList.setItems(count, (index) => fieldLabel(entry, index), count > 0 ? fieldIndex : -1);
  }

  void selectEntry(int index, {int? field, bool updateJump = true}) {
    final count = entryCount();
    if (count <= 0) return;
    entryIndex = math.max(0, math.min(index, count - 1));
    if (field != null) {
      fieldIndex = field;
    } else if (resetFieldOnEntryChange) {
      fieldIndex = 0;
    }
    entriesList.select(entryIndex);
    if (updateJump) setJump(formatJump(entryIndex));
    populateFields();
    loadSelectedValue();
  }

  void onFieldSelect(int index) {
    fieldIndex = index;
    loadSelectedValue();
  }

  void onJumpChange() {
    final count = entryCount();
    final raw = jumpBox.text.trim();
    if (count <= 0 || raw.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(raw)) return;
    final target = int.parse(raw);
    if (target >= 0 && target < count) selectEntry(target, updateJump: false);
  }

  void loadSelectedValue() {
    final location = currentLocation();
    final text = location == null ? '' : valueText(location.$1, location.$2);
    editor.text = text;
    loadedText = text;
    loadedBytes = encodedLength(text);
    updateLengthLabel();
    highlightEditorMatches();
  }

  int? encodedLength(String text) {
    final doc = document;
    if (doc == null) return null;
    try {
      return encodeText(text, documentEncoding(doc)).length;
    } on TextEncodeError {
      return null;
    }
  }

  void updateLengthLabel() {
    final doc = document;
    if (doc == null) {
      lengthLabel.set('');
      return;
    }
    final text = editorValue();
    final label = encodingLabel(documentEncoding(doc));
    final chars = grouped(text.runes.length);
    final bytes = encodedLength(text);
    if (bytes == null) {
      lengthLabel.set('$chars chars|not valid $label');
      return;
    }
    var details = '$chars chars|${grouped(bytes)} bytes $label';
    final loaded = loadedBytes;
    if (loaded != null && bytes != loaded) details += ' (${signedGrouped(bytes - loaded)})';
    lengthLabel.set(details);
  }

  void focusSearch() => searchBox.focus(selectAll: true);

  void clearSearch() {
    searchBox.text = '';
    runSearch();
  }

  void scheduleSearch() {
    searchPending = true;
    SetTimer(hwnd, searchTimerId, searchDelayMs, nullptr);
  }

  @override
  void timer(int id) {
    if (id == searchTimerId) {
      KillTimer(hwnd, searchTimerId);
      if (searchPending) runSearch();
    }
  }

  void runSearch({bool keepPosition = false}) {
    searchPending = false;
    KillTimer(hwnd, searchTimerId);
    final query = searchBox.text.replaceAll(searchSeparator, '');
    final previous = keepPosition ? resultsList.selected : -1;
    if (query.isEmpty || document == null) {
      searchQuery = '';
      searchMatches = [];
      searchTruncated = false;
    } else {
      if (searchIndex.stale) searchIndex.rebuild(searchTexts());
      searchQuery = query;
      final (matches, truncated) =
          searchIndex.search(query, exact: exactToggle.value, caseSensitive: caseToggle.value);
      searchMatches = matches;
      searchTruncated = truncated;
    }
    final count = searchMatches.length;
    if (searchQuery.isNotEmpty) {
      final overflow = searchTruncated ? '+' : '';
      resultsHeadingLabel.set('Results  ${grouped(count)}$overflow ${count == 1 ? 'match' : 'matches'}');
    } else {
      resultsHeadingLabel.set('Results');
    }
    resultsList.setItems(count, resultLabel, math.min(previous, count - 1));
    highlightEditorMatches();
  }

  String resultLabel(int index) {
    final record = searchMatches[index];
    if (record >= searchIndex.texts.length) return '';
    final (entry, field) = searchIndex.locate(record);
    final snippet = buildSnippet(searchIndex.textAt(record), searchQuery, caseToggle.value);
    return '${resultEntryLabel(entry)}|${resultFieldLabel(entry, field)}|$snippet';
  }

  void onResultSelect(int index) {
    if (index >= searchMatches.length) return;
    final record = searchMatches[index];
    if (record >= searchIndex.texts.length) return;
    final (entry, field) = searchIndex.locate(record);
    selectEntry(entry, field: field);
  }

  void stepResult(int delta) {
    if (searchPending) runSearch();
    final count = searchMatches.length;
    if (count == 0) return;
    final current = resultsList.selected;
    final target = current >= 0 ? (current + delta) % count : (delta > 0 ? 0 : count - 1);
    resultsList.choose(target < 0 ? target + count : target);
  }

  void highlightEditorMatches() {
    final query = searchQuery;
    if (query.isEmpty || document == null) {
      editor.highlight(const [], searchHitColor);
      return;
    }
    final text = editor.text;
    final caseSensitive = caseToggle.value;
    if (exactToggle.value) {
      final same = caseSensitive ? text == query : text.toLowerCase() == query.toLowerCase();
      editor.highlight(same ? [(0, text.length)] : const [], searchHitColor);
      return;
    }
    var haystack = text;
    var needle = query;
    if (!caseSensitive) {
      final lowered = text.toLowerCase();
      final loweredQuery = query.toLowerCase();
      if (lowered.length == text.length) {
        haystack = lowered;
        needle = loweredQuery;
      }
    }
    final ranges = <(int, int)>[];
    var start = 0;
    while (ranges.length < highlightLimit && needle.isNotEmpty) {
      final at = haystack.indexOf(needle, start);
      if (at < 0) break;
      ranges.add((at, at + needle.length));
      start = at + needle.length;
    }
    editor.highlight(ranges, searchHitColor);
  }

  void dragColumn(int which, double delta) {
    final total = bodyRect.$3 - 16 - 12;
    if (which == 0) {
      columnA = (columnA + delta).clamp(90.0, math.max(90.0, total - columnB - 160));
    } else {
      columnB = (columnB + delta).clamp(120.0, math.max(120.0, total - columnA - 160));
    }
    layout();
  }

  void dragSplit(double delta) {
    columnsHeight += delta;
    layout();
  }

  @override
  void layoutBody(double bx, double by, double bw, double bh) {
    final left = bx + 8;
    final inner = bw - 16;
    var y = by + 6;
    final infoH = math.max(16.0, infoLabel.heightFor(inner));
    infoLabel.place(left, y, inner, infoH);
    y += infoH + 2;
    final statusH = math.max(14.0, statusLabel.heightFor(inner));
    statusLabel.place(left, y, inner, statusH);
    y += statusH + 6;

    const rowH = 24.0;
    final searchW = Direct2D.measure('Search', labelBoldStyle).$1.ceilToDouble();
    searchLabel.place(left, y, searchW, rowH);
    final jumpW = 64.0;
    var right = left + inner;
    jumpBox.place(right - jumpW, y + 1, jumpW, rowH - 2);
    right -= jumpW + 8;
    final jumpLabelW = Direct2D.measure(jumpHeading, labelBoldStyle).$1.ceilToDouble() + 2;
    jumpLabel.place(right - jumpLabelW, y, jumpLabelW, rowH);
    right -= jumpLabelW + 16;
    caseToggle.place(right - 30, y + 1, 30, rowH - 2);
    right -= 30 + 4;
    exactToggle.place(right - 46, y + 1, 46, rowH - 2);
    right -= 46 + 8;
    searchBox.place(left + searchW + 8, y + 1, right - (left + searchW + 8), rowH - 2);
    y += rowH + 6;

    final areaBottom = by + bh - 2;
    final available = areaBottom - y;
    columnsHeight = columnsHeight.clamp(110.0, math.max(110.0, available - 6 - 120));
    final columnsTop = y;
    final total = inner - 12;
    columnA = columnA.clamp(90.0, math.max(90.0, total - 120 - 160));
    columnB = columnB.clamp(120.0, math.max(120.0, total - columnA - 160));
    final resultsW = math.max(0.0, total - columnA - columnB);
    const headingH = 18.0;
    final listH = columnsHeight - headingH;
    var cx = left;
    for (final (heading, list, width) in [
      (entriesHeadingLabel, entriesList, columnA),
      (fieldsHeadingLabel, fieldsList, columnB),
      (resultsHeadingLabel, resultsList, resultsW),
    ]) {
      heading.place(cx, columnsTop, width, headingH - 2);
      list.place(cx, columnsTop + headingH, width, listH);
      list.clampTop();
      cx += width + 6;
    }
    columnSashA.place(left + columnA, columnsTop, 6, columnsHeight);
    columnSashB.place(left + columnA + 6 + columnB, columnsTop, 6, columnsHeight);
    splitSash.place(left, columnsTop + columnsHeight, inner, 6);

    var vy = columnsTop + columnsHeight + 6 + 6;
    const buttonH = 22.0;
    final valueW = Direct2D.measure('Value', labelBoldStyle).$1.ceilToDouble() + 2;
    valueLabel.place(left, vy, valueW, buttonH);
    var bxRight = left + inner;
    for (final button in valueButtons.reversed) {
      final width = button.text.length > 1 ? 34.0 : 28.0;
      button.place(bxRight - width, vy, width, buttonH);
      bxRight -= width + 4;
    }
    lengthLabel.place(left + valueW + 10, vy, math.max(0, bxRight - (left + valueW + 10)), buttonH);
    vy += buttonH + 4;
    editor.place(left, vy, inner, math.max(20, areaBottom - vy));
  }

  @override
  void paintBody(Graphics g) {
    for (final box in [searchBox, jumpBox, editor]) {
      g.fillRect(box.x, box.y, box.w, box.h, fieldBg);
    }
  }

  @override
  bool panelKey(int vk) {
    if (vk == VK_ESCAPE) {
      host.closeApp();
      return true;
    }
    if (vk == VK_F1) {
      host.toggleTopmost();
      return true;
    }
    if (vk == 0x46 && keyDown(VK_CONTROL)) {
      focusSearch();
      return true;
    }
    return false;
  }

  @override
  bool textBoxKey(TextBox box, int msg, int vk) {
    if (msg == WM_CHAR) {
      if (box != editor && (vk == 13 || vk == 27 || vk == 6)) return true;
      return box == editor && (vk == 27 || vk == 6);
    }
    if (vk == VK_F1) {
      host.toggleTopmost();
      return true;
    }
    if (vk == 0x46 && keyDown(VK_CONTROL)) {
      focusSearch();
      return true;
    }
    if (box == searchBox) {
      if (vk == VK_RETURN) {
        stepResult(keyDown(VK_SHIFT) ? -1 : 1);
        return true;
      }
      if (vk == VK_ESCAPE) {
        clearSearch();
        return true;
      }
    }
    if (box == jumpBox && vk == VK_RETURN) {
      onJumpChange();
      return true;
    }
    if (vk == VK_ESCAPE) {
      host.closeApp();
      return true;
    }
    return false;
  }

  @override
  void textBoxChanged(TextBox box) {
    if (box == searchBox) {
      scheduleSearch();
    } else if (box == jumpBox) {
      onJumpChange();
    } else if (box == editor) {
      updateLengthLabel();
      if (searchQuery.isNotEmpty) highlightEditorMatches();
    }
  }
}

class BinEditor extends EditorPanel {
  final expandedDefaults = <int, Map<String, Object>>{};
  late final Button encodingButton;

  BinEditor(EditorHost host) : super('BIN Editor', host);

  BinDocument? get doc => document as BinDocument?;

  @override
  String get titleNoun => 'BIN';
  @override
  String get documentNoun => 'BIN';
  @override
  String get errorTitle => 'BIN Error';
  @override
  String get emptyInfo => 'No BIN loaded.';
  @override
  String get loadedStatus => 'BIN loaded.';
  @override
  List<FileFilter> get openFilters => const [
        FileFilter('All BIN files', '*.bin;*.bin_c;*.bin_j;*.bin_k'),
        FileFilter('BIN files', '*.bin'),
        FileFilter('BIN C files', '*.bin_c'),
        FileFilter('BIN J files', '*.bin_j'),
        FileFilter('BIN K files', '*.bin_k'),
      ];
  @override
  String get saveExtension => '.bin_c';
  @override
  String get fallbackName => 'edited.bin';
  @override
  bool get resetFieldOnEntryChange => false;
  @override
  (double, double) get columnWidths => (150, 240);

  @override
  String idleStatus() => 'Open a 20070319 BIN to start editing.';

  @override
  Object parse(Uint8List data, String encoding, String? filePath) => parseBinBytes(data, encoding, filePath);

  @override
  int documentCount(Object d) => (d as BinDocument).entryCount;
  @override
  String documentEncoding(Object d) => (d as BinDocument).encoding;
  @override
  String? documentPath(Object d) => (d as BinDocument).filePath;
  @override
  Uint8List documentBytes(Object d, String encoding) => (d as BinDocument).toBytes(encoding);

  @override
  void buildHeaderExtras() {
    encodingButton = addHeader(Button('UTF-8', toggleEncoding, accent, accentActive, black)..w = 54);
  }

  @override
  void refreshHeaderExtras() {
    final d = doc;
    encodingButton.text = d == null ? 'UTF-8' : encodingLabel(d.encoding);
  }

  @override
  List<Button> extraValueButtons() => [Button('E', expandDocument, 0xFF5B547B, 0xFF7E76A8)];

  @override
  void documentReplaced() => expandedDefaults.clear();

  @override
  int fieldCount(int entryIndex) => doc!.parameters.length;
  @override
  String entryLabel(int entryIndex) => 'Entry ${pad3(entryIndex)}';
  @override
  String fieldLabel(int entryIndex, int fieldIndex) => doc!.parameters[fieldIndex].name;

  @override
  String valueText(int entryIndex, int fieldIndex) {
    final parameter = doc!.parameters[fieldIndex];
    return formatValueForEditor(parameter.safeTypeName, doc!.getValue(entryIndex, parameter.name));
  }

  @override
  Iterable<List<String>> searchTexts() sync* {
    final d = doc!;
    final columns = [for (final p in d.parameters) (p.name, p.safeTypeName)];
    for (final entry in d.entries) {
      yield [for (final (name, type) in columns) formatValueForEditor(type, entry[name] ?? '')];
    }
  }

  @override
  void storeValue(int entryIndex, int fieldIndex, String rawValue) =>
      doc!.setValue(entryIndex, doc!.parameters[fieldIndex].name, rawValue);

  @override
  String updatedStatus(int entryIndex, int fieldIndex) =>
      'Updated ${doc!.parameters[fieldIndex].name} for entry ${pad3(entryIndex)}.';

  @override
  String infoText() {
    final d = doc!;
    final name = displayName('BIN');
    return '$name$dirtyMarker\n${d.entryCount} entries|${d.parameters.length} fields|${displayPath(name)}';
  }

  void toggleEncoding() {
    final d = doc;
    if (d == null) return;
    d.encoding = d.encoding == 'utf-8' ? 'cp932' : 'utf-8';
    dirty = true;
    status = 'Save encoding set to ${encodingLabel(d.encoding)}.';
    refresh();
  }

  @override
  void restoreSelectedValue() {
    final d = doc;
    final original = originalDocument as BinDocument?;
    final location = currentLocation();
    if (d == null || original == null || location == null) return;
    final (entry, field) = location;
    final parameter = d.parameters[field];
    if (entry >= original.entryCount) {
      final defaults = expandedDefaults[entry] ?? const {};
      if (defaults.containsKey(parameter.name)) {
        d.entries[entry][parameter.name] = defaults[parameter.name]!;
        status = 'Restored ${parameter.name} for duplicated entry ${pad3(entry)}.';
      } else {
        d.unsetValue(entry, parameter.name);
        status = 'Cleared ${parameter.name} for duplicated entry ${pad3(entry)}.';
      }
    } else {
      if (original.hasValue(entry, parameter.name)) {
        d.entries[entry][parameter.name] = original.getValue(entry, parameter.name);
      } else {
        d.unsetValue(entry, parameter.name);
      }
      status = 'Restored ${parameter.name} for entry ${pad3(entry)} from the original BIN.';
    }
    dirty = true;
    valueChanged(entry, field);
    refresh();
  }

  void expandDocument() {
    final d = doc;
    if (d == null) return;
    if (d.entryCount <= 0) {
      showError('Expand Failed', 'This BIN has no existing entries to duplicate yet.');
      return;
    }
    if (!commitCurrentValue(false)) {
      showError('Expand Failed', 'The current value couldnt be saved into memory. Fix it before duplicating an entry.');
      return;
    }
    final source = entryIndex;
    final copy = Map<String, Object>.of(d.entries[source]);
    final added = d.appendEntry(copy);
    expandedDefaults[added] = Map<String, Object>.of(copy);
    dirty = true;
    entryIndex = added;
    status = 'Duplicated entry ${pad3(source)} into entry ${pad3(added)}.';
    searchIndex.invalidate();
    refresh();
  }
}

class ShopEditor extends EditorPanel {
  String game = shopGameY0;

  ShopEditor(EditorHost host) : super('Shop BINs', host);

  ShopBinDocument? get doc => document as ShopBinDocument?;

  @override
  String get titleNoun => 'Shop BIN';
  @override
  String get documentNoun => 'shop BIN';
  @override
  String get errorTitle => 'Shop BIN Error';
  @override
  String get emptyInfo => 'No shop BIN loaded.';
  @override
  List<FileFilter> get openFilters => const [FileFilter('Shop BIN files', '*.bin'), FileFilter('All files', '*.*')];
  @override
  String get saveExtension => '.bin';
  @override
  String get fallbackName => 'edited_shop.bin';
  @override
  (double, double) get columnWidths => (150, 200);

  @override
  String idleStatus() => 'Open a ${shopGameLabels[game]} shop BIN to start editing.';
  @override
  String loadedMessage() => '${shopGameLabels[game]} shop BIN loaded.';

  @override
  Object parse(Uint8List data, String encoding, String? filePath) => parseShopBinBytes(data, game, encoding, filePath);

  @override
  int documentCount(Object d) => (d as ShopBinDocument).entryCount;
  @override
  String documentEncoding(Object d) => (d as ShopBinDocument).encoding;
  @override
  String? documentPath(Object d) => (d as ShopBinDocument).filePath;
  @override
  Uint8List documentBytes(Object d, String encoding) => (d as ShopBinDocument).toBytes(encoding);

  void openForGame(String target) {
    final file = askOpenPath('Open ${shopGameLabels[target]} shop BIN');
    if (file == null || !confirmOpenDiscard()) return;
    final previous = game;
    game = target;
    if (!loadDocument(file)) {
      game = previous;
      refresh();
    }
  }

  List<String> fieldNames(int entryIndex) => doc!.fieldNamesForEntry(entryIndex);

  @override
  int fieldCount(int entryIndex) => fieldNames(entryIndex).length;
  @override
  String entryLabel(int entryIndex) => doc!.entryLabel(entryIndex);
  @override
  String fieldLabel(int entryIndex, int fieldIndex) => fieldNames(entryIndex)[fieldIndex];
  @override
  String valueText(int entryIndex, int fieldIndex) =>
      formatShopValueForEditor(doc!.getValue(entryIndex, fieldNames(entryIndex)[fieldIndex]));

  @override
  Iterable<List<String>> searchTexts() sync* {
    final d = doc!;
    for (var i = 0; i < d.entryCount; i++) {
      yield [for (final name in d.fieldNamesForEntry(i)) formatShopValueForEditor(d.getValue(i, name))];
    }
  }

  @override
  void valueChanged(int entryIndex, int fieldIndex) => searchIndex.invalidate();

  @override
  void storeValue(int entryIndex, int fieldIndex, String rawValue) =>
      doc!.setValue(entryIndex, fieldNames(entryIndex)[fieldIndex], rawValue);

  @override
  String updatedStatus(int entryIndex, int fieldIndex) =>
      'Updated ${fieldNames(entryIndex)[fieldIndex]} for entry ${pad3(entryIndex)}.';

  @override
  String infoText() {
    final d = doc!;
    final name = displayName('Shop BIN');
    return '$name$dirtyMarker\n${shopGameLabels[d.game]}|${d.sharedCount} shared|${d.itemCount} items|'
        '${displayPath(name)}';
  }

  @override
  void restoreSelectedValue() {
    final d = doc;
    final original = originalDocument as ShopBinDocument?;
    final location = currentLocation();
    if (d == null || original == null || location == null) return;
    final (entry, field) = location;
    if (entry >= original.entryCount) return;
    final name = fieldNames(entry)[field];
    try {
      d.setValue(entry, name, original.getValue(entry, name));
    } catch (error) {
      showError('Restore Failed', describe(error));
      return;
    }
    dirty = true;
    status = 'Restored $name for entry ${pad3(entry)} from the original shop BIN.';
    valueChanged(entry, field);
    refresh();
  }
}

class StringTableEditor extends EditorPanel {
  StringTableEditor(EditorHost host) : super('String Table', host);

  StringTableDocument? get doc => document as StringTableDocument?;

  @override
  String get titleNoun => 'String Table';
  @override
  String get documentNoun => 'string table';
  @override
  String get entriesHeading => 'Groups';
  @override
  String get fieldsHeading => 'Strings';
  @override
  String get jumpHeading => 'Jump to Group';
  @override
  int get jumpDigits => 4;
  @override
  String get errorTitle => 'String Table Error';
  @override
  String get emptyInfo => 'No string table loaded.';
  @override
  String get loadedStatus => 'String table loaded.';
  @override
  String? get openTitle => 'Open string table';
  @override
  List<FileFilter> get openFilters => const [
        FileFilter('String table', 'string_tbl*.bin'),
        FileFilter('BIN files', '*.bin'),
        FileFilter('All files', '*.*'),
      ];
  @override
  String get saveExtension => '.bin';
  @override
  String get fallbackName => 'string_tbl.bin';
  @override
  bool get skipUnchangedOnApply => true;
  @override
  (double, double) get columnWidths => (250, 300);

  @override
  String idleStatus() => 'Open a string_tbl.bin to start editing.';

  @override
  Object parse(Uint8List data, String encoding, String? filePath) => parseStringTableBytes(data, encoding, filePath);

  @override
  int documentCount(Object d) => (d as StringTableDocument).entryCount;
  @override
  String documentEncoding(Object d) => (d as StringTableDocument).encoding;
  @override
  String? documentPath(Object d) => (d as StringTableDocument).filePath;
  @override
  Uint8List documentBytes(Object d, String encoding) => (d as StringTableDocument).toBytes(encoding);

  @override
  int fieldCount(int entryIndex) => doc!.groups[entryIndex].length;
  @override
  String entryLabel(int entryIndex) => doc!.entryLabel(entryIndex);
  @override
  String fieldLabel(int entryIndex, int fieldIndex) => doc!.fieldLabel(entryIndex, fieldIndex);
  @override
  String resultEntryLabel(int entryIndex) => 'Group ${pad4(entryIndex)}';
  @override
  String resultFieldLabel(int entryIndex, int fieldIndex) => 'String ${pad3(fieldIndex)}';
  @override
  String valueText(int entryIndex, int fieldIndex) =>
      formatStringTableValueForEditor(doc!.getValue(entryIndex, fieldIndex));

  @override
  Iterable<List<String>> searchTexts() sync* {
    for (final group in doc!.groups) {
      yield [for (final value in group) value ?? ''];
    }
  }

  @override
  void storeValue(int entryIndex, int fieldIndex, String rawValue) {
    encodeText(rawValue, doc!.encoding);
    doc!.setValue(entryIndex, fieldIndex, rawValue);
  }

  @override
  String updatedStatus(int entryIndex, int fieldIndex) => 'Updated group ${pad4(entryIndex)} string ${pad3(fieldIndex)}.';

  @override
  String savedStatus(String outputPath, Uint8List outputBytes) {
    final change = outputBytes.length - (sourceBytes?.length ?? 0);
    return 'Created string table at ${shortenPathSmart(outputPath)} '
        '(${outputBytes.length} bytes, ${change >= 0 ? '+$change' : '$change'} vs original).';
  }

  @override
  String infoText() {
    final d = doc!;
    final file = path ?? d.filePath ?? 'string_tbl.bin';
    return '${fileNameOf(file)}$dirtyMarker\n${d.entryCount} groups|${d.stringCount} strings|'
        '${encodingLabel(d.encoding)}|${shortenPathSmart(file)}';
  }

  @override
  void restoreSelectedValue() {
    final d = doc;
    final original = originalDocument as StringTableDocument?;
    final location = currentLocation();
    if (d == null || original == null || location == null) return;
    d.setValue(location.$1, location.$2, original.getValue(location.$1, location.$2));
    dirty = true;
    status = 'Restored group ${pad4(location.$1)} string ${pad3(location.$2)} from the original file.';
    valueChanged(location.$1, location.$2);
    refresh();
  }
}
