#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commctrl.h>
#include <commoncontrols.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <string>
#include <unordered_map>
#include "../common/path_ftp_utils.h"

namespace aero {

// Some MinGW import libraries omit these shell GUIDs; supply the documented values.
static const GUID kIIDIImageList =
    { 0x46EB5926, 0x582E, 0x4017, { 0x9F, 0xDF, 0xE8, 0x99, 0x8D, 0xAA, 0x09, 0x50 } };

static const GUID kIIDIShellItemImageFactory =
    { 0xBCC18B79, 0xBA16, 0x442F, { 0x80, 0xC4, 0x8A, 0x59, 0xC3, 0x0C, 0x46, 0x3B } };

struct CachedFileVisuals {
    HICON iconSmall = nullptr; // 16x16
    HICON iconLarge = nullptr; // 48x48 (or 32x32 fallback)
    std::wstring typeName;
};

class ShellIconCache {
public:
    ShellIconCache() = default;

    ~ShellIconCache() {
        Clear();
    }

    void Initialize(HINSTANCE hInst, int appIconResId) {
        hAppIconSmall_ = static_cast<HICON>(LoadImageW(
            hInst, MAKEINTRESOURCEW(appIconResId), IMAGE_ICON, 16, 16, LR_DEFAULTCOLOR));
        hAppIconLarge_ = static_cast<HICON>(LoadImageW(
            hInst, MAKEINTRESOURCEW(appIconResId), IMAGE_ICON, 48, 48, LR_DEFAULTCOLOR));

        // Obtain 48x48 extra-large system image list for Windows 7 Tiles/Computer drives
        SHGetImageList(SHIL_EXTRALARGE, kIIDIImageList, reinterpret_cast<void**>(&extraLargeList_));

        InitStockIcons();
    }

    void Clear() {
        for (auto& kv : byKey_) {
            if (kv.second.iconSmall) DestroyIcon(kv.second.iconSmall);
            if (kv.second.iconLarge) DestroyIcon(kv.second.iconLarge);
        }
        byKey_.clear();
        if (extraLargeList_) {
            extraLargeList_->Release();
            extraLargeList_ = nullptr;
        }
        if (stockComputerSmall_) DestroyIcon(stockComputerSmall_);
        if (stockComputerLarge_) DestroyIcon(stockComputerLarge_);
        if (stockNetworkSmall_) DestroyIcon(stockNetworkSmall_);
        if (stockNetworkLarge_) DestroyIcon(stockNetworkLarge_);
        if (stockFavoritesSmall_) DestroyIcon(stockFavoritesSmall_);
        if (hAppIconSmall_) DestroyIcon(hAppIconSmall_);
        if (hAppIconLarge_) DestroyIcon(hAppIconLarge_);
    }

    HICON GetComputerIconSmall() const { return stockComputerSmall_ ? stockComputerSmall_ : hAppIconSmall_; }
    HICON GetComputerIconLarge() const { return stockComputerLarge_ ? stockComputerLarge_ : hAppIconLarge_; }
    HICON GetNetworkIconSmall() const { return stockNetworkSmall_ ? stockNetworkSmall_ : hAppIconSmall_; }
    HICON GetNetworkIconLarge() const { return stockNetworkLarge_ ? stockNetworkLarge_ : hAppIconLarge_; }
    HICON GetFavoritesIconSmall() const { return stockFavoritesSmall_ ? stockFavoritesSmall_ : hAppIconSmall_; }

    CachedFileVisuals GetForVirtualFolder() {
        auto it = byKey_.find(L"__DIR__");
        if (it != byKey_.end()) return it->second;

        CachedFileVisuals vis = QueryShellInfo(L"Folder", FILE_ATTRIBUTE_DIRECTORY, true);
        if (vis.typeName.empty()) vis.typeName = L"File folder";
        byKey_[L"__DIR__"] = vis;
        return vis;
    }

