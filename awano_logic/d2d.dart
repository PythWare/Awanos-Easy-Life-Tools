import 'dart:ffi';
import 'native.dart'; import 'win.dart';

final d2d1 = DynamicLibrary.open('d2d1.dll');
final dwrite = DynamicLibrary.open('dwrite.dll');

final class ColorF extends Struct {
  @Float()
  external double r;
  @Float()
  external double g;
  @Float()
  external double b;
  @Float()
  external double a;
}

final class RectF extends Struct {
  @Float()
  external double left;
  @Float()
  external double top;
  @Float()
  external double right;
  @Float()
  external double bottom;
}

final class RoundedRectF extends Struct {
  external RectF rect;
  @Float()
  external double radiusX;
  @Float()
  external double radiusY;
}

final class PointF extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class EllipseF extends Struct {
  external PointF point;
  @Float()
  external double radiusX;
  @Float()
  external double radiusY;
}

final class RenderTargetProps extends Struct {
  @Int32()
  external int type;
  @Int32()
  external int format;
  @Int32()
  external int alphaMode;
  @Float()
  external double dpiX;
  @Float()
  external double dpiY;
  @Int32()
  external int usage;
  @Int32()
  external int minLevel;
}

final class HwndTargetProps extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Int32()
  external int presentOptions;
}

final class SizeU extends Struct {
  @Uint32()
  external int width;
  @Uint32()
  external int height;
}

final class TextMetrics extends Struct {
  @Float()
  external double left;
  @Float()
  external double top;
  @Float()
  external double width;
  @Float()
  external double widthIncludingTrailingWhitespace;
  @Float()
  external double height;
  @Float()
  external double layoutWidth;
  @Float()
  external double layoutHeight;
  @Uint32()
  external int maxBidiReorderingDepth;
  @Uint32()
  external int lineCount;
}

final class Trimming extends Struct {
  @Int32()
  external int granularity;
  @Uint32()
  external int delimiter;
  @Uint32()
  external int delimiterCount;
}

const iidD2DFactory = '{06152247-6f50-465a-9245-118bfd3b6007}';
const iidDWriteFactory = '{b859ee5a-d838-4b5b-a2e8-1adc7d93db48}';
const recreateTarget = 0x8899000C;

final D2D1CreateFactory = d2d1.lookupFunction<Int32 Function(Int32, Pointer<GUID>, Pointer, Pointer<IntPtr>),
    int Function(int, Pointer<GUID>, Pointer, Pointer<IntPtr>)>('D2D1CreateFactory');
final DWriteCreateFactory = dwrite.lookupFunction<Int32 Function(Int32, Pointer<GUID>, Pointer<IntPtr>),
    int Function(int, Pointer<GUID>, Pointer<IntPtr>)>('DWriteCreateFactory');

const weightNormal = 400;
const weightSemiBold = 600;
const weightBold = 700;
const alignLeading = 0;
const alignTrailing = 1;
const alignCenter = 2;
const vAlignNear = 0;
const vAlignFar = 1;
const vAlignCenter = 2;

class TextStyle {
  final String family;
  final double size;
  final int weight;
  final int align;
  final int vAlign;
  final bool wrap;
  const TextStyle(this.family, this.size,
      {this.weight = weightNormal, this.align = alignLeading, this.vAlign = vAlignCenter, this.wrap = false});

  TextStyle copy({int? weight, int? align, int? vAlign, bool? wrap, double? size}) => TextStyle(family, size ?? this.size,
      weight: weight ?? this.weight, align: align ?? this.align, vAlign: vAlign ?? this.vAlign, wrap: wrap ?? this.wrap);

  String get key => '$family|$size|$weight|$align|$vAlign|$wrap';
}

class Direct2D {
  static int factory = 0;
  static int writeFactory = 0;
  static final formats = <String, int>{};

  static void start() {
    if (factory != 0) return;
    scoped((a) {
      final out = a<IntPtr>();
      if (D2D1CreateFactory(0, guid(iidD2DFactory, a), nullptr, out) != 0) throw StateError('Direct2D is unavailable');
      factory = out.value;
      if (DWriteCreateFactory(0, guid(iidDWriteFactory, a), out) != 0) throw StateError('DirectWrite is unavailable');
      writeFactory = out.value;
    });
  }

  static final createTextFormat = comMethod<
          Int32 Function(IntPtr, Pointer<Uint16>, IntPtr, Int32, Int32, Int32, Float, Pointer<Uint16>, Pointer<IntPtr>)>(
      writeFactory, 15)
      .asFunction<int Function(int, Pointer<Uint16>, int, int, int, int, double, Pointer<Uint16>, Pointer<IntPtr>)>();
  static final createTextLayout =
      comMethod<Int32 Function(IntPtr, Pointer<Uint16>, Uint32, IntPtr, Float, Float, Pointer<IntPtr>)>(writeFactory, 18)
          .asFunction<int Function(int, Pointer<Uint16>, int, int, double, double, Pointer<IntPtr>)>();

