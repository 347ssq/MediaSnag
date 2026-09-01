"""HTTP server for MediaSnag web UI."""

import json
import os
import socket
import threading
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlparse

from . import config
from .downloader import TaskManager


class DownloadHandler(SimpleHTTPRequestHandler):
    """HTTP request handler for MediaSnag."""

    task_manager = None
    static_dir = None
    userscript_path = None

    def log_message(self, format, *args):
        pass

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def _send_file(self, path, content_type):
        try:
            with open(path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self._send_404()

    def _send_404(self, detail=""):
        lines = [
            "MediaSnag: 404 页面不存在",
            f"请求的路径: {self.path}",
        ]
        if detail:
            lines.append(detail)
        lines += [
            f"服务器版本: {config.APP_VERSION}",
            "",
            "可用地址:",
            "  /                    主界面",
            "  /setup.html          首次设置向导",
            "  /userscript.user.js  油猴脚本（安装/更新）",
            "  /health              状态检查（含版本号）",
        ]
        body = ("\n".join(lines) + "\n").encode("utf-8")
        self.send_response(404)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == "/" or path == "/index.html":
            self._serve_static("index.html", "text/html; charset=utf-8")
        elif path == "/setup.html":
            self._serve_static("setup.html", "text/html; charset=utf-8")
        elif path == "/style.css":
            self._serve_static("style.css", "text/css; charset=utf-8")
        elif path == "/app.js":
            self._serve_static("app.js", "application/javascript; charset=utf-8")
        elif path == "/api/analyze":
            self._handle_analyze(params)
        elif path == "/api/progress":
            self._handle_progress(params)
        elif path == "/api/tasks":
            self._handle_list_tasks()
        elif path == "/userscript.user.js":
            self._serve_userscript()
        elif path == "/health":
            self._send_json({"status": "ok", "version": config.APP_VERSION})
        else:
            self._send_404()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/download":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            data = json.loads(body)
            self._handle_download(data)
        else:
            self.send_error(404)

    def _serve_static(self, filename, content_type):
        if self.static_dir:
            path = os.path.join(self.static_dir, filename)
            self._send_file(path, content_type)
        else:
            self._send_404()

    def _serve_userscript(self):
        if self.userscript_path and os.path.exists(self.userscript_path):
            self._send_file(
                self.userscript_path,
                "text/javascript; charset=utf-8"
            )
        else:
            self._send_404(detail=f"脚本文件未找到: {self.userscript_path}")

    def _handle_analyze(self, params):
        url = params.get("url", [None])[0]
        if not url:
            self._send_json({"error": "Missing url parameter"}, 400)
            return

        from .downloader import analyze_video
        self._send_json(analyze_video(url))

    def _handle_download(self, data):
        url = data.get("url")
        quality = data.get("quality", "1080p")
        dl_type = data.get("type", "video")
        audio_format = data.get("audio_format")

        if not url:
            self._send_json({"error": "Missing url"}, 400)
            return

        task = self.task_manager.create_task(url, quality, dl_type, audio_format)
        task.run()

        self._send_json({"task_id": task.task_id, "status": "started"})

    def _handle_progress(self, params):
        task_id = params.get("id", [None])[0]
        if not task_id:
            self._send_json({"error": "Missing id parameter"}, 400)
            return

        task = self.task_manager.get_task(task_id)
        if not task:
            self._send_json({"error": "Task not found"}, 404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        last_progress = -1
        while True:
            if task.progress != last_progress or task.status in ("completed", "error"):
                data = {
                    "progress": task.progress,
                    "speed": task.speed,
                    "eta": task.eta,
                    "filename": os.path.basename(task.filename) if task.filename else "",
                    "status": task.status,
                    "error": task.error,
                }
                msg = f"data: {json.dumps(data)}\n\n"
                self.wfile.write(msg.encode("utf-8"))
                self.wfile.flush()
                last_progress = task.progress

                if task.status in ("completed", "error"):
                    break

            time.sleep(0.5)

    def _handle_list_tasks(self):
        tasks = self.task_manager.list_tasks()
        result = []
        for t in tasks:
            result.append({
                "task_id": t.task_id,
                "url": t.url,
                "quality": t.quality,
                "type": t.dl_type,
                "status": t.status,
                "progress": t.progress,
            })
        self._send_json({"tasks": result})


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in separate threads."""
    allow_reuse_address = True
    daemon_threads = True


def find_available_port(start_port, max_port):
    """Find an available port in the given range."""
    for port in range(start_port, max_port + 1):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            sock.bind(("127.0.0.1", port))
            sock.close()
            return port
        except OSError:
            continue
    return None


def start_server(static_dir, userscript_path, port=None):
    """Start the HTTP server.

    Returns (server, actual_port) tuple.
    """
    if port is None:
        port = find_available_port(config.SERVER_PORT, config.SERVER_PORT_MAX)
        if port is None:
            raise RuntimeError("No available port found")

    DownloadHandler.static_dir = static_dir
    DownloadHandler.userscript_path = userscript_path
    DownloadHandler.task_manager = TaskManager()

    server = ThreadedHTTPServer(("127.0.0.1", port), DownloadHandler)

    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    return server, port
