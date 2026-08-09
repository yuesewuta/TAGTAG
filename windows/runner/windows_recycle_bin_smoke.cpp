#include <windows.h>

#include <filesystem>
#include <iostream>
#include <string>

#include "windows_recycle_bin.h"

namespace {

bool RoundTrip(const std::wstring& resource_path) {
  const tagtag::RecycleBinResult recycled =
      tagtag::MoveToRecycleBin(resource_path);
  if (FAILED(recycled.status) || recycled.token.empty() ||
      std::filesystem::exists(resource_path)) {
    return false;
  }
  const HRESULT restore_status =
      tagtag::RestoreFromRecycleBin(recycled.token, resource_path);
  return SUCCEEDED(restore_status) && std::filesystem::exists(resource_path);
}

}  // namespace

int wmain() {
  const HRESULT com_status =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_status)) {
    std::wcerr << L"COM initialization failed" << std::endl;
    return 1;
  }

  wchar_t temporary_directory[MAX_PATH] = {};
  wchar_t temporary_file[MAX_PATH] = {};
  if (::GetTempPathW(MAX_PATH, temporary_directory) == 0 ||
      ::GetTempFileNameW(temporary_directory, L"ttg", 0, temporary_file) ==
          0) {
    ::CoUninitialize();
    return 2;
  }
  const std::wstring resource_path(temporary_file);

  if (!RoundTrip(resource_path)) {
    std::wcerr << L"File Recycle Bin round trip failed" << std::endl;
    ::DeleteFileW(resource_path.c_str());
    ::CoUninitialize();
    return 3;
  }

  const std::filesystem::path folder_path =
      std::filesystem::path(temporary_directory) /
      (L"tagtag-recycle-folder-" + std::to_wstring(::GetCurrentProcessId()));
  const std::filesystem::path nested_path = folder_path / L"nested";
  std::filesystem::create_directories(nested_path);
  const std::filesystem::path nested_file = nested_path / L"note.txt";
  HANDLE nested_handle = ::CreateFileW(
      nested_file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (nested_handle == INVALID_HANDLE_VALUE) {
    std::filesystem::remove_all(folder_path);
    ::DeleteFileW(resource_path.c_str());
    ::CoUninitialize();
    return 4;
  }
  ::CloseHandle(nested_handle);

  if (!RoundTrip(folder_path.wstring()) ||
      !std::filesystem::exists(nested_file)) {
    std::wcerr << L"Folder Recycle Bin round trip failed" << std::endl;
    std::filesystem::remove_all(folder_path);
    ::DeleteFileW(resource_path.c_str());
    ::CoUninitialize();
    return 5;
  }

  std::filesystem::remove_all(folder_path);
  ::DeleteFileW(resource_path.c_str());
  ::CoUninitialize();
  std::wcout << L"GREEN: Windows Recycle Bin file and folder round trips passed"
             << std::endl;
  return 0;
}
