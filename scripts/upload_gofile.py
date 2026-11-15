#!/usr/bin/env python3
"""Upload the release ZIP to gofile.io (or any host) from YOUR machine.

gofile.io is not reachable from the build sandbox, so run this locally -
one command, no dependencies beyond the Python standard library:

    python3 scripts/upload_gofile.py
    python3 scripts/upload_gofile.py path/to/file.zip

It prints a direct https://gofile.io/d/XXXXXX link (plus the direct-download
URL) that you can share immediately.
"""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

API = "https://api.gofile.io"


def get_server() -> str:
    with urllib.request.urlopen(f"{API}/servers", timeout=30) as response:
        payload = json.load(response)
    data = payload.get("data") or {}
    servers = data.get("servers") or []
    if not servers:
        raise SystemExit("gofile.io did not return an upload server; try again later")
    return servers[0]["name"]


def upload(path: Path) -> dict:
    server = get_server()
    url = f"https://{server}.gofile.io/contents/uploadfile"
    boundary = "----AeroExplorerBoundary7d31f0"
    head = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    body = head + path.read_bytes() + tail
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
            "User-Agent": "AeroExplorerUploader/1.0",
        },
        method="POST",
    )
    print(f"uploading {path.name} ({path.stat().st_size:,} bytes) to {server}.gofile.io ...")
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.load(response)


def main() -> int:
    default = Path(__file__).resolve().parent.parent / "releases" / "AeroExplorer-v1.0.0-win64.zip"
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not path.is_file():
        raise SystemExit(f"file not found: {path}")
    result = upload(path)
    if result.get("status") != "ok":
        raise SystemExit(f"upload failed: {result}")
    data = result.get("data", {})
    folder = data.get("parentFolder") or data.get("folderId") or ""
    print("\nUpload complete:")
    print(f"  page            : https://gofile.io/d/{folder}")
    print(f"  direct download : {data.get('downloadPage') or 'https://gofile.io/d/' + str(folder)}")
    print(f"  file            : {data.get('name')}  ({data.get('size')} bytes)")
    print(f"  md5             : {data.get('md5')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
