"""Runs the headless Beatcraft tests in a real Lua 5.1 runtime (via lupa)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".work", "pydeps"))

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".work", "test-library", "Library.lua")
    if not os.path.isfile(path):
        sys.exit("Test library not found: %s (build it with the commands in README.md)" % path)
    lib = os.path.abspath(path).replace("\\", "/")
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = os.path.join(ROOT, "Beatcraft").replace("\\", "/")
    g.LIB_PATH = lib
    for name in ("wowmock.lua", "test_addon.lua", "test_gameplay.lua", "test_frame_practice.lua", "test_live_frames.lua"):
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            L.execute(f.read())
    sys.exit(1 if g.RESULT_FAILED else 0)


if __name__ == "__main__":
    main()
