#include "flutter_window.h"

#include <cmath>
#include <optional>
#include <shellapi.h>
#include <sstream>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "tagtag_entrypoint_protocol.h"
#include "utils.h"
#include "windows_recycle_bin.h"

namespace {

constexpr int kQuickTagHotkeyId = 0x5447;
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayCommandShow = 0x5450;
constexpr UINT kTrayCommandQuickTag = 0x5451;
constexpr UINT kTrayCommandExit = 0x5452;
constexpr wchar_t kTrayTooltip[] = L"TAGTAG";
constexpr wchar_t kFloatingDropTargetClassName[] =
    L"TAGTAG_FLOATING_DROP_TARGET";
constexpr int kFloatingDropTargetSize = 64;
constexpr UINT kFloatingDropTargetProximityMessage = WM_APP + 2;
constexpr UINT_PTR kFloatingDropTargetSlideTimer = 1;
constexpr UINT_PTR kFloatingDropTargetGlowTimer = 2;
constexpr DWORD kFloatingDropTargetSlideStepMs = 16;
constexpr DWORD kFloatingDropTargetSlideMs = 180;
constexpr DWORD kFloatingDropTargetGlowStepMs = 55;
constexpr DWORD kFloatingDropTargetGlowPeriodMs = 900;
constexpr LONG kFloatingDropTargetDragThreshold = 4;
constexpr int kFloatingDropTargetProximityMargin = 64;
constexpr LONG kFloatingDropTargetEdgeSlack = 6;
// Drag must stop within this distance of a left/right work-area edge for the
// ball to snap; otherwise it stays where it was released.
constexpr LONG kFloatingDropTargetSnapThreshold = 48;

struct FloatingDropTargetHookState {
  HWND window = nullptr;
  bool active = false;
  bool button_down = false;
};

FloatingDropTargetHookState g_floating_drop_target_hook;

// Low-level mouse hooks cannot reliably distinguish file drags from other
// drags globally, so the proximity approximation is "left button held while
// moving near the ball". Keep this O(1) and allocation-free: hit-test an
// inflated window rect and post state changes only.
LRESULT CALLBACK FloatingDropTargetProximityProc(int code, WPARAM wparam,
                                                 LPARAM lparam) {
  if (code == HC_ACTION && g_floating_drop_target_hook.window != nullptr &&
      (wparam == WM_MOUSEMOVE || wparam == WM_LBUTTONDOWN ||
       wparam == WM_LBUTTONUP)) {
    const auto& info = *reinterpret_cast<const MSLLHOOKSTRUCT*>(lparam);
    // Track the button ourselves: reading its state mid-hook is unreliable
    // for injected input, while the hook always sees every down/up event.
    if (wparam == WM_LBUTTONDOWN) {
      g_floating_drop_target_hook.button_down = true;
    } else if (wparam == WM_LBUTTONUP) {
      g_floating_drop_target_hook.button_down = false;
    }
    RECT rect{};
    GetWindowRect(g_floating_drop_target_hook.window, &rect);
    InflateRect(&rect, kFloatingDropTargetProximityMargin,
                kFloatingDropTargetProximityMargin);
    const bool active = PtInRect(&rect, info.pt) != FALSE &&
                        g_floating_drop_target_hook.button_down;
    if (active != g_floating_drop_target_hook.active) {
      g_floating_drop_target_hook.active = active;
      PostMessage(g_floating_drop_target_hook.window,
                  kFloatingDropTargetProximityMessage,
                  static_cast<WPARAM>(active ? 1 : 0), 0);
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

const std::string* StringArgument(const flutter::MethodCall<flutter::EncodableValue>& call,
                                  const char* name) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto iterator = arguments->find(flutter::EncodableValue(name));
  if (iterator == arguments->end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&iterator->second);
}

std::optional<int64_t> IntegerArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* name) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto iterator = arguments->find(flutter::EncodableValue(name));
  if (iterator == arguments->end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

std::optional<double> DoubleArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* name) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto iterator = arguments->find(flutter::EncodableValue(name));
  if (iterator == arguments->end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  return std::nullopt;
}

std::string HResultDetails(HRESULT status) {
  std::ostringstream stream;
  stream << "HRESULT 0x" << std::hex << static_cast<unsigned long>(status);
  return stream.str();
}

std::vector<std::wstring> ExplorerPathsFromCopyData(
    const COPYDATASTRUCT* copy_data) {
  if (copy_data == nullptr ||
      copy_data->dwData != tagtag::kExplorerPathsCopyDataId ||
      copy_data->lpData == nullptr ||
      copy_data->cbData < 2 * sizeof(wchar_t) ||
      copy_data->cbData % sizeof(wchar_t) != 0) {
    return {};
  }

  const auto* characters = static_cast<const wchar_t*>(copy_data->lpData);
  const size_t character_count = copy_data->cbData / sizeof(wchar_t);
  std::vector<std::wstring> paths;
  size_t start = 0;
  for (size_t index = 0; index < character_count; ++index) {
    if (characters[index] != L'\0') {
      continue;
    }
    if (index == start) {
      return index == character_count - 1 ? paths : std::vector<std::wstring>();
    }
    paths.emplace_back(characters + start, index - start);
    start = index + 1;
  }
  return {};
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  recycle_bin_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "tagtag/windows_recycle_bin",
          &flutter::StandardMethodCodec::GetInstance());
  recycle_bin_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "recycle") {
          const std::string* resource_path = StringArgument(call, "path");
          if (resource_path == nullptr || resource_path->empty()) {
            result->Error("invalid_arguments", "Missing resource path");
            return;
          }
          const tagtag::RecycleBinResult recycle_result =
              tagtag::MoveToRecycleBin(Utf16FromUtf8(*resource_path));
          if (FAILED(recycle_result.status)) {
            result->Error("recycle_failed", "Windows could not recycle item",
                          flutter::EncodableValue(
                              HResultDetails(recycle_result.status)));
            return;
          }
          result->Success(
              flutter::EncodableValue(Utf8FromUtf16(recycle_result.token.c_str())));
          return;
        }
        if (call.method_name() == "restore") {
          const std::string* token = StringArgument(call, "token");
          const std::string* destination_path =
              StringArgument(call, "destinationPath");
          if (token == nullptr || token->empty() || destination_path == nullptr ||
              destination_path->empty()) {
            result->Error("invalid_arguments",
                          "Missing recycle token or destination path");
            return;
          }
          const HRESULT status = tagtag::RestoreFromRecycleBin(
              Utf16FromUtf8(*token), Utf16FromUtf8(*destination_path));
          if (FAILED(status)) {
            result->Error("restore_failed",
                          "Windows could not restore recycled item",
                          flutter::EncodableValue(HResultDetails(status)));
            return;
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  quick_tag_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "tagtag/windows_quick_tag",
          &flutter::StandardMethodCodec::GetInstance());
  quick_tag_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "isRegistered") {
          result->Success(flutter::EncodableValue(quick_tag_registered_));
          return;
        }
        if (call.method_name() == "setShortcut") {
          const auto modifiers = IntegerArgument(call, "modifiers");
          const auto virtual_key = IntegerArgument(call, "virtualKey");
          if (!modifiers.has_value() || !virtual_key.has_value() ||
              *modifiers < 0 || *virtual_key < 0) {
            result->Error("invalid_arguments", "Invalid Quick Tag shortcut");
            return;
          }
          result->Success(flutter::EncodableValue(SetQuickTagShortcut(
              static_cast<UINT>(*modifiers),
              static_cast<UINT>(*virtual_key))));
          return;
        }
        result->NotImplemented();
      });
  floating_drop_target_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "tagtag/windows_floating_drop_target",
          &flutter::StandardMethodCodec::GetInstance());
  floating_drop_target_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setEnabled") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid_arguments",
                          "Floating drop target requires a bool value");
            return;
          }
          result->Success(
              flutter::EncodableValue(SetFloatingDropTargetEnabled(*enabled)));
          return;
        }
        if (call.method_name() == "setPosition") {
          const auto x = DoubleArgument(call, "x");
          const auto y = DoubleArgument(call, "y");
          if (!x.has_value() || !y.has_value()) {
            result->Error("invalid_arguments",
                          "Floating drop target position requires x and y");
            return;
          }
          floating_drop_target_position_ =
              POINT{static_cast<LONG>(std::lround(*x)),
                    static_cast<LONG>(std::lround(*y))};
          if (floating_drop_target_window_ != nullptr &&
              IsWindowVisible(floating_drop_target_window_) &&
              !floating_drop_target_captured_) {
            ApplyFloatingDropTargetPosition();
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "isEnabled") {
          result->Success(flutter::EncodableValue(floating_drop_target_enabled_));
          return;
        }
        result->NotImplemented();
      });
  close_behavior_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "tagtag/windows_close_behavior",
          &flutter::StandardMethodCodec::GetInstance());
  close_behavior_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setCloseToTray") {
          const auto* close_to_tray = std::get_if<bool>(call.arguments());
          if (close_to_tray == nullptr) {
            result->Error("invalid_arguments",
                          "Close behavior requires a bool value");
            return;
          }
          close_to_tray_ = *close_to_tray;
          result->Success(flutter::EncodableValue(close_to_tray_));
          return;
        }
        result->NotImplemented();
      });
  quick_tag_registered_ =
      RegisterHotKey(GetHandle(), kQuickTagHotkeyId, quick_tag_modifiers_,
                     quick_tag_virtual_key_) != FALSE;
  if (quick_tag_registered_) {
    quick_tag_window_ = GetHandle();
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  DestroyFloatingDropTarget();
  RemoveTrayIcon();
  if (quick_tag_registered_) {
    UnregisterHotKey(quick_tag_window_, kQuickTagHotkeyId);
    quick_tag_registered_ = false;
    quick_tag_window_ = nullptr;
  }
  floating_drop_target_channel_.reset();
  quick_tag_channel_.reset();
  recycle_bin_channel_.reset();
  close_behavior_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetQuickTagShortcut(UINT modifiers, UINT virtual_key) {
  const HWND window = GetHandle();
  const UINT previous_modifiers = quick_tag_modifiers_;
  const UINT previous_virtual_key = quick_tag_virtual_key_;
  if (quick_tag_registered_) {
    UnregisterHotKey(quick_tag_window_, kQuickTagHotkeyId);
    quick_tag_registered_ = false;
  }
  if (RegisterHotKey(window, kQuickTagHotkeyId, modifiers, virtual_key) !=
      FALSE) {
    quick_tag_registered_ = true;
    quick_tag_window_ = window;
    quick_tag_modifiers_ = modifiers;
    quick_tag_virtual_key_ = virtual_key;
    return true;
  }
  quick_tag_registered_ =
      RegisterHotKey(window, kQuickTagHotkeyId, previous_modifiers,
                     previous_virtual_key) != FALSE;
  quick_tag_window_ = quick_tag_registered_ ? window : nullptr;
  return false;
}

void FlutterWindow::ShowAndActivate(HWND window) {
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
}

void FlutterWindow::ActivateQuickTag(HWND window) {
  ShowAndActivate(window);
  if (quick_tag_channel_) {
    quick_tag_channel_->InvokeMethod(
        "activated", std::make_unique<flutter::EncodableValue>());
  }
}

void FlutterWindow::ActivateExternalQuickTag(
    HWND window, const COPYDATASTRUCT* copy_data) {
  const std::vector<std::wstring> paths = ExplorerPathsFromCopyData(copy_data);
  ActivateExternalQuickTag(window, paths);
}

void FlutterWindow::ActivateExternalQuickTag(
    HWND window, const std::vector<std::wstring>& paths) {
  if (paths.empty()) {
    return;
  }
  ShowAndActivate(window);
  if (quick_tag_channel_) {
    flutter::EncodableList external_paths;
    for (const std::wstring& path : paths) {
      external_paths.emplace_back(Utf8FromUtf16(path.c_str()));
    }
    quick_tag_channel_->InvokeMethod(
        "externalPaths",
        std::make_unique<flutter::EncodableValue>(std::move(external_paths)));
  }
}

bool FlutterWindow::SetFloatingDropTargetEnabled(bool enabled) {
  if (enabled && !CreateFloatingDropTarget()) {
    return false;
  }
  floating_drop_target_enabled_ = enabled;
  if (enabled) {
    InstallFloatingDropTargetHook();
    ShowFloatingDropTarget();
  } else if (floating_drop_target_window_ != nullptr) {
    UninstallFloatingDropTargetHook();
    KillTimer(floating_drop_target_window_, kFloatingDropTargetSlideTimer);
    KillTimer(floating_drop_target_window_, kFloatingDropTargetGlowTimer);
    floating_drop_target_sliding_ = false;
    floating_drop_target_glow_ = false;
    floating_drop_target_hover_ = false;
    floating_drop_target_tracking_leave_ = false;
    if (floating_drop_target_captured_) {
      ReleaseCapture();
      floating_drop_target_captured_ = false;
      floating_drop_target_dragging_ = false;
    }
    // Restore the logo-only pixels in case a glow frame was showing.
    UpdateFloatingDropTargetPixels(0);
    ShowWindow(floating_drop_target_window_, SW_HIDE);
  }
  return true;
}

bool FlutterWindow::CreateFloatingDropTarget() {
  if (floating_drop_target_window_ != nullptr) {
    return true;
  }

  WNDCLASSW window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kFloatingDropTargetClassName;
  window_class.lpfnWndProc = FlutterWindow::FloatingDropTargetWndProc;
  const ATOM registration = RegisterClassW(&window_class);
  if (registration == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  floating_drop_target_class_registered_ = registration != 0;

  floating_drop_target_window_ = CreateWindowExW(
      WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED,
      kFloatingDropTargetClassName, L"TAGTAG", WS_POPUP, 0, 0,
      kFloatingDropTargetSize, kFloatingDropTargetSize, nullptr, nullptr,
      GetModuleHandle(nullptr), this);
  if (floating_drop_target_window_ == nullptr) {
    if (floating_drop_target_class_registered_) {
      UnregisterClassW(kFloatingDropTargetClassName, GetModuleHandle(nullptr));
      floating_drop_target_class_registered_ = false;
    }
    return false;
  }
  DragAcceptFiles(floating_drop_target_window_, TRUE);
  UpdateFloatingDropTargetPixels(0);
  return true;
}

// Renders the app icon with per-pixel alpha so the floating target shows
// only the logo, no background disc. When glow_alpha is above zero a soft
// ring is composited over the logo for the proximity "ready to accept"
// pulse; the ring pixels are premultiplied src-over in place.
void FlutterWindow::UpdateFloatingDropTargetPixels(int glow_alpha) {
  if (floating_drop_target_window_ == nullptr) {
    return;
  }
  const int size = kFloatingDropTargetSize;
  HDC screen_dc = GetDC(nullptr);
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = size;
  bitmap_info.bmiHeader.biHeight = -size;  // top-down
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(memory_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &bits, nullptr, 0);
  if (bitmap == nullptr || bits == nullptr) {
    if (bitmap != nullptr) DeleteObject(bitmap);
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return;
  }
  ZeroMemory(bits, static_cast<size_t>(size) * size * 4);
  HGDIOBJ previous_bitmap = SelectObject(memory_dc, bitmap);
  HICON icon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      size, size, LR_DEFAULTCOLOR));
  if (icon != nullptr) {
    DrawIconEx(memory_dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL);
    DestroyIcon(icon);
  }
  // DrawIconEx writes straight (non-premultiplied) colors; UpdateLayeredWindow
  // needs premultiplied alpha.
  unsigned char* pixels = static_cast<unsigned char*>(bits);
  const int count = size * size;
  for (int index = 0; index < count; ++index) {
    const unsigned char alpha = pixels[index * 4 + 3];
    pixels[index * 4 + 0] =
        static_cast<unsigned char>((pixels[index * 4 + 0] * alpha + 127) / 255);
    pixels[index * 4 + 1] =
        static_cast<unsigned char>((pixels[index * 4 + 1] * alpha + 127) / 255);
    pixels[index * 4 + 2] =
        static_cast<unsigned char>((pixels[index * 4 + 2] * alpha + 127) / 255);
  }
  if (glow_alpha > 0) {
    const double center = (size - 1) / 2.0;
    const double outer = size / 2.0 - 1.0;
    const double inner = outer - 5.0;
    const int ring_red = 150;
    const int ring_green = 182;
    const int ring_blue = 250;
    for (int row = 0; row < size; ++row) {
      for (int column = 0; column < size; ++column) {
        const double dx = column - center;
        const double dy = row - center;
        const double distance = std::sqrt(dx * dx + dy * dy);
        double coverage = 0.0;
        if (distance >= inner && distance <= outer) {
          coverage = 1.0;
        } else if (distance > inner - 2.0 && distance < inner) {
          coverage = (distance - (inner - 2.0)) / 2.0;
        } else if (distance > outer && distance < outer + 2.0) {
          coverage = 1.0 - (distance - outer) / 2.0;
        }
        if (coverage <= 0.0) {
          continue;
        }
        const int alpha = static_cast<int>(glow_alpha * coverage);
        const int inverse = 255 - alpha;
        unsigned char* pixel = pixels + (row * size + column) * 4;
        pixel[0] = static_cast<unsigned char>(
            (ring_blue * alpha + pixel[0] * inverse + 127) / 255);
        pixel[1] = static_cast<unsigned char>(
            (ring_green * alpha + pixel[1] * inverse + 127) / 255);
        pixel[2] = static_cast<unsigned char>(
            (ring_red * alpha + pixel[2] * inverse + 127) / 255);
        pixel[3] = static_cast<unsigned char>(
            (255 * alpha + pixel[3] * inverse + 127) / 255);
      }
    }
  }
  RECT window_rect{};
  GetWindowRect(floating_drop_target_window_, &window_rect);
  POINT destination{window_rect.left, window_rect.top};
  POINT origin{0, 0};
  SIZE extent{size, size};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  UpdateLayeredWindow(floating_drop_target_window_, screen_dc, &destination,
                      &extent, memory_dc, &origin, 0, &blend, ULW_ALPHA);
  SelectObject(memory_dc, previous_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);
}

