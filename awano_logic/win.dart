import 'dart:ffi';
import 'native.dart';

final user32 = DynamicLibrary.open('user32.dll');
final gdi32 = DynamicLibrary.open('gdi32.dll');
final ole32 = DynamicLibrary.open('ole32.dll');
final shell32 = DynamicLibrary.open('shell32.dll');
final uxtheme = DynamicLibrary.open('uxtheme.dll');

final class POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class SIZE extends Struct {
  @Int32()
  external int cx;
  @Int32()
  external int cy;
}

final class RECT extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class MSG extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int message;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  external POINT pt;
  @Uint32()
  external int lPrivate;
}

typedef WndProcNative = IntPtr Function(IntPtr hwnd, Uint32 msg, IntPtr wParam, IntPtr lParam);

final class WNDCLASSEXW extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int style;
  external Pointer<NativeFunction<WndProcNative>> lpfnWndProc;
  @Int32()
  external int cbClsExtra;
  @Int32()
  external int cbWndExtra;
  @IntPtr()
  external int hInstance;
  @IntPtr()
  external int hIcon;
  @IntPtr()
  external int hCursor;
  @IntPtr()
  external int hbrBackground;
  external Pointer<Uint16> lpszMenuName;
  external Pointer<Uint16> lpszClassName;
  @IntPtr()
  external int hIconSm;
}

final class BITMAPINFOHEADER extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class TRACKMOUSEEVENT extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwFlags;
  @IntPtr()
  external int hwndTrack;
  @Uint32()
  external int dwHoverTime;
}

final class MONITORINFO extends Struct {
  @Uint32()
  external int cbSize;
  external RECT rcMonitor;
  external RECT rcWork;
  @Uint32()
  external int dwFlags;
}

final class NMHDR extends Struct {
  @IntPtr()
  external int hwndFrom;
  @IntPtr()
  external int idFrom;
  @Uint32()
  external int code;
}

@Packed(4)
final class MSGFILTER extends Struct {
  @IntPtr()
  external int hwndFrom;
  @IntPtr()
  external int idFrom;
  @Uint32()
  external int code;
  @Uint32()
  external int headerPadding;
  @Uint32()
  external int msg;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
}

final class GUID extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;

  void parse(String s) {
    final h = s.replaceAll(RegExp(r'[{}\-]'), '');
    data1 = int.parse(h.substring(0, 8), radix: 16);
    data2 = int.parse(h.substring(8, 12), radix: 16);
    data3 = int.parse(h.substring(12, 16), radix: 16);
    for (var i = 0; i < 8; i++) {
      data4[i] = int.parse(h.substring(16 + 2 * i, 18 + 2 * i), radix: 16);
    }
  }
}

Pointer<GUID> guid(String s, Allocator a) => a<GUID>()..ref.parse(s);

const WS_POPUP = 0x80000000;
const WS_CHILD = 0x40000000;
const WS_VISIBLE = 0x10000000;
const WS_CLIPCHILDREN = 0x02000000;
const WS_CLIPSIBLINGS = 0x04000000;
const WS_SYSMENU = 0x00080000;
const WS_MINIMIZEBOX = 0x00020000;
const WS_VSCROLL = 0x00200000;
const WS_TABSTOP = 0x00010000;
const WS_EX_LAYERED = 0x00080000;
const WS_EX_APPWINDOW = 0x00040000;
const WS_EX_TOOLWINDOW = 0x00000080;
const WS_EX_TOPMOST = 0x00000008;
const WS_EX_NOPARENTNOTIFY = 0x00000004;
const CS_DROPSHADOW = 0x00020000;
const CS_DBLCLKS = 0x0008;

const ES_MULTILINE = 0x0004;
const ES_AUTOVSCROLL = 0x0040;
const ES_AUTOHSCROLL = 0x0080;
const ES_READONLY = 0x0800;
const ES_WANTRETURN = 0x1000;
const ES_CENTER = 0x0001;
const ES_NOHIDESEL = 0x0100;
const ES_SAVESEL = 0x00008000;

const SW_SHOW = 5;
const SW_HIDE = 0;
const SW_SHOWNA = 8;
const SW_SHOWNOACTIVATE = 4;

