# Beatcraft

A rhythm game inside World of Warcraft, inspired by osu!.

- **Raid Mode**: your rotation becomes a song. Notes fall down one lane per ability, timed to land on the music's beat. You press your normal keybinds, the ability casts as usual, and Beatcraft scores your timing (Perfect / Great / Good / Miss), tracks your combo, and grades every fight.
- **Downtime Mode**: a full osu!-style game (circles, sliders, spinners, song select, mods, high scores) for the time between pulls, in queues, or in town. It closes itself when combat starts, a ready check goes out, or a queue pops.

Built for **TBC Anniversary** (2.5.x). It also loads on Classic Era, and is meant to move to **WoW: Forever** once that client exists.

Beatcraft never presses anything for you. Every cast is still your own key press, so it stays within Blizzard's addon rules.

---

## Install

1. Unzip everything somewhere, for example your Desktop.
2. Double-click **`Beatcraft Manager.bat`**.
3. Pick your WoW version if it asks, then choose **[1] Install / update the Beatcraft addon**.
4. Install **BugSack** and **BugGrabber** from CurseForge. If Beatcraft hits an error, they capture it so you can send it back.

## Add songs

Beatcraft plays osu! beatmaps. WoW can only play `.mp3` and `.ogg` audio, and nearly all osu! maps use mp3.

- **From `.osz` files:** put them in the `Import` folder and choose **[2]** in the manager.
- **From osu! (stable):** choose **[3]** and pick songs from your osu! Songs folder in the window that opens.
- **From osu!lazer:** export the maps as `.osz` first (right-click a map, then Export), then use **[2]**.

**Fully restart WoW after importing.** `/reload` is not enough, because WoW only notices new sound and image files at startup.

Songs are stored in a separate addon, `Beatcraft_Library`, so updating Beatcraft never deletes them. Only import maps you have on your own PC, and don't share the library folder publicly: the songs are copyrighted.

## Play

| Command | What it does |
|---|---|
| `/beat` | Main menu (also the pink minimap button) |
| `/beat play` | Song select (Downtime Mode) |
| `/beat raid` | Turn Raid Mode on/off (right-click the minimap button works too) |
| `/beat editor` | Rotation editor |
| `/beat calibrate` | Audio offset calibration, worth doing once |
| `/beat unlock` / `/beat lock` | Move the Raid Mode lanes |

### Raid Mode
- Turn it on and target an enemy. Lanes show your abilities with their keybinds.
- When combat starts, a song from your library starts playing. Each note lands on a beat inside WoW's 400 ms spell-queue window, so pressing on the beat **never delays your cast**.
- Abilities with a cast time (Slam, Steady Shot, Shadow Bolt...) are hold notes; finishing the cast completes them.
- Yellow-edged lanes are off-GCD abilities (Heroic Strike, Kill Command...).
- Healers, and any spec without a rotation, get **Freestyle**: every spell you cast is judged against the beat.
- **Song notes** (Options): extra lanes driven by the song's beatmap, hit with two spare keys (default Z/X; those keys are overridden only while Raid Mode is on). This is where the real rhythm-game difficulty comes in, so turn it up on farm content.
- After each fight you get a grade, accuracy and max combo.

### Downtime Mode
- Song select: type to search, Up/Down picks a song, Left/Right picks a difficulty, F2 picks a random song, Enter plays.
- Play with **Z / X** or the mouse buttons. During a song: **Esc** quits, **`** retries, **- / =** shifts that map's offset by 5 ms.
- Mods: EZ, NF, HR, HD.
- Personal bests are shared quietly with guildmates who also run Beatcraft (you can turn this off in Options), and appear as a guild leaderboard.

### Rotation editor
Every class and talent tree has a default priority list. Open `/beat editor` to change it. Conditions are short expressions like `combo >= 5 and debuff("Rupture") < 1`; the **Condition help** button lists everything you can use. **Import / Export** turns a rotation into text so you can share it with friends.

## Troubleshooting

- **"Could not play this song"**: restart WoW fully after importing.
- **No sound while alt-tabbed**: enable *Sound in Background* in WoW's sound settings.
- **Notes feel early or late**: run `/beat calibrate`, or adjust *Global audio offset* in Options.
- **Music too loud in raids**: pick a different *Music channel* in Options (for example Dialog), then turn that slider down in WoW's sound settings.
- **The addon is listed as out of date**: tick *Load out of date AddOns* on the AddOns screen.

## Status

Version 0.1.0 has **not been played inside the real game yet**. It was built against the TBC Anniversary client's API and tested headlessly: 318 automated checks run it in Lua 5.1 against a mock of the WoW API, including a full-combo autoplay of a test map and a simulated player in Raid Mode. Expect a round or two of fixes after first contact with the real client. Send any BugSack errors back.

---

## For developers

```
Beatcraft/            the addon (load order in Beatcraft.toc)
  Compat.lua          API wrappers across client flavors
  Rotation/           default rotations, condition sandbox, rotation engine
  Raid/RaidMode.lua   Raid Mode
  Game/               Downtime Mode: playfield, song select, results
  UI/                 menu, editor, options, calibration, minimap button
Importer/             Beatcraft-Manager.ps1 (installs the addon, builds Beatcraft_Library)
tools/                test harness and asset generators
```

Run the tests (needs Python and `pip install lupa`):

```bash
python tools/make_test_osz.py build/test_import
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File Importer/Beatcraft-Manager.ps1 -Action import -LibraryPath build/lib/Beatcraft_Library -Source build/test_import
```

```bash
python tools/run_tests.py build/lib/Beatcraft_Library/Library.lua
```

Regenerate textures with `python tools/make_media.py` (needs Pillow).
