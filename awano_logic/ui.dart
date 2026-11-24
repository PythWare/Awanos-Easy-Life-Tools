import 'dart:ffi'; import 'dart:math' as math;
import 'd2d.dart'; import 'native.dart'; import 'win.dart';

const accent = 0xFFF4B400;
const accentActive = 0xFFFFD663;
const panelBg = 0xFF0F141B;
const panelFrame = 0xFF202833;
const panelOutline = 0xFF3A4656;
const headerBg = 0xFF1C2734;
const fieldBg = 0xFF1A212A;
const trough = 0xFF121821;
const scrollActive = 0xFF6E83A1;
const scrollThumb = 0xFF3B4859;
const headingFg = 0xFFDFE7F0;
const mutedFg = 0xFFB8C2CE;
const goldFg = 0xFFE1B85E;
const toggleOff = 0xFF2D3846;
const white = 0xFFFFFFFF;
const black = 0xFF000000;
const lilac = 0xFFBF98D9;

const uiFont = 'Segoe UI';
const monoFont = 'Consolas';
double pt(double points) => points * 96 / 72;

final labelStyle = TextStyle(uiFont, pt(8));
final labelBoldStyle = TextStyle(uiFont, pt(8), weight: weightBold);
final titleStyle = TextStyle(uiFont, pt(10), weight: weightBold);
final buttonStyle = TextStyle(uiFont, pt(8), weight: weightBold, align: alignCenter);
final listStyle = TextStyle(monoFont, pt(9));

int colorRef(int argb) => ((argb & 0xFF) << 16) | (argb & 0xFF00) | ((argb >> 16) & 0xFF);

final windows = <int, BaseWindow>{};
void Function(Object error)? errorReporter;