const WM_CREATE = 0x0001;
const WM_DESTROY = 0x0002;
const WM_MOVE = 0x0003;
const WM_SIZE = 0x0005;
const WM_ACTIVATE = 0x0006;
const WM_SETFOCUS = 0x0007;
const WM_KILLFOCUS = 0x0008;
const WM_PAINT = 0x000F;
const WM_CLOSE = 0x0010;
const WM_QUIT = 0x0012;
const WM_ERASEBKGND = 0x0014;
const WM_SETCURSOR = 0x0020;
const WM_MOUSEACTIVATE = 0x0021;
const WM_GETMINMAXINFO = 0x0024;
const WM_SETFONT = 0x0030;
const WM_NOTIFY = 0x004E;
const WM_SETICON = 0x0080;
const WM_NCHITTEST = 0x0084;
const WM_NCMOUSEMOVE = 0x00A0;
const WM_NCLBUTTONDOWN = 0x00A1;
const WM_NCLBUTTONDBLCLK = 0x00A3;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_CHAR = 0x0102;
const WM_SYSKEYDOWN = 0x0104;
const WM_COMMAND = 0x0111;
const WM_TIMER = 0x0113;
const WM_CTLCOLOREDIT = 0x0133;
const WM_MOUSEMOVE = 0x0200;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_LBUTTONDBLCLK = 0x0203;
const WM_RBUTTONDOWN = 0x0204;
const WM_RBUTTONUP = 0x0205;
const WM_MOUSEWHEEL = 0x020A;
const WM_CAPTURECHANGED = 0x0215;
const WM_MOUSELEAVE = 0x02A3;
const WM_DPICHANGED = 0x02E0;
const WM_SETTEXT = 0x000C;
const WM_GETTEXT = 0x000D;
const WM_GETTEXTLENGTH = 0x000E;
const WM_USER = 0x0400;
const WM_APP = 0x8000;

const MK_SHIFT = 0x0004;
const MK_CONTROL = 0x0008;

const HTCLIENT = 1;
const HTCAPTION = 2;
const HTTRANSPARENT = -1;
const TME_LEAVE = 0x2;
const ULW_ALPHA = 0x2;
const PM_REMOVE = 0x1;
const QS_ALLINPUT = 0x04FF;
const MWMO_INPUTAVAILABLE = 0x0004;
const MA_NOACTIVATE = 3;

const MB_OK = 0x0;
const MB_YESNO = 0x4;
const MB_ICONERROR = 0x10;
const MB_ICONQUESTION = 0x20;
const MB_ICONWARNING = 0x30;
const MB_ICONINFORMATION = 0x40;
const MB_SETFOREGROUND = 0x10000;
const IDYES = 6;

const IDC_ARROW = 32512;
const IDC_IBEAM = 32513;
const IDC_SIZENWSE = 32642;
const IDC_SIZEWE = 32644;
const IDC_SIZENS = 32645;
const IDC_SIZEALL = 32646;
const IDC_HAND = 32649;

const SWP_NOSIZE = 0x0001;
const SWP_NOMOVE = 0x0002;
const SWP_NOZORDER = 0x0004;
const SWP_NOACTIVATE = 0x0010;
const SWP_SHOWWINDOW = 0x0040;
const SWP_NOOWNERZORDER = 0x0200;
const HWND_TOP = 0;
const HWND_TOPMOST = -1;
const HWND_NOTOPMOST = -2;
const MONITOR_DEFAULTTONEAREST = 2;

const VK_BACK = 0x08;
const VK_TAB = 0x09;
const VK_RETURN = 0x0D;
const VK_SHIFT = 0x10;
const VK_CONTROL = 0x11;
const VK_ESCAPE = 0x1B;
const VK_PRIOR = 0x21;
const VK_NEXT = 0x22;
const VK_END = 0x23;
const VK_HOME = 0x24;
const VK_UP = 0x26;
const VK_DOWN = 0x28;
const VK_F1 = 0x70;

final RegisterClassExW =
    user32.lookupFunction<Uint16 Function(Pointer<WNDCLASSEXW>), int Function(Pointer<WNDCLASSEXW>)>('RegisterClassExW');
final CreateWindowExW = user32.lookupFunction<
    IntPtr Function(
        Uint32, Pointer<Uint16>, Pointer<Uint16>, Uint32, Int32, Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer),
    int Function(int, Pointer<Uint16>, Pointer<Uint16>, int, int, int, int, int, int, int, int, Pointer)>('CreateWindowExW');