    CachedFileVisuals GetForLocalItem(const std::wstring& fullPath, const std::wstring& name, bool isDir, bool isDrive) {
        if (isDrive) {
            std::wstring key = L"__DRIVE__" + ToLowerW(fullPath);
            auto it = byKey_.find(key);
            if (it != byKey_.end()) return it->second;
            CachedFileVisuals vis = QueryShellInfo(fullPath, FILE_ATTRIBUTE_DIRECTORY, false);
            if (vis.typeName.empty()) vis.typeName = L"Local Disk";
            byKey_[key] = vis;
            return vis;
        }

        if (isDir) {
            // Check special shell folders (Desktop, Downloads, Pictures, etc.) per-path up to a modest cap
            if (byKey_.size() < 512) {
                std::wstring key = L"__SPECIALDIR__" + ToLowerW(fullPath);
                auto it = byKey_.find(key);
                if (it != byKey_.end()) return it->second;
                CachedFileVisuals vis = QueryShellInfo(fullPath, FILE_ATTRIBUTE_DIRECTORY, false);
                if (vis.iconSmall && vis.iconLarge) {
                    if (vis.typeName.empty()) vis.typeName = L"File folder";
                    byKey_[key] = vis;
                    return vis;
                }
            }
            return GetForVirtualFolder();
        }

        std::wstring ext = ExtractExtensionLower(name);
        // Per-file icon for .exe, .ico, .lnk, .scr
        if ((ext == L".exe" || ext == L".ico" || ext == L".lnk") && byKey_.size() < 600) {
            std::wstring key = L"__FILE__" + ToLowerW(fullPath);
            auto it = byKey_.find(key);
            if (it != byKey_.end()) return it->second;
            CachedFileVisuals vis = QueryShellInfo(fullPath, FILE_ATTRIBUTE_NORMAL, false);
            byKey_[key] = vis;
            return vis;
        }

        return GetForExtension(ext, name);
    }

    CachedFileVisuals GetForRemoteFtpItem(const std::wstring& name, bool isDir) {
        if (isDir) {
            return GetForVirtualFolder();
        }
        std::wstring ext = ExtractExtensionLower(name);
        return GetForExtension(ext, name);
    }

private:
    IImageList* extraLargeList_ = nullptr;
    HICON hAppIconSmall_ = nullptr;
    HICON hAppIconLarge_ = nullptr;
    HICON stockComputerSmall_ = nullptr;
    HICON stockComputerLarge_ = nullptr;
    HICON stockNetworkSmall_ = nullptr;
    HICON stockNetworkLarge_ = nullptr;
    HICON stockFavoritesSmall_ = nullptr;
    std::unordered_map<std::wstring, CachedFileVisuals> byKey_;

    static std::wstring ExtractExtensionLower(const std::wstring& name) {
        size_t dot = name.rfind(L'.');
        if (dot == std::wstring::npos || dot == 0 || dot + 1 >= name.size()) {
            return L"__NOEXT__";
        }
        return ToLowerW(name.substr(dot));
    }

    CachedFileVisuals GetForExtension(const std::wstring& extLower, const std::wstring& sampleName) {
        std::wstring key = L"__EXT__" + extLower;
        auto it = byKey_.find(key);
        if (it != byKey_.end()) return it->second;

        std::wstring probe = (extLower == L"__NOEXT__") ? L"file" : (L"sample" + extLower);
        if (!sampleName.empty() && extLower == L"__NOEXT__") probe = sampleName;

        CachedFileVisuals vis = QueryShellInfo(probe, FILE_ATTRIBUTE_NORMAL, true);
        if (vis.typeName.empty()) {
            vis.typeName = (extLower == L"__NOEXT__") ? L"File" : (extLower.substr(1) + L" File");
        }
        byKey_[key] = vis;
        return vis;
    }

