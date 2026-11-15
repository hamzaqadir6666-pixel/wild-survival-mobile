#pragma once

#define IDI_APP_ICON                101

// Dialog IDs
#define IDD_FTP_MANAGER             201
#define IDD_INPUT_PROMPT            202
#define IDD_ABOUT                   203

// FTP Manager Controls
#define IDC_FTP_LIST                1001
#define IDC_FTP_PROFILE_NAME        1002
#define IDC_FTP_HOST                1003
#define IDC_FTP_PORT                1004
#define IDC_FTP_ANON                1005
#define IDC_FTP_USER                1006
#define IDC_FTP_PASS                1007
#define IDC_FTP_PATH                1008
#define IDC_FTP_PASSIVE             1009
#define IDC_FTP_SAVE_PROFILE        1010
#define IDC_FTP_DELETE_PROFILE      1011
#define IDC_FTP_NEW_PROFILE         1012
#define IDC_FTP_FTPS                1013

// Input Prompt Controls
#define IDC_PROMPT_LABEL            1020
#define IDC_PROMPT_EDIT             1021

// Child Window / Command IDs
#define IDC_NAV_TREE                1101
#define IDC_ADDRESS_EDIT            1102
#define IDC_SEARCH_EDIT             1103
#define IDC_FILE_CANVAS             1104

// Menu / Command IDs
#define IDM_ORG_CUT                 2001
#define IDM_ORG_COPY                2002
#define IDM_ORG_PASTE               2003
#define IDM_ORG_SELECT_ALL          2004
#define IDM_ORG_RENAME              2005
#define IDM_ORG_DELETE              2006
#define IDM_ORG_PROPERTIES          2007
#define IDM_ORG_TOGGLE_NAVPANE      2008
#define IDM_ORG_TOGGLE_DETAILSPANE  2009
#define IDM_ORG_TOGGLE_PREVIEWPANE  2010
#define IDM_ORG_TOGGLE_HIDDEN       2011
#define IDM_ORG_TOGGLE_EXT          2012
#define IDM_ORG_NEW_WINDOW          2013
#define IDM_ORG_CLOSE               2014

#define IDM_CMD_NEW_FOLDER          2020
#define IDM_CMD_NEW_TEXTFILE        2021
#define IDM_CMD_OPEN                2022
#define IDM_CMD_COPY_PATH           2023
#define IDM_CMD_SYS_PROPS           2024
#define IDM_CMD_APPWIZ              2025
#define IDM_CMD_CONTROL_PANEL       2026
#define IDM_CMD_OPEN_CMD_HERE       2027

#define IDM_FTP_CONNECT_DLG         2040
#define IDM_FTP_UPLOAD_FILES        2041
#define IDM_FTP_DOWNLOAD_SEL        2042
#define IDM_FTP_DISCONNECT          2043
#define IDM_FTP_QUICK_BASE          2100 // 2100..2199 saved FTP sites

#define IDM_VIEW_LARGE_ICONS        2201
#define IDM_VIEW_TILES              2202
#define IDM_VIEW_DETAILS            2203
#define IDM_VIEW_LIST               2204
#define IDM_VIEW_CONTENT            2205

#define IDM_VIEW_REFRESH            2206

#define IDM_SORT_NAME               2210
#define IDM_SORT_DATE               2211
#define IDM_SORT_TYPE               2212
#define IDM_SORT_SIZE               2213

#define IDM_HIST_BASE               2300 // 2300..2399 history entries
#define IDM_HELP_ABOUT              2400

// Custom Async Window Messages
#define WM_APP_FTP_LIST_DONE        (WM_APP + 10)
#define WM_APP_FTP_PROGRESS         (WM_APP + 11)
#define WM_APP_FTP_OP_DONE          (WM_APP + 12)
#define WM_APP_ADDRESS_COMMIT       (WM_APP + 13)
#define WM_APP_ADDRESS_CANCEL       (WM_APP + 14)
#define WM_APP_SEARCH_COMMIT        (WM_APP + 15)
