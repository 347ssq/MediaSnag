#!/usr/bin/env python3
"""MediaSnag Windows launcher (no console window).

Invoked by:
- Desktop/Start Menu shortcut (no args → open Web UI)
- URL scheme registry (ytdl:// or ytdla:// argument)
"""

import os
import sys

# Get the directory containing this script (app directory)
app_dir = os.path.dirname(os.path.abspath(__file__))
# Get the parent directory (install root)
install_root = os.path.dirname(app_dir)

# pythonw.exe has no console: sys.stdout/stderr are None, and any print()
# would crash the app and kill the download server right after startup.
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")

# Named mutex so the installer can detect running instances and close
# them before replacing files (AppMutex=MediaSnagAppMutex in mediasnag.iss).
if sys.platform == "win32":
    try:
        import ctypes
        ctypes.windll.kernel32.CreateMutexW(None, False, "MediaSnagAppMutex")
    except Exception:
        pass

# Add both directories to sys.path for imports to work
for path in [install_root, app_dir]:
    if path not in sys.path:
        sys.path.insert(0, path)

try:
    from app.__main__ import main
    main()
except Exception as e:
    # If running without console, write error to a log file
    error_log = os.path.join(install_root, "error.log")
    with open(error_log, "w", encoding="utf-8") as f:
        import traceback
        f.write(f"Error: {e}\n\n")
        f.write(traceback.format_exc())
    # Try to show a message box
    try:
        import ctypes
        ctypes.windll.user32.MessageBoxW(0, str(e), "MediaSnag Error", 0x10)
    except:
        pass
    sys.exit(1)
