#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  void ShowAndActivate(HWND window);
  void ActivateQuickTag(HWND window);
  void ActivateExternalQuickTag(HWND window, const COPYDATASTRUCT* copy_data);
  void ActivateExternalQuickTag(HWND window,
                                const std::vector<std::wstring>& paths);
  bool AddTrayIcon(HWND window);
  void RemoveTrayIcon();
  void ShowTrayMenu(HWND window);
  void HandleTrayCommand(HWND window, UINT command);
  bool SetFloatingDropTargetEnabled(bool enabled);
  bool SetQuickTagShortcut(UINT modifiers, UINT virtual_key);
  bool CreateFloatingDropTarget();
  void DestroyFloatingDropTarget();
  void ShowFloatingDropTarget();
  static LRESULT CALLBACK FloatingDropTargetWndProc(HWND window,
                                                     UINT message,
                                                     WPARAM wparam,
                                                     LPARAM lparam) noexcept;
  LRESULT HandleFloatingDropTargetMessage(HWND window, UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam) noexcept;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      recycle_bin_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      quick_tag_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      floating_drop_target_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      close_behavior_channel_;
  bool quick_tag_registered_ = false;
  HWND quick_tag_window_ = nullptr;
  UINT quick_tag_modifiers_ = 0x0002 | 0x0004 | 0x4000;
  UINT quick_tag_virtual_key_ = 'T';
  bool tray_icon_added_ = false;
  HWND tray_window_ = nullptr;
  bool floating_drop_target_enabled_ = false;
  HWND floating_drop_target_window_ = nullptr;
  bool floating_drop_target_class_registered_ = false;
  bool close_to_tray_ = true;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