void FlutterWindow::DestroyFloatingDropTarget() {
  UninstallFloatingDropTargetHook();
  if (floating_drop_target_window_ != nullptr) {
    DragAcceptFiles(floating_drop_target_window_, FALSE);
    DestroyWindow(floating_drop_target_window_);
    floating_drop_target_window_ = nullptr;
  }
  if (floating_drop_target_class_registered_) {
    UnregisterClassW(kFloatingDropTargetClassName, GetModuleHandle(nullptr));
    floating_drop_target_class_registered_ = false;
  }
  floating_drop_target_enabled_ = false;
  floating_drop_target_captured_ = false;
  floating_drop_target_dragging_ = false;
  floating_drop_target_snap_ = FloatingTargetSnap::kNone;
  floating_drop_target_hover_ = false;
  floating_drop_target_tracking_leave_ = false;
  floating_drop_target_expanded_ = false;
  floating_drop_target_glow_ = false;
  floating_drop_target_sliding_ = false;
}

void FlutterWindow::ShowFloatingDropTarget() {
  if (floating_drop_target_window_ == nullptr) {
    return;
  }
  if (floating_drop_target_position_.has_value()) {
    ApplyFloatingDropTargetPosition();
    SetWindowPos(floating_drop_target_window_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    return;
  }
  RECT work_area{};
  if (SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0) == FALSE) {
    return;
  }
  const int margin = 18;
  floating_drop_target_snap_ = FloatingTargetSnap::kNone;
  floating_drop_target_expanded_ = false;
  SetWindowPos(floating_drop_target_window_, HWND_TOPMOST,
               work_area.right - kFloatingDropTargetSize - margin,
               work_area.bottom - kFloatingDropTargetSize - margin,
               kFloatingDropTargetSize, kFloatingDropTargetSize,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

// Applies the persisted logical center, clamped to the nearest monitor work
// area. A point that lands on a work-area edge restores the docked state.
void FlutterWindow::ApplyFloatingDropTargetPosition() {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr || !floating_drop_target_position_.has_value()) {
    return;
  }
  const POINT saved = *floating_drop_target_position_;
  const HMONITOR monitor = MonitorFromPoint(saved, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{static_cast<DWORD>(sizeof(monitor_info))};
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int size = kFloatingDropTargetSize;
  const LONG min_cx = work.left + size / 2;
  const LONG max_cx = work.right - size / 2;
  const LONG min_cy = work.top + size / 2;
  const LONG max_cy = work.bottom - size / 2;
  const LONG cx =
      saved.x < min_cx ? min_cx : (saved.x > max_cx ? max_cx : saved.x);
  const LONG cy =
      saved.y < min_cy ? min_cy : (saved.y > max_cy ? max_cy : saved.y);
  FloatingTargetSnap snap = FloatingTargetSnap::kNone;
  LONG left = cx - size / 2;
  if (cx <= min_cx + kFloatingDropTargetEdgeSlack) {
    snap = FloatingTargetSnap::kLeft;
    left = work.left - size * 2 / 3;
  } else if (cx >= max_cx - kFloatingDropTargetEdgeSlack) {
    snap = FloatingTargetSnap::kRight;
    left = work.right - size / 3;
  }
  floating_drop_target_snap_ = snap;
  floating_drop_target_expanded_ = false;
  SetWindowPos(window, HWND_TOPMOST, left, cy - size / 2, size, size,
               SWP_NOACTIVATE);
}

// Starts the edge snap after a drag, but only when the drag stopped near a
// left/right work-area edge; otherwise the ball stays where it was released
// and simply persists the free position.
void FlutterWindow::BeginFloatingDropTargetSnap() {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr) {
    return;
  }
  RECT rect{};
  GetWindowRect(window, &rect);
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{static_cast<DWORD>(sizeof(monitor_info))};
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int size = kFloatingDropTargetSize;
  const LONG center_x = rect.left + size / 2;
  const bool near_left = center_x <= work.left + kFloatingDropTargetSnapThreshold;
  const bool near_right =
      center_x >= work.right - kFloatingDropTargetSnapThreshold;
  if (!near_left && !near_right) {
    floating_drop_target_snap_ = FloatingTargetSnap::kNone;
    floating_drop_target_expanded_ = false;
    ReportFloatingDropTargetPosition();
    return;
  }
  const bool dock_left = near_left;
  POINT target{};
  target.x = dock_left ? work.left - size * 2 / 3 : work.right - size / 3;
  target.y = rect.top < work.top
                 ? work.top
                 : (rect.top > work.bottom - size ? work.bottom - size
                                                  : rect.top);
  floating_drop_target_expanded_ = false;
  BeginFloatingDropTargetSlide(target, true,
                               dock_left ? FloatingTargetSnap::kLeft
                                         : FloatingTargetSnap::kRight);
}

void FlutterWindow::BeginFloatingDropTargetSlide(POINT target,
                                                 bool finalize_snap,
                                                 FloatingTargetSnap snap) {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr) {
    return;
  }
  RECT rect{};
  GetWindowRect(window, &rect);
  floating_drop_target_slide_start_.x = rect.left;
  floating_drop_target_slide_start_.y = rect.top;
  floating_drop_target_slide_target_ = target;
  floating_drop_target_slide_start_tick_ = GetTickCount();
  floating_drop_target_slide_finalize_ = finalize_snap;
  floating_drop_target_slide_snap_ = snap;
  floating_drop_target_sliding_ = true;
  SetTimer(window, kFloatingDropTargetSlideTimer, kFloatingDropTargetSlideStepMs,
           nullptr);
}

