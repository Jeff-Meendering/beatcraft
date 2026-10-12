"""Builds a synthetic .osz (beatmap + fake MP3 + background) for testing the
importer and the addon without real osu! content.

usage: python tools/make_test_osz.py <output_dir>
"""
import io
import os
import sys
import zipfile

from PIL import Image, ImageDraw

OSU = """osu file format v14

[General]
AudioFilename: audio.mp3
AudioLeadIn: 0
PreviewTime: 10000
Mode: 0

[Metadata]
Title:Test Song
TitleUnicode:Test Song
Artist:Beatcraft "QA" \\ Team
Creator:tester
Version:{version}
Source:
Tags:test sample
BeatmapID:0
BeatmapSetID:{setid}

[Difficulty]
HPDrainRate:5
CircleSize:4
OverallDifficulty:{od}
ApproachRate:{ar}
SliderMultiplier:1.4
SliderTickRate:1

[Events]
//Background and Video events
0,0,"bg.png",0,0
//Break Periods
2,20000,24000

[TimingPoints]
1000,500,4,2,0,60,1,0
8000,-50,4,2,0,60,0,0
16000,-100,4,2,0,60,0,0
30000,400,4,2,0,60,1,0

[Colours]
Combo1 : 255,128,0
Combo2 : 0,200,255

[HitObjects]
{objects}
"""


def objects():
    lines = []
    t = 1000
    # circles on the beat
    for i in range(16):
        lines.append(f"{64 + (i % 8) * 50},{100 + (i % 3) * 60},{t},{5 if i == 0 else 1},0,0:0:0:0:")
        t += 500
    # sliders of each curve type
    lines.append(f"100,200,{t},6,0,B|150:100|250:100|300:200,1,250,0|0,0:0|0:0,0:0:0:0:")
    t += 1000
    lines.append(f"300,200,{t},2,0,P|350:100|400:200,2,150")
    t += 1500
    lines.append(f"100,300,{t},2,0,L|300:300,1,200")
    t += 1000
    lines.append(f"200,100,{t},2,0,C|250:150|300:100|350:150,1,180")
    t += 1000
    # spinner
    lines.append(f"256,192,{t},12,0,{t + 3000},0:0:0:0:")
    t += 4000
    # after the break (20000-24000)
    t = max(t, 25000)
    for i in range(20):
        lines.append(f"{80 + (i % 6) * 60},{80 + (i % 4) * 60},{t},1,0,0:0:0:0:")
        t += 400
    return "\n".join(lines)


def fake_mp3(seconds):
    # ID3v2 header with a small padded tag, then MPEG-1 Layer III frames
    tag = b"ID3" + bytes([4, 0, 0, 0, 0, 0, 20]) + b"\0" * 20
    frame_len = 417  # 128 kbps, 44.1 kHz, no padding
    header = bytes([0xFF, 0xFB, 0x90, 0x00])
    frame = header + b"\0" * (frame_len - 4)
    n = int(seconds * 44100 / 1152)
    return tag + frame * n


def background():
    im = Image.new("RGB", (1920, 1080), (30, 20, 60))
    d = ImageDraw.Draw(im)
    d.ellipse((760, 340, 1160, 740), fill=(255, 102, 170))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue()


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "Test Song.osz")
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("audio.mp3", fake_mp3(60))
        z.writestr("bg.png", background())
        for version, od, ar in (("Easy", 3, 4), ("Hard", 7, 8)):
            z.writestr(f"Beatcraft - Test Song (tester) [{version}].osu",
                       OSU.format(version=version, od=od, ar=ar, setid=987654, objects=objects()))
        # an osu!mania difficulty that must be skipped
        z.writestr("Beatcraft - Test Song (tester) [Mania].osu",
                   OSU.format(version="Mania", od=5, ar=5, setid=987654, objects=objects()).replace("Mode: 0", "Mode: 3"))
    print(path)


if __name__ == "__main__":
    main()
