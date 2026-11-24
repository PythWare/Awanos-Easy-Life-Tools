import 'dart:async'; import 'dart:ffi'; import 'dart:io'; import 'dart:isolate';
import 'd2d.dart'; import 'editors.dart'; import 'launcher.dart'; import 'native.dart'; import 'par_batch.dart';
import 'shop_bin.dart'; import 'side_panels.dart'; import 'ui.dart'; import 'win.dart';

const appTitle = "Awano's Easy Life Tools";
const mainButtons = ['Tools', 'Guide'];
const subOptions = {
  'Tools': ['BIN Editor', 'Shop BINs', 'String Table', 'PAR Unpack'],
  'Guide': ['BIN Guide', 'Usage Docs'],
};
const subSubOptions = {
  'BIN Editor': ['Open', 'Close'],
  'Shop BINs': ['Y0', 'Y3', 'Close'],
  'String Table': ['Open', 'Close'],
  'PAR Unpack': ['Batch Unpack'],
  'BIN Guide': ['Info', 'Credits'],
  'Usage Docs': ['Usage', 'Explanations'],
};
const editorSubs = {'BIN Editor', 'Shop BINs', 'String Table'};
const closeMessage = WM_APP + 1;

const guideContent = {
  'BIN Guide/Info': (
    'BIN Guide, Info',
    'Awano has two BIN editors because the files arent the same format.\n\n'
        "BIN Editor opens the older 20070319 files, usually named .bin_c, .bin_j, or .bin_k. They're table style files "
        'with entries and named parameter fields. Shop BINs opens Y0 and Y3 shop tables. They use separate binary layouts.\n\n'
        'String Table opens string_tbl.bin. Its a list of groups, each group holding pointers to text. Saving rebuilds '
        'every pointer so strings can grow or shrink.',
  ),
  'BIN Guide/Credits': (
    'BIN Guide, Credits',
    "2007 BIN editor source reference: SlowpokeVG's JavaScript BIN work.\n\n"
        "Shop BIN binary template references: Violet's Y0 and Y3 shop BIN 010 templates.",
  ),
  'Usage Docs/Usage': (
    'Usage Docs, Usage',
    'BIN Editor opens 20070319 .bin_c, .bin_j, and .bin_k files. Use Open to pick a file and Close to unload it.\n\n'
        '2007 BIN buttons: UTF-8 or CP932 changes the save encoding. S applies the Value box to the selected entry and '
        'field. RA reloads all values from the original file. E duplicates the current entry for expansion work. C saves '
        'a new BIN. R restores only the selected value from the original load.\n\n'
        'Shop BINs opens Y0 and Y3 shop tables. Press Y0 or Y3 to pick a file for that game. Close unloads the current '
        'shop BIN.\n\n'
        'Shop buttons: S applies the Value box. RA reloads all values from the original shop BIN. C saves a new shop BIN. '
        'R restores only the selected field from the original load.\n\n'
        'String Table opens string_tbl.bin. Pick a group on the left and a string on the right. S, RA, C, and R work the '
        'same as in Shop BINs.\n\n'
        'Search: every editor has a search bar that looks through every value in the file. Exact only matches whole '
        'values, Aa makes it case sensitive. Enter jumps to the next result, Shift+Enter to the previous one, Esc clears '
        'it, and Ctrl+F focuses it. Clicking a result opens that entry and field.\n\n'
        'Panels: drag the title bar to move a panel anywhere on screen, drag the corner grip to resize it, and drag the '
        'gaps between lists or above the Value box to give any section more room. Picking an editor in the Tools menu '
        'brings its panel back if a file is still loaded.\n\n'
        'Launcher: right-drag anywhere on it or drag the title to move it along with its panels. F1 toggles always on '
        'top and Esc closes the app.',
  ),
  'Usage Docs/Explanations': (
    'Usage Docs, Explanations',
    'Entries are the rows in the loaded table. Fields are the values stored for the selected row.\n\n'
        'Text fields can be longer than the visible area, scroll as needed. The line above the Value box shows the '
        'character and byte count of the value and how many bytes it changed since it was loaded.\n\n'
        'The 2007 BIN editor has an E button because those tables can be expanded by duplicating an entry.\n\n'
        'Shop BIN numeric edits should keep the table compact. Description edits may grow the file because the save path '
        'rewrites the string area and updates pointers.\n\n'
        'String Table strings marked (null) have no text at all. They stay null unless you type something and press S.',
  ),
};

