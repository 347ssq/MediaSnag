"""Video/audio downloader using yt-dlp Python API."""

import json
import os
import sys
import threading
from pathlib import Path

from . import config


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


def get_available_qualities(url):
    """Detect available video qualities for a URL.

    Returns list of quality strings like ["1080p", "720p", "480p", "360p"].
    """
    yt_dlp = _get_yt_dlp()

    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:
        print(f"Error extracting info: {e}", file=sys.stderr)
        return ["360p", "720p", "1080p"]

    if not info or "formats" not in info:
        return ["360p", "720p", "1080p"]

    heights = set()
    for fmt in info["formats"]:
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


def get_video_info(url):
    """Get video title and thumbnail URL."""
    yt_dlp = _get_yt_dlp()

    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
            return {
                "title": info.get("title", "Unknown"),
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration"),
            }
    except Exception:
        return {"title": "Unknown", "thumbnail": None, "duration": None}


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

        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.download([self.url])
            self.status = "completed"
            self.progress = 100
        except Exception as e:
            self.status = "error"
            self.error = str(e)

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
