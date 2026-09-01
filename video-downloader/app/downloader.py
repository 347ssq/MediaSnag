"""Video/audio downloader using yt-dlp Python API."""

import json
import os
import sys
import threading
import time
from pathlib import Path

from . import config

RETRY_DELAY_412 = 5


def _get_yt_dlp():
    """Import and return yt_dlp module."""
    install_dir = config.get_install_dir()
    source_dir = install_dir / "source"
    if source_dir.exists():
        sys.path.insert(0, str(source_dir))
    import yt_dlp
    return yt_dlp


QUALITY_MAP = {
    "4K": 2160,
    "2K": 1440,
    "1080p": 1080,
    "720p": 720,
    "480p": 480,
    "360p": 360,
    "240p": 240,
    "144p": 144,
}


def _cookie_sources():
    """Browser cookie sources to try, in order.

    A real logged-in session (cookies) greatly reduces 412 risk-control
    blocks on sites like Bilibili, and unlocks higher qualities.
    """
    if config.get_platform() == "windows":
        return [("edge",), None]
    return [None]


def _get_cookie_file():
    data_dir = config.get_data_dir()
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir / "session_cookies.txt"


def _apply_session_cookies(opts):
    cookie_file = _get_cookie_file()
    if cookie_file.exists():
        opts["cookiefile"] = str(cookie_file)


def _save_session_cookies(ydl):
    # Persist the session (e.g. Bilibili buvid3) so follow-up requests
    # look like the same browser instead of a fresh anonymous client,
    # which is what triggers 412 risk-control blocks.
    try:
        jar = getattr(ydl, "cookiejar", None)
        if jar is not None and len(jar) > 0:
            jar.save(str(_get_cookie_file()), ignore_discard=True, ignore_expires=True)
    except Exception as e:
        print(f"Cookie save failed: {e}", file=sys.stderr)


def _is_412(error):
    return "412" in str(error)


def _extract_info(url):
    """Run a single yt-dlp extraction, trying cookie sources in order.

    Returns (info_dict, error). Retries once after a short wait when
    Bilibili-style 412 risk control kicks in.
    """
    yt_dlp = _get_yt_dlp()

    base_opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }

    last_error = None
    for attempt in range(2):
        if attempt > 0:
            time.sleep(RETRY_DELAY_412)
        for cookies in _cookie_sources():
            opts = dict(base_opts)
            if cookies:
                opts["cookiesfrombrowser"] = cookies
            _apply_session_cookies(opts)
            ydl = yt_dlp.YoutubeDL(opts)
            try:
                info = ydl.extract_info(url, download=False)
                return info, None
            except Exception as e:
                last_error = e
                print(f"Extraction failed (cookies={cookies}): {e}", file=sys.stderr)
            finally:
                _save_session_cookies(ydl)
                ydl.close()
        if last_error is None or not _is_412(last_error):
            break
    return None, last_error


def _qualities_from_info(info):
    heights = set()
    for fmt in info.get("formats", []):
        h = fmt.get("height")
        if h and h > 0:
            heights.add(h)

    available = []
    for label, min_height in QUALITY_MAP.items():
        if any(h >= min_height for h in heights):
            if label not in available:
                available.append(label)

    if not available:
        return ["360p", "720p", "1080p"]

    quality_order = ["4K", "2K", "1080p", "720p", "480p", "360p", "240p", "144p"]
    return [q for q in quality_order if q in available]


def analyze_video(url):
    """One-pass analysis: title, thumbnail, duration and qualities.

    Merges what used to be two separate extractions — consecutive
    requests trip Bilibili's 412 risk control.
    """
    info, error = _extract_info(url)

    if not info:
        return {
            "title": None,
            "thumbnail": None,
            "duration": None,
            "qualities": ["360p", "720p", "1080p"],
            "error": str(error) if error else "Unknown error",
        }

    return {
        "title": info.get("title"),
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
        "qualities": _qualities_from_info(info),
        "error": None,
    }


def build_format_selector(quality, dl_type="video"):
    """Build yt-dlp format selector string."""
    if dl_type == "audio":
        return "bestaudio/best"

    height = QUALITY_MAP.get(quality, 1080)

    if height >= 1080:
        return f"bestvideo[height<={height}]+bestaudio/best[height<={height}]"
    else:
        return f"bestvideo[height<={height}]+bestaudio/best[height<={height}]/best"