  static int format(TextStyle style) {
    final cached = formats[style.key];
    if (cached != null) return cached;
    return scoped((a) {
      final out = a<IntPtr>();
      final hr = createTextFormat(writeFactory, wstr(style.family, a), 0, style.weight, 0, 5, style.size, wstr('en-us', a), out);
      if (hr != 0) throw StateError('CreateTextFormat failed 0x${(hr & 0xFFFFFFFF).toRadixString(16)}');
      final f = out.value;
      comMethod<Int32 Function(IntPtr, Int32)>(f, 3).asFunction<int Function(int, int)>()(f, style.align);
      comMethod<Int32 Function(IntPtr, Int32)>(f, 4).asFunction<int Function(int, int)>()(f, style.vAlign);
      comMethod<Int32 Function(IntPtr, Int32)>(f, 5).asFunction<int Function(int, int)>()(f, style.wrap ? 0 : 1);
      if (!style.wrap) {
        final trimming = a<Trimming>()..ref.granularity = 1;
        comMethod<Int32 Function(IntPtr, Pointer<Trimming>, IntPtr)>(f, 9)
            .asFunction<int Function(int, Pointer<Trimming>, int)>()(f, trimming, 0);
      }
      formats[style.key] = f;
      return f;
    });
  }

  static (double, double) measure(String text, TextStyle style, [double maxWidth = 100000, double maxHeight = 100000]) {
    if (text.isEmpty) return (0, style.size * 1.33);
    return scoped((a) {
      final out = a<IntPtr>();
      if (createTextLayout(writeFactory, wstr(text, a), text.length, format(style), maxWidth, maxHeight, out) != 0) {
        return (0.0, style.size * 1.33);
      }
      final metrics = a<TextMetrics>();
      comMethod<Int32 Function(IntPtr, Pointer<TextMetrics>)>(out.value, 60)
          .asFunction<int Function(int, Pointer<TextMetrics>)>()(out.value, metrics);
      comRelease(out.value);
      return (metrics.ref.widthIncludingTrailingWhitespace, metrics.ref.height);
    });
  }
}

class Graphics {
  int target = 0;
  int brush = 0;
  final bool layered;
  final int hwnd;
  double dpi;
  final rect = heap<RectF>();
  final rounded = heap<RoundedRectF>();
  final ellipse = heap<EllipseF>();
  final color = heap<ColorF>();
  final pointA = heap<PointF>();
  final pointB = heap<PointF>();
  final clipStack = <int>[];

  Graphics.forWindow(this.hwnd, this.dpi) : layered = false {
    Direct2D.start();
    createHwndTarget();
  }

  Graphics.forLayered(this.dpi)
      : layered = true,
        hwnd = 0 {
    Direct2D.start();
    scoped((a) {
      final props = a<RenderTargetProps>()
        ..ref.type = 0
        ..ref.format = 87
        ..ref.alphaMode = 1
        ..ref.dpiX = dpi
        ..ref.dpiY = dpi
        ..ref.usage = 0
        ..ref.minLevel = 0;
      final out = a<IntPtr>();
      final hr = comMethod<Int32 Function(IntPtr, Pointer<RenderTargetProps>, Pointer<IntPtr>)>(Direct2D.factory, 16)
          .asFunction<int Function(int, Pointer<RenderTargetProps>, Pointer<IntPtr>)>()(Direct2D.factory, props, out);
      if (hr != 0) throw StateError('CreateDCRenderTarget failed 0x${(hr & 0xFFFFFFFF).toRadixString(16)}');
      target = out.value;
      afterTarget();
      comMethod<Void Function(IntPtr, Int32)>(target, 34).asFunction<void Function(int, int)>()(target, 2);
    });
  }

  void createHwndTarget() {
    scoped((a) {
      final client = a<RECT>();
      GetClientRect(hwnd, client);
      final props = a<RenderTargetProps>()
        ..ref.type = 0
        ..ref.format = 0
        ..ref.alphaMode = 0
        ..ref.dpiX = dpi
        ..ref.dpiY = dpi;
      final hprops = a<HwndTargetProps>()
        ..ref.hwnd = hwnd
        ..ref.width = client.ref.right > 0 ? client.ref.right : 1
        ..ref.height = client.ref.bottom > 0 ? client.ref.bottom : 1
        ..ref.presentOptions = 0;
      final out = a<IntPtr>();
      final hr = comMethod<Int32 Function(IntPtr, Pointer<RenderTargetProps>, Pointer<HwndTargetProps>, Pointer<IntPtr>)>(
              Direct2D.factory, 14)
          .asFunction<int Function(int, Pointer<RenderTargetProps>, Pointer<HwndTargetProps>, Pointer<IntPtr>)>()(
          Direct2D.factory, props, hprops, out);
      if (hr != 0) throw StateError('CreateHwndRenderTarget failed 0x${(hr & 0xFFFFFFFF).toRadixString(16)}');
      target = out.value;
      afterTarget();
    });
  }

