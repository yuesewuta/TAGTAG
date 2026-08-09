#include "flutter_window.h"

#include <optional>
#include <sstream>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
#include "windows_recycle_bin.h"

namespace {

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

std::string HResultDetails(HRESULT status) {
  std::ostringstream stream;
  stream << "HRESULT 0x" << std::hex << static_cast<unsigned long>(status);
  return stream.str();
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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  recycle_bin_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