int windowProc(int hwnd, int msg, int wParam, int lParam) {
  final window = windows[hwnd];
  if (window != null) {
    try {
      final result = window.handle(msg, wParam, lParam);
      if (result != null) return result;
    } catch (error, stack) {
      errorReporter?.call('$error\n$stack');
    }
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

late final NativeCallable<WndProcNative> windowCallback;
var classesRegistered = false;

void registerClasses() {
  if (classesRegistered) return;
  classesRegistered = true;
  windowCallback = NativeCallable<WndProcNative>.isolateLocal(windowProc, exceptionalReturn: 0);
  scoped((a) {
    for (final (name, style) in [('AwanoLauncher', 0), ('AwanoPanel', CS_DROPSHADOW)]) {
      final wc = a<WNDCLASSEXW>()
        ..ref.cbSize = sizeOf<WNDCLASSEXW>()
        ..ref.style = style
        ..ref.lpfnWndProc = windowCallback.nativeFunction
        ..ref.hInstance = GetModuleHandleW(nullptr)
        ..ref.hCursor = LoadCursorW(0, IDC_ARROW)
        ..ref.lpszClassName = wstr(name, a);
      RegisterClassExW(wc);
    }
  });
}

abstract class BaseWindow {
  int hwnd = 0;
  double dpi = 96;
  double get scale => dpi / 96;
  int? handle(int msg, int wParam, int lParam);
}

abstract class Widget {
  double x = 0, y = 0, w = 0, h = 0;
  bool visible = true;
  late Panel panel;

  bool contains(double px, double py) => visible && px >= x && px < x + w && py >= y && py < y + h;
  void place(double nx, double ny, double nw, double nh) {
    x = nx;
    y = ny;
    w = nw < 0 ? 0 : nw;
    h = nh < 0 ? 0 : nh;
  }

  void paint(Graphics g);
  void down(double px, double py) {}
  void move(double px, double py, bool pressed) {}
  void up(double px, double py) {}
  void leave() {}
  bool wheel(int delta) => false;
  bool key(int vk) => false;
  int get cursor => IDC_ARROW;
  bool get focusable => false;
  void invalidate() => panel.invalidate();
}

class Label extends Widget {
  String text;
  TextStyle style;
  int color;
  Label(this.text, this.style, this.color);

  void set(String value) {
    if (value == text) return;
    text = value;
    invalidate();
  }

  double heightFor(double width) => Direct2D.measure(text.isEmpty ? ' ' : text, style, width).$2.ceilToDouble();

  @override
  void paint(Graphics g) => g.text(text, x, y, w, h, style, color);
}

class Button extends Widget {
  String text;
  int background;
  int activeBackground;
  int foreground;
  void Function() onClick;
  bool enabled = true;
  bool hover = false;
  bool pressed = false;
  Button(this.text, this.onClick, this.background, this.activeBackground, [this.foreground = white]);

  @override
  void paint(Graphics g) {
    var fill = hover ? activeBackground : background;
    if (pressed && hover) fill = mixColor(activeBackground, black, 0.18);
    if (!enabled) fill = mixColor(background, panelBg, 0.45);
    g.fillRounded(x, y, w, h, 3, fill);
    g.text(text, x, y, w, h, buttonStyle, enabled ? foreground : mixColor(foreground, panelBg, 0.45));
  }

  @override
  int get cursor => enabled ? IDC_HAND : IDC_ARROW;

  @override
  void move(double px, double py, bool isPressed) {
    final inside = contains(px, py);
    if (inside != hover) {
      hover = inside;
      invalidate();
    }
  }

  @override
  void leave() {
    if (hover) {
      hover = false;
      invalidate();
    }
  }

  @override
  void down(double px, double py) {
    if (!enabled) return;
    pressed = true;
    invalidate();
  }

  @override
  void up(double px, double py) {
    final fire = pressed && contains(px, py) && enabled;
    pressed = false;
    invalidate();
    if (fire) onClick();
  }
}

class ToggleButton extends Button {
  bool value = false;
  void Function() onChange;
  ToggleButton(String text, this.onChange) : super(text, () {}, toggleOff, scrollActive) {
    onClick = toggle;
  }

  void toggle() {
    value = !value;
    background = value ? accent : toggleOff;
    activeBackground = value ? accentActive : scrollActive;
    foreground = value ? black : white;
    invalidate();
    onChange();
  }
}

class ProgressBar extends Widget {
  double value = 0;

  @override
  void paint(Graphics g) {
    g.fillRounded(x, y, w, h, h / 2, fieldBg);
    final fill = w * value.clamp(0.0, 1.0);
    if (fill > 0) g.fillRounded(x, y, math.max(fill, h), h, h / 2, accent);
  }
}

class Sash extends Widget {
  final bool vertical;
  void Function(double delta) onDrag;
  double last = 0;
  bool hover = false;
  Sash(this.vertical, this.onDrag);

  @override
  void paint(Graphics g) {
    if (!hover) return;
    if (vertical) {
      g.fillRounded(x + w / 2 - 1, y + 4, 2, h - 8, 1, withAlpha(scrollActive, 0.8));
    } else {
      g.fillRounded(x + 4, y + h / 2 - 1, w - 8, 2, 1, withAlpha(scrollActive, 0.8));
    }
  }

  @override
  int get cursor => vertical ? IDC_SIZEWE : IDC_SIZENS;

  @override
  void move(double px, double py, bool pressed) {
    if (pressed) {
      final now = vertical ? px : py;
      final delta = now - last;
      if (delta != 0) {
        last = now;
        onDrag(delta);
      }
    } else if (!hover) {
      hover = true;
      invalidate();
    }
  }

  @override
  void leave() {
    if (hover) {
      hover = false;
      invalidate();
    }
  }

  @override
  void down(double px, double py) => last = vertical ? px : py;
}

class VirtualList extends Widget {
  void Function(int index)? onSelect;
  int count = 0;
  int top = 0;
  int selected = -1;
  int hovered = -1;
  String Function(int index)? labelFor;
  double wheelRemainder = 0;
  bool draggingThumb = false;
  double thumbGrab = 0;
  bool thumbHover = false;
  static const scrollWidth = 12.0;

  VirtualList(this.onSelect);

  double get lineHeight => (Direct2D.measure('Ag', listStyle).$2 + 3).ceilToDouble();
  int get rows => math.max(1, (h / lineHeight).floor());
  double get listWidth => w - scrollWidth;

  void setItems(int newCount, String Function(int index)? label, [int newSelected = -1]) {
    count = math.max(0, newCount);
    labelFor = label;
    selected = math.min(newSelected, count - 1);
    if (selected >= 0) see(selected);
    clampTop();
    invalidate();
  }

  void select(int index, [bool reveal = true]) {
    if (count <= 0) return;
    selected = index.clamp(0, count - 1);
    if (reveal) see(selected);
    invalidate();
  }

  void choose(int index) {
    select(index);
    if (selected >= 0) onSelect?.call(selected);
  }

  void see(int index) {
    if (index < top) {
      top = index;
    } else if (index >= top + rows) {
      top = index - rows + 1;
    }
    clampTop();
  }

  void clampTop() => top = math.max(0, math.min(top, count - rows));

  void scrollTo(int newTop) {
    top = newTop;
    clampTop();
    invalidate();
  }

  (double, double) thumb() {
    if (count <= rows) return (y, h);
    final size = math.max(24.0, h * rows / count);
    final range = h - size;
    final pos = y + range * top / math.max(1, count - rows);
    return (pos, size);
  }

  @override
  void paint(Graphics g) {
    g.fillRect(x, y, w, h, fieldBg);
    g.fillRect(x + listWidth, y, scrollWidth, h, trough);
    final line = lineHeight;
    g.pushClip(x, y, listWidth, h);
    final end = math.min(count, top + rows + 1);
    for (var index = top; index < end; index++) {
      final rowY = y + (index - top) * line;
      final isSelected = index == selected;
      if (isSelected) {
        g.fillRect(x, rowY, listWidth, line, accent);
      } else if (index == hovered) {
        g.fillRect(x, rowY, listWidth, line, 0xFF242D39);
      }
      final label = labelFor?.call(index) ?? '';
      g.text(label, x + 4, rowY, listWidth - 6, line, listStyle, isSelected ? black : white);
    }
    g.popClip();
    if (count > rows) {
      final (pos, size) = thumb();
      g.fillRounded(x + listWidth + 2, pos + 2, scrollWidth - 4, size - 4, 4,
          draggingThumb || thumbHover ? scrollActive : scrollThumb);
    }
  }

  @override
  bool get focusable => true;

  @override
  void down(double px, double py) {
    panel.focusWidget(this);
    if (px >= x + listWidth) {
      if (count <= rows) return;
      final (pos, size) = thumb();
      if (py >= pos && py < pos + size) {
        draggingThumb = true;
        thumbGrab = py - pos;
      } else {
        scrollTo(top + (py < pos ? -rows : rows));
      }
      invalidate();
      return;
    }
    final index = top + ((py - y) / lineHeight).floor();
    if (index >= 0 && index < count) choose(index);
  }

  @override
  void move(double px, double py, bool pressed) {
    if (draggingThumb) {
      final size = thumb().$2;
      final range = h - size;
      if (range > 0) {
        final fraction = ((py - thumbGrab - y) / range).clamp(0.0, 1.0);
        scrollTo((fraction * (count - rows)).round());
      }
      return;
    }
    final overThumb = px >= x + listWidth;
    final index = overThumb ? -1 : top + ((py - y) / lineHeight).floor();
    final newHovered = index >= 0 && index < count ? index : -1;
    if (newHovered != hovered || overThumb != thumbHover) {
      hovered = newHovered;
      thumbHover = overThumb;
      invalidate();
    }
  }

  @override
  void up(double px, double py) {
    if (draggingThumb) {
      draggingThumb = false;
      invalidate();
    }
  }

  @override
  void leave() {
    if (hovered != -1 || thumbHover) {
      hovered = -1;
      thumbHover = false;
      invalidate();
    }
  }

  @override
  bool wheel(int delta) {
    wheelRemainder += -delta * 3;
    final steps = (wheelRemainder / 120).truncate();
    if (steps != 0) {
      wheelRemainder -= steps * 120;
      scrollTo(top + steps);
    }
    return true;
  }

  void moveSelection(int delta) {
    if (count <= 0) return;
    choose(selected >= 0 ? selected + delta : (delta > 0 ? 0 : count - 1));
  }

  @override
  bool key(int vk) {
    switch (vk) {
      case VK_UP:
        moveSelection(-1);
      case VK_DOWN:
        moveSelection(1);
      case VK_PRIOR:
        moveSelection(-rows);
      case VK_NEXT:
        moveSelection(rows);
      case VK_HOME:
        moveSelection(-count);
      case VK_END:
        moveSelection(count);
      default:
        return false;
    }
    return true;
  }
}

const EM_EXLIMITTEXT = WM_USER + 53;
const EM_EXSETSEL = WM_USER + 55;
const EM_GETOLEINTERFACE = WM_USER + 60;
const EM_SETBKGNDCOLOR = WM_USER + 67;
const EM_SETCHARFORMAT = WM_USER + 68;
const EM_SETEVENTMASK = WM_USER + 69;
const EM_SETSEL = 0x00B1;
const EM_SETRECT = 0x00B3;
const EM_SCROLLCARET = 0x00B7;
const EM_GETLINECOUNT = 0x00BA;
const EM_LINEINDEX = 0x00BB;
const EM_REPLACESEL = 0x00C2;
const EM_EMPTYUNDOBUFFER = 0x00CD;
const EM_SETREADONLY = 0x00CF;
const EM_SETMARGINS = 0x00D3;
const ENM_CHANGE = 0x0001;
const ENM_KEYEVENTS = 0x00010000;
const EN_CHANGE = 0x0300;
const EN_MSGFILTER = 0x0700;
const SCF_SELECTION = 0x0001;
const SCF_ALL = 0x0004;
const CFM_COLOR = 0x40000000;
const CFM_FACE = 0x20000000;
const CFM_SIZE = 0x80000000;
const CFM_CHARSET = 0x08000000;
const CFM_BACKCOLOR = 0x04000000;
const CFM_BOLD = 0x00000001;
const WM_VSCROLL = 0x0115;
const SB_TOP = 6;
const SB_BOTTOM = 7;
const iidTextDocument = '{8CC497C0-A1DF-11CE-8098-00AA0047BE5D}';
const tomSuspend = -9999995;
const tomResume = -9999994;
const charFormatSize = 116;

class TextBox {
  final Panel panel;
  int hwnd = 0;
  final bool multiline;
  final bool readOnly;
  final String face;
  final double points;
  int background;
  int foreground;
  final int id;
  double x = 0, y = 0, w = 0, h = 0;
  bool visible = true;
  bool updating = false;
  void Function()? onChange;
  bool Function(int msg, int vk)? onKey;
  int textDocument = 0;
  final double padX;
  final double padY;

  TextBox(this.panel, this.id,
      {this.multiline = false,
      this.readOnly = false,
      bool center = false,
      this.face = monoFont,
      this.points = 9,
      this.background = fieldBg,
      this.foreground = white,
      this.padX = 4,
      this.padY = 3}) {
    var style = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | ES_NOHIDESEL;
    style |= multiline ? (ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL | ES_WANTRETURN) : ES_AUTOHSCROLL;
    if (readOnly) style |= ES_READONLY;
    if (center) style |= ES_CENTER;
    hwnd = scoped((a) => CreateWindowExW(
        0, wstr('RICHEDIT50W', a), wstr('', a), style, 0, 0, 10, 10, panel.hwnd, id, GetModuleHandleW(nullptr), nullptr));
    if (hwnd == 0) throw StateError('RichEdit could not be created');
    SendMessageW(hwnd, EM_EXLIMITTEXT, 0, 0x7FFFFFFE);
    SendMessageW(hwnd, EM_SETEVENTMASK, 0, ENM_CHANGE | ENM_KEYEVENTS);
    scoped((a) => SetWindowTheme(hwnd, wstr('DarkMode_Explorer', a), nullptr));
    final unknown = scoped((a) {
      final out = a<IntPtr>();
      SendMessagePtr(hwnd, EM_GETOLEINTERFACE, 0, out);
      return out.value;
    });
    if (unknown != 0) {
      textDocument = comQuery(unknown, iidTextDocument);
      comRelease(unknown);
    }
    applyColors();
    panel.textBoxes[hwnd] = this;
  }

  void applyColors() {
    SendMessageW(hwnd, EM_SETBKGNDCOLOR, 0, colorRef(background));
    setFormat(SCF_ALL, colorRef(foreground), null);
  }

  void setFormat(int scope, int? textColor, int? backColor, {bool includeFont = true}) {
    scoped((a) {
      final f = a<Uint8>(charFormatSize);
      final bytes = f.asTypedList(charFormatSize);
      var mask = 0;
      if (textColor != null) mask |= CFM_COLOR;
      if (backColor != null) mask |= CFM_BACKCOLOR;
      if (includeFont) mask |= CFM_FACE | CFM_SIZE | CFM_BOLD;
      void putU32(int offset, int value) {
        bytes[offset] = value & 0xFF;
        bytes[offset + 1] = (value >> 8) & 0xFF;
        bytes[offset + 2] = (value >> 16) & 0xFF;
        bytes[offset + 3] = (value >> 24) & 0xFF;
      }

      putU32(0, charFormatSize);
      putU32(4, mask);
      putU32(12, (points * 20).round());
      if (textColor != null) putU32(20, textColor);
      for (var i = 0; i < face.length && i < 31; i++) {
        bytes[26 + i * 2] = face.codeUnitAt(i) & 0xFF;
        bytes[27 + i * 2] = face.codeUnitAt(i) >> 8;
      }
      if (backColor != null) putU32(96, backColor);
      SendMessagePtr(hwnd, EM_SETCHARFORMAT, scope, f);
    });
  }

  void suspendUndo(bool suspend) {
    if (textDocument == 0) return;
    comMethod<Int32 Function(IntPtr, Int32, Pointer<Int32>)>(textDocument, 22)
        .asFunction<int Function(int, int, Pointer<Int32>)>()(textDocument, suspend ? tomSuspend : tomResume, nullptr);
  }

  void place(double nx, double ny, double nw, double nh) {
    x = nx;
    y = ny;
    w = nw < 0 ? 0 : nw;
    h = nh < 0 ? 0 : nh;
    final s = panel.scale;
    MoveWindow(hwnd, (x * s).round(), (y * s).round(), (w * s).round(), (h * s).round(), 1);
    scoped((a) {
      if (multiline) {
        final r = a<RECT>()
          ..ref.left = (padX * s).round()
          ..ref.top = (padY * s).round()
          ..ref.right = ((w - padX) * s).round()
          ..ref.bottom = ((h - padY) * s).round();
        SendMessagePtr(hwnd, EM_SETRECT, 0, r);
      } else {
        final line = pt(points) * 1.32 * s;
        final top = math.max(0, ((h * s - line) / 2).floor());
        final r = a<RECT>()
          ..ref.left = (padX * s).round()
          ..ref.top = top
          ..ref.right = ((w - padX) * s).round()
          ..ref.bottom = (h * s).round();
        SendMessagePtr(hwnd, EM_SETRECT, 0, r);
      }
    });
  }

  void show(bool value) {
    visible = value;
    ShowWindow(hwnd, value ? SW_SHOWNA : SW_HIDE);
  }

  String get text {
    final length = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0);
    if (length <= 0) return '';
    return scoped((a) {
      final buffer = a<Uint16>(length + 1);
      final got = SendMessagePtr(hwnd, WM_GETTEXT, length + 1, buffer);
      return String.fromCharCodes(buffer.asTypedList(got)).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    });
  }

  set text(String value) {
    updating = true;
    try {
      suspendUndo(true);
      SendMessageW(hwnd, EM_SETSEL, 0, -1);
      scoped((a) => SendMessagePtr(hwnd, EM_REPLACESEL, 0, wstr(value, a)));
      setFormat(SCF_ALL, colorRef(foreground), colorRef(background));
      SendMessageW(hwnd, EM_SETSEL, 0, 0);
      SendMessageW(hwnd, WM_VSCROLL, SB_TOP, 0);
      suspendUndo(false);
      SendMessageW(hwnd, EM_EMPTYUNDOBUFFER, 0, 0);
    } finally {
      updating = false;
    }
  }

  void append(String line, int limitLines) {
    updating = true;
    try {
      suspendUndo(true);
      final hasText = SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0) > 0;
      SendMessageW(hwnd, EM_SETSEL, -1, -1);
      scoped((a) => SendMessagePtr(hwnd, EM_REPLACESEL, 0, wstr(hasText ? '\r$line' : line, a)));
      final lines = SendMessageW(hwnd, EM_GETLINECOUNT, 0, 0);
      if (lines > limitLines) {
        final cut = SendMessageW(hwnd, EM_LINEINDEX, lines - limitLines, 0);
        if (cut > 0) {
          SendMessageW(hwnd, EM_SETSEL, 0, cut);
          scoped((a) => SendMessagePtr(hwnd, EM_REPLACESEL, 0, wstr('', a)));
        }
      }
      SendMessageW(hwnd, EM_SETSEL, -1, -1);
      SendMessageW(hwnd, WM_VSCROLL, SB_BOTTOM, 0);
      suspendUndo(false);
    } finally {
      updating = false;
    }
  }

  void selectRange(int start, int end) {
    scoped((a) {
      final range = a<Int32>(2);
      range[0] = start;
      range[1] = end;
      SendMessagePtr(hwnd, EM_EXSETSEL, 0, range);
    });
  }

  (int, int) selection() {
    return scoped((a) {
      final range = a<Int32>(2);
      SendMessagePtr(hwnd, WM_USER + 52, 0, range);
      return (range[0], range[1]);
    });
  }

  void highlight(List<(int, int)> ranges, int color) {
    updating = true;
    try {
      suspendUndo(true);
      final (start, end) = selection();
      SendMessageW(hwnd, WM_SETREDRAW, 0, 0);
      setFormat(SCF_ALL, null, colorRef(background), includeFont: false);
      for (final (from, to) in ranges) {
        selectRange(from, to);
        setFormat(SCF_SELECTION, null, colorRef(color), includeFont: false);
      }
      selectRange(start, end);
      SendMessageW(hwnd, WM_SETREDRAW, 1, 0);
      InvalidateRect(hwnd, nullptr, 1);
      suspendUndo(false);
    } finally {
      updating = false;
    }
  }

  void focus({bool selectAll = false}) {
    SetFocus(hwnd);
    if (selectAll) SendMessageW(hwnd, EM_SETSEL, 0, -1);
  }

  void dispose() {
    comRelease(textDocument);
    panel.textBoxes.remove(hwnd);
  }
}