String appDirectory() {
  final exe = Platform.resolvedExecutable.toLowerCase();
  if (exe.endsWith('dart.exe') || exe.endsWith('dartvm.exe')) return Directory.current.path;
  return File(Platform.resolvedExecutable).parent.path;
}

class AwanoApp {
  late final LauncherWindow launcher;
  late final EditorHost host;
  late final BinEditor binEditor;
  late final ShopEditor shopEditor;
  late final StringTableEditor stringTableEditor;
  late final ParPanel parPanel;
  late final GuidePanel guidePanel;
  late final Map<String, EditorPanel> editors;
  late final List<Panel> exclusivePanels;
  late final List<Panel> panels;
  bool topmost = true;
  bool quitting = false;

  String? parRoot;
  String? parOutputRoot;
  String parStatus = 'Select a folder to batch unpack PAR archives.';
  String parSummary = '';
  double parProgress = 0;
  bool parRunning = false;
  bool parCancelRequested = false;
  int parTopLevel = 0, parNested = 0, parTotal = 0, parCompleted = 0, parActive = 0, parQueued = 0, parErrors = 0;
  ReceivePort? parPort;
  SendPort? parControl;

  void start() {
    SetProcessDpiAwarenessContext(-4);
    CoInitializeEx(nullptr, 0x2 | 0x4);
    scoped((a) => LoadLibraryW(wstr('Msftedit.dll', a)));
    Direct2D.start();
    errorReporter = (error) => messageBox(launcher.hwnd, 'Unexpected error:\n$error', appTitle, MB_OK | MB_ICONERROR);

    launcher = LauncherWindow(appTitle, mainButtons, subOptions, subSubOptions, onLauncherClick, closeApp,
        toggleTopmost, (dx, dy) => followLauncher());
    host = EditorHost(showExclusive, () => launcher.hwnd, () => launcher.origin, requestClose, toggleTopmost);
    binEditor = BinEditor(host);
    shopEditor = ShopEditor(host);
    stringTableEditor = StringTableEditor(host);
    editors = {'BIN Editor': binEditor, 'Shop BINs': shopEditor, 'String Table': stringTableEditor};
    parPanel = ParPanel(host, closeParPanel)..onCancel = cancelParBatch;
    guidePanel = GuidePanel(host, () => guidePanel.hide());
    exclusivePanels = [binEditor, shopEditor, stringTableEditor, guidePanel];
    panels = [...exclusivePanels, parPanel];
    refreshParWidgets();
    launcher.show();
  }

  void followLauncher() {
    for (final panel in panels) {
      if (panel.panelVisible) panel.applyGeometry(launcher.origin);
    }
  }

  void showExclusive(Panel panel) {
    for (final other in exclusivePanels) {
      if (other != panel) other.hide();
    }
    panel.show();
  }

  void hideExclusive() {
    for (final panel in exclusivePanels) {
      panel.hide();
    }
  }

  void hideParPanelIfIdle() {
    if (parRunning && !parCancelRequested) return;
    parPanel.hide();
  }

  void onLauncherClick(String kind, String name) {
    switch (kind) {
      case 'main':
        launcher.main = launcher.main == name ? null : name;
        launcher.sub = null;
        hideExclusive();
        hideParPanelIfIdle();
        launcher.stateChanged();
      case 'sub':
        launcher.sub = launcher.sub == name ? null : name;
        hideExclusive();
        final sub = launcher.sub;
        if (sub != null && editorSubs.contains(sub)) editors[sub]!.showPanel();
        if (sub == 'PAR Unpack' && parRoot != null) {
          parPanel.show();
        } else {
          hideParPanelIfIdle();
        }
        launcher.stateChanged();
      case 'subsub':
        runSubSubAction(launcher.sub ?? '', name);
    }
  }

