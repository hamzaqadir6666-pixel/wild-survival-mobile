# Windows 7 Aero Explorer for Windows 10 &amp; 11

A native, dependency-free re-creation of the Windows 7 File Explorer chrome, built for
Windows 10 / 11 x64 — **with first-class FTP support**. No Electron, no .NET runtime, no
installation framework: two small Win32 executables cross-compiled from C++17.

| Deliverable | Path | Size | What it is |
| --- | --- | --- | --- |
| Explorer | [`releases/AeroExplorer.exe`](releases/AeroExplorer.exe) | ~1.2 MB | The portable file manager |
| Setup wizard | [`releases/AeroExplorerSetup.exe`](releases/AeroExplorerSetup.exe) | ~1.6 MB | Windows 7 style installer with the app embedded |
| Uninstaller | [`releases/Uninstall.exe`](releases/Uninstall.exe) | ~0.45 MB | Standalone removal tool (also installed by Setup) |
| Portable bundle | [`releases/AeroExplorer-portable.zip`](releases/AeroExplorer-portable.zip) | ~0.7 MB | Explorer + Uninstaller + this README |
| Checksums | [`releases/SHA256SUMS.txt`](releases/SHA256SUMS.txt) | — | SHA-256 of every artifact |

> SmartScreen will warn because the binaries are not code-signed: **More info → Run anyway**,
> or verify the SHA-256 first.

**Direct download links (GitHub):**

| Artifact | Link |
| --- | --- |
| Portable ZIP | <https://github.com/hamzaqadir6666-pixel/wild-survival-mobile/blob/arena/98e7797b-wild-survival-mobile/releases/AeroExplorer-portable.zip?raw=true> |
| Setup wizard | <https://github.com/hamzaqadir6666-pixel/wild-survival-mobile/blob/arena/98e7797b-wild-survival-mobile/releases/AeroExplorerSetup.exe?raw=true> |
| Portable EXE | <https://github.com/hamzaqadir6666-pixel/wild-survival-mobile/blob/arena/98e7797b-wild-survival-mobile/releases/AeroExplorer.exe?raw=true> |
| Uninstaller | <https://github.com/hamzaqadir6666-pixel/wild-survival-mobile/blob/arena/98e7797b-wild-survival-mobile/releases/Uninstall.exe?raw=true> |

The ZIP is also stored uncompressed-friendly inside the repository, so the branch archive
(`Code → Download ZIP`) contains it too and needs no extra request.

---

## 1. Quick start

### Installer (recommended)

1. Run `AeroExplorerSetup.exe` (it requests administrator rights).
2. Walk the six pages: Welcome → License → Install location → Components → Installing → Finish.
3. Leave **Launch Windows 7 Aero Explorer now** checked and press **Finish**.

Silent / unattended:

```bat
AeroExplorerSetup.exe /S
AeroExplorerSetup.exe /S /DIR="D:\Apps\AeroExplorer" /NODESKTOPSHORTCUT /NOCONTEXTMENU /NOLAUNCH
```

| Switch | Meaning |
| --- | --- |
| `/S` | Silent install, no UI, exit code 0 on success |
| `/DIR=<path>` | Destination folder (default `%ProgramFiles%\AeroExplorer`) |
| `/NODESKTOPSHORTCUT` | Skip the desktop shortcut |
| `/NOSTARTMENUSHORTCUT` | Skip the Start Menu group |
| `/NOCONTEXTMENU` | Skip the folder context menu entry |
| `/NOFTPHANDLER` | Do not register the `ftp://` handler |
| `/NOLAUNCH` | Do not start the app when finished (silent installs already default to not launching) |
| `/LAUNCH` | Start the app when finished, even in silent mode |

A setup log is always written to `%TEMP%\AeroExplorerSetup.log`.

### Portable

Just run `AeroExplorer.exe`. The only thing it writes is your saved FTP bookmark file in
`%APPDATA%\AeroExplorer\ftp_sites.ini`.

---

## 2. Using the explorer

### Windows 7 chrome

* **Navigation band** — glass gradient, circular Aero orbs for Back / Forward / Up, a
  breadcrumb address bar (click a crumb to jump) and a search box.
* **Command bar** — glossy two-tone strip with `Organize`, `View`, `FTP` and `New folder`.
* **Navigation pane** — Favorites, drives and saved FTP servers in a themed tree.
* **File canvas** — five view modes with Windows 7 selection rectangles and group headers
  (`Hard Disk Drives`, `Devices with Removable Storage`, `Network Locations & FTP Sites`).
* **Details pane** — large 48×48 icon, type, size, date modified and path; drives show a
  glossy capacity bar that turns red past 90 % used.
* **Status bar** — item counts, selection totals, live transfer status.

Switch views from **View** (or sort by clicking a column header):