def build_audio_opts(audio_format):
    """Build postprocessors for audio download."""
    if audio_format == "mp3_best":
        return {
            "format": "bestaudio/best",
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "0",
            }],
        }
    elif audio_format == "mp3_128k":
        return {
            "format": "bestaudio/best",
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "5",
            }],
        }
    else:
        return {
            "format": "bestaudio/best",
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
            }],
        }


class DownloadTask:
    """Represents a single download task with progress tracking."""

    def __init__(self, url, quality, dl_type="video", audio_format=None, task_id=None):
        self.url = url
        self.quality = quality
        self.dl_type = dl_type
        self.audio_format = audio_format
        self.task_id = task_id
        self.progress = 0
        self.speed = 0
        self.eta = 0
        self.filename = ""
        self.status = "pending"
        self.error = None
        self._callbacks = []
        self._thread = None

    def add_callback(self, callback):
        self._callbacks.append(callback)

    def _notify(self):
        data = {
            "task_id": self.task_id,
            "progress": self.progress,
            "speed": self.speed,
            "eta": self.eta,
            "filename": self.filename,
            "status": self.status,
            "error": self.error,
        }
        for cb in self._callbacks:
            try:
                cb(data)
            except Exception:
                pass

    def _progress_hook(self, d):
        if d["status"] == "downloading":
            self.status = "downloading"
            self.filename = d.get("filename", "")
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            downloaded = d.get("downloaded_bytes", 0)
            if total > 0:
                self.progress = round(downloaded / total * 100, 1)
            self.speed = d.get("speed", 0) or 0
            self.eta = d.get("eta", 0) or 0
        elif d["status"] == "finished":
            self.status = "processing"
            self.progress = 100
            self.filename = d.get("filename", "")
        self._notify()

    def run(self):
        """Execute the download in a background thread."""
        self._thread = threading.Thread(target=self._run_impl, daemon=True)
        self._thread.start()

    def _run_impl(self):
        yt_dlp = _get_yt_dlp()

        download_dir = str(config.get_download_dir())
        ffmpeg_path = str(config.get_ffmpeg_path())

        if self.dl_type == "audio":
            opts = build_audio_opts(self.audio_format or "mp3_best")
        else:
            opts = {
                "format": build_format_selector(self.quality, "video"),
                "merge_output_format": "mp4",
            }

        opts.update({
            "outtmpl": os.path.join(download_dir, "%(title)s.%(ext)s"),
            "ffmpeg_location": ffmpeg_path,
            "noplaylist": True,
            "concurrent_fragment_downloads": 4,
            "progress_hooks": [self._progress_hook],
            "quiet": True,
            "no_warnings": True,
        })

        self.status = "downloading"
        self._notify()

        last_error = None
        for attempt in range(2):
            if attempt > 0:
                time.sleep(RETRY_DELAY_412)
            for cookies in _cookie_sources():
                attempt_opts = dict(opts)
                if cookies:
                    attempt_opts["cookiesfrombrowser"] = cookies
                _apply_session_cookies(attempt_opts)
                ydl = yt_dlp.YoutubeDL(attempt_opts)
                try:
                    ydl.download([self.url])
                    self.status = "completed"
                    self.progress = 100
                    self._notify()
                    return
                except Exception as e:
                    last_error = e
                    print(f"Download failed (cookies={cookies}): {e}", file=sys.stderr)
                finally:
                    _save_session_cookies(ydl)
                    ydl.close()
                # Mid-transfer failure: retrying would just re-download,
                # so surface the error instead.
                if self.progress > 0:
                    self.status = "error"
                    self.error = str(last_error)
                    self._notify()
                    return
            if last_error is None or not _is_412(last_error):
                break

        self.status = "error"
        self.error = str(last_error) if last_error else "Unknown error"

        self._notify()


class TaskManager:
    """Manages download tasks."""

    def __init__(self):
        self._tasks = {}
        self._counter = 0
        self._lock = threading.Lock()

    def create_task(self, url, quality, dl_type="video", audio_format=None):
        with self._lock:
            self._counter += 1
            task_id = str(self._counter)

        task = DownloadTask(url, quality, dl_type, audio_format, task_id)
        self._tasks[task_id] = task
        return task

    def get_task(self, task_id):
        return self._tasks.get(task_id)

    def list_tasks(self):
        return list(self._tasks.values())
