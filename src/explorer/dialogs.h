#pragma once

#include <windows.h>
#include <string>
#include <vector>

#include "../common/path_ftp_utils.h"
#include "ftp_client.h"
#include "models.h"
#include "resource.h"

namespace aero {

struct InputPromptState {
    std::wstring windowTitle;
    std::wstring promptLabel;
    std::wstring value;
};

inline std::wstring GetDlgItemString(HWND hDlg, int id) {
    HWND hCtrl = GetDlgItem(hDlg, id);
    if (!hCtrl) return L"";
    int len = GetWindowTextLengthW(hCtrl);
    if (len <= 0) return L"";
    std::wstring s(static_cast<size_t>(len) + 1, L'\0');
    GetWindowTextW(hCtrl, &s[0], len + 1);
    s.resize(static_cast<size_t>(len));
    return s;
}

inline INT_PTR CALLBACK InputPromptDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* st = reinterpret_cast<InputPromptState*>(GetWindowLongPtrW(hDlg, GWLP_USERDATA));
    switch (msg) {
        case WM_INITDIALOG: {
            st = reinterpret_cast<InputPromptState*>(lParam);
            SetWindowLongPtrW(hDlg, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));
            if (st) {
                if (!st->windowTitle.empty()) SetWindowTextW(hDlg, st->windowTitle.c_str());
                SetDlgItemTextW(hDlg, IDC_PROMPT_LABEL, st->promptLabel.c_str());
                SetDlgItemTextW(hDlg, IDC_PROMPT_EDIT, st->value.c_str());
                SendDlgItemMessageW(hDlg, IDC_PROMPT_EDIT, EM_SETSEL, 0, -1);
            }
            return TRUE;
        }
        case WM_COMMAND: {
            switch (LOWORD(wParam)) {
                case IDOK: {
                    if (st) {
                        st->value = TrimW(GetDlgItemString(hDlg, IDC_PROMPT_EDIT));
                    }
                    EndDialog(hDlg, IDOK);
                    return TRUE;
                }
                case IDCANCEL:
                    EndDialog(hDlg, IDCANCEL);
                    return TRUE;
            }
            break;
        }
    }
    return FALSE;
}

inline bool ShowInputPromptDialog(HINSTANCE hInst,
                                  HWND hParent,
                                  const std::wstring& title,
                                  const std::wstring& label,
                                  std::wstring& inOutValue) {
    InputPromptState st{ title, label, inOutValue };
    INT_PTR res = DialogBoxParamW(hInst, MAKEINTRESOURCEW(IDD_INPUT_PROMPT), hParent,
                                  InputPromptDlgProc, reinterpret_cast<LPARAM>(&st));
    if (res == IDOK && !st.value.empty()) {
        inOutValue = st.value;
        return true;
    }
    return false;
}

inline INT_PTR CALLBACK AboutDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM) {
    if (msg == WM_INITDIALOG) return TRUE;
    if (msg == WM_COMMAND && (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)) {
        EndDialog(hDlg, LOWORD(wParam));
        return TRUE;
    }
    return FALSE;
}

inline void ShowAboutDialog(HINSTANCE hInst, HWND hParent) {
    DialogBoxParamW(hInst, MAKEINTRESOURCEW(IDD_ABOUT), hParent, AboutDlgProc, 0);
}

struct FtpManagerDialogState {
    std::vector<FtpSiteProfile> profiles;
    int selectedIdx = -1;
    FtpUrlInfo resultTarget;
    bool profilesModified = false;
};

inline void PopulateFtpFieldsFromProfile(HWND hDlg, const FtpSiteProfile& p) {
    SetDlgItemTextW(hDlg, IDC_FTP_PROFILE_NAME, p.title.c_str());
    SetDlgItemTextW(hDlg, IDC_FTP_HOST, p.host.c_str());
    SetDlgItemInt(hDlg, IDC_FTP_PORT, p.port, FALSE);
    CheckDlgButton(hDlg, IDC_FTP_ANON, p.anonymous ? BST_CHECKED : BST_UNCHECKED);
    SetDlgItemTextW(hDlg, IDC_FTP_USER, p.anonymous ? L"anonymous" : p.username.c_str());
    SetDlgItemTextW(hDlg, IDC_FTP_PASS, p.anonymous ? L"" : p.password.c_str());
    SetDlgItemTextW(hDlg, IDC_FTP_PATH, p.initialPath.empty() ? L"/" : p.initialPath.c_str());
    CheckDlgButton(hDlg, IDC_FTP_PASSIVE, p.passive ? BST_CHECKED : BST_UNCHECKED);
    CheckDlgButton(hDlg, IDC_FTP_FTPS, p.useFtps ? BST_CHECKED : BST_UNCHECKED);

    EnableWindow(GetDlgItem(hDlg, IDC_FTP_USER), !p.anonymous);
    EnableWindow(GetDlgItem(hDlg, IDC_FTP_PASS), !p.anonymous);
}

