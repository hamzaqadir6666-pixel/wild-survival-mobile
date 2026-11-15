#!/usr/bin/env python3
"""Tiny static server for the Aero Explorer download / demo page.

Serves preview/ at /, the generated icons at /assets/, and streams the real
Windows binaries from releases/ through /download/<name> with proper
Content-Disposition headers so the browser saves them as files.
"""

from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
PREVIEW = ROOT / "preview"
ASSETS = ROOT / "preview" / "public"
RELEASES = ROOT / "releases"

HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8000"))

EXPOSED_ARTIFACTS = [
    "AeroExplorer.exe",
    "AeroExplorerSetup.exe",
    "AeroExplorer-portable.zip",
    "AeroExplorer-v1.0.0-win64.zip",
    "INSTALL.txt",
    "Uninstall.exe",
    "SHA256SUMS.txt",
]


def pretty_size(num_bytes: int) -> str:
    value = float(num_bytes)
    for unit in ("bytes", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            if unit == "bytes":
                return f"{int(value)} bytes"
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} GB"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


_hash_cache: dict[str, tuple[float, str]] = {}


def cached_hash(path: Path) -> str:
    mtime = path.stat().st_mtime
    cached = _hash_cache.get(path.name)
    if cached and cached[0] == mtime:
        return cached[1]
    value = sha256_of(path)
    _hash_cache[path.name] = (mtime, value)
    return value


class Handler(BaseHTTPRequestHandler):
    server_version = "AeroExplorerPreview/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        print(f"  {self.address_string()} {fmt % args}")

    # ------------------------------------------------------------- helpers
    def _send_bytes(self, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if extra:
            for key, value in extra.items():
                self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_file(self, path: Path, download_name: str | None = None) -> None:
        if not path.is_file():
            self._not_found()
            return
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if path.suffix.lower() in {".exe", ".zip"}:
            content_type = "application/octet-stream"
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "none")
        if download_name:
            self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            with path.open("rb") as handle:
                shutil.copyfileobj(handle, self.wfile, length=1 << 20)

    def _not_found(self) -> None:
        body = b"Not found"
        self.send_response(404)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, payload: dict) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self._send_bytes(body, "application/json; charset=utf-8")

    # -------------------------------------------------------------- routes
    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        route = unquote(parsed.path)

        if route in ("/", "/index.html"):
            self._send_file(PREVIEW / "index.html")
            return
        if route == "/api/artifacts":
            artifacts = []
            for name in EXPOSED_ARTIFACTS:
                path = RELEASES / name
                if not path.is_file():
                    continue
                artifacts.append(
                    {
                        "name": name,
                        "size": path.stat().st_size,
                        "prettySize": pretty_size(path.stat().st_size),
                        "sha256": cached_hash(path),
                        "url": f"/download/{name}",
                    }
                )
            self._json({"artifacts": artifacts})
            return
        if route in ("/download", "/download/"):
            # Small self-contained index so the links are discoverable.
            rows = []
            for name in EXPOSED_ARTIFACTS:
                path = RELEASES / name
                if path.is_file():
                    rows.append(
                        f'<li><a href="/download/{name}">{name}</a>'
                        f' &mdash; {path.stat().st_size:,} bytes</li>'
                    )
            body = (
                "<!DOCTYPE html><meta charset=utf-8><title>Aero Explorer downloads</title>"
                "<body style='font-family:Segoe UI,sans-serif;padding:28px'>"
                "<h1>Windows 7 Aero Explorer &mdash; downloads</h1><ul>"
                + "".join(rows)
                + "</ul><p><a href='/'>Interactive preview</a></p></body>"
            ).encode("utf-8")
            self._send_bytes(body, "text/html; charset=utf-8")
            return
        if route.startswith("/download/"):
            name = route[len("/download/"):]
            if "/" in name or "\\" in name or name.startswith("."):
                self._not_found()
                return
            self._send_file(RELEASES / name, download_name=name)
            return
        if route.startswith("/assets/"):
            name = route[len("/assets/"):]
            if "/" in name or "\\" in name or name.startswith("."):
                self._not_found()
                return
            self._send_file(ASSETS / name)
            return

        # Anything else is a static file from preview/.
        relative = route.lstrip("/")
        if not relative or ".." in relative:
            self._not_found()
            return
        self._send_file(PREVIEW / relative)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    RELEASES.mkdir(exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Aero Explorer preview server listening on http://{HOST}:{PORT}")
    print(f"  demo page : http://localhost:{PORT}/")
    print(f"  downloads : /download/AeroExplorerSetup.exe, /download/AeroExplorer.exe")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