final DefWindowProcW = user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('DefWindowProcW');
final DestroyWindow = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');
final ShowWindow = user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final IsWindowVisible = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
final PostQuitMessage = user32.lookupFunction<Void Function(Int32), void Function(int)>('PostQuitMessage');
final PostMessageW = user32
    .lookupFunction<Int32 Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('PostMessageW');
final SendMessageW = user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('SendMessageW');
final SendMessagePtr = user32.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, Pointer),
    int Function(int, int, int, Pointer)>('SendMessageW');
final PeekMessageW = user32.lookupFunction<Int32 Function(Pointer<MSG>, IntPtr, Uint32, Uint32, Uint32),
    int Function(Pointer<MSG>, int, int, int, int)>('PeekMessageW');
final TranslateMessage = user32.lookupFunction<Int32 Function(Pointer<MSG>), int Function(Pointer<MSG>)>('TranslateMessage');
final DispatchMessageW = user32.lookupFunction<IntPtr Function(Pointer<MSG>), int Function(Pointer<MSG>)>('DispatchMessageW');
final MsgWaitForMultipleObjectsEx = user32.lookupFunction<Uint32 Function(Uint32, Pointer, Uint32, Uint32, Uint32),
    int Function(int, Pointer, int, int, int)>('MsgWaitForMultipleObjectsEx');
final UpdateLayeredWindow = user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Pointer<POINT>, Pointer<SIZE>, IntPtr, Pointer<POINT>, Uint32, Pointer<Uint32>, Uint32),
    int Function(int, int, Pointer<POINT>, Pointer<SIZE>, int, Pointer<POINT>, int, Pointer<Uint32>, int)>(
  'UpdateLayeredWindow',
);
final GetDC = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final ReleaseDC = user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
final SetTimer = user32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr, Uint32, Pointer), int Function(int, int, int, Pointer)>('SetTimer');
final KillTimer = user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('KillTimer');
final GetWindowRect =
    user32.lookupFunction<Int32 Function(IntPtr, Pointer<RECT>), int Function(int, Pointer<RECT>)>('GetWindowRect');
final GetClientRect =
    user32.lookupFunction<Int32 Function(IntPtr, Pointer<RECT>), int Function(int, Pointer<RECT>)>('GetClientRect');
final SetWindowPos = user32.lookupFunction<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');
final MoveWindow = user32.lookupFunction<Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32),
    int Function(int, int, int, int, int, int)>('MoveWindow');
final GetCursorPos = user32.lookupFunction<Int32 Function(Pointer<POINT>), int Function(Pointer<POINT>)>('GetCursorPos');
final ScreenToClient =
    user32.lookupFunction<Int32 Function(IntPtr, Pointer<POINT>), int Function(int, Pointer<POINT>)>('ScreenToClient');
final SetCapture = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetCapture');
final ReleaseCapture = user32.lookupFunction<Int32 Function(), int Function()>('ReleaseCapture');
final GetCapture = user32.lookupFunction<IntPtr Function(), int Function()>('GetCapture');
final LoadCursorW = user32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('LoadCursorW');
final SetCursor = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetCursor');
final TrackMouseEvent =
    user32.lookupFunction<Int32 Function(Pointer<TRACKMOUSEEVENT>), int Function(Pointer<TRACKMOUSEEVENT>)>('TrackMouseEvent');
final MessageBoxW = user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>, Uint32),
    int Function(int, Pointer<Uint16>, Pointer<Uint16>, int)>('MessageBoxW');
final SetForegroundWindow = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final SetFocus = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetFocus');
final GetFocus = user32.lookupFunction<IntPtr Function(), int Function()>('GetFocus');
final GetKeyState = user32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetKeyState');
final InvalidateRect =
    user32.lookupFunction<Int32 Function(IntPtr, Pointer<RECT>, Int32), int Function(int, Pointer<RECT>, int)>('InvalidateRect');
final ValidateRect = user32.lookupFunction<Int32 Function(IntPtr, Pointer<RECT>), int Function(int, Pointer<RECT>)>('ValidateRect');
final MonitorFromWindow = user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('MonitorFromWindow');
final GetMonitorInfoW = user32
    .lookupFunction<Int32 Function(IntPtr, Pointer<MONITORINFO>), int Function(int, Pointer<MONITORINFO>)>('GetMonitorInfoW');
