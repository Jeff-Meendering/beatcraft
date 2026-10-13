"""Zips the addon folder into dist/Beatcraft-<version>.zip."""
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Beatcraft")


def main():
    with open(os.path.join(ADDON, "Beatcraft.toc"), encoding="utf-8") as f:
        version = re.search(r"^## Version:\s*(\S+)", f.read(), re.M).group(1)
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", "Beatcraft-%s.zip" % version)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, _, files in os.walk(ADDON):
            for name in sorted(files):
                path = os.path.join(folder, name)
                z.write(path, os.path.relpath(path, ROOT))
    print(out)


if __name__ == "__main__":
    main()
