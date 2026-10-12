"""Runs the headless Beatcraft tests in a real Lua 5.1 runtime (via lupa).

usage: python tools/run_tests.py <path to generated Library.lua>
Requires: pip install lupa
"""
import os
import sys

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    lib = os.path.abspath(sys.argv[1]).replace("\\", "/")
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = os.path.join(ROOT, "Beatcraft").replace("\\", "/")
    g.LIB_PATH = lib
    for name in ("wowmock.lua", "test_addon.lua"):
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            L.execute(f.read())
    sys.exit(1 if g.RESULT_FAILED else 0)


if __name__ == "__main__":
    main()
