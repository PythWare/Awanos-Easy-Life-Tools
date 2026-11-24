import 'dart:ffi'; import 'dart:math' as math;
import 'd2d.dart'; import 'native.dart'; import 'ui.dart'; import 'win.dart';

const launcherWidth = 900.0;
const launcherHeight = 460.0;
const inactive = 0xFF444444;
const stripBg = 0xFF555555;
const stripItem = 0xFF666666;
const subStripBg = 0xFFFFFFFF;
const subStripItem = 0xFFDDDDDD;

class HitTarget {
  final String kind;
  final String name;
  final double x, y, w, h;
  final bool circle;
  HitTarget(this.kind, this.name, this.x, this.y, this.w, this.h, {this.circle = false});

  bool contains(double px, double py) {
    if (circle) {
      final dx = px - x, dy = py - y;
      return dx * dx + dy * dy <= w * w;
    }
    return px >= x && px <= x + w && py >= y && py <= y + h;
  }
}

class LauncherWindow extends BaseWindow {
  final String title;
  final List<String> mainButtons;
  final Map<String, List<String>> subOptions;
  final Map<String, List<String>> subSubOptions;
  String? main;
  String? sub;
  final void Function(String kind, String name) onClick;
  final void Function() onEscape;
  final void Function() onToggleTopmost;
  final void Function(int dx, int dy) onMoved;
  late Graphics gfx;
  int memDc = 0, dib = 0, oldBitmap = 0;
  int pixelWidth = 0, pixelHeight = 0;
  int x = 300, y = 200;
  final targets = <HitTarget>[];
  String hoverKey = '';
  String pressKey = '';
  final hoverLevels = <String, double>{};
  bool dragging = false;
  int dragX = 0, dragY = 0;
  bool tracking = false;
  bool timerOn = false;
  final clock = Stopwatch()..start();
  double lastTick = 0;
  double reveal = 1;
  bool topmost = true;