final IsWindow = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindow');
final GetParent = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetParent');
final EnableWindow = user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('EnableWindow');
final MessageBeep = user32.lookupFunction<Int32 Function(Uint32), int Function(int)>('MessageBeep');
final GetModuleHandleW =
    kernel32.lookupFunction<IntPtr Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>('GetModuleHandleW');
final LoadLibraryW = kernel32.lookupFunction<IntPtr Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>('LoadLibraryW');
final GetDpiForWindow = user32.lookupFunction<Uint32 Function(IntPtr), int Function(int)>('GetDpiForWindow');
final GetDpiForSystem = user32.lookupFunction<Uint32 Function(), int Function()>('GetDpiForSystem');
final SetProcessDpiAwarenessContext =
    user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetProcessDpiAwarenessContext');
final SetWindowTheme = uxtheme.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>),
    int Function(int, Pointer<Uint16>, Pointer<Uint16>)>('SetWindowTheme');

final CreateCompatibleDC = gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');
final DeleteDC = gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final SelectObject = gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SelectObject');
final DeleteObject = gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final CreateDIBSection = gdi32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<BITMAPINFOHEADER>, Uint32, Pointer<Pointer<Uint8>>, IntPtr, Uint32),
    int Function(int, Pointer<BITMAPINFOHEADER>, int, Pointer<Pointer<Uint8>>, int, int)>('CreateDIBSection');
final CreateSolidBrush = gdi32.lookupFunction<IntPtr Function(Uint32), int Function(int)>('CreateSolidBrush');
final CreateBitmap = gdi32.lookupFunction<IntPtr Function(Int32, Int32, Uint32, Uint32, Pointer),
    int Function(int, int, int, int, Pointer)>('CreateBitmap');

final class ICONINFO extends Struct {
  @Int32()
  external int fIcon;
  @Uint32()
  external int xHotspot;
  @Uint32()
  external int yHotspot;
  @IntPtr()
  external int hbmMask;
  @IntPtr()
  external int hbmColor;
}

final CreateIconIndirect =
    user32.lookupFunction<IntPtr Function(Pointer<ICONINFO>), int Function(Pointer<ICONINFO>)>('CreateIconIndirect');

final CoInitializeEx = ole32.lookupFunction<Int32 Function(Pointer, Uint32), int Function(Pointer, int)>('CoInitializeEx');
final CoCreateInstance = ole32.lookupFunction<
    Int32 Function(Pointer<GUID>, IntPtr, Uint32, Pointer<GUID>, Pointer<IntPtr>),
    int Function(Pointer<GUID>, int, int, Pointer<GUID>, Pointer<IntPtr>)>('CoCreateInstance');
final CoTaskMemFree = ole32.lookupFunction<Void Function(Pointer), void Function(Pointer)>('CoTaskMemFree');
final SHCreateItemFromParsingName = shell32.lookupFunction<
    Int32 Function(Pointer<Uint16>, Pointer, Pointer<GUID>, Pointer<IntPtr>),
    int Function(Pointer<Uint16>, Pointer, Pointer<GUID>, Pointer<IntPtr>)>('SHCreateItemFromParsingName');

Pointer<NativeFunction<T>> comMethod<T extends Function>(int object, int index) {
  final vtable = Pointer<Pointer<IntPtr>>.fromAddress(object).value;
  return Pointer<NativeFunction<T>>.fromAddress(vtable[index]);
}

void comRelease(int object) {
  if (object == 0) return;
  comMethod<Uint32 Function(IntPtr)>(object, 2).asFunction<int Function(int)>()(object);
}

int comQuery(int object, String iid) {
  return scoped((a) {
    final out = a<IntPtr>();
    final hr = comMethod<Int32 Function(IntPtr, Pointer<GUID>, Pointer<IntPtr>)>(object, 0)
        .asFunction<int Function(int, Pointer<GUID>, Pointer<IntPtr>)>()(object, guid(iid, a), out);
    return hr == 0 ? out.value : 0;
  });
}

int lowWord(int value) => value & 0xFFFF;
int highWord(int value) => (value >> 16) & 0xFFFF;
int signedLow(int value) => (value & 0xFFFF) >= 0x8000 ? (value & 0xFFFF) - 0x10000 : value & 0xFFFF;
int signedHigh(int value) => signedLow(value >> 16);
bool keyDown(int vk) => (GetKeyState(vk) & 0x8000) != 0;

