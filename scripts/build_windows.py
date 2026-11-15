#!/usr/bin/env python3
"""Cross-compile the Windows 7 Aero Explorer deliverables on Linux.

Outputs (written to releases/):
  AeroExplorer.exe        native x64 GUI file explorer with FTP support
  AeroExplorerSetup.exe   Windows 7 style setup wizard (payload embedded)
  Uninstall.exe           standalone uninstaller (also embedded in the setup)
  AeroExplorer-portable.zip  both executables for a no-install workflow

The toolchain is Zig's clang/LLVM based cross compiler (pip package `ziglang`)
plus the `pefile` package for post-build PE verification.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASES = ROOT / "releases"
BUILD = ROOT / "build"

EXPLORER_SOURCES = [
    "src/explorer/explorer_main.cpp",
    "src/explorer/explorer_nav.cpp",
    "src/explorer/explorer_paint.cpp",
    "src/explorer/explorer_shell.cpp",
    "src/explorer/explorer_cmds.cpp",
    "src/explorer/explorer_ftp.cpp",
]

EXPLORER_LIBS = [
    "-lcomctl32", "-lshell32", "-lshlwapi", "-lole32", "-luuid", "-lgdi32",
    "-lgdiplus", "-lwininet", "-ldwmapi", "-luxtheme", "-lcomdlg32", "-ladvapi32",
]

UNINSTALLER_LIBS = [
    "-lcomctl32", "-lshell32", "-lshlwapi", "-lole32", "-luuid", "-lgdi32",
    "-lgdiplus", "-ladvapi32", "-luxtheme",
]

SETUP_LIBS = [
    "-lcomctl32", "-lshell32", "-lshlwapi", "-lole32", "-luuid", "-lgdi32",
    "-lgdiplus", "-ladvapi32", "-luxtheme",
]

CXX = [sys.executable, "-m", "ziglang", "c++"]
RC = [sys.executable, "-m", "ziglang", "rc"]


def log(message: str) -> None:
    print(f"\033[1;34m==>\033[0m {message}", flush=True)


def run(cmd: list[str], cwd: Path | None = None) -> None:
    printable = " ".join(str(c) for c in cmd)
    print(f"    $ {printable}", flush=True)
    subprocess.run([str(c) for c in cmd], cwd=str(cwd or ROOT), check=True)


def compile_resource(rc_file: Path, out_file: Path, include_dirs: list[Path]) -> None:
    out_file.parent.mkdir(parents=True, exist_ok=True)
    cmd = list(RC)
    for inc in include_dirs:
        cmd.append(f"-I{inc}")
    cmd += [str(rc_file), str(out_file)]
    run(cmd)


def link_exe(sources: list[Path], res_file: Path, out_exe: Path, libs: list[str],
             include_dirs: list[Path], extra_flags: list[str] | None = None) -> None:
    out_exe.parent.mkdir(parents=True, exist_ok=True)
    # Keep the link-generated .pdb out of the deliverable folder.
    pdb_dir = BUILD / "pdb"
    pdb_dir.mkdir(parents=True, exist_ok=True)
    cmd = list(CXX) + [
        "-target", "x86_64-windows-gnu",
        "-std=c++17",
        "-O2",
        "-municode",
        "-Wall", "-Wextra",
        "-Wno-unused-parameter",
        "-Wno-missing-field-initializers",
        "-Wl,--subsystem,windows",
    ]
    for inc in include_dirs:
        cmd.append(f"-I{inc}")
    cmd += [str(s) for s in sources]
    cmd += ["-Wl,/pdb:" + str(pdb_dir / (out_exe.stem + ".pdb"))]
    cmd.append(str(res_file))
    cmd += libs
    if extra_flags:
        cmd += extra_flags
    cmd += ["-o", str(out_exe)]
    run(cmd)


def build_packer() -> Path:
    packer = BUILD / "pack_payload"
    run(["g++", "-std=c++17", "-O2", "-Wall", "-Wextra",
         str(ROOT / "scripts" / "pack_payload.cpp"), "-o", str(packer)])
    return packer


def verify_pe(path: Path, expect_subsystem: int = 2) -> dict:
    import pefile  # imported lazily so --help works without the dependency

    pe = pefile.PE(str(path), fast_load=False)
    machine = pe.FILE_HEADER.Machine
    subsystem = pe.OPTIONAL_HEADER.Subsystem
    if machine != 0x8664:
        raise SystemExit(f"{path.name}: expected x86_64 machine 0x8664, got 0x{machine:x}")
    if subsystem != expect_subsystem:
        raise SystemExit(f"{path.name}: expected GUI subsystem {expect_subsystem}, got {subsystem}")

    resources: list[tuple[int, bool]] = []
    icons = 0
    payload_size = 0
    has_manifest = False
    version_strings: dict[str, str] = {}

    if hasattr(pe, "DIRECTORY_ENTRY_RESOURCE"):
        for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
            rid = entry.id if entry.id is not None else -1
            is_dir = entry.directory is not None
            resources.append((rid, is_dir))
            if rid == 3 and is_dir:  # RT_ICON
                icons = len(entry.directory.entries)
            if rid == 24 and is_dir:  # RT_MANIFEST
                has_manifest = True
            if rid == 10 and is_dir:  # RCDATA
                for name_entry in entry.directory.entries:
                    data_entry = name_entry.directory.entries[0]
                    payload_size = data_entry.data.struct.Size

    if hasattr(pe, "FileInfo"):
        for file_info in pe.FileInfo:
            for entry in file_info:
                if getattr(entry, "Key", b"") != b"StringFileInfo":
                    continue
                for table in entry.StringTable:
                    for key, value in table.entries.items():
                        key_text = key.decode("utf-8", "replace") if isinstance(key, bytes) else str(key)
                        if isinstance(value, bytes):
                            try:
                                value_text = value.decode("utf-16-le")
                            except UnicodeDecodeError:
                                value_text = value.decode("latin-1", "replace")
                        else:
                            value_text = str(value)
                        version_strings[key_text] = value_text.rstrip("\x00")

    pe.close()
    return {
        "machine": machine,
        "subsystem": subsystem,
        "size": path.stat().st_size,
        "resources": resources,
        "icon_count": icons,
        "has_manifest": has_manifest,
        "payload_size": payload_size,
        "version": version_strings,
    }


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if not (ROOT / "assets" / "aero_explorer.ico").exists():
        raise SystemExit("assets/aero_explorer.ico is missing - run scripts/generate_assets.py first")

    RELEASES.mkdir(exist_ok=True)
    BUILD.mkdir(exist_ok=True)

    log("Compiling explorer resources")
    explorer_res = BUILD / "explorer.res"
    compile_resource(ROOT / "src/explorer/explorer.rc", explorer_res, [ROOT / "src/explorer"])

    log("Building AeroExplorer.exe")
    explorer_exe = RELEASES / "AeroExplorer.exe"
    link_exe(
        [ROOT / s for s in EXPLORER_SOURCES],
        explorer_res,
        explorer_exe,
        EXPLORER_LIBS,
        [ROOT / "src/explorer", ROOT / "src/common"],
    )

    log("Building Uninstall.exe")
    uninstall_res = BUILD / "uninstall.res"
    compile_resource(ROOT / "src/uninstaller/uninstall.rc", uninstall_res,
                     [ROOT / "src/uninstaller"])
    uninstall_exe = RELEASES / "Uninstall.exe"
    link_exe(
        [ROOT / "src/uninstaller/uninstall_main.cpp"],
        uninstall_res,
        uninstall_exe,
        UNINSTALLER_LIBS,
        [ROOT / "src/uninstaller", ROOT / "src/common"],
    )

    log("Packing the APK1 installation payload")
    packer = build_packer()
    payload = ROOT / "src/installer/aeroexplorer_payload.bin"
    run([str(packer), str(payload),
         f"AeroExplorer.exe={explorer_exe}",
         f"Uninstall.exe={uninstall_exe}"])

    log("Compiling setup wizard resources (payload embedded as RCDATA)")
    setup_res = BUILD / "setup.res"
    compile_resource(ROOT / "src/installer/setup.rc", setup_res,
                     [ROOT / "src/installer"])

    log("Building AeroExplorerSetup.exe")
    setup_exe = RELEASES / "AeroExplorerSetup.exe"
    link_exe(
        [ROOT / "src/installer/setup_main.cpp"],
        setup_res,
        setup_exe,
        SETUP_LIBS,
        [ROOT / "src/installer", ROOT / "src/common"],
    )

    log("Verifying PE headers, resources and version metadata")
    explorer_info = verify_pe(explorer_exe)
    uninstall_info = verify_pe(uninstall_exe)
    setup_info = verify_pe(setup_exe)

    if explorer_info["icon_count"] < 1:
        raise SystemExit("AeroExplorer.exe has no icons")
    if uninstall_info["icon_count"] < 1:
        raise SystemExit("Uninstall.exe has no icons")
    if setup_info["icon_count"] < 1:
        raise SystemExit("AeroExplorerSetup.exe has no icons")
    if not explorer_info["has_manifest"]:
        raise SystemExit("AeroExplorer.exe is missing its application manifest")
    if setup_info["payload_size"] < 100_000:
        raise SystemExit("AeroExplorerSetup.exe payload looks truncated")
    if explorer_info["version"].get("ProductName") != "Windows 7 Aero Explorer":
        raise SystemExit("AeroExplorer.exe version resource is missing ProductName")

    # Round-trip the embedded payload from the final setup binary.
    sys.path.insert(0, str(ROOT / "scripts"))
    import pefile

    pe = pefile.PE(str(setup_exe))
    embedded = None
    for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if entry.id == 10:
            for name_entry in entry.directory.entries:
                data_entry = name_entry.directory.entries[0]
                blob = pe.get_data(data_entry.data.struct.OffsetToData, data_entry.data.struct.Size)
                embedded = bytes(blob)
                break
    pe.close()
    if embedded is None:
        raise SystemExit("could not read the embedded payload back")
    if embedded != payload.read_bytes():
        raise SystemExit("embedded payload does not match the packed archive")
    magic, count = struct.unpack_from("<II", embedded, 0)
    if magic != 0x314B5041:  # 'APK1'
        raise SystemExit(f"unexpected payload magic 0x{magic:08x}")
    if count != 2:
        raise SystemExit(f"expected 2 payload entries, found {count}")

    log("Writing the portable ZIP")
    portable = RELEASES / "AeroExplorer-portable.zip"
    with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        zf.write(explorer_exe, "AeroExplorer/AeroExplorer.exe")
        zf.write(uninstall_exe, "AeroExplorer/Uninstall.exe")
        readme = ROOT / "README.md"
        if readme.exists():
            zf.write(readme, "AeroExplorer/README.md")

    log("Writing checksums")
    lines = []
    for artifact in (explorer_exe, uninstall_exe, setup_exe, portable):
        lines.append(f"{sha256_of(artifact)}  {artifact.name}")
    (RELEASES / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print()
    print("  Build summary")
    print("  " + "-" * 68)
    for path, info in ((explorer_exe, explorer_info), (uninstall_exe, uninstall_info),
                       (setup_exe, setup_info)):
        print(f"  {path.name:<26} {info['size']:>10,} bytes   x64 GUI PE32+"
              f"   icons={info['icon_count']}  manifest={'yes' if info['has_manifest'] else 'no'}")
    print(f"  {portable.name:<26} {portable.stat().st_size:>10,} bytes")
    print(f"  embedded payload           {len(embedded):>10,} bytes ({count} entries)")
    print("  " + "-" * 68)
    for line in lines:
        print("  " + line)
    print()
    print(f"  deliverables in {RELEASES}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as exc:
        print(f"\nBuild failed: {exc}", file=sys.stderr)
        sys.exit(exc.returncode or 1)