const WM_SETREDRAW = 0x000B;

abstract class Panel extends BaseWindow {
  String title;
  double width, height;
  double offsetX, offsetY;
  final double minWidth, minHeight;
  final widgets = <Widget>[];
  final headerWidgets = <Widget>[];
  final textBoxes = <int, TextBox>{};
  Graphics? gfx;
  Widget? hovered;
  Widget? captured;
  Widget? focused;
  bool panelVisible = false;
  bool tracking = false;
  String dragMode = '';
  int dragStartX = 0, dragStartY = 0;
  double dragStartW = 0, dragStartH = 0;
  late final Button closeButton;
  (int, int) Function() originProvider;
  void Function() onClose;
  bool topmost = true;
  static const headerHeight = 28.0;
  static const footerHeight = 14.0;
  static const frameInset = 3.0;

  Panel(this.title, this.width, this.height, this.offsetX, this.offsetY, this.originProvider, this.onClose,
      {this.minWidth = 360, this.minHeight = 260}) {
    registerClasses();
    hwnd = scoped((a) => CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, wstr('AwanoPanel', a), wstr(title, a),
        WS_POPUP | WS_CLIPCHILDREN, 0, 0, 10, 10, 0, 0, GetModuleHandleW(nullptr), nullptr));
    dpi = GetDpiForWindow(hwnd).toDouble();
    windows[hwnd] = this;
    gfx = Graphics.forWindow(hwnd, dpi);
    closeButton = Button('X', () => onClose(), 0xFF4A4F57, 0xFF6B7380);
    addHeader(closeButton);
  }

  T add<T extends Widget>(T widget) {
    widget.panel = this;
    widgets.add(widget);
    return widget;
  }

  T addHeader<T extends Widget>(T widget) {
    widget.panel = this;
    headerWidgets.add(widget);
    return widget;
  }

  void invalidate() {
    if (hwnd != 0) InvalidateRect(hwnd, nullptr, 0);
  }

  (double, double, double, double) get bodyRect {
    const inset = frameInset + 1 + 2;
    return (inset, inset + headerHeight, width - inset * 2, height - inset * 2 - headerHeight - footerHeight);
  }

  void layoutHeader() {
    final right = width - frameInset - 1 - 2 - 6;
    closeButton.place(right - 26, frameInset + 1 + 2 + 4, 26, headerHeight - 8);
    var cursor = right - 26 - 2;
    for (final widget in headerWidgets) {
      if (widget == closeButton) continue;
      cursor -= widget.w;
      widget.place(cursor, frameInset + 1 + 2 + 4, widget.w, headerHeight - 8);
      cursor -= 2;
    }
  }

  void layoutBody(double x, double y, double w, double h);

  void layout() {
    layoutHeader();
    final (x, y, w, h) = bodyRect;
    layoutBody(x, y, w, h);
    invalidate();
  }

  void paintBody(Graphics g) {}

  void paint() {
    final g = gfx;
    if (g == null) return;
    g.begin();
    g.clear(panelFrame);
    g.fillRect(frameInset, frameInset, width - frameInset * 2, height - frameInset * 2, panelBg);
    g.strokeRect(frameInset, frameInset, width - frameInset * 2, height - frameInset * 2, panelOutline);
    const inner = frameInset + 1;
    g.fillRect(inner + 2, inner + 2, width - (inner + 2) * 2, headerHeight, headerBg);
    g.text(title, inner + 2 + 8, inner + 2, width - 200, headerHeight, titleStyle, white);
    paintBody(g);
    for (final widget in [...headerWidgets, ...widgets]) {
      if (widget.visible) widget.paint(g);
    }
    final gx = width - inner - 2 - 13;
    final gy = height - inner - 2 - 12;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j <= i; j++) {
        g.fillRect(gx + 8 - j * 4, gy + i * 4, 2, 2, scrollActive);
      }
    }
    g.end();
  }

  void applyGeometry([(int, int)? origin]) {
    final (ox, oy) = origin ?? originProvider();
    SetWindowPos(hwnd, 0, ox + (offsetX * scale).round(), oy + (offsetY * scale).round(), (width * scale).round(),
        (height * scale).round(), SWP_NOZORDER | SWP_NOACTIVATE);
  }

  void keepOnScreen() {
    final (ox, oy) = originProvider();
    scoped((a) {
      final info = a<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
      GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), info);
      final work = info.ref.rcWork;
      final px = ox + (offsetX * scale).round();
      final py = oy + (offsetY * scale).round();
      final pw = (width * scale).round();
      final ph = (height * scale).round();
      if (px < work.left || px >= work.right || py < work.top || py >= work.bottom) return;
      final nx = math.max(work.left, math.min(px, work.right - pw));
      final ny = math.max(work.top, math.min(py, work.bottom - ph));
      offsetX = (nx - ox) / scale;
      offsetY = (ny - oy) / scale;
    });
  }

  void fitToScreen() {
    scoped((a) {
      final info = a<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
      GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), info);
      final work = info.ref.rcWork;
      width = math.max(minWidth, math.min(width, (work.right - work.left) / scale - 48));
      height = math.max(minHeight, math.min(height, (work.bottom - work.top) / scale - 48));
    });
  }

  void show() {
    if (!panelVisible) {
      keepOnScreen();
      applyGeometry();
      ShowWindow(hwnd, SW_SHOW);
      panelVisible = true;
      layout();
    }
    SetWindowPos(hwnd, topmost ? HWND_TOPMOST : HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    SetForegroundWindow(hwnd);
  }

  void hide() {
    if (panelVisible) {
      ShowWindow(hwnd, SW_HIDE);
      panelVisible = false;
    }
  }

  void setTopmost(bool value) {
    topmost = value;
    SetWindowPos(hwnd, value ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  void focusWidget(Widget? widget) {
    focused = widget;
    if (GetFocus() != hwnd) SetFocus(hwnd);
  }

  Widget? hit(double px, double py) {
    for (final widget in [...widgets.reversed, ...headerWidgets]) {
      if (widget.contains(px, py)) return widget;
    }
    return null;
  }

  bool inGrip(double px, double py) => px >= width - 20 && py >= height - 18;
  bool inHeader(double px, double py) => py >= frameInset && py < frameInset + 3 + headerHeight;

  bool panelKey(int vk) => false;
  bool textBoxKey(TextBox box, int msg, int vk) => false;
  void textBoxChanged(TextBox box) {}
  void timer(int id) {}

  @override
  int? handle(int msg, int wParam, int lParam) {
    switch (msg) {
      case WM_PAINT:
        paint();
        ValidateRect(hwnd, nullptr);
        return 0;
      case WM_ERASEBKGND:
        return 1;
      case WM_SIZE:
        gfx?.resize(lowWord(lParam), highWord(lParam));
        width = lowWord(lParam) / scale;
        height = highWord(lParam) / scale;
        layout();
        return 0;
      case WM_DPICHANGED:
        dpi = lowWord(wParam).toDouble();
        gfx?.changeDpi(dpi);
        applyGeometry();
        return 0;
      case WM_SETCURSOR:
        if (wParam != hwnd || lowWord(lParam) != HTCLIENT) return null;
        final p = cursorPoint();
        var cursor = IDC_ARROW;
        if (captured != null) {
          cursor = captured!.cursor;
        } else if (dragMode == 'resize' || inGrip(p.$1, p.$2)) {
          cursor = IDC_SIZENWSE;
        } else {
          cursor = hit(p.$1, p.$2)?.cursor ?? IDC_ARROW;
        }
        SetCursor(LoadCursorW(0, cursor));
        return 1;
      case WM_LBUTTONDOWN:
        final px = signedLow(lParam) / scale;
        final py = signedHigh(lParam) / scale;
        SetCapture(hwnd);
        final widget = hit(px, py);
        if (widget != null) {
          captured = widget;
          if (!widget.focusable && GetFocus() != hwnd && !textBoxes.containsKey(GetFocus())) SetFocus(hwnd);
          widget.down(px, py);
        } else if (inGrip(px, py)) {
          beginDrag('resize');
        } else if (inHeader(px, py)) {
          beginDrag('move');
        } else {
          SetFocus(hwnd);
        }
        return 0;
      case WM_MOUSEMOVE:
        final px = signedLow(lParam) / scale;
        final py = signedHigh(lParam) / scale;
        if (!tracking) {
          scoped((a) {
            final tme = a<TRACKMOUSEEVENT>()
              ..ref.cbSize = sizeOf<TRACKMOUSEEVENT>()
              ..ref.dwFlags = TME_LEAVE
              ..ref.hwndTrack = hwnd;
            TrackMouseEvent(tme);
          });
          tracking = true;
        }
        if (dragMode.isNotEmpty) {
          continueDrag();
          return 0;
        }
        if (captured != null) {
          captured!.move(px, py, true);
          return 0;
        }
        final widget = hit(px, py);
        if (widget != hovered) {
          hovered?.leave();
          hovered = widget;
        }
        widget?.move(px, py, false);
        return 0;
      case WM_LBUTTONUP:
        final px = signedLow(lParam) / scale;
        final py = signedHigh(lParam) / scale;
        final widget = captured;
        captured = null;
        dragMode = '';
        ReleaseCapture();
        widget?.up(px, py);
        return 0;
      case WM_CAPTURECHANGED:
        if (lParam != hwnd) {
          dragMode = '';
          captured = null;
        }
        return 0;
      case WM_MOUSELEAVE:
        tracking = false;
        hovered?.leave();
        hovered = null;
        return 0;
      case WM_MOUSEWHEEL:
        final pts = scoped((a) {
          final p = a<POINT>()
            ..ref.x = signedLow(lParam)
            ..ref.y = signedHigh(lParam);
          ScreenToClient(hwnd, p);
          return (p.ref.x / scale, p.ref.y / scale);
        });
        hit(pts.$1, pts.$2)?.wheel(signedHigh(wParam));
        return 0;
      case WM_KEYDOWN:
        if (panelKey(wParam)) return 0;
        if (focused != null && focused!.key(wParam)) return 0;
        return null;
      case WM_COMMAND:
        if (highWord(wParam) == EN_CHANGE) {
          final box = textBoxes[lParam];
          if (box != null && !box.updating) textBoxChanged(box);
          return 0;
        }
        return null;
      case WM_NOTIFY:
        final header = Pointer<NMHDR>.fromAddress(lParam).ref;
        if (header.code == EN_MSGFILTER) {
          final filter = Pointer<MSGFILTER>.fromAddress(lParam).ref;
          final box = textBoxes[header.hwndFrom];
          if (box != null && (filter.msg == WM_KEYDOWN || filter.msg == WM_CHAR)) {
            return textBoxKey(box, filter.msg, filter.wParam) ? 1 : 0;
          }
          return 0;
        }
        return null;
      case WM_TIMER:
        timer(wParam);
        return 0;
      case WM_CLOSE:
        onClose();
        return 0;
    }
    return null;
  }

  (double, double) cursorPoint() {
    return scoped((a) {
      final p = a<POINT>();
      GetCursorPos(p);
      ScreenToClient(hwnd, p);
      return (p.ref.x / scale, p.ref.y / scale);
    });
  }

  void beginDrag(String mode) {
    dragMode = mode;
    scoped((a) {
      final p = a<POINT>();
      GetCursorPos(p);
      dragStartX = p.ref.x;
      dragStartY = p.ref.y;
    });
    dragStartW = width;
    dragStartH = height;
  }

  void continueDrag() {
    final (cx, cy) = scoped((a) {
      final p = a<POINT>();
      GetCursorPos(p);
      return (p.ref.x, p.ref.y);
    });
    if (dragMode == 'move') {
      offsetX += (cx - dragStartX) / scale;
      offsetY += (cy - dragStartY) / scale;
      dragStartX = cx;
      dragStartY = cy;
      applyGeometry();
    } else if (dragMode == 'resize') {
      width = math.max(minWidth, dragStartW + (cx - dragStartX) / scale);
      height = math.max(minHeight, dragStartH + (cy - dragStartY) / scale);
      applyGeometry();
    }
  }
}