  LauncherWindow(this.title, this.mainButtons, this.subOptions, this.subSubOptions, this.onClick, this.onEscape,
      this.onToggleTopmost, this.onMoved) {
    registerClasses();
    hwnd = scoped((a) => CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_APPWINDOW, wstr('AwanoLauncher', a),
        wstr(title, a), WS_POPUP | WS_SYSMENU | WS_MINIMIZEBOX, x, y, 10, 10, 0, 0, GetModuleHandleW(nullptr), nullptr));
    dpi = GetDpiForWindow(hwnd).toDouble();
    windows[hwnd] = this;
    gfx = Graphics.forLayered(dpi);
    createSurface();
  }

  void createSurface() {
    if (memDc != 0) {
      SelectObject(memDc, oldBitmap);
      DeleteObject(dib);
      DeleteDC(memDc);
    }
    pixelWidth = (launcherWidth * scale).round();
    pixelHeight = (launcherHeight * scale).round();
    scoped((a) {
      final bi = a<BITMAPINFOHEADER>()
        ..ref.biSize = sizeOf<BITMAPINFOHEADER>()
        ..ref.biWidth = pixelWidth
        ..ref.biHeight = -pixelHeight
        ..ref.biPlanes = 1
        ..ref.biBitCount = 32;
      final bits = a<Pointer<Uint8>>();
      memDc = CreateCompatibleDC(0);
      dib = CreateDIBSection(memDc, bi, 0, bits, 0, 0);
      oldBitmap = SelectObject(memDc, dib);
    });
  }

  int makeIcon(int size) {
    return scoped((a) {
      final bi = a<BITMAPINFOHEADER>()
        ..ref.biSize = sizeOf<BITMAPINFOHEADER>()
        ..ref.biWidth = size
        ..ref.biHeight = -size
        ..ref.biPlanes = 1
        ..ref.biBitCount = 32;
      final bits = a<Pointer<Uint8>>();
      final dc = CreateCompatibleDC(0);
      final color = CreateDIBSection(dc, bi, 0, bits, 0, 0);
      final old = SelectObject(dc, color);
      final g = Graphics.forLayered(96);
      g.bindDc(dc, size, size);
      g.begin();
      g.clear(0x00000000);
      final s = size / 32;
      g.fillRounded(1 * s, 1 * s, 30 * s, 30 * s, 7 * s, 0xFF0F141B);
      g.strokeRounded(1 * s, 1 * s, 30 * s, 30 * s, 7 * s, lilac, 1.5 * s);
      g.text('A', 0, 0, 32 * s, 32 * s, TextStyle(uiFont, 21 * s, weight: weightBold, align: alignCenter), lilac);
      g.end();
      g.dispose();
      SelectObject(dc, old);
      DeleteDC(dc);
      final mask = CreateBitmap(size, size, 1, 1, nullptr);
      final info = a<ICONINFO>()
        ..ref.fIcon = 1
        ..ref.hbmMask = mask
        ..ref.hbmColor = color;
      final icon = CreateIconIndirect(info);
      DeleteObject(mask);
      DeleteObject(color);
      return icon;
    });
  }

  void show() {
    SendMessageW(hwnd, WM_SETICON, 1, makeIcon(64));
    SendMessageW(hwnd, WM_SETICON, 0, makeIcon(32));
    render();
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
  }

  double level(String key) => hoverLevels[key] ?? 0;

  void kick() {
    if (!timerOn) {
      lastTick = clock.elapsedMicroseconds / 1e6;
      SetTimer(hwnd, 1, 15, nullptr);
      timerOn = true;
    }
  }

  void tick() {
    final now = clock.elapsedMicroseconds / 1e6;
    final dt = (now - lastTick).clamp(0.0, 0.1);
    lastTick = now;
    var animating = false;
    final keys = {...hoverLevels.keys, if (hoverKey.isNotEmpty) hoverKey};
    for (final key in keys) {
      final target = key == hoverKey ? 1.0 : 0.0;
      final current = hoverLevels[key] ?? 0;
      var next = current + (target - current) * (1 - math.exp(-dt * 18));
      if ((next - target).abs() < 0.01) next = target;
      if (next == 0) {
        hoverLevels.remove(key);
      } else {
        hoverLevels[key] = next;
      }
      if (next != target) animating = true;
    }
    if (reveal < 1) {
      reveal = math.min(1, reveal + dt * 7);
      animating = true;
    }
    render();
    if (!animating) {
      KillTimer(hwnd, 1);
      timerOn = false;
    }
  }

  void stateChanged() {
    reveal = 0;
    kick();
  }

  void render() {
    targets.clear();
    gfx.bindDc(memDc, pixelWidth, pixelHeight);
    gfx.begin();
    gfx.clear(0x00000000);
    drawTitle();
    drawMain();
    drawStrip();
    drawSubStrip();
    gfx.end();
    present();
  }

  void present() {
    scoped((a) {
      final size = a<SIZE>()
        ..ref.cx = pixelWidth
        ..ref.cy = pixelHeight;
      final src = a<POINT>();
      final dst = a<POINT>()
        ..ref.x = x
        ..ref.y = y;
      final blend = a<Uint32>()..value = (255 << 16) | (1 << 24);
      final screen = GetDC(0);
      UpdateLayeredWindow(hwnd, screen, dst, size, memDc, src, 0, blend, ULW_ALPHA);
      ReleaseDC(0, screen);
    });
  }

  void shadow(double x, double y, double w, double h, double radius) {
    for (var i = 1; i <= 6; i++) {
      gfx.fillRounded(x - i + 3, y - i + 5, w + i * 2 - 6, h + i * 2 - 6, radius + i, withAlpha(black, 0.05));
    }
  }

  void drawTitle() {
    final style = TextStyle(uiFont, pt(14), weight: weightBold, align: alignCenter);
    gfx.text(title, 1.5, 11.5, launcherWidth, 30, style, withAlpha(black, 0.55));
    gfx.text(title, 0, 10, launcherWidth, 30, style, lilac);
  }

  void drawMain() {
    final letter = TextStyle(uiFont, pt(12), weight: weightBold, align: alignCenter);
    for (var i = 0; i < mainButtons.length; i++) {
      final name = mainButtons[i];
      final cx = 60.0, cy = 120.0 + i * 100, radius = 30.0;
      final selected = main == name;
      final key = 'main:$name';
      final hover = level(key);
      gfx.fillCircle(cx + 1.5, cy + 3, radius + 1, withAlpha(black, 0.35));
      final base = selected ? accent : mixColor(inactive, 0xFF5A5A5A, hover);
      gfx.fillCircle(cx, cy, radius * (1 + 0.04 * hover), base);
      gfx.strokeCircle(cx, cy, radius * (1 + 0.04 * hover) - 0.5, withAlpha(white, selected ? 0.35 : 0.12 + 0.2 * hover));
      gfx.text(name[0], cx - radius, cy - radius, radius * 2, radius * 2, letter, selected ? 0xFF1A1A1A : white);
      targets.add(HitTarget('main', name, cx, cy, radius, radius, circle: true));
    }
  }

  void drawStrip() {
    final current = main;
    if (current == null) return;
    final items = subOptions[current]!;
    const baseX = 140.0, baseY = 100.0;
    final alpha = Curves.easeOut(reveal);
    final slide = (1 - alpha) * -12;
    final bgH = items.length * 60.0 + 10;
    shadow(baseX - 10 + slide, baseY - 10, 200, bgH, 10);
    gfx.fillRounded(baseX - 10 + slide, baseY - 10, 200, bgH, 10, withAlpha(stripBg, alpha));
    final style = TextStyle(uiFont, pt(9.5), weight: weightSemiBold, align: alignCenter);
    for (var i = 0; i < items.length; i++) {
      final text = items[i];
      final y = baseY + i * 60;
      final selected = sub == text;
      final key = 'sub:$text';
      final hover = level(key);
      final fill = selected ? accent : mixColor(stripItem, 0xFF7A7A7A, hover);
      gfx.fillRounded(baseX + slide, y, 180, 50, 7, withAlpha(fill, alpha));
      gfx.text(text, baseX + slide, y, 180, 50, style, withAlpha(selected ? 0xFF1A1A1A : white, alpha));
      targets.add(HitTarget('sub', text, baseX, y, 180, 50));
    }
  }

  void drawSubStrip() {
    final current = sub;
    if (current == null) return;
    final items = subSubOptions[current] ?? const [];
    if (items.isEmpty) return;
    const baseX = 340.0, baseY = 100.0;
    final alpha = Curves.easeOut(reveal);
    final slide = (1 - alpha) * -12;
    final bgH = items.length * 60.0 + 10;
    shadow(baseX - 10 + slide, baseY - 10, 200, bgH, 10);
    gfx.fillRounded(baseX - 10 + slide, baseY - 10, 200, bgH, 10, withAlpha(subStripBg, alpha));
    final style = TextStyle(uiFont, pt(9.5), weight: weightSemiBold, align: alignCenter);
    for (var i = 0; i < items.length; i++) {
      final text = items[i];
      final y = baseY + i * 60;
      final key = 'subsub:$text';
      final hover = level(key);
      var fill = mixColor(subStripItem, 0xFFC8C8C8, hover);
      if (pressKey == key) fill = 0xFFB4B4B4;
      gfx.fillRounded(baseX + slide, y, 180, 50, 7, withAlpha(fill, alpha));
      gfx.text(text, baseX + slide, y, 180, 50, style, withAlpha(black, alpha));
      targets.add(HitTarget('subsub', text, baseX, y, 180, 50));
    }
  }

  HitTarget? targetAt(double px, double py) {
    for (final target in targets) {
      if (target.contains(px, py)) return target;
    }
    return null;
  }

  (int, int) get origin => (x, y);

  void moveBy(int dx, int dy) {
    x += dx;
    y += dy;
    SetWindowPos(hwnd, 0, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    onMoved(dx, dy);
  }

  void setTopmost(bool value) {
    topmost = value;
    SetWindowPos(hwnd, value ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  (int, int) cursor() => scoped((a) {
        final p = a<POINT>();
        GetCursorPos(p);
        return (p.ref.x, p.ref.y);
      });

  @override
  int? handle(int msg, int wParam, int lParam) {
    switch (msg) {
      case WM_NCHITTEST:
        return HTCLIENT;
      case WM_SETCURSOR:
        if (lowWord(lParam) != HTCLIENT) return null;
        final p = scoped((a) {
          final pt = a<POINT>();
          GetCursorPos(pt);
          return ((pt.ref.x - x) / scale, (pt.ref.y - y) / scale);
        });
        SetCursor(LoadCursorW(0, dragging ? IDC_SIZEALL : (targetAt(p.$1, p.$2) != null ? IDC_HAND : IDC_ARROW)));
        return 1;
      case WM_MOUSEMOVE:
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
        if (dragging) {
          final (cx, cy) = cursor();
          final dx = cx - dragX, dy = cy - dragY;
          dragX = cx;
          dragY = cy;
          if (dx != 0 || dy != 0) moveBy(dx, dy);
          return 0;
        }
        final target = targetAt(signedLow(lParam) / scale, signedHigh(lParam) / scale);
        final key = target == null ? '' : '${target.kind}:${target.name}';
        if (key != hoverKey) {
          hoverKey = key;
          kick();
        }
        return 0;
      case WM_MOUSELEAVE:
        tracking = false;
        if (hoverKey.isNotEmpty) {
          hoverKey = '';
          kick();
        }
        return 0;
      case WM_LBUTTONDOWN:
        final px = signedLow(lParam) / scale, py = signedHigh(lParam) / scale;
        final target = targetAt(px, py);
        if (target == null) {
          if (py < 50) startDrag();
          return 0;
        }
        if (target.kind == 'subsub') {
          pressKey = 'subsub:${target.name}';
          render();
          SetCapture(hwnd);
        }
        onClick(target.kind, target.name);
        return 0;
      case WM_LBUTTONUP:
        if (dragging) {
          dragging = false;
          ReleaseCapture();
        }
        if (pressKey.isNotEmpty) {
          pressKey = '';
          ReleaseCapture();
          render();
        }
        return 0;
      case WM_RBUTTONDOWN:
        startDrag();
        return 0;
      case WM_RBUTTONUP:
        if (dragging) {
          dragging = false;
          ReleaseCapture();
        }
        return 0;
      case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) onEscape();
        if (wParam == VK_F1) onToggleTopmost();
        return 0;
      case WM_TIMER:
        tick();
        return 0;
      case WM_DPICHANGED:
        dpi = lowWord(wParam).toDouble();
        gfx.dispose();
        gfx = Graphics.forLayered(dpi);
        createSurface();
        render();
        return 0;
      case WM_CLOSE:
        onEscape();
        return 0;
      case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return null;
  }

  void startDrag() {
    dragging = true;
    final (cx, cy) = cursor();
    dragX = cx;
    dragY = cy;
    SetCapture(hwnd);
  }
}

class Curves {
  static double easeOut(double t) => 1 - math.pow(1 - t.clamp(0.0, 1.0), 3).toDouble();
}
