"""app.paths - Youtube Scrapper."""


import os
import sys


def _base_dir():
    """Root folder the app reads its bundled data (fonts/, assets/) from.

    Works in three run modes:
      1. `python main.py`            → the project root (two levels up).
      2. PyInstaller --onedir/onefile → the unpacked bundle root, which
         PyInstaller advertises as sys._MEIPASS. Data files added through the
         spec's `datas=` land there, so fonts/ and assets/ resolve correctly
         regardless of where the .exe itself sits or what the current working
         directory happens to be when the user double-clicks it.
    """
    if getattr(sys, "frozen", False):
        # _MEIPASS is set by the PyInstaller bootloader (onefile: a temp
        # dir; onedir: the _internal folder next to the exe). Fall back to
        # the exe's own directory if it is somehow unset.
        return getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


BASE_DIR = _base_dir()


def asset_path(*parts):
    return os.path.join(BASE_DIR, *parts)
