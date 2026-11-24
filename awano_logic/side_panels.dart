import 'dart:math' as math;
import 'd2d.dart'; import 'editors.dart'; import 'ui.dart'; import 'win.dart';

const parPanelWidth = 640.0;
const parPanelHeight = 480.0;
const guidePanelWidth = 600.0;
const guidePanelHeight = 480.0;
const sidePanelX = 540.0;
const parLogLimit = 120;

class ParPanel extends Panel {
  final EditorHost host;
  late final Label infoLabel = add(Label('No PAR batch running.', labelBoldStyle.copy(wrap: true, vAlign: vAlignNear), white));
  late final Label statusLabel = add(Label('', labelStyle.copy(wrap: true, vAlign: vAlignNear), mutedFg));
  late final Label summaryLabel = add(Label('', labelBoldStyle.copy(wrap: true, vAlign: vAlignNear), goldFg));
  late final ProgressBar progress = add(ProgressBar());
  late final Button cancelButton;
  late final TextBox log;
  void Function() onCancel = () {};

  ParPanel(this.host, void Function() close)
      : super('PAR Unpack', parPanelWidth, parPanelHeight, sidePanelX, 84, host.origin, close) {
    cancelButton = add(Button('Done', () => onCancel(), 0xFF6A4A4A, 0xFF8F6161));
    log = TextBox(this, 201, multiline: true, readOnly: true, points: 8);
    fitToScreen();
  }

  void resetLog(String first) => log.text = first;
  void appendLog(String message) {
    if (message.isNotEmpty) log.append(message, parLogLimit);
  }

  @override
  void layoutBody(double bx, double by, double bw, double bh) {
    final left = bx + 8;
    final inner = bw - 16;
    var y = by + 6;
    for (final (label, gap) in [(infoLabel, 2.0), (statusLabel, 2.0), (summaryLabel, 2.0)]) {
      if (label.text.isEmpty) {
        label.place(left, y, inner, 0);
        continue;
      }
      final height = math.max(14.0, label.heightFor(inner));
      label.place(left, y, inner, height);
      y += height + gap;
    }
    y += 4;
    progress.place(left, y, inner, 12);
    y += 12 + 6;
    final bottom = by + bh - 4;
    cancelButton.place(left + inner - 68, bottom - 24, 68, 24);
    log.place(left, y, inner, math.max(30, bottom - 24 - 6 - y));
  }

  @override
  void paintBody(Graphics g) => g.fillRect(log.x, log.y, log.w, log.h, fieldBg);

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
    return false;
  }

  @override
  bool textBoxKey(TextBox box, int msg, int vk) {
    if (msg == WM_CHAR) return vk == 27;
    return panelKey(vk);
  }
}

class GuidePanel extends Panel {
  final EditorHost host;
  late final TextBox body;

  GuidePanel(this.host, void Function() close)
      : super('Guide', guidePanelWidth, guidePanelHeight, sidePanelX, 76, host.origin, close) {
    body = TextBox(this, 301, multiline: true, readOnly: true, face: uiFont, points: 10, padX: 10, padY: 8);
    fitToScreen();
  }

  void showPage(String newTitle, String text) {
    title = newTitle;
    body.text = text;
    invalidate();
  }

  @override
  void layoutBody(double bx, double by, double bw, double bh) => body.place(bx + 8, by + 8, bw - 16, bh - 16);

  @override
  void paintBody(Graphics g) => g.fillRect(body.x, body.y, body.w, body.h, fieldBg);

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
    return false;
  }

  @override
  bool textBoxKey(TextBox box, int msg, int vk) {
    if (msg == WM_CHAR) return vk == 27;
    return panelKey(vk);
  }
}