  void afterTarget() {
    scoped((a) {
      setColor(0xFFFFFFFF);
      final out = a<IntPtr>();
      createBrush(target, color, nullptr, out);
      brush = out.value;
    });
  }

  late final createBrush = comMethod<Int32 Function(IntPtr, Pointer<ColorF>, Pointer, Pointer<IntPtr>)>(target, 8)
      .asFunction<int Function(int, Pointer<ColorF>, Pointer, Pointer<IntPtr>)>();
  late final drawLineFn = comMethod<Void Function(IntPtr, PointF, PointF, IntPtr, Float, IntPtr)>(target, 15)
      .asFunction<void Function(int, PointF, PointF, int, double, int)>();
  late final drawRectFn = comMethod<Void Function(IntPtr, Pointer<RectF>, IntPtr, Float, IntPtr)>(target, 16)
      .asFunction<void Function(int, Pointer<RectF>, int, double, int)>();
  late final fillRectFn = comMethod<Void Function(IntPtr, Pointer<RectF>, IntPtr)>(target, 17)
      .asFunction<void Function(int, Pointer<RectF>, int)>();
  late final drawRoundedFn = comMethod<Void Function(IntPtr, Pointer<RoundedRectF>, IntPtr, Float, IntPtr)>(target, 18)
      .asFunction<void Function(int, Pointer<RoundedRectF>, int, double, int)>();
  late final fillRoundedFn = comMethod<Void Function(IntPtr, Pointer<RoundedRectF>, IntPtr)>(target, 19)
      .asFunction<void Function(int, Pointer<RoundedRectF>, int)>();
  late final drawEllipseFn = comMethod<Void Function(IntPtr, Pointer<EllipseF>, IntPtr, Float, IntPtr)>(target, 20)
      .asFunction<void Function(int, Pointer<EllipseF>, int, double, int)>();
  late final fillEllipseFn = comMethod<Void Function(IntPtr, Pointer<EllipseF>, IntPtr)>(target, 21)
      .asFunction<void Function(int, Pointer<EllipseF>, int)>();
  late final drawTextFn =
      comMethod<Void Function(IntPtr, Pointer<Uint16>, Uint32, IntPtr, Pointer<RectF>, IntPtr, Int32, Int32)>(target, 27)
          .asFunction<void Function(int, Pointer<Uint16>, int, int, Pointer<RectF>, int, int, int)>();
  late final pushClipFn = comMethod<Void Function(IntPtr, Pointer<RectF>, Int32)>(target, 45)
      .asFunction<void Function(int, Pointer<RectF>, int)>();
  late final popClipFn = comMethod<Void Function(IntPtr)>(target, 46).asFunction<void Function(int)>();
  late final clearFn = comMethod<Void Function(IntPtr, Pointer<ColorF>)>(target, 47)
      .asFunction<void Function(int, Pointer<ColorF>)>();
  late final beginDrawFn = comMethod<Void Function(IntPtr)>(target, 48).asFunction<void Function(int)>();
  late final endDrawFn = comMethod<Int32 Function(IntPtr, Pointer, Pointer)>(target, 49)
      .asFunction<int Function(int, Pointer, Pointer)>();
  late final setDpiFn = comMethod<Void Function(IntPtr, Float, Float)>(target, 51)
      .asFunction<void Function(int, double, double)>();
  late final setBrushColorFn = comMethod<Void Function(IntPtr, Pointer<ColorF>)>(brush, 8)
      .asFunction<void Function(int, Pointer<ColorF>)>();

  void setColor(int argb) {
    color.ref
      ..a = ((argb >> 24) & 0xFF) / 255.0
      ..r = ((argb >> 16) & 0xFF) / 255.0
      ..g = ((argb >> 8) & 0xFF) / 255.0
      ..b = (argb & 0xFF) / 255.0;
  }

  int useColor(int argb) {
    setColor(argb);
    setBrushColorFn(brush, color);
    return brush;
  }

  void setRect(double x, double y, double w, double h) {
    rect.ref
      ..left = x
      ..top = y
      ..right = x + w
      ..bottom = y + h;
  }

