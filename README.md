# Beatcraft

An osu!-style rhythm game addon for WoW (TBC Anniversary, Classic Era).

- **Raid Mode**: your rotation as notes on the music's beat.
- **Downtime Mode**: full osu! gameplay between pulls.

## Setup

1. Run `Beatcraft Manager.bat` and choose **1** to install.
2. Put `.osz` beatmaps in `Import/` and choose **2** (or **3** for your osu! Songs folder).
3. Fully restart WoW.

## Commands

`/beat` menu · `/beat play` · `/beat raid` · `/beat editor` · `/beat calibrate` · `/beat unlock`

## Tests

```bash
python tools/run_tests.py <path to Library.lua>
```