void FlutterWindow::CompleteFloatingDropTargetSlide() {
  if (!floating_drop_target_slide_finalize_) {
    return;
  }
  floating_drop_target_slide_finalize_ = false;
  floating_drop_target_snap_ = floating_drop_target_slide_snap_;
  ReportFloatingDropTargetPosition();
}

void FlutterWindow::ReportFloatingDropTargetPosition() {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr || floating_drop_target_channel_ == nullptr) {
    return;
  }
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{static_cast<DWORD>(sizeof(monitor_info))};
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int size = kFloatingDropTargetSize;
  RECT rect{};
  GetWindowRect(window, &rect);
  // Report the logical fully-visible center so a restart can restore the
  // docked state for points that sit on a work-area edge.
  double logical_x = rect.left + size / 2.0;
  if (floating_drop_target_snap_ == FloatingTargetSnap::kLeft) {
    logical_x = work.left + size / 2.0;
  } else if (floating_drop_target_snap_ == FloatingTargetSnap::kRight) {
    logical_x = work.right - size / 2.0;
  }
  const double logical_y = rect.top + size / 2.0;
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("x")] = flutter::EncodableValue(logical_x);
  arguments[flutter::EncodableValue("y")] = flutter::EncodableValue(logical_y);
  floating_drop_target_channel_->InvokeMethod(
      "savePosition",
      std::make_unique<flutter::EncodableValue>(std::move(arguments)));
}

