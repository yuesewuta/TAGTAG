#include "flutter_window.h"

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
    ShowFloatingDropTarget();
  } else if (floating_drop_target_window_ != nullptr) {
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
  UpdateFloatingDropTargetPixels();
  return true;
}

// Renders the app icon with per-pixel alpha so the floating target shows
// only the logo, no background disc.
void FlutterWindow::UpdateFloatingDropTargetPixels() {
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
}

void FlutterWindow::ShowFloatingDropTarget() {
  if (floating_drop_target_window_ == nullptr) {
    return;
  }
  RECT work_area{};
  if (SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0) == FALSE) {
    return;
  }
  const int margin = 18;
  SetWindowPos(floating_drop_target_window_, HWND_TOPMOST,
               work_area.right - kFloatingDropTargetSize - margin,
               work_area.bottom - kFloatingDropTargetSize - margin,
               kFloatingDropTargetSize, kFloatingDropTargetSize,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
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
    case WM_LBUTTONUP:
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