| View | Shortcut on the View menu |
| --- | --- |
| Large Icons | `View → Large Icons` |
| Tiles | `View → Tiles` (48 px icon + size/subtitle) |
| Details | `View → Details` (sortable columns) |
| List | `View → List` (columns that wrap) |
| Content | `View → Content` (two-line rows) |

### Keyboard

| Keys | Action |
| --- | --- |
| `Alt`+`←` / `Alt`+`→` | Back / Forward |
| `Alt`+`↑` or `Backspace` | Up one level |
| `Alt`+`D` or `Ctrl`+`L` | Edit the address bar |
| `Ctrl`+`K` | FTP Connection Manager |
| `Ctrl`+`Shift`+`N` | New folder (local or remote) |
| `Ctrl`+`A` / `C` / `X` / `V` | Select all / copy / cut / paste |
| `F2` | Rename (works on FTP too) |
| `Del` | Delete (Recycle Bin locally, remote delete on FTP) |
| `F5` | Refresh |
| `F1` | About &amp; shortcut reference |

### File operations

Local operations use the Win32 shell: Recycle Bin deletes, drag &amp; drop copy from Windows
Explorer, `Ctrl`+`C`/`Ctrl`+`V`, "Copy as path", and the native Properties sheet.

---

## 3. FTP support

FTP folders behave like local folders — same views, same breadcrumbs, same shortcuts.

### Connecting

Three ways:

1. **Address bar** — type and press Enter:
   `ftp://user:password@server.example.com:21/some/folder`
2. **FTP Connection Manager** (`Ctrl`+`K` or the **FTP** button) — fill in host, port, user,
   password, remote folder, passive mode, optional FTPS; press **Save** to keep a bookmark.
3. **Computer → Network Locations & FTP Sites** — double-click a saved server or the bundled
   demo (Rebex public test server, `demo` / `password`).

Everything after the first successful login is reused: navigating inside the same host keeps
the authenticated session (the URL shown in the address bar is fully qualified so double-clicks
and drag &amp; drop keep working), and a dropped idle connection is re-established transparently
on the next folder change.

### What you can do

| Operation | How |
| --- | --- |
| Upload | Drag files/folders from Windows Explorer onto the FTP folder; `Ctrl`+`V` after copying; `FTP → Upload files…`; right-click → *Upload file here…* |
| Download | Double-click a remote file (downloads to a folder you pick and opens it), or `FTP → Download selected…` |
| New folder | `Ctrl`+`Shift`+`N`, the command bar button, or `Organize → New folder` |
| Rename | `F2` (uses `RNFR`/`RNTO` on the server) |
| Delete | `Del` — files and **recursive** folder removal, after confirmation |
| Disconnect | `FTP → Disconnect from server` |

Transfers run on a worker thread with 64 KB streaming chunks and live byte progress painted
into the address bar plus the status bar, so the window never freezes. Recursive directory
upload and download are supported.

### Saved sites

`%APPDATA%\AeroExplorer\ftp_sites.ini`

```ini
[General]
Count=1

[Site0]
Title=Rebex Public Demo FTP
Host=test.rebex.net
Port=21
Anonymous=0
Username=demo
PasswordEnc=...
InitialPath=/pub/example
Passive=1
UseFtps=0
```

Passwords are stored obfuscated (not plain text) but are **recoverable** — the file is
per-user and protected by your Windows profile ACLs. Use FTPS (`AUTH TLS`, tick *Explicit
FTPS*) when the server offers it, and note that WinINet validates TLS using the system trust
store.

### Networking notes

* Passive (PASV) mode is on by default and is what you want behind NAT/firewalls.
* Ports, IPv6 literals (`ftp://[::1]:21/`), percent-encoded credentials and non-ASCII file
  names (with `OPTS UTF8 ON` requested) are all handled.
* Timeouts are 12 s connect / 20 s I/O so a dead server fails fast instead of hanging the UI.

---

## 4. Uninstalling

* **Apps &amp; Features → Windows 7 Aero Explorer → Uninstall**, or
* Start Menu → *AeroExplorer* → *Uninstall Windows 7 Aero Explorer*, or
* run `Uninstall.exe` from the install folder.

The uninstaller removes shortcuts, the context-menu registration, the `ftp://` handler, the
Apps &amp; Features entry and the program files. Two checkboxes let you keep or delete your
saved FTP sites and choose whether to strip the context menu. Silent:

```bat
Uninstall.exe /S /DIR="C:\Program Files\AeroExplorer" /REMOVESETTINGS /REMOVECTXMENU
```

Any file still locked by a running instance is queued for deletion via `RunOnce`, and a
temp-folder relaunch lets the uninstaller delete the folder that contains itself.

---

## 5. Building from source

Requirements: Python 3.10+, `g++` for the host-side packer, plus the pure-Python toolchain.