// Hover or proximity glow slides a docked ball fully out; leaving either
// state slides it back. Expansion slides may interrupt each other, but never
// an in-flight drag-end snap.
void FlutterWindow::UpdateFloatingDropTargetExpansion() {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr ||
      floating_drop_target_snap_ == FloatingTargetSnap::kNone ||
      floating_drop_target_captured_ ||
      (floating_drop_target_sliding_ &&
       floating_drop_target_slide_finalize_)) {
    return;
  }
  const bool expanded =
      floating_drop_target_hover_ || floating_drop_target_glow_;
  if (expanded == floating_drop_target_expanded_) {
    return;
  }
  floating_drop_target_expanded_ = expanded;
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{static_cast<DWORD>(sizeof(monitor_info))};
  GetMonitorInfoW(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int size = kFloatingDropTargetSize;
  RECT rect{};
  GetWindowRect(window, &rect);
  POINT target{};
  target.y = rect.top;
  if (expanded) {
    target.x = floating_drop_target_snap_ == FloatingTargetSnap::kLeft
                   ? work.left
                   : work.right - size;
  } else {
    target.x = floating_drop_target_snap_ == FloatingTargetSnap::kLeft
                   ? work.left - size * 2 / 3
                   : work.right - size / 3;
  }
  BeginFloatingDropTargetSlide(target, false, floating_drop_target_snap_);
}

