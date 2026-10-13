# Beatcraft

An osu!-style rhythm game addon for WoW (TBC Anniversary, Classic Era).

- **Raid Mode**: your rotation as notes on the music's beat.
- **Downtime Mode**: full osu! gameplay between pulls.
- **Moving raid frames**: real party/raid or focus frames that jump after every click, in or out of combat.
- **Frame Practice**: an out-of-combat aim drill with simulated moving frames.

## Setup

1. Run `Beatcraft Manager.bat` and choose **1** to install.
2. Put `.osz` beatmaps in `Import/` and choose **2** (or **3** for your osu! Songs folder).
3. Fully restart WoW.

The manager can download ffmpeg to also import beatmap videos and hitsounds.

## Commands

`/beat` menu · `/beat play` · `/beat live` · `/beat frames` · `/beat raid` · `/beat editor` · `/beat calibrate` · `/beat unlock` · Tab toggles the see-through background

**Moving raid frames** (`/beat live`): real secure unit frames that target (or cast a spell you set) on left-click, then jump to a random spot nearby. The most injured member is marked **CLICK**; hitting it builds a combo and a summary prints after each fight. WoW blocks addons from moving these frames smoothly in combat, so they hop on each click instead. Settings changed mid-fight apply when combat ends.

**Frame Practice** (`/beat frames`): simulated raid or focus frames drift around for 30 seconds; click the one marked **CLICK**. Bests are saved per style and speed. It closes when combat starts.

The default background lightly blends the song image or video over the WoW world at 85% opacity, with the interface at 95% opacity. Tab cycles through blended, song, and world-only backgrounds; your selection is saved. Options includes a song/video opacity slider.

During play: Z/X or mouse buttons hit notes, Escape pauses, Enter restarts a paused song, Escape again returns to song select, and ` retries. Minus/equals adjust the map's audio offset. WoW cannot seek audio, so paused songs restart to preserve sync.

Options include cursor size, mouse input, video, background dim, and optional kiai flashes. Song select expands difficulty cards in the song browser; double-click a difficulty to play. Slider ticks, repeats, and tails contribute to combo; circle stacks follow the map's stack leniency. Scores use Beatcraft's scoring model rather than matching osu! leaderboards.

Re-import maps once after updating to preserve slider edge sounds and map stack leniency. Restart WoW to load new textures or imported media.

Video imports default to 640x360 at 12 fps. The manager also accepts `-VideoQuality compact` (384x216, 8 fps) or `-VideoQuality sharp` (960x540, 12 fps). Higher quality uses more disk space; WoW displays video as texture atlases rather than native video playback. Existing imports keep their old quality until re-imported from the original beatmap.

## Tests

```bash
python tools/make_test_osz.py .work/test-import
powershell -NoProfile -File Importer/Beatcraft-Manager.ps1 -Action import -LibraryPath .work/test-library -Source .work/test-import
python tools/run_tests.py
```

`python tools/package.py` builds `dist/Beatcraft-<version>.zip`.
