# Beatcraft

An osu!-style rhythm game addon for WoW (TBC Anniversary, Classic Era).

- **Raid Mode**: your rotation as notes on the music's beat.
- **Downtime Mode**: full osu! gameplay between pulls.

## Setup

1. Run `Beatcraft Manager.bat` and choose **1** to install.
2. Put `.osz` beatmaps in `Import/` and choose **2** (or **3** for your osu! Songs folder).
3. Fully restart WoW.

The manager can download ffmpeg to also import beatmap videos and hitsounds.

## Commands

`/beat` menu · `/beat play` · `/beat raid` · `/beat editor` · `/beat calibrate` · `/beat unlock` · Tab toggles the see-through background

During play: Z/X or mouse buttons hit notes, Escape pauses, Enter restarts a paused song, Escape again returns to song select, and ` retries. Minus/equals adjust the map's audio offset. WoW cannot seek audio, so paused songs restart to preserve sync.

Options include cursor size, mouse input, video, background dim, and optional kiai flashes. Song select expands difficulty cards in the song browser; double-click a difficulty to play. Slider ticks, repeats, and tails contribute to combo; circle stacks follow the map's stack leniency. Scores use Beatcraft's scoring model rather than matching osu! leaderboards.

Re-import maps once after updating to preserve slider edge sounds and map stack leniency. Restart WoW to load new textures or imported media.

Video imports default to 640x360 at 12 fps. The manager also accepts `-VideoQuality compact` (384x216, 8 fps) or `-VideoQuality sharp` (960x540, 12 fps). Higher quality uses more disk space; WoW displays video as texture atlases rather than native video playback. Existing imports keep their old quality until re-imported from the original beatmap.

## Tests

```bash
python tools/make_test_osz.py .work/test-import
powershell -NoProfile -File Importer/Beatcraft-Manager.ps1 -Action import -LibraryPath .work/test-library -Source .work/test-import
python tools/run_tests.py .work/test-library/Library.lua
```
