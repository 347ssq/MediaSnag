"""Cross-platform configuration for MediaSnag."""

import os
import platform
import sys
from pathlib import Path


def get_platform():
    """Return normalized platform name: 'macos', 'windows', or 'linux'."""
    system = platform.system().lower()
    if system == "darwin":
        return "macos"
    elif system == "windows":
        return "windows"
    return "linux"


def get_arch():
    """Return normalized architecture: 'arm64' or 'x86_64'."""
    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        return "arm64"
    return "x86_64"


def get_install_dir():
    """Return the installation directory for the current platform."""
    if get_platform() == "macos":
        return Path.home() / "Library" / "ytdlp"
    elif get_platform() == "windows":
        return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "MediaSnag"
    else:
        return Path.home() / ".local" / "share" / "ytdlp"


def get_python_path():
    """Return path to the bundled Python executable."""
    base = get_install_dir() / "python"
    if get_platform() == "windows":
        return base / "python.exe"
    return base / "bin" / "python3"


def get_ffmpeg_path():
    """Return path to the bundled ffmpeg executable."""
    base = get_install_dir() / "bin"
    name = "ffmpeg.exe" if get_platform() == "windows" else "ffmpeg"
    return base / name


def get_ffprobe_path():
    """Return path to the bundled ffprobe executable."""
    base = get_install_dir() / "bin"
    name = "ffprobe.exe" if get_platform() == "windows" else "ffprobe"
    return base / name


def get_download_dir():
    """Return the user's Downloads directory."""
    if get_platform() == "windows":
        return Path(os.environ.get("USERPROFILE", Path.home())) / "Downloads"
    return Path.home() / "Downloads"


def get_data_dir():
    """Return directory for runtime data (lock files, port file)."""
    return get_install_dir() / "data"


def get_userscript_path():
    """Return path to the bundled userscript."""
    if get_platform() == "windows":
        return get_install_dir() / "userscript.user.js"
    return get_install_dir() / "app" / "templates" / "universal_downloader.user.js"


SERVER_PORT = 19527
SERVER_PORT_MAX = 19537

APP_VERSION = "1.0.3"
