"""Native macOS download flow using osascript dialogs.

Replicates the original AppleScript behavior: native dialogs for quality
selection, notifications for progress/completion.
"""

import os
import platform
import subprocess
import sys
import urllib.parse
from pathlib import Path

from . import config


def _osascript(script):
    """Run an osascript and return stdout."""
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=300
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"osascript error: {e}", file=sys.stderr)
        return ""


def _notify(title, message, sound="default"):
    """Show a macOS notification."""
    sound_clause = f'sound name "{sound}"' if sound else ""
    _osascript(
        f'display notification "{message}" with title "{title}" {sound_clause}'
    )


def _alert(title, message):
    """Show a macOS alert dialog."""
    _osascript(
        f'display alert "{title}" message "{message}"'
    )


def _choose_from_list(title, items, default=None):
    """Show a native choose from list dialog. Returns selected item or None."""
    items_str = ", ".join(f'"{i}"' for i in items)
    default_clause = ""
    if default:
        default_clause = f' default items {{"{default}"}}'
    result = _osascript(
        f'choose from list {{{items_str}}}{default_clause} with title "{title}"'
    )
    if not result or result == "false":
        return None
    return result


def _get_yt_dlp():
    """Import yt_dlp."""
    install_dir = config.get_install_dir()
    source_dir = install_dir / "source"
    if source_dir.exists():
        sys.path.insert(0, str(source_dir))
    import yt_dlp
    return yt_dlp


def _get_available_qualities(url):
    """Get available video qualities using yt-dlp."""
    yt_dlp = _get_yt_dlp()
    quality_map = {
        "4K": 2160, "2K": 1440, "1080p": 1080, "720p": 720,
        "480p": 480, "360p": 360, "240p": 240, "144p": 144,
    }

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
    for label, min_height in quality_map.items():
        if any(h >= min_height for h in heights):
            if label not in available:
                available.append(label)

    if not available:
        return ["360p", "720p", "1080p"]

    quality_order = ["4K", "2K", "1080p", "720p", "480p", "360p", "240p", "144p"]
    return [q for q in quality_order if q in available]


def _build_format(quality):
    """Build yt-dlp format string for a quality label."""
    height_map = {
        "4K": 2160, "2K": 1440, "1080p": 1080, "720p": 720,
        "480p": 480, "360p": 360, "240p": 240, "144p": 144,
    }
    height = height_map.get(quality, 1080)
    if height >= 1080:
        return f"bestvideo[height<={height}]+bestaudio/best[height<={height}]"
    else:
        return f"bestvideo[height<={height}]+bestaudio/best[height<={height}]/best"


def _download(url, format_str, download_dir, ffmpeg_path):
    """Download video using yt-dlp Python API."""
    yt_dlp = _get_yt_dlp()

    opts = {
        "format": format_str,
        "merge_output_format": "mp4",
        "outtmpl": os.path.join(download_dir, "%(title)s.%(ext)s"),
        "ffmpeg_location": ffmpeg_path,
        "noplaylist": True,
        "concurrent_fragment_downloads": 4,
        "quiet": True,
        "no_warnings": True,
    }

    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])


def _download_audio(url, audio_format, download_dir, ffmpeg_path):
    """Download audio using yt-dlp Python API."""
    yt_dlp = _get_yt_dlp()

    if audio_format == "MP3 最佳音质":
        postprocessors = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "0",
        }]
    elif audio_format == "MP3 128kbps":
        postprocessors = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "5",
        }]
    else:
        postprocessors = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "m4a",
        }]

    opts = {
        "format": "bestaudio/best",
        "outtmpl": os.path.join(download_dir, "%(title)s.%(ext)s"),
        "ffmpeg_location": ffmpeg_path,
        "noplaylist": True,
        "postprocessors": postprocessors,
        "quiet": True,
        "no_warnings": True,
    }

    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])


def _resolve_ffmpeg():
    """Find a working ffmpeg binary, preferring bundled but falling back to system."""
    bundled = config.get_ffmpeg_path()
    if bundled.is_file() and os.access(bundled, os.X_OK):
        if _ffmpeg_runs(bundled):
            return str(bundled.parent)

    for candidate in [
        Path("/opt/homebrew/bin/ffmpeg"),
        Path("/usr/local/bin/ffmpeg"),
    ]:
        if candidate.is_file() and _ffmpeg_runs(candidate):
            return str(candidate.parent)

    from shutil import which
    sys_ffmpeg = which("ffmpeg")
    if sys_ffmpeg and _ffmpeg_runs(Path(sys_ffmpeg)):
        return str(Path(sys_ffmpeg).parent)

    return str(config.get_install_dir() / "bin")


def _ffmpeg_runs(path):
    """Check if an ffmpeg binary actually runs (catches arch mismatches)."""
    try:
        r = subprocess.run(
            [str(path), "-version"],
            capture_output=True, timeout=5
        )
        return r.returncode == 0
    except Exception:
        return False


def handle_download(url, dl_type="video"):
    """Handle a download request with native macOS dialogs.

    Args:
        url: The video/audio URL to download
        dl_type: "video" or "audio"
    """
    if platform.system() != "Darwin":
        print("Native dialogs only supported on macOS", file=sys.stderr)
        return

    download_dir = str(config.get_download_dir())
    ffmpeg_dir = _resolve_ffmpeg()

    try:
        if dl_type == "video":
            _notify("MediaSnag", "正在检查视频可用清晰度...")
            qualities = _get_available_qualities(url)

            quality = _choose_from_list("选择清晰度", qualities, qualities[0])
            if not quality:
                return

            format_str = _build_format(quality)
            _notify("MediaSnag", f"开始下载 {quality}...")
            _download(url, format_str, download_dir, ffmpeg_dir)
            _notify("MediaSnag", "下载完成！", sound="Glass")
        else:
            audio_options = ["MP3 最佳音质", "MP3 128kbps", "M4A 最佳音质"]
            choice = _choose_from_list("选择音频格式", audio_options, audio_options[0])
            if not choice:
                return

            _notify("MediaSnag", f"开始下载 {choice}...")
            _download_audio(url, choice, download_dir, ffmpeg_dir)
            _notify("MediaSnag", "下载完成！", sound="Glass")

    except Exception as e:
        print(f"Download error: {e}", file=sys.stderr)
        _alert("下载失败", str(e)[:200])