void FlutterWindow::SetFloatingDropTargetGlow(bool active) {
  const HWND window = floating_drop_target_window_;
  if (window == nullptr || active == floating_drop_target_glow_) {
    return;
  }
  floating_drop_target_glow_ = active;
  if (active) {
    floating_drop_target_glow_start_ = GetTickCount();
    SetTimer(window, kFloatingDropTargetGlowTimer, kFloatingDropTargetGlowStepMs,
             nullptr);
  } else {
    KillTimer(window, kFloatingDropTargetGlowTimer);
    // Restore the logo-only pixels.
    UpdateFloatingDropTargetPixels(0);
  }
  UpdateFloatingDropTargetExpansion();
}

void FlutterWindow::InstallFloatingDropTargetHook() {
  if (floating_drop_target_hook_ != nullptr ||
      floating_drop_target_window_ == nullptr) {
    return;
  }
  g_floating_drop_target_hook.window = floating_drop_target_window_;
  g_floating_drop_target_hook.active = false;
  floating_drop_target_hook_ =
      SetWindowsHookExW(WH_MOUSE_LL, FloatingDropTargetProximityProc,
                        GetModuleHandle(nullptr), 0);
  if (floating_drop_target_hook_ == nullptr) {
    g_floating_drop_target_hook.window = nullptr;
  }
}