inline FtpSiteProfile ReadFtpFieldsFromDialog(HWND hDlg) {
    FtpSiteProfile p;
    p.title = TrimW(GetDlgItemString(hDlg, IDC_FTP_PROFILE_NAME));
    std::wstring rawHost = TrimW(GetDlgItemString(hDlg, IDC_FTP_HOST));

    // If user pasted full ftp:// URL into Host field, smartly extract components!
    if (IsFtpUrl(rawHost)) {
        FtpUrlInfo parsed = ParseFtpUrl(rawHost);
        if (parsed.valid) {
            p.host = parsed.host;
            p.port = parsed.port;
            p.useFtps = parsed.useFtps;
            if (parsed.explicitCredentials) {
                p.anonymous = false;
                p.username = parsed.username;
                p.password = parsed.password;
            }
            p.initialPath = parsed.remotePath;
            if (p.title.empty()) p.title = p.host;
            p.passive = IsDlgButtonChecked(hDlg, IDC_FTP_PASSIVE) == BST_CHECKED;
            return p;
        }
    }

    p.host = rawHost;
    BOOL portOk = FALSE;
    UINT portVal = GetDlgItemInt(hDlg, IDC_FTP_PORT, &portOk, FALSE);
    p.port = (portOk && portVal > 0 && portVal <= 65535) ? static_cast<uint16_t>(portVal) : 21;
    p.anonymous = IsDlgButtonChecked(hDlg, IDC_FTP_ANON) == BST_CHECKED;
    p.username = p.anonymous ? L"anonymous" : TrimW(GetDlgItemString(hDlg, IDC_FTP_USER));
    if (p.username.empty()) p.username = L"anonymous";
    p.password = p.anonymous ? L"anonymous@aeroexplorer.local" : GetDlgItemString(hDlg, IDC_FTP_PASS);
    p.initialPath = NormalizeFtpPath(TrimW(GetDlgItemString(hDlg, IDC_FTP_PATH)));
    p.passive = IsDlgButtonChecked(hDlg, IDC_FTP_PASSIVE) == BST_CHECKED;
    p.useFtps = IsDlgButtonChecked(hDlg, IDC_FTP_FTPS) == BST_CHECKED;
    if (p.title.empty()) p.title = p.host;
    return p;
}

inline void RefreshFtpListbox(HWND hDlg, FtpManagerDialogState* st) {
    HWND hList = GetDlgItem(hDlg, IDC_FTP_LIST);
    SendMessageW(hList, LB_RESETCONTENT, 0, 0);
    for (const auto& p : st->profiles) {
        std::wstring label = p.title.empty() ? p.host : p.title;
        SendMessageW(hList, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label.c_str()));
    }
    if (st->selectedIdx >= 0 && st->selectedIdx < static_cast<int>(st->profiles.size())) {
        SendMessageW(hList, LB_SETCURSEL, st->selectedIdx, 0);
    }
}