int messageBox(int owner, String text, String title, int flags) =>
    scoped((a) => MessageBoxW(owner, wstr(text, a), wstr(title, a), flags | MB_SETFOREGROUND));

class FileFilter {
  final String label;
  final String patterns;
  const FileFilter(this.label, this.patterns);
}

const clsidFileOpenDialog = '{DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7}';
const clsidFileSaveDialog = '{C0B4E2F3-BA21-4773-8DBA-335EC946EB8B}';
const iidFileOpenDialog = '{d57c7288-d4ad-4768-be02-9d969532d960}';
const iidFileSaveDialog = '{84bccd23-5fde-4cdb-aea4-af64b83d78ab}';
const iidShellItem = '{43826d1e-e718-42ee-bc55-a1e261c37bfe}';

String? fileDialog(
  int owner, {
  bool save = false,
  bool folder = false,
  String? title,
  List<FileFilter> filters = const [],
  String? fileName,
  String? defaultExtension,
  String? startIn,
}) {
  return scoped((a) {
    final ppv = a<IntPtr>();
    final hr = CoCreateInstance(guid(save ? clsidFileSaveDialog : clsidFileOpenDialog, a), 0, 1,
        guid(save ? iidFileSaveDialog : iidFileOpenDialog, a), ppv);
    if (hr != 0) return null;
    final dialog = ppv.value;
    try {
      final options = a<Uint32>();
      comMethod<Int32 Function(IntPtr, Pointer<Uint32>)>(dialog, 10)
          .asFunction<int Function(int, Pointer<Uint32>)>()(dialog, options);
      var flags = options.value | 0x40;
      if (folder) flags |= 0x20;
      if (!save && !folder) flags |= 0x1000;
      comMethod<Int32 Function(IntPtr, Uint32)>(dialog, 9).asFunction<int Function(int, int)>()(dialog, flags);
      if (filters.isNotEmpty && !folder) {
        final spec = a<Pointer<Uint16>>(filters.length * 2);
        for (var i = 0; i < filters.length; i++) {
          spec[i * 2] = wstr(filters[i].label, a);
          spec[i * 2 + 1] = wstr(filters[i].patterns, a);
        }
        comMethod<Int32 Function(IntPtr, Uint32, Pointer)>(dialog, 4)
            .asFunction<int Function(int, int, Pointer)>()(dialog, filters.length, spec);
      }
      if (title != null) {
        comMethod<Int32 Function(IntPtr, Pointer<Uint16>)>(dialog, 17)
            .asFunction<int Function(int, Pointer<Uint16>)>()(dialog, wstr(title, a));
      }
      if (fileName != null) {
        comMethod<Int32 Function(IntPtr, Pointer<Uint16>)>(dialog, 15)
            .asFunction<int Function(int, Pointer<Uint16>)>()(dialog, wstr(fileName, a));
      }
      if (defaultExtension != null) {
        comMethod<Int32 Function(IntPtr, Pointer<Uint16>)>(dialog, 22)
            .asFunction<int Function(int, Pointer<Uint16>)>()(dialog, wstr(defaultExtension, a));
      }
      if (startIn != null) {
        final item = a<IntPtr>();
        if (SHCreateItemFromParsingName(wstr(startIn, a), nullptr, guid(iidShellItem, a), item) == 0) {
          comMethod<Int32 Function(IntPtr, IntPtr)>(dialog, 12).asFunction<int Function(int, int)>()(dialog, item.value);
          comRelease(item.value);
        }
      }
      final shown = comMethod<Int32 Function(IntPtr, IntPtr)>(dialog, 3).asFunction<int Function(int, int)>()(dialog, owner);
      if (shown != 0) return null;
      final item = a<IntPtr>();
      if (comMethod<Int32 Function(IntPtr, Pointer<IntPtr>)>(dialog, 20)
              .asFunction<int Function(int, Pointer<IntPtr>)>()(dialog, item) !=
          0) {
        return null;
      }
      final name = a<Pointer<Uint16>>();
      final ok = comMethod<Int32 Function(IntPtr, Uint32, Pointer<Pointer<Uint16>>)>(item.value, 5)
          .asFunction<int Function(int, int, Pointer<Pointer<Uint16>>)>()(item.value, 0x80058000, name);
      comRelease(item.value);
      if (ok != 0) return null;
      final path = fromWstr(name.value);
      CoTaskMemFree(name.value);
      return path;
    } finally {
      comRelease(dialog);
    }
  });
}