```bash
pip install --user --break-system-packages ziglang==0.14.1 pefile
python3 scripts/generate_assets.py   # icons + wizard artwork (needs Pillow)
python3 scripts/build_windows.py     # builds everything into releases/
python3 preview/server.py            # local download page + interactive demo
```

`build_windows.py` cross-compiles with Zig 0.14.1's clang/LLVM for
`x86_64-windows-gnu`, then verifies the results with `pefile`: machine type `0x8664`,
GUI subsystem, icon group present, manifest parses, version strings, and that the payload
embedded in the setup binary round-trips byte-for-byte to the packed archive.

### Source layout

```
src/common/                 shared, host-testable headers
  version.h                 product name/version/registry keys
  path_ftp_utils.h          ftp:// URL parse + build, breadcrumbs, Win7 size formats
  pack_format.h             APK1 archive: LZSS compressor + IEEE CRC32
  app_manifest.xml          explorer manifest (asInvoker, PerMonitorV2)
  installer_manifest.xml    setup manifest (requireAdministrator)
  uninstaller_manifest.xml  uninstaller manifest (requireAdministrator)
src/explorer/               AeroExplorer.exe
  explorer_main.cpp         window creation, layout, tree, drop target, WinMain
  explorer_nav.cpp          navigation, enumeration, sorting/filtering, history
  explorer_paint.cpp        GDI+ chrome, five view modes, details pane
  explorer_shell.cpp        window procs, mouse/keyboard, address bar, notifications
  explorer_cmds.cpp         menus, clipboard, local file operations
  explorer_ftp.cpp          background FTP workers + progress plumbing
  aero_theme.h              Aero primitives (orbs, glass boxes, capacity bars, headers)
  ftp_client.h              WinINet FTP client, profile storage
  shell_icons.h             16/32/48 px shell icons + type names, cached
  dialogs.h                 FTP Connection Manager, input prompt, about
  explorer.rc / resource.h  icon, manifest, version info, dialogs
src/installer/              AeroExplorerSetup.exe
  setup_main.cpp            six-page wizard, extraction, registration, /S mode
  setup.rc / setup_rc.h     artwork, payload RCDATA, version info
src/uninstaller/            Uninstall.exe
  uninstall_main.cpp        removal, self-delete, /S mode
scripts/generate_assets.py  supersampled Aero icon + wizard bitmap generator
scripts/pack_payload.cpp    host packer (APK1) used by the build
scripts/build_windows.py    full cross-compile + verification pipeline
tests/test_common.cpp       unit tests for URL/pack code (runs on Linux)
preview/                    download portal + browser replica of the UI
```

### Tests

```bash
g++ -std=c++17 -O2 -Wall -Wextra tests/test_common.cpp -o /tmp/test_common && /tmp/test_common
```

Covers URL round-tripping, credential encoding, IPv6/port parsing, breadcrumb generation,
Win7 byte/drive formatting, LZSS round-trips and corruption rejection in the archive format.

---

## 6. Design notes

* **Rendering.** The chrome is drawn with GDI+ into an off-screen 32-bit DIB and blitted once
  per paint (no flicker, no theme dependency). Orbs, glass boxes, glossy toolbars, selection
  rectangles and capacity bars are gradients + arcs, so they scale cleanly with DPI.
* **Icons.** 16 px from `SHGFI_SMALLICON`, 48 px from `IShellItemImageFactory`
  (`SIIGBF_ICONONLY`) with the system extra-large image list as a fallback, all cached by
  extension (or by path for `.exe`/`.lnk`/`.ico`).
* **DPI.** One `dpi_` value scales every metric through `MulDiv`; `WM_DPICHANGED` recreates the
  fonts and re-lays everything out. The manifest requests PerMonitorV2.
* **Extraction.** `pack_format.h` stores each file as LZSS with an IEEE CRC32; the wizard
  verifies each entry after decompression, so a truncated download cannot produce a broken
  install. The same header is compiled into the Linux packer, so pack and unpack share one
  implementation.
* **No silent side effects.** The portable build writes one INI. The installer registers only
  what you tick, and registration is reversible by the uninstaller.

## 7. Known limitations

* Uploads send files as-is; there is no resume/restart (`REST`) or bandwidth throttle.
* Only explicit FTPS (`AUTH TLS`) is attempted; implicit FTPS on port 990 is not.
* Unix-style FTP servers are assumed (`LIST` output is parsed by WinINet, not by this app).
* Files without a shell association fall back to the Windows "Open with" dialog.
* The binaries are unsigned; sign them with `signtool` if you distribute widely.

## License

MIT — see the license page inside the setup wizard, or `LICENSE` semantics of the MIT text
reproduced there. Not affiliated with Microsoft; "Windows" is a trademark of Microsoft
Corporation.