inline INT_PTR CALLBACK FtpManagerDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* st = reinterpret_cast<FtpManagerDialogState*>(GetWindowLongPtrW(hDlg, GWLP_USERDATA));
    switch (msg) {
        case WM_INITDIALOG: {
            st = reinterpret_cast<FtpManagerDialogState*>(lParam);
            SetWindowLongPtrW(hDlg, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));
            if (st) {
                if (!st->profiles.empty()) {
                    st->selectedIdx = 0;
                    RefreshFtpListbox(hDlg, st);
                    PopulateFtpFieldsFromProfile(hDlg, st->profiles[0]);
                } else {
                    FtpSiteProfile blank;
                    blank.anonymous = false;
                    blank.username = L"";
                    blank.password = L"";
                    PopulateFtpFieldsFromProfile(hDlg, blank);
                }
            }
            return TRUE;
        }
        case WM_COMMAND: {
            if (!st) break;
            WORD id = LOWORD(wParam);
            WORD code = HIWORD(wParam);

            if (id == IDC_FTP_LIST && code == LBN_SELCHANGE) {
                int sel = static_cast<int>(SendDlgItemMessageW(hDlg, IDC_FTP_LIST, LB_GETCURSEL, 0, 0));
                if (sel >= 0 && sel < static_cast<int>(st->profiles.size())) {
                    st->selectedIdx = sel;
                    PopulateFtpFieldsFromProfile(hDlg, st->profiles[sel]);
                }
                return TRUE;
            }
            if (id == IDC_FTP_LIST && code == LBN_DBLCLK) {
                SendMessageW(hDlg, WM_COMMAND, MAKEWPARAM(IDOK, BN_CLICKED), 0);
                return TRUE;
            }
            if (id == IDC_FTP_ANON) {
                bool anon = IsDlgButtonChecked(hDlg, IDC_FTP_ANON) == BST_CHECKED;
                EnableWindow(GetDlgItem(hDlg, IDC_FTP_USER), !anon);
                EnableWindow(GetDlgItem(hDlg, IDC_FTP_PASS), !anon);
                if (anon) {
                    SetDlgItemTextW(hDlg, IDC_FTP_USER, L"anonymous");
                }
                return TRUE;
            }
            if (id == IDC_FTP_NEW_PROFILE) {
                st->selectedIdx = -1;
                SendDlgItemMessageW(hDlg, IDC_FTP_LIST, LB_SETCURSEL, static_cast<WPARAM>(-1), 0);
                FtpSiteProfile fresh;
                fresh.title = L"My FTP Server";
                fresh.host = L"";
                fresh.port = 21;
                fresh.anonymous = false;
                fresh.username = L"";
                fresh.password = L"";
                fresh.initialPath = L"/";
                fresh.passive = true;
                PopulateFtpFieldsFromProfile(hDlg, fresh);
                SetFocus(GetDlgItem(hDlg, IDC_FTP_HOST));
                return TRUE;
            }
            if (id == IDC_FTP_SAVE_PROFILE) {
                FtpSiteProfile cur = ReadFtpFieldsFromDialog(hDlg);
                if (cur.host.empty()) {
                    MessageBoxW(hDlg, L"Please enter an FTP server hostname or IP address.",
                                L"FTP Connection Manager", MB_ICONWARNING | MB_OK);
                    return TRUE;
                }
                if (st->selectedIdx >= 0 && st->selectedIdx < static_cast<int>(st->profiles.size())) {
                    st->profiles[st->selectedIdx] = cur;
                } else {
                    st->profiles.push_back(cur);
                    st->selectedIdx = static_cast<int>(st->profiles.size()) - 1;
                }
                AeroFtpClient::SaveProfiles(st->profiles);
                st->profilesModified = true;
                RefreshFtpListbox(hDlg, st);
                return TRUE;
            }
            if (id == IDC_FTP_DELETE_PROFILE) {
                if (st->selectedIdx >= 0 && st->selectedIdx < static_cast<int>(st->profiles.size())) {
                    st->profiles.erase(st->profiles.begin() + st->selectedIdx);
                    if (st->selectedIdx >= static_cast<int>(st->profiles.size())) {
                        st->selectedIdx = static_cast<int>(st->profiles.size()) - 1;
                    }
                    AeroFtpClient::SaveProfiles(st->profiles);
                    st->profilesModified = true;
                    RefreshFtpListbox(hDlg, st);
                    if (st->selectedIdx >= 0) {
                        PopulateFtpFieldsFromProfile(hDlg, st->profiles[st->selectedIdx]);
                    }
                }
                return TRUE;
            }
            if (id == IDOK) {
                FtpSiteProfile cur = ReadFtpFieldsFromDialog(hDlg);
                if (cur.host.empty()) {
                    MessageBoxW(hDlg, L"Please enter an FTP Host / IP address to connect.",
                                L"FTP Connection Manager", MB_ICONWARNING | MB_OK);
                    SetFocus(GetDlgItem(hDlg, IDC_FTP_HOST));
                    return TRUE;
                }
                st->resultTarget.valid = true;
                st->resultTarget.host = cur.host;
                st->resultTarget.port = cur.port;
                st->resultTarget.passive = cur.passive;
                st->resultTarget.useFtps = cur.useFtps;
                st->resultTarget.username = cur.username;
                st->resultTarget.password = cur.password;
                st->resultTarget.explicitCredentials = !cur.anonymous;
                st->resultTarget.remotePath = cur.initialPath;
                EndDialog(hDlg, IDOK);
                return TRUE;
            }
            if (id == IDCANCEL) {
                EndDialog(hDlg, IDCANCEL);
                return TRUE;
            }
            break;
        }
    }
    return FALSE;
}

inline bool ShowFtpManagerDialog(HINSTANCE hInst,
                                 HWND hParent,
                                 std::vector<FtpSiteProfile>& inOutProfiles,
                                 FtpUrlInfo& outTarget,
                                 bool& outProfilesChanged) {
    FtpManagerDialogState st;
    st.profiles = inOutProfiles;
    INT_PTR res = DialogBoxParamW(hInst, MAKEINTRESOURCEW(IDD_FTP_MANAGER), hParent,
                                  FtpManagerDlgProc, reinterpret_cast<LPARAM>(&st));
    outProfilesChanged = st.profilesModified;
    if (st.profilesModified) {
        inOutProfiles = st.profiles;
    }
    if (res == IDOK && st.resultTarget.valid) {
        outTarget = st.resultTarget;
        return true;
    }
    return false;
}

} // namespace aero