  void runSubSubAction(String sub, String name) {
    final guide = guideContent['$sub/$name'];
    if (guide != null) {
      guidePanel.showPage(guide.$1, guide.$2);
      showExclusive(guidePanel);
      return;
    }
    switch ('$sub/$name') {
      case 'PAR Unpack/Batch Unpack':
        startParBatchUnpack();
      case 'BIN Editor/Open':
        binEditor.openDocument();
      case 'BIN Editor/Close':
        binEditor.closeDocument();
      case 'Shop BINs/Y0':
        shopEditor.openForGame(shopGameY0);
      case 'Shop BINs/Y3':
        shopEditor.openForGame(shopGameY3);
      case 'Shop BINs/Close':
        shopEditor.closeDocument();
      case 'String Table/Open':
        stringTableEditor.openDocument();
      case 'String Table/Close':
        stringTableEditor.closeDocument();
    }
  }

  int get parDialogOwner => parPanel.panelVisible ? parPanel.hwnd : launcher.hwnd;

  void startParBatchUnpack([String? chosen]) {
    if (parRunning) {
      messageBox(parDialogOwner, 'A PAR batch is already running.', 'PAR Unpack', MB_OK | MB_ICONINFORMATION);
      return;
    }
    final folder = chosen ?? fileDialog(parDialogOwner, folder: true, title: 'Choose a folder to batch unpack');
    if (folder == null) return;
    final rootName = folder.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
    final outputRoot = '${appDirectory()}\\PAR_Unpacker\\${rootName}_awano_unpack';
    parRoot = folder;
    parOutputRoot = null;
    parStatus = 'Scanning for PAR archives';
    parSummary = '';
    parProgress = 0;
    parRunning = true;
    parCancelRequested = false;
    parTopLevel = parNested = parTotal = parCompleted = parActive = parQueued = parErrors = 0;
    parPanel.resetLog('Selected $folder for PAR batch unpack.');
    refreshParWidgets();
    parPanel.show();

    final port = ReceivePort();
    parPort = port;
    port.listen(onParEvent);
    Isolate.spawn(parBatchEntry, <Object?>[port.sendPort, folder, outputRoot, parMaxWorkers], debugName: 'par-batch');
  }

  void onParEvent(dynamic message) {
    final event = Map<String, Object?>.from(message as Map);
    switch (event['type']) {
      case 'control':
        parControl = event['port'] as SendPort;
        if (parCancelRequested) parControl!.send('cancel');
      case 'log':
        parPanel.appendLog(event['message'] as String? ?? '');
      case 'summary':
        parSummary = event['message'] as String? ?? '';
      case 'state':
        applyParState(event);
      case 'error':
        parRunning = false;
        parStatus = event['message'] as String? ?? 'PAR batch failed.';
        parPanel.appendLog(parStatus);
        refreshParWidgets();
        messageBox(parDialogOwner, parStatus, 'PAR Batch Error', MB_OK | MB_ICONERROR);
      case 'finished':
        parRunning = false;
        parCancelRequested = false;
        if (parErrors == 0 && parTotal > 0) parStatus = 'PAR batch unpack finished.';
        parPort?.close();
        parPort = null;
        parControl = null;
    }
    refreshParWidgets();
  }

  void applyParState(Map<String, Object?> event) {
    int value(String key, int fallback) => (event[key] as num?)?.toInt() ?? fallback;
    parTopLevel = value('top_level_jobs', parTopLevel);
    parNested = value('nested_jobs', parNested);
    parStatus = event['status'] as String? ?? parStatus;
    parOutputRoot = event['output_root'] as String? ?? parOutputRoot;
    parProgress = (event['progress'] as num?)?.toDouble() ?? parProgress;
    parRunning = event['running'] as bool? ?? parRunning;
    parTotal = value('total_jobs', parTotal);
    parCompleted = value('completed_jobs', parCompleted);
    parActive = value('active_jobs', parActive);
    parQueued = value('queued_jobs', parQueued);
    parErrors = value('error_count', parErrors);
  }

