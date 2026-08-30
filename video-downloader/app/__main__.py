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


def find_running_server():
    """Return the port of an already-running MediaSnag server, or None."""
    import urllib.request

    for port in range(config.SERVER_PORT, config.SERVER_PORT_MAX + 1):
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/health", timeout=0.3
            ) as resp:
                if resp.status == 200:
                    return port
        except Exception:
            continue
    return None


def start_server_and_open_browser(url=None):
    """Start the HTTP server and open the browser.

    If a MediaSnag server is already running, reuse it instead of
    starting a second instance (which would grab another port and
    leave stale processes behind).
    """
    from .server import start_server

    server = None
    existing_port = find_running_server()
    if existing_port:
        port = existing_port
    else:
        static_dir = os.path.join(os.path.dirname(__file__), "static")
        userscript_path = config.get_userscript_path()

        server, port = start_server(static_dir, userscript_path)

        # Record PID so the installer can terminate this instance
        # before replacing files on upgrade.
        try:
            data_dir = config.get_data_dir()
            os.makedirs(data_dir, exist_ok=True)
            with open(os.path.join(data_dir, "mediasnag.pid"), "w") as f:
                f.write(str(os.getpid()))
        except OSError:
            pass

    if url:
        page = f"http://127.0.0.1:{port}/?url={urllib.parse.quote(url, safe='')}"
    else:
        page = f"http://127.0.0.1:{port}/"

    webbrowser.open(page)

    # Install root is parent of app directory, matches where installer creates the marker
    install_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    first_run_marker = os.path.join(install_root, "first_run")
    if os.path.exists(first_run_marker):
        import time
        time.sleep(1)
        webbrowser.open(f"http://127.0.0.1:{port}/userscript.user.js")
        try:
            os.remove(first_run_marker)
        except OSError:
            pass

    if server is None:
        # Reused an existing server; this process has nothing to serve.
        return

    print(f"MediaSnag {config.APP_VERSION} running on {page}")
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