void FlutterWindow::UninstallFloatingDropTargetHook() {
  if (floating_drop_target_hook_ != nullptr) {
    UnhookWindowsHookEx(floating_drop_target_hook_);
    floating_drop_target_hook_ = nullptr;
  }
  g_floating_drop_target_hook.window = nullptr;
  g_floating_drop_target_hook.active = false;
}

LRESULT CALLBACK FlutterWindow::FloatingDropTargetWndProc(
    HWND window, UINT const message, WPARAM const wparam,
    LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(
        window, GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* owner = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (owner != nullptr) {
    return owner->HandleFloatingDropTargetMessage(window, message, wparam,
                                                   lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT FlutterWindow::HandleFloatingDropTargetMessage(
    HWND window, UINT const message, WPARAM const wparam,
    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_HAND));
      return TRUE;
    case WM_ERASEBKGND:
      return TRUE;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      BeginPaint(window, &paint);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      SetCapture(window);
      floating_drop_target_captured_ = true;
      floating_drop_target_dragging_ = false;
      POINT cursor{};
      GetCursorPos(&cursor);
      floating_drop_target_press_point_ = cursor;
      RECT rect{};
      GetWindowRect(window, &rect);
      floating_drop_target_grab_offset_.x = cursor.x - rect.left;
      floating_drop_target_grab_offset_.y = cursor.y - rect.top;
      return 0;
    }
    case WM_MOUSEMOVE: {
      POINT cursor{};
      GetCursorPos(&cursor);
      if (floating_drop_target_captured_) {
        const LONG dx = cursor.x - floating_drop_target_press_point_.x;
        const LONG dy = cursor.y - floating_drop_target_press_point_.y;
        if (!floating_drop_target_dragging_ &&
            (dx > kFloatingDropTargetDragThreshold ||
             dx < -kFloatingDropTargetDragThreshold ||
             dy > kFloatingDropTargetDragThreshold ||
             dy < -kFloatingDropTargetDragThreshold)) {
          floating_drop_target_dragging_ = true;
          // Interrupt any slide; the ball leaves the docked state at once.
          KillTimer(window, kFloatingDropTargetSlideTimer);
          floating_drop_target_sliding_ = false;
          floating_drop_target_slide_finalize_ = false;
          floating_drop_target_snap_ = FloatingTargetSnap::kNone;
          floating_drop_target_expanded_ = false;
          SetFloatingDropTargetGlow(false);
        }
        if (floating_drop_target_dragging_) {
          SetWindowPos(window, nullptr,
                       cursor.x - floating_drop_target_grab_offset_.x,
                       cursor.y - floating_drop_target_grab_offset_.y, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
        return 0;
      }
      floating_drop_target_hover_ = true;
      if (!floating_drop_target_tracking_leave_) {
        TRACKMOUSEEVENT tracking{static_cast<DWORD>(sizeof(tracking)), TME_LEAVE, window, 0};
        TrackMouseEvent(&tracking);
        floating_drop_target_tracking_leave_ = true;
      }
      UpdateFloatingDropTargetExpansion();
      return 0;
    }
    case WM_MOUSELEAVE:
      floating_drop_target_tracking_leave_ = false;
      floating_drop_target_hover_ = false;
      UpdateFloatingDropTargetExpansion();
      return 0;
    case WM_TIMER: {
      if (wparam == kFloatingDropTargetSlideTimer) {
        const DWORD elapsed =
            GetTickCount() - floating_drop_target_slide_start_tick_;
        double progress =
            static_cast<double>(elapsed) / kFloatingDropTargetSlideMs;
        const bool done = progress >= 1.0;
        if (done) {
          progress = 1.0;
        }
        // Ease-out cubic.
        const double ease = 1.0 - std::pow(1.0 - progress, 3.0);
        const int x = floating_drop_target_slide_start_.x +
                      static_cast<int>(
                          (floating_drop_target_slide_target_.x -
                           floating_drop_target_slide_start_.x) *
                          ease);
        const int y = floating_drop_target_slide_start_.y +
                      static_cast<int>(
                          (floating_drop_target_slide_target_.y -
                           floating_drop_target_slide_start_.y) *
                          ease);
        SetWindowPos(window, nullptr, x, y, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        if (done) {
          KillTimer(window, kFloatingDropTargetSlideTimer);
          floating_drop_target_sliding_ = false;
          CompleteFloatingDropTargetSlide();
        }
        return 0;
      }
      if (wparam == kFloatingDropTargetGlowTimer) {
        if (!floating_drop_target_glow_) {
          KillTimer(window, kFloatingDropTargetGlowTimer);
          return 0;
        }
        const DWORD elapsed =
            (GetTickCount() - floating_drop_target_glow_start_) %
            kFloatingDropTargetGlowPeriodMs;
        const double phase = static_cast<double>(elapsed) /
                             kFloatingDropTargetGlowPeriodMs;
        // Pulse between alpha 0.35 and 0.75 over one glow period.
        const double wave =
            0.55 + 0.20 * std::sin(phase * 6.283185307179586);
        UpdateFloatingDropTargetPixels(static_cast<int>(wave * 255.0));
        return 0;
      }
      break;
    }
    case kFloatingDropTargetProximityMessage:
      // Ignore proximity while the ball itself is being dragged.
      if (!floating_drop_target_captured_) {
        SetFloatingDropTargetGlow(wparam != 0);
      }
      return 0;
    case WM_LBUTTONUP:
      if (!floating_drop_target_captured_) {
        return 0;
      }
      ReleaseCapture();
      floating_drop_target_captured_ = false;
      if (floating_drop_target_dragging_) {
        floating_drop_target_dragging_ = false;
        BeginFloatingDropTargetSnap();
        return 0;
      }
      ActivateQuickTag(GetHandle());
      return 0;
    case WM_DROPFILES: {
      const HDROP dropped_files = reinterpret_cast<HDROP>(wparam);
      const UINT count = DragQueryFileW(dropped_files, 0xFFFFFFFF, nullptr, 0);
      std::vector<std::wstring> paths;
      paths.reserve(count);
      for (UINT index = 0; index < count; ++index) {
        const UINT length = DragQueryFileW(dropped_files, index, nullptr, 0);
        if (length == 0) {
          continue;
        }
        std::wstring path(length + 1, L'\0');
        DragQueryFileW(dropped_files, index, path.data(), length + 1);
        path.resize(length);
        paths.push_back(std::move(path));
      }
      DragFinish(dropped_files);
      ActivateExternalQuickTag(GetHandle(), paths);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

bool FlutterWindow::AddTrayIcon(HWND window) {
  NOTIFYICONDATAW tray_icon{};
  tray_icon.cbSize = sizeof(tray_icon);
  tray_icon.hWnd = window;
  tray_icon.uID = kTrayIconId;
  tray_icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_icon.uCallbackMessage = kTrayCallbackMessage;
  tray_icon.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(tray_icon.szTip, kTrayTooltip, _TRUNCATE);
  if (Shell_NotifyIconW(NIM_ADD, &tray_icon) == FALSE) {
    return false;
  }
  tray_icon.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &tray_icon);
  tray_icon_added_ = true;
  tray_window_ = window;
  return true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  NOTIFYICONDATAW tray_icon{};
  tray_icon.cbSize = sizeof(tray_icon);
  tray_icon.hWnd = tray_window_;
  tray_icon.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon);
  tray_icon_added_ = false;
  tray_window_ = nullptr;
}

void FlutterWindow::ShowTrayMenu(HWND window) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayCommandShow, L"Show TAGTAG");
  AppendMenuW(menu, MF_STRING, kTrayCommandQuickTag, L"Quick Tag");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandExit, L"Exit TAGTAG");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  const UINT command = TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, cursor.x, cursor.y,
      0, window, nullptr);
  DestroyMenu(menu);
  PostMessage(window, WM_NULL, 0, 0);
  if (command != 0) {
    HandleTrayCommand(window, command);
  }
}

void FlutterWindow::HandleTrayCommand(HWND window, UINT command) {
  switch (command) {
    case kTrayCommandShow:
      ShowAndActivate(window);
      return;
    case kTrayCommandQuickTag:
      ActivateQuickTag(window);
      return;
    case kTrayCommandExit:
      DestroyWindow(window);
      return;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA) {
    const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (copy_data != nullptr &&
        copy_data->dwData == tagtag::kExplorerPathsCopyDataId) {
      ActivateExternalQuickTag(hwnd, copy_data);
      return 0;
    }
  }

  if (message == kTrayCallbackMessage) {
    switch (LOWORD(lparam)) {
      case WM_CONTEXTMENU:
      case WM_RBUTTONUP:
        ShowTrayMenu(hwnd);
        return 0;
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowAndActivate(hwnd);
        return 0;
    }
  }

  if (message == WM_HOTKEY && wparam == kQuickTagHotkeyId) {
    ActivateQuickTag(hwnd);
    return 0;
  }

  if (message == WM_CLOSE) {
    if (close_to_tray_) {
      ShowWindow(hwnd, SW_HIDE);
    } else {
      DestroyWindow(hwnd);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
