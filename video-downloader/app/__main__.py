#!/usr/bin/env python3
"""MediaSnag - Cross-platform entry point.

Handles invocation modes:
1. URL scheme:  mediasnag "ytdl://ENCODED_URL" → download
2. --serve:     mediasnag --serve → start web server + open browser
3. Direct run:  mediasnag → platform-specific ready behavior
"""

import os
import platform
import sys
import urllib.parse
import webbrowser

from . import config


def parse_url_arg():
    """Parse URL scheme argument from command line.

    Returns (url, dl_type) or (None, None).
    """
    for arg in sys.argv[1:]:
        if arg == "--serve":
            continue
        if arg.startswith("ytdla://"):
            encoded = arg[8:]
            url = urllib.parse.unquote(encoded)
            return url, "audio"
        elif arg.startswith("ytdl://"):
            encoded = arg[7:]
            url = urllib.parse.unquote(encoded)
            return url, "video"
    return None, None


def has_serve_flag():
    return "--serve" in sys.argv[1:]


def start_server_and_open_browser(url=None):
    """Start the HTTP server and open the browser."""
    from .server import start_server

    static_dir = os.path.join(os.path.dirname(__file__), "static")
    userscript_path = config.get_userscript_path()

    server, port = start_server(static_dir, userscript_path)

    if url:
        page = f"http://127.0.0.1:{port}/?url={urllib.parse.quote(url, safe='')}"
    else:
        page = f"http://127.0.0.1:{port}/"

    webbrowser.open(page)

    first_run_marker = os.path.join(os.path.dirname(static_dir), "first_run")
    if os.path.exists(first_run_marker):
        import time
        time.sleep(1)
        webbrowser.open(f"http://127.0.0.1:{port}/userscript.user.js")
        try:
            os.remove(first_run_marker)
        except OSError:
            pass

    print(f"MediaSnag running on {page}")
    print("Press Ctrl+C to stop.")

    try:
        import time
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.shutdown()
        print("\nStopped.")


def main():
    url, dl_type = parse_url_arg()
    system = platform.system()

    if has_serve_flag() or system == "Windows":
        start_server_and_open_browser(url)
        return

    if url and system == "Darwin":
        from .native_download import handle_download
        handle_download(url, dl_type)
        return

    if not url and system == "Darwin":
        import subprocess
        subprocess.run([
            "osascript", "-e",
            'display notification "MediaSnag 已就绪，在浏览器中点击下载按钮即可" '
            'with title "MediaSnag" sound name "Glass"'
        ], capture_output=True, timeout=10)
    elif not url:
        print("MediaSnag is ready. Use ytdl:// URL scheme to download.")


if __name__ == "__main__":
    main()