  void cancelParBatch() {
    if (!parRunning || parCancelRequested) return;
    parCancelRequested = true;
    parControl?.send('cancel');
    parStatus = 'Cancelling PAR batch';
    parPanel.appendLog('Cancellation requested. Waiting for active workers to stop.');
    refreshParWidgets();
  }

  void closeParPanel() {
    if (parRunning) {
      final answer = messageBox(parDialogOwner, 'Cancel the current PAR batch and hide the panel?', 'Close PAR Unpack',
          MB_YESNO | MB_ICONQUESTION);
      if (answer != IDYES) return;
      cancelParBatch();
    }
    parPanel.hide();
  }

  void refreshParWidgets() {
    final root = parRoot;
    if (root != null) {
      final lines = [root.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last, 'In:  ${shortenPathSmart(root)}'];
      final output = parOutputRoot;
      if (output != null) lines.add('Out: ${shortenPathSmart(output)}');
      parPanel.infoLabel.set(lines.join('\n'));
    } else {
      parPanel.infoLabel.set('No PAR batch running.');
    }
    parPanel.statusLabel.set(parStatus);
    parPanel.summaryLabel.set(parSummary);
    parPanel.progress.value = parProgress;
    parPanel.cancelButton
      ..enabled = parRunning
      ..text = parRunning ? 'Cancel' : 'Done';
    if (parPanel.panelVisible) parPanel.layout();
    parPanel.invalidate();
  }

  void requestClose() => PostMessageW(launcher.hwnd, closeMessage, 0, 0);

  void closeApp() {
    if (quitting) return;
    if (editors.values.any((editor) => editor.dirty)) {
      final answer = messageBox(
          launcher.hwnd, 'There are unsaved edits. Discard them and exit?', 'Exit', MB_YESNO | MB_ICONQUESTION);
      if (answer != IDYES) return;
    }
    if (parRunning) cancelParBatch();
    quitting = true;
    for (final panel in panels) {
      panel.hide();
      DestroyWindow(panel.hwnd);
    }
    DestroyWindow(launcher.hwnd);
  }

  void toggleTopmost() {
    topmost = !topmost;
    launcher.setTopmost(topmost);
    for (final panel in panels) {
      panel.setTopmost(topmost);
    }
  }

  void openFromArguments(List<String> args) {
    for (var i = 0; i + 1 < args.length; i += 2) {
      final file = args[i + 1];
      switch (args[i]) {
        case '--bin':
          launcher.main = 'Tools';
          launcher.sub = 'BIN Editor';
          binEditor.loadDocument(file);
        case '--shop-y0':
        case '--shop-y3':
          launcher.main = 'Tools';
          launcher.sub = 'Shop BINs';
          shopEditor.game = args[i] == '--shop-y3' ? shopGameY3 : shopGameY0;
          shopEditor.loadDocument(file);
        case '--strings':
          launcher.main = 'Tools';
          launcher.sub = 'String Table';
          stringTableEditor.loadDocument(file);
        case '--par':
          launcher.main = 'Tools';
          launcher.sub = 'PAR Unpack';
          startParBatchUnpack(file);
      }
    }
    launcher.stateChanged();
  }

  Future<void> run([List<String> args = const []]) async {
    start();
    if (args.isNotEmpty) openFromArguments(args);
    final msg = heap<MSG>();
    var running = true;
    while (running) {
      while (PeekMessageW(msg, 0, 0, 0, PM_REMOVE) != 0) {
        if (msg.ref.message == WM_QUIT) {
          running = false;
          break;
        }
        if (msg.ref.message == closeMessage && msg.ref.hwnd == launcher.hwnd) {
          closeApp();
          continue;
        }
        TranslateMessage(msg);
        DispatchMessageW(msg);
      }
      if (!running) break;
      MsgWaitForMultipleObjectsEx(0, nullptr, parRunning ? 15 : 200, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
      await Future<void>.delayed(Duration.zero);
    }
    heap.free(msg);
    parPort?.close();
  }
}
