#include "windows_recycle_bin.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <atomic>
#include <filesystem>
#include <string>
#include <vector>

namespace tagtag {
namespace {

using Microsoft::WRL::ComPtr;

std::wstring EncodePidl(PCIDLIST_ABSOLUTE pidl) {
  if (pidl == nullptr) {
    return std::wstring();
  }
  const UINT byte_count = ILGetSize(pidl);
  if (byte_count == 0) {
    return std::wstring();
  }
  constexpr wchar_t kHex[] = L"0123456789abcdef";
  const auto* bytes = reinterpret_cast<const unsigned char*>(pidl);
  std::wstring token = L"pidl:";
  token.reserve(5 + static_cast<size_t>(byte_count) * 2);
  for (UINT index = 0; index < byte_count; ++index) {
    token.push_back(kHex[bytes[index] >> 4]);
    token.push_back(kHex[bytes[index] & 0x0f]);
  }
  return token;
}

int HexValue(wchar_t value) {
  if (value >= L'0' && value <= L'9') {
    return value - L'0';
  }
  if (value >= L'a' && value <= L'f') {
    return value - L'a' + 10;
  }
  if (value >= L'A' && value <= L'F') {
    return value - L'A' + 10;
  }
  return -1;
}

PIDLIST_ABSOLUTE DecodePidl(const std::wstring& token) {
  constexpr wchar_t kPrefix[] = L"pidl:";
  if (token.rfind(kPrefix, 0) != 0) {
    return nullptr;
  }
  const size_t hex_length = token.size() - 5;
  if (hex_length == 0 || hex_length % 2 != 0) {
    return nullptr;
  }
  const size_t byte_count = hex_length / 2;
  auto* pidl = static_cast<PIDLIST_ABSOLUTE>(
      ::CoTaskMemAlloc(byte_count));
  if (pidl == nullptr) {
    return nullptr;
  }
  auto* bytes = reinterpret_cast<unsigned char*>(pidl);
  for (size_t index = 0; index < byte_count; ++index) {
    const int high = HexValue(token[5 + index * 2]);
    const int low = HexValue(token[6 + index * 2]);
    if (high < 0 || low < 0) {
      ::CoTaskMemFree(pidl);
      return nullptr;
    }
    bytes[index] = static_cast<unsigned char>((high << 4) | low);
  }
  return pidl;
}

class DeleteProgressSink final : public IFileOperationProgressSink {
 public:
  DeleteProgressSink() = default;

  const std::wstring& token() const { return token_; }
  HRESULT delete_status() const { return delete_status_; }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,
                                           void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_IFileOperationProgressSink) {
      *object = static_cast<IFileOperationProgressSink*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ++reference_count_; }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --reference_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE StartOperations() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR,
                                           HRESULT, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD, IShellItem*, IShellItem*,
                                       LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*,
                                        LPCWSTR, HRESULT,
                                        IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*,
                                       LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*,
                                        LPCWSTR, HRESULT,
                                        IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*,
                                           HRESULT delete_status,
                                           IShellItem* recycled_item) override {
    delete_status_ = delete_status;
    if (FAILED(delete_status) || recycled_item == nullptr) {
      return S_OK;
    }
    PIDLIST_ABSOLUTE pidl = nullptr;
    const HRESULT status = ::SHGetIDListFromObject(recycled_item, &pidl);
    if (SUCCEEDED(status) && pidl != nullptr) {
      token_ = EncodePidl(pidl);
      ::CoTaskMemFree(pidl);
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR,
                                       DWORD, HRESULT, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE UpdateProgress(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }

 private:
  ~DeleteProgressSink() = default;

  std::atomic<ULONG> reference_count_{1};
  HRESULT delete_status_ = E_FAIL;
  std::wstring token_;
};

HRESULT CreateFileOperation(ComPtr<IFileOperation>* operation) {
  const HRESULT status = ::CoCreateInstance(
      CLSID_FileOperation, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(operation->ReleaseAndGetAddressOf()));
  if (FAILED(status)) {
    return status;
  }
  return (*operation)->SetOperationFlags(
      FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT |
      FOFX_RECYCLEONDELETE);
}

HRESULT PerformFileOperation(IFileOperation* operation) {
  HRESULT status = operation->PerformOperations();
  if (FAILED(status)) {
    return status;
  }
  BOOL aborted = FALSE;
  status = operation->GetAnyOperationsAborted(&aborted);
  if (FAILED(status)) {
    return status;
  }
  return aborted ? HRESULT_FROM_WIN32(ERROR_CANCELLED) : S_OK;
}

}  // namespace

RecycleBinResult MoveToRecycleBin(const std::wstring& resource_path) {
  ComPtr<IShellItem> source;
  HRESULT status = ::SHCreateItemFromParsingName(
      resource_path.c_str(), nullptr, IID_PPV_ARGS(&source));
  if (FAILED(status)) {
    return {status, std::wstring()};
  }

  ComPtr<IFileOperation> operation;
  status = CreateFileOperation(&operation);
  if (FAILED(status)) {
    return {status, std::wstring()};
  }

  auto* sink = new DeleteProgressSink();
  status = operation->DeleteItem(source.Get(), sink);
  if (SUCCEEDED(status)) {
    status = PerformFileOperation(operation.Get());
  }
  if (SUCCEEDED(status) && FAILED(sink->delete_status())) {
    status = sink->delete_status();
  }
  const std::wstring token = sink->token();
  sink->Release();
  if (SUCCEEDED(status) && token.empty()) {
    status = HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
  }
  return {status, token};
}

HRESULT RestoreFromRecycleBin(const std::wstring& token,
                              const std::wstring& destination_path) {
  PIDLIST_ABSOLUTE pidl = DecodePidl(token);
  if (pidl == nullptr) {
    return E_INVALIDARG;
  }
  ComPtr<IShellItem> recycled_item;
  HRESULT status = ::SHCreateItemFromIDList(
      pidl, IID_PPV_ARGS(&recycled_item));
  ::CoTaskMemFree(pidl);
  if (FAILED(status)) {
    return status;
  }

  const std::filesystem::path destination(destination_path);
  ComPtr<IShellItem> destination_folder;
  status = ::SHCreateItemFromParsingName(
      destination.parent_path().c_str(), nullptr,
      IID_PPV_ARGS(&destination_folder));
  if (FAILED(status)) {
    return status;
  }

  ComPtr<IFileOperation> operation;
  status = CreateFileOperation(&operation);
  if (FAILED(status)) {
    return status;
  }
  status = operation->MoveItem(recycled_item.Get(), destination_folder.Get(),
                               destination.filename().c_str(), nullptr);
  if (FAILED(status)) {
    return status;
  }
  return PerformFileOperation(operation.Get());
}

}  // namespace tagtag