  void resize(int width, int height) {
    if (layered) return;
    scoped((a) {
      final size = a<SizeU>()
        ..ref.width = width < 1 ? 1 : width
        ..ref.height = height < 1 ? 1 : height;
      comMethod<Int32 Function(IntPtr, Pointer<SizeU>)>(target, 58).asFunction<int Function(int, Pointer<SizeU>)>()(target, size);
    });
  }

  void changeDpi(double newDpi) {
    dpi = newDpi;
    setDpiFn(target, dpi, dpi);
  }

  void bindDc(int hdc, int width, int height) {
    scoped((a) {
      final r = a<RECT>()
        ..ref.right = width
        ..ref.bottom = height;
      comMethod<Int32 Function(IntPtr, IntPtr, Pointer<RECT>)>(target, 57)
          .asFunction<int Function(int, int, Pointer<RECT>)>()(target, hdc, r);
    });
  }

  void begin() => beginDrawFn(target);

  bool end() {
    final hr = endDrawFn(target, nullptr, nullptr);
    if ((hr & 0xFFFFFFFF) == recreateTarget && !layered) {
      comRelease(brush);
      comRelease(target);
      createHwndTarget();
      return false;
    }
    return true;
  }

  void clear(int argb) {
    setColor(argb);
    clearFn(target, color);
  }

  void fillRect(double x, double y, double w, double h, int argb) {
    if (w <= 0 || h <= 0) return;
    setRect(x, y, w, h);
    fillRectFn(target, rect, useColor(argb));
  }

  void strokeRect(double x, double y, double w, double h, int argb, [double width = 1]) {
    setRect(x + width / 2, y + width / 2, w - width, h - width);
    drawRectFn(target, rect, useColor(argb), width, 0);
  }

  void fillRounded(double x, double y, double w, double h, double radius, int argb) {
    if (w <= 0 || h <= 0) return;
    rounded.ref
      ..rect.left = x
      ..rect.top = y
      ..rect.right = x + w
      ..rect.bottom = y + h
      ..radiusX = radius
      ..radiusY = radius;
    fillRoundedFn(target, rounded, useColor(argb));
  }

  void strokeRounded(double x, double y, double w, double h, double radius, int argb, [double width = 1]) {
    rounded.ref
      ..rect.left = x + width / 2
      ..rect.top = y + width / 2
      ..rect.right = x + w - width / 2
      ..rect.bottom = y + h - width / 2
      ..radiusX = radius
      ..radiusY = radius;
    drawRoundedFn(target, rounded, useColor(argb), width, 0);
  }

  void fillCircle(double cx, double cy, double r, int argb) {
    ellipse.ref
      ..point.x = cx
      ..point.y = cy
      ..radiusX = r
      ..radiusY = r;
    fillEllipseFn(target, ellipse, useColor(argb));
  }

  void strokeCircle(double cx, double cy, double r, int argb, [double width = 1]) {
    ellipse.ref
      ..point.x = cx
      ..point.y = cy
      ..radiusX = r
      ..radiusY = r;
    drawEllipseFn(target, ellipse, useColor(argb), width, 0);
  }

  void line(double x1, double y1, double x2, double y2, int argb, [double width = 1]) {
    pointA.ref
      ..x = x1
      ..y = y1;
    pointB.ref
      ..x = x2
      ..y = y2;
    drawLineFn(target, pointA.ref, pointB.ref, useColor(argb), width, 0);
  }

  void text(String value, double x, double y, double w, double h, TextStyle style, int argb) {
    if (value.isEmpty || w <= 0 || h <= 0) return;
    scoped((a) {
      setRect(x, y, w, h);
      drawTextFn(target, wstr(value, a), value.length, Direct2D.format(style), rect, useColor(argb), 2, 0);
    });
  }

  void pushClip(double x, double y, double w, double h) {
    setRect(x, y, w, h);
    pushClipFn(target, rect, 1);
    clipStack.add(1);
  }

  void popClip() {
    if (clipStack.isEmpty) return;
    clipStack.removeLast();
    popClipFn(target);
  }

  void dispose() {
    comRelease(brush);
    comRelease(target);
    for (final p in [rect, rounded, ellipse, color, pointA, pointB]) {
      heap.free(p);
    }
  }
}

int withAlpha(int argb, double alpha) => ((alpha.clamp(0.0, 1.0) * 255).round() << 24) | (argb & 0xFFFFFF);

int mixColor(int a, int b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  int ch(int shift) {
    final ca = (a >> shift) & 0xFF, cb = (b >> shift) & 0xFF;
    return (ca + (cb - ca) * t).round() & 0xFF;
  }

  return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int hexColor(String hex) => 0xFF000000 | int.parse(hex.replaceAll('#', ''), radix: 16);