    // Resolve a crisp 48x48 icon. For real files we ask the shell thumbnail/icon
    // factory (Vista+); otherwise fall back to the extra-large system image list.
    HICON LoadLargeIcon(const std::wstring& pathOrDummy, DWORD attrs, bool useFileAttrs) {
        if (!useFileAttrs) {
            IShellItemImageFactory* factory = nullptr;
            if (SUCCEEDED(SHCreateItemFromParsingName(pathOrDummy.c_str(), nullptr,
                                                      kIIDIShellItemImageFactory,
                                                      reinterpret_cast<void**>(&factory))) &&
                factory) {
                SIZE size = { 48, 48 };
                HBITMAP bmp = nullptr;
                if (SUCCEEDED(factory->GetImage(size, SIIGBF_ICONONLY, &bmp)) && bmp) {
                    HICON icon = IconFromBitmap(bmp);
                    DeleteObject(bmp);
                    factory->Release();
                    if (icon) return icon;
                } else {
                    factory->Release();
                }
            }
        }

        // Ask for the index in the large (32x32) system list and reuse it on the
        // extra-large list; the shell builds both lists in the same index order.
        SHFILEINFOW sfi = {};
        UINT flags = SHGFI_SYSICONINDEX | (useFileAttrs ? SHGFI_USEFILEATTRIBUTES : 0);
        if (SHGetFileInfoW(pathOrDummy.c_str(), attrs, &sfi, sizeof(sfi), flags) && extraLargeList_) {
            HICON hxl = nullptr;
            if (SUCCEEDED(extraLargeList_->GetIcon(sfi.iIcon, ILD_TRANSPARENT, &hxl)) && hxl) {
                return hxl;
            }
        }

        SHFILEINFOW large = {};
        if (SHGetFileInfoW(pathOrDummy.c_str(), attrs, &large, sizeof(large),
                           (useFileAttrs ? SHGFI_USEFILEATTRIBUTES : 0) | SHGFI_ICON | SHGFI_LARGEICON)) {
            return large.hIcon;
        }
        return nullptr;
    }

    static HICON IconFromBitmap(HBITMAP colorBitmap) {
        BITMAP bm = {};
        if (!GetObjectW(colorBitmap, sizeof(bm), &bm) || bm.bmWidth <= 0 || bm.bmHeight <= 0) {
            return nullptr;
        }
        HBITMAP mask = CreateBitmap(bm.bmWidth, bm.bmHeight, 1, 1, nullptr);
        if (!mask) return nullptr;
        ICONINFO info = {};
        info.fIcon = TRUE;
        info.hbmColor = colorBitmap;
        info.hbmMask = mask;
        HICON icon = CreateIconIndirect(&info);
        DeleteObject(mask);
        return icon;
    }

    CachedFileVisuals QueryShellInfo(const std::wstring& pathOrDummy, DWORD attrs, bool useFileAttrs) {
        CachedFileVisuals out;
        UINT baseFlags = SHGFI_TYPENAME | (useFileAttrs ? SHGFI_USEFILEATTRIBUTES : 0);

        SHFILEINFOW sfiSmall = {};
        if (SHGetFileInfoW(pathOrDummy.c_str(), attrs, &sfiSmall, sizeof(sfiSmall),
                           baseFlags | SHGFI_ICON | SHGFI_SMALLICON)) {
            out.iconSmall = sfiSmall.hIcon;
            out.typeName = sfiSmall.szTypeName;
        }
        if (out.typeName.empty()) {
            SHFILEINFOW sfiType = {};
            if (SHGetFileInfoW(pathOrDummy.c_str(), attrs, &sfiType, sizeof(sfiType), baseFlags)) {
                out.typeName = sfiType.szTypeName;
            }
        }

        out.iconLarge = LoadLargeIcon(pathOrDummy, attrs, useFileAttrs);
        return out;
    }

    void InitStockIcons() {
        SHSTOCKICONINFO sii = {};
        sii.cbSize = sizeof(sii);
        if (SUCCEEDED(SHGetStockIconInfo(SIID_DESKTOPPC, SHGSI_ICON | SHGSI_SMALLICON, &sii))) {
            stockComputerSmall_ = sii.hIcon;
        }
        sii = {};
        sii.cbSize = sizeof(sii);
        if (SUCCEEDED(SHGetStockIconInfo(SIID_DESKTOPPC, SHGSI_ICON | SHGSI_LARGEICON, &sii))) {
            stockComputerLarge_ = sii.hIcon;
        }
        sii = {};
        sii.cbSize = sizeof(sii);
        if (SUCCEEDED(SHGetStockIconInfo(SIID_WORLD, SHGSI_ICON | SHGSI_SMALLICON, &sii))) {
            stockNetworkSmall_ = sii.hIcon;
        }
        sii = {};
        sii.cbSize = sizeof(sii);
        if (SUCCEEDED(SHGetStockIconInfo(SIID_WORLD, SHGSI_ICON | SHGSI_LARGEICON, &sii))) {
            stockNetworkLarge_ = sii.hIcon;
        }
        // Star/Favorites icon from shell32.dll (index 43 is classic Windows star/favorites)
        ExtractIconExW(L"shell32.dll", 43, nullptr, &stockFavoritesSmall_, 1);
    }
};

} // namespace aero
