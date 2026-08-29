#!/usr/bin/env python3
"""MediaSnag Windows launcher (no console window).

Invoked by:
- Desktop/Start Menu shortcut (no args → open Web UI)
- URL scheme registry (ytdl:// or ytdla:// argument)
"""

import os
import sys

app_dir = os.path.dirname(os.path.abspath(__file__))
if app_dir not in sys.path:
    sys.path.insert(0, os.path.dirname(app_dir))

from app.__main__ import main

main()
