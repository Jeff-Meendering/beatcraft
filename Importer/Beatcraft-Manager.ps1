param(
	[string]$WowPath,
	[string]$LibraryPath,
	[string]$Action,
	[string]$Source,
	[ValidateSet('compact', 'clear', 'sharp')][string]$VideoQuality = 'clear'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsFile = Join-Path $ScriptDir 'settings.json'
$AddonSource = Join-Path $Root 'Beatcraft'
$ImportDir = Join-Path $Root 'Import'
$LibAddon = 'Beatcraft_Library'
$FfmpegDir = Join-Path $ScriptDir 'ffmpeg'
$FfmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$VideoProfiles = @{
	compact = @{ Fps = 8; Cols = 5; Rows = 9; W = 384; H = 216; Size = 2048 }
	clear = @{ Fps = 12; Cols = 3; Rows = 5; W = 640; H = 360; Size = 2048 }
	sharp = @{ Fps = 12; Cols = 2; Rows = 3; W = 960; H = 540; Size = 2048 }
}
$Video = $VideoProfiles[$VideoQuality]
$script:Ffmpeg = $null
$script:IncludeVideo = $true
$Utf8 = New-Object System.Text.UTF8Encoding $false

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Info($msg) { Write-Host $msg -ForegroundColor Gray }
function Write-Good($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Title($msg) { Write-Host $msg -ForegroundColor Magenta }

function Get-Settings {
	if (Test-Path -LiteralPath $SettingsFile) {
		try { return Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json } catch { }
	}
	return [pscustomobject]@{ WowPath = $null; OsuSongs = $null }
}

function Get-Setting($s, [string]$name, $default) {
	$p = $s.PSObject.Properties[$name]
	if ($p -and $null -ne $p.Value) { return $p.Value }
	return $default
}

function Set-Setting($s, [string]$name, $value) {
	$s | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

function Save-Settings($s) {
	[IO.File]::WriteAllText($SettingsFile, ($s | ConvertTo-Json), $Utf8)
}

function Find-WowRoots {
	$roots = New-Object System.Collections.Generic.List[string]
	foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')) {
		try {
			$p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
			if ($p) { $roots.Add((Split-Path -Parent $p.TrimEnd('\'))) }
		} catch { }
	}
	foreach ($drive in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
		foreach ($sub in @('Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft', 'Games\World of Warcraft', 'Blizzard\World of Warcraft')) {
			$roots.Add((Join-Path $drive $sub))
		}
	}
	$roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique
}

function Find-Flavors {
	$list = @()
	foreach ($root in Find-WowRoots) {
		foreach ($d in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
			if ($d.Name -match '^_.+_$' -and $d.Name -ne '_retail_' -and $d.Name -ne '_ptr_') {
				$list += $d.FullName
			}
		}
	}
	return $list
}

function Select-Flavor($settings, [switch]$Force) {
	if (-not $Force -and $settings.WowPath -and (Test-Path -LiteralPath $settings.WowPath)) { return $settings.WowPath }
	$flavors = @(Find-Flavors)
	if ($flavors.Count -eq 0) {
		Write-Warn 'Could not find World of Warcraft automatically.'
		$p = Read-Host 'Paste the path of your WoW version folder (for example C:\Program Files (x86)\World of Warcraft\_anniversary_)'
		if (-not (Test-Path -LiteralPath $p)) { throw "Folder not found: $p" }
		$settings.WowPath = $p
	} elseif ($flavors.Count -eq 1 -and -not $Force) {
		$settings.WowPath = $flavors[0]
	} else {
		Write-Host ''
		Write-Host 'Which WoW version do you play Beatcraft on?'
		for ($i = 0; $i -lt $flavors.Count; $i++) {
			$hint = ''
			if ($flavors[$i] -like '*_anniversary_') { $hint = '  (TBC Anniversary)' }
			if ($flavors[$i] -like '*_classic_era_') { $hint = '  (Classic Era)' }
			Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $flavors[$i], $hint)
		}
		$pick = Read-Host 'Number'
		$n = 0
		if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $flavors.Count) { throw 'Invalid choice.' }
		$settings.WowPath = $flavors[$n - 1]
	}
	Save-Settings $settings
	return $settings.WowPath
}

function Read-OsuFile([string]$path) {
	$lines = [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)
	$data = @{
		Path = $path; FormatVersion = 14; General = @{}; Metadata = @{}; Difficulty = @{}; Colours = @{}
		Events = New-Object System.Collections.Generic.List[string]
		TimingPoints = New-Object System.Collections.Generic.List[string]
		HitObjects = New-Object System.Collections.Generic.List[string]
	}
	$section = ''
	foreach ($raw in $lines) {
		$line = $raw.Trim()
		if ($line -eq '' -or $line.StartsWith('//')) { continue }
		if ($line -match '^osu file format v(\d+)$') { $data.FormatVersion = [int]$Matches[1]; continue }
		if ($line -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
		switch ($section) {
			{ $_ -in 'General', 'Metadata', 'Difficulty', 'Colours' } {
				$i = $line.IndexOf(':')
				if ($i -gt 0) { $data[$section][$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
			}
			'Events' { $data.Events.Add($line) }
			'TimingPoints' { $data.TimingPoints.Add($line) }
			'HitObjects' { $data.HitObjects.Add($line) }
		}
	}
	$mode = 0
	if ($data.General.ContainsKey('Mode')) { $mode = [int]$data.General['Mode'] }
	$data.Mode = $mode
	return $data
}

function Get-Field($table, $key, $default) {
	if ($table.ContainsKey($key) -and $table[$key] -ne '') { return $table[$key] }
	return $default
}

function Get-Background($osu) {
	foreach ($e in $osu.Events) {
		if ($e -match '^(0|Background),\s*0\s*,\s*"([^"]+)"') { return $Matches[2] }
		if ($e -match '^(0|Background),\s*0\s*,\s*([^,]+)') { return $Matches[2].Trim() }
	}
	return $null
}

function Get-FileMd5([string]$path) {
	$md5 = [Security.Cryptography.MD5]::Create()
	try {
		$bytes = [IO.File]::ReadAllBytes($path)
		return (($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
	} finally { $md5.Dispose() }
}

function Get-StringMd5([string]$s) {
	$md5 = [Security.Cryptography.MD5]::Create()
	try {
		return (($md5.ComputeHash($Utf8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join '')
	} finally { $md5.Dispose() }
}

function Convert-ImageToTga([string]$src, [string]$dst, [int]$width = 1024, [int]$height = 512) {
	$bytes = [IO.File]::ReadAllBytes($src)
	$ms = New-Object IO.MemoryStream(, $bytes)
	$img = [Drawing.Image]::FromStream($ms)
	try {
		$targetRatio = $width / $height
		$srcRatio = $img.Width / $img.Height
		if ($srcRatio -gt $targetRatio) {
			$cropH = $img.Height; $cropW = [int]($img.Height * $targetRatio)
		} else {
			$cropW = $img.Width; $cropH = [int]($img.Width / $targetRatio)
		}
		$cropX = [int](($img.Width - $cropW) / 2); $cropY = [int](($img.Height - $cropH) / 2)
		$bmp = New-Object Drawing.Bitmap($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
		$g = [Drawing.Graphics]::FromImage($bmp)
		$g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
		$g.DrawImage($img, (New-Object Drawing.Rectangle(0, 0, $width, $height)), $cropX, $cropY, $cropW, $cropH, [Drawing.GraphicsUnit]::Pixel)
		$g.Dispose()
		$rect = New-Object Drawing.Rectangle(0, 0, $width, $height)
		$data = $bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
		$stride = $data.Stride
		$pixels = New-Object byte[] ($stride * $height)
		[Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
		$bmp.UnlockBits($data)
		$bmp.Dispose()
		$rowBytes = $width * 4
		$out = New-Object byte[] (18 + $rowBytes * $height)
		$out[2] = 2
		$out[12] = $width -band 0xFF; $out[13] = $width -shr 8
		$out[14] = $height -band 0xFF; $out[15] = $height -shr 8
		$out[16] = 32; $out[17] = 8
		for ($y = 0; $y -lt $height; $y++) {
			[Array]::Copy($pixels, $y * $stride, $out, 18 + ($height - 1 - $y) * $rowBytes, $rowBytes)
		}
		[IO.File]::WriteAllBytes($dst, $out)
	} finally {
		$img.Dispose(); $ms.Dispose()
	}
}

$Mp3Bitrates1 = @(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
$Mp3Bitrates2 = @(0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)
$Mp3Rates = @{ 3 = @(44100, 48000, 32000); 2 = @(22050, 24000, 16000); 0 = @(11025, 12000, 8000) }

function Get-Mp3Frames([byte[]]$b) {
	$frames = New-Object System.Collections.Generic.List[object]
	$pos = 0
	if ($b.Length -gt 10 -and $b[0] -eq 0x49 -and $b[1] -eq 0x44 -and $b[2] -eq 0x33) {
		$size = ($b[6] -shl 21) -bor ($b[7] -shl 14) -bor ($b[8] -shl 7) -bor $b[9]
		$pos = 10 + $size
		if (($b[5] -band 0x10) -ne 0) { $pos += 10 }
	}
	$n = $b.Length
	while ($pos + 4 -le $n) {
		if ($b[$pos] -ne 0xFF -or ($b[$pos + 1] -band 0xE0) -ne 0xE0) { $pos++; continue }
		$ver = ($b[$pos + 1] -shr 3) -band 3
		$layer = ($b[$pos + 1] -shr 1) -band 3
		$brIdx = ($b[$pos + 2] -shr 4) -band 15
		$srIdx = ($b[$pos + 2] -shr 2) -band 3
		$pad = ($b[$pos + 2] -shr 1) -band 1
		if ($ver -eq 1 -or $layer -ne 1 -or $brIdx -eq 0 -or $brIdx -eq 15 -or $srIdx -eq 3) { $pos++; continue }
		$rate = $Mp3Rates[$ver][$srIdx]
		if ($ver -eq 3) {
			$br = $Mp3Bitrates1[$brIdx] * 1000
			$len = [int][Math]::Floor(144 * $br / $rate) + $pad
			$samples = 1152
		} else {
			$br = $Mp3Bitrates2[$brIdx] * 1000
			$len = [int][Math]::Floor(72 * $br / $rate) + $pad
			$samples = 576
		}
		if ($len -lt 5) { $pos++; continue }
		$frames.Add(@($pos, $len, ($samples * 1000.0 / $rate)))
		$pos += $len
	}
	return , $frames
}

function Save-Mp3Preview([string]$src, [string]$dst, [double]$startMs, [double]$durMs) {
	$b = [IO.File]::ReadAllBytes($src)
	$frames = Get-Mp3Frames $b
	if ($frames.Count -lt 10) { return 0 }
	$total = 0.0
	foreach ($f in $frames) { $total += $f[2] }
	if ($startMs -lt 0 -or $startMs -ge $total) { $startMs = $total * 0.4 }
	$t = 0.0; $first = -1; $last = -1
	for ($i = 0; $i -lt $frames.Count; $i++) {
		if ($first -lt 0 -and $t -ge $startMs) { $first = $i }
		if ($first -ge 0 -and $t -ge $startMs + $durMs) { break }
		$last = $i
		$t += $frames[$i][2]
	}
	if ($first -lt 0 -or $last -le $first) { return $total }
	$from = $frames[$first][0]
	$to = $frames[$last][0] + $frames[$last][1]
	if ($to -gt $b.Length) { $to = $b.Length }
	$out = New-Object byte[] ($to - $from)
	[Array]::Copy($b, $from, $out, 0, $out.Length)
	[IO.File]::WriteAllBytes($dst, $out)
	return $total
}

$BlpSource = @'
using System;
using System.IO;

public static class BeatcraftBlp {
	public static void FromTga(string tgaPath, string blpPath) {
		byte[] t = File.ReadAllBytes(tgaPath);
		if (t[2] != 2) throw new Exception("TGA must be uncompressed");
		int w = t[12] | (t[13] << 8), h = t[14] | (t[15] << 8), px = t[16] / 8;
		bool topDown = (t[17] & 0x20) != 0;
		int off = 18 + t[0];
		int bw = w / 4, bh = h / 4;
		byte[] data = new byte[bw * bh * 16];
		byte[] r = new byte[16], g = new byte[16], b = new byte[16];
		int o = 0;
		for (int by = 0; by < bh; by++) {
			for (int bx = 0; bx < bw; bx++) {
				for (int i = 0; i < 16; i++) {
					int x = bx * 4 + (i & 3), y = by * 4 + (i >> 2);
					int row = topDown ? y : h - 1 - y;
					int p = off + (row * w + x) * px;
					b[i] = t[p]; g[i] = t[p + 1]; r[i] = t[p + 2];
				}
				data[o] = 255; data[o + 1] = 255;
				o += 8;
				EncodeColor(r, g, b, data, o);
				o += 8;
			}
		}
		using (var fs = new FileStream(blpPath, FileMode.Create))
		using (var bw2 = new BinaryWriter(fs)) {
			bw2.Write(new byte[] { 66, 76, 80, 50 });
			bw2.Write((uint)1);
			bw2.Write((byte)2); bw2.Write((byte)8); bw2.Write((byte)7); bw2.Write((byte)0);
			bw2.Write((uint)w); bw2.Write((uint)h);
			bw2.Write((uint)1172);
			for (int k = 1; k < 16; k++) bw2.Write((uint)0);
			bw2.Write((uint)data.Length);
			for (int k = 1; k < 16; k++) bw2.Write((uint)0);
			bw2.Write(new byte[1024]);
			bw2.Write(data);
		}
	}

	static int To565(int r, int g, int b) {
		return ((r * 31 + 127) / 255 << 11) | ((g * 63 + 127) / 255 << 5) | ((b * 31 + 127) / 255);
	}

	static void Expand(int c, out int r, out int g, out int b) {
		r = ((c >> 11) & 31) * 255 / 31;
		g = ((c >> 5) & 63) * 255 / 63;
		b = (c & 31) * 255 / 31;
	}

	static void EncodeColor(byte[] r, byte[] g, byte[] b, byte[] dst, int o) {
		int minR = 255, minG = 255, minB = 255, maxR = 0, maxG = 0, maxB = 0;
		for (int i = 0; i < 16; i++) {
			minR = Math.Min(minR, r[i]); maxR = Math.Max(maxR, r[i]);
			minG = Math.Min(minG, g[i]); maxG = Math.Max(maxG, g[i]);
			minB = Math.Min(minB, b[i]); maxB = Math.Max(maxB, b[i]);
		}
		int insR = (maxR - minR) >> 4, insG = (maxG - minG) >> 4, insB = (maxB - minB) >> 4;
		int c0 = To565(maxR - insR, maxG - insG, maxB - insB);
		int c1 = To565(minR + insR, minG + insG, minB + insB);
		if (c0 < c1) { int tmp = c0; c0 = c1; c1 = tmp; }
		uint idx = 0;
		if (c0 != c1) {
			int r0, g0, b0, r1, g1, b1;
			Expand(c0, out r0, out g0, out b0);
			Expand(c1, out r1, out g1, out b1);
			int[] pr = { r0, r1, (2 * r0 + r1) / 3, (r0 + 2 * r1) / 3 };
			int[] pg = { g0, g1, (2 * g0 + g1) / 3, (g0 + 2 * g1) / 3 };
			int[] pb = { b0, b1, (2 * b0 + b1) / 3, (b0 + 2 * b1) / 3 };
			for (int i = 0; i < 16; i++) {
				int best = 0, bestD = int.MaxValue;
				for (int k = 0; k < 4; k++) {
					int dr = r[i] - pr[k], dg = g[i] - pg[k], db = b[i] - pb[k];
					int d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
					if (d < bestD) { bestD = d; best = k; }
				}
				idx |= (uint)best << (2 * i);
			}
		}
		dst[o] = (byte)(c0 & 255); dst[o + 1] = (byte)(c0 >> 8);
		dst[o + 2] = (byte)(c1 & 255); dst[o + 3] = (byte)(c1 >> 8);
		dst[o + 4] = (byte)(idx & 255); dst[o + 5] = (byte)((idx >> 8) & 255);
		dst[o + 6] = (byte)((idx >> 16) & 255); dst[o + 7] = (byte)(idx >> 24);
	}
}
'@

function Find-Ffmpeg {
	$local = Join-Path $FfmpegDir 'ffmpeg.exe'
	if (Test-Path -LiteralPath $local) { return $local }
	$cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	return $null
}

function Install-Ffmpeg {
	$ProgressPreference = 'SilentlyContinue'
	$zip = Join-Path ([IO.Path]::GetTempPath()) 'beatcraft-ffmpeg.zip'
	$tmp = Join-Path ([IO.Path]::GetTempPath()) ('beatcraft-ffmpeg-' + [Guid]::NewGuid().ToString('N'))
	try {
		Write-Info 'Downloading ffmpeg (about 110 MB)...'
		Invoke-WebRequest -Uri $FfmpegUrl -OutFile $zip -UseBasicParsing
		[IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
		$exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
		New-Item -ItemType Directory -Path $FfmpegDir -Force | Out-Null
		Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $FfmpegDir 'ffmpeg.exe')
		Write-Good 'ffmpeg installed.'
		return (Join-Path $FfmpegDir 'ffmpeg.exe')
	} finally {
		if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
		if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
	}
}

function Initialize-Ffmpeg($settings, [switch]$Interactive) {
	$script:IncludeVideo = Get-Setting $settings 'IncludeVideo' $true
	$script:Ffmpeg = Find-Ffmpeg
	if (-not $script:Ffmpeg -and $Interactive -and -not (Get-Setting $settings 'AskedFfmpeg' $false)) {
		Write-Host ''
		Write-Host 'Beatcraft can also import beatmap videos and hitsounds using ffmpeg (free, ~110 MB from gyan.dev).'
		$a = Read-Host 'Download ffmpeg now? (y/n)'
		Set-Setting $settings 'AskedFfmpeg' $true
		Save-Settings $settings
		if ($a -match '^[yY]') { $script:Ffmpeg = Install-Ffmpeg }
	}
}

function Invoke-Ffmpeg([string[]]$arguments) {
	$old = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try {
		$out = & $script:Ffmpeg @arguments 2>&1 | ForEach-Object { "$_" }
		return @{ Ok = ($LASTEXITCODE -eq 0); Output = ($out -join "`n") }
	} finally {
		$ErrorActionPreference = $old
	}
}

function Get-VideoEvent($osu) {
	foreach ($e in $osu.Events) {
		if ($e -match '^(1|Video)\s*,\s*(-?\d+)\s*,\s*"?([^",]+)"?') { return @([int]$Matches[2], $Matches[3].Trim()) }
	}
	return $null
}

function Save-Video([string]$src, [string]$dest, [int]$offset) {
	$probe = Invoke-Ffmpeg @('-hide_banner', '-i', $src)
	if ($probe.Output -notmatch 'Duration:\s*(\d+):(\d+):(\d+(\.\d+)?)') { throw 'could not read video length' }
	$seconds = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + (ConvertTo-Double $Matches[3])
	$revision = (Get-StringMd5 ((Get-FileMd5 $src) + ":" + (@($Video.Fps, $Video.Cols, $Video.Rows, $Video.W, $Video.H, $Video.Size) -join ':'))).Substring(0, 12)
	$assetDir = 'q' + $revision
	$videoRoot = Join-Path $dest 'video'
	$dir = Join-Path $videoRoot $assetDir
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
	$filter = "fps=$($Video.Fps),scale=$($Video.W):$($Video.H):force_original_aspect_ratio=increase:flags=lanczos,crop=$($Video.W):$($Video.H),tile=$($Video.Cols)x$($Video.Rows),pad=$($Video.Size):$($Video.Size):0:0"
	$r = Invoke-Ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-i', $src, '-an', '-vf', $filter, '-c:v', 'targa', '-rle', '0', '-pix_fmt', 'bgra', (Join-Path $dir 'v%03d.tga'))
	if (-not $r.Ok) { throw $r.Output }
	if (-not ('BeatcraftBlp' -as [type])) { Add-Type -TypeDefinition $BlpSource -Language CSharp }
	$sheets = @(Get-ChildItem -LiteralPath $dir -Filter 'v*.tga')
	foreach ($sheet in $sheets) {
		[BeatcraftBlp]::FromTga($sheet.FullName, [IO.Path]::ChangeExtension($sheet.FullName, '.blp'))
		Remove-Item -LiteralPath $sheet.FullName
	}
	$frames = [int][Math]::Floor($seconds * $Video.Fps)
	$info = @($offset, $Video.Fps, $Video.Cols, $Video.Rows, $Video.W, $Video.H, $Video.Size, $sheets.Count, $frames, $assetDir) -join ' '
	[IO.File]::WriteAllText((Join-Path $videoRoot 'video.txt'), $info)
	return $sheets.Count
}

function Save-Hitsounds([string]$src, [string]$dest) {
	$dir = Join-Path $dest 'hs'
	$count = 0
	foreach ($f in Get-ChildItem -LiteralPath $src -File) {
		if ($f.Name -notmatch '^(normal|soft|drum)-(hitnormal|hitwhistle|hitfinish|hitclap)(\d*)\.(wav|ogg|mp3)$') { continue }
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		$name = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()
		if ($f.Length -lt 100) {
			[IO.File]::WriteAllText((Join-Path $dir "$name.silent"), '')
		} elseif ($f.Extension -ieq '.ogg') {
			Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dir "$name.ogg")
		} else {
			$r = Invoke-Ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-i', $f.FullName, '-c:a', 'libvorbis', '-q:a', '5', '-ar', '44100', (Join-Path $dir "$name.ogg"))
			if (-not $r.Ok) { continue }
		}
		$count++
	}
	return $count
}

function Get-LibraryRoot([string]$wow) {
	if ($LibraryPath) { return $LibraryPath }
	return Join-Path $wow "Interface\AddOns\$LibAddon"
}

function Import-SetFolder([string]$dir, [string]$libRoot, [string]$label) {
	$osuFiles = @(Get-ChildItem -LiteralPath $dir -Filter '*.osu' -File)
	$maps = @()
	foreach ($f in $osuFiles) {
		try {
			$m = Read-OsuFile $f.FullName
			if ($m.Mode -eq 0 -and $m.HitObjects.Count -gt 0) { $maps += $m }
		} catch { Write-Warn "  could not read $($f.Name): $_" }
	}
	$name = $label
	if (-not $name) { $name = Split-Path -Leaf $dir }
	if ($maps.Count -eq 0) {
		$modes = @{ 1 = 'osu!taiko'; 2 = 'osu!catch'; 3 = 'osu!mania' }
		$found = @($osuFiles | ForEach-Object { try { $modes[(Read-OsuFile $_.FullName).Mode] } catch { } } | Where-Object { $_ } | Select-Object -Unique)
		if ($found.Count -gt 0) {
			Write-Warn "  skipped '$name': it's an $($found -join '/') map; Beatcraft plays osu!standard maps only"
		} else {
			Write-Warn "  skipped '$name': no osu!standard difficulties"
		}
		return $false
	}
	$first = $maps[0]
	$audio = Get-Field $first.General 'AudioFilename' ''
	$audioPath = Join-Path $dir $audio
	$ext = [IO.Path]::GetExtension($audio).ToLower()
	if (-not (Test-Path -LiteralPath $audioPath)) {
		Write-Warn "  skipped '$name': audio file '$audio' is missing"
		return $false
	}
	if ($ext -ne '.mp3' -and $ext -ne '.ogg') {
		Write-Warn "  skipped '$name': WoW can only play .mp3 or .ogg (this song is $ext)"
		return $false
	}
	$meta = $first.Metadata
	$setId = 0
	[void][int]::TryParse((Get-Field $meta 'BeatmapSetID' '0'), [ref]$setId)
	if ($setId -gt 0) {
		$id = "set$setId"
	} else {
		$id = 'h' + (Get-StringMd5 ((Get-Field $meta 'Title' '') + '|' + (Get-Field $meta 'Artist' '') + '|' + (Get-Field $meta 'Creator' ''))).Substring(0, 10)
	}
	$dest = Join-Path $libRoot "Songs\$id"
	if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
	New-Item -ItemType Directory -Path $dest -Force | Out-Null

	Copy-Item -LiteralPath $audioPath -Destination (Join-Path $dest "audio$ext")
	$i = 0
	foreach ($m in $maps) {
		if ((Get-Field $m.General 'AudioFilename' '') -ne $audio) { continue }
		$i++
		Copy-Item -LiteralPath $m.Path -Destination (Join-Path $dest ("map{0:D2}.osu" -f $i))
	}

	$bg = Get-Background $first
	if ($bg) {
		$bgPath = Join-Path $dir $bg
		if (Test-Path -LiteralPath $bgPath) {
			try { Convert-ImageToTga $bgPath (Join-Path $dest 'bg.tga') } catch { Write-Warn "  background not converted: $_" }
		}
	}
	if ($ext -eq '.mp3') {
		$previewTime = ConvertTo-Double (Get-Field $first.General 'PreviewTime' '-1')
		try {
			$total = Save-Mp3Preview (Join-Path $dest "audio$ext") (Join-Path $dest 'preview.mp3') $previewTime 20000
			if ($total -gt 0) { [IO.File]::WriteAllText((Join-Path $dest 'length.txt'), [string][int]$total) }
		} catch { Write-Warn "  preview not created: $_" }
	}
	$extras = @()
	if ($script:Ffmpeg) {
		$vid = Get-VideoEvent $first
		if ($vid -and $script:IncludeVideo) {
			$vidPath = Join-Path $dir $vid[1]
			if (Test-Path -LiteralPath $vidPath) {
				try { $extras += "video, $(Save-Video $vidPath $dest $vid[0]) sheets" } catch { Write-Warn "  video not converted: $_" }
			}
		}
		try {
			$n = Save-Hitsounds $dir $dest
			if ($n -gt 0) { $extras += "$n hitsounds" }
		} catch { Write-Warn "  hitsounds not converted: $_" }
	}
	$extraText = ''
	if ($extras.Count -gt 0) { $extraText = ', ' + ($extras -join ', ') }
	Write-Good ("  + {0} - {1}  ({2} difficulties{3})" -f (Get-Field $meta 'Artist' '?'), (Get-Field $meta 'Title' '?'), $i, $extraText)
	return $true
}

function Import-Osz([string]$file, [string]$libRoot) {
	$tmp = Join-Path ([IO.Path]::GetTempPath()) ('beatcraft_' + [Guid]::NewGuid().ToString('N'))
	try {
		[IO.Compression.ZipFile]::ExtractToDirectory($file, $tmp)
		return Import-SetFolder $tmp $libRoot (Split-Path -Leaf $file)
	} catch {
		Write-Warn "  could not open $(Split-Path -Leaf $file): $_"
		return $false
	} finally {
		if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
	}
}

function ConvertTo-LuaString([string]$s) {
	if ($null -eq $s) { $s = '' }
	$sb = New-Object Text.StringBuilder
	[void]$sb.Append('"')
	foreach ($ch in $s.ToCharArray()) {
		switch ($ch) {
			'\' { [void]$sb.Append('\\') }
			'"' { [void]$sb.Append('\"') }
			"`n" { [void]$sb.Append('\n') }
			"`r" { }
			default {
				if ([int]$ch -lt 32) { [void]$sb.Append(' ') } else { [void]$sb.Append($ch) }
			}
		}
	}
	[void]$sb.Append('"')
	return $sb.ToString()
}

$Invariant = [Globalization.CultureInfo]::InvariantCulture

function ConvertTo-Double($v) {
	if ($v -is [string]) { return [double]::Parse($v.Trim(), $Invariant) }
	return [double]$v
}

function ConvertTo-LuaNumber($v) {
	return (ConvertTo-Double $v).ToString($Invariant)
}

function Compress-HitObject([string]$line) {
	$f = $line.Split(',')
	if ($f.Count -lt 4) { return $null }
	$type = 0
	[void][int]::TryParse($f[3], [ref]$type)
	if (($type -band 2) -ne 0) { $keep = 11 } elseif (($type -band 8) -ne 0) { $keep = 7 } else { $keep = 6 }
	if ($f.Count -lt $keep) { $keep = $f.Count }
	return ($f[0..($keep - 1)] -join ',')
}

function Get-MapEntry($osu, [string]$hash) {
	$d = $osu.Difficulty
	$objects = New-Object System.Collections.Generic.List[string]
	$firstT = $null; $lastT = 0
	foreach ($line in $osu.HitObjects) {
		$c = Compress-HitObject $line
		if (-not $c) { continue }
		$objects.Add($c)
		$f = $c.Split(',')
		$t = [double]::Parse($f[2], [Globalization.CultureInfo]::InvariantCulture)
		if ($null -eq $firstT) { $firstT = $t }
		$end = $t
		if (([int]$f[3] -band 8) -ne 0 -and $f.Count -ge 6) { $end = ConvertTo-Double $f[5] }
		if ($end -gt $lastT) { $lastT = $end }
	}
	if ($null -eq $firstT) { $firstT = 0 }

	$reds = @()
	foreach ($tp in $osu.TimingPoints) {
		$f = $tp.Split(',')
		if ($f.Count -lt 2) { continue }
		$bl = [double]::Parse($f[1], [Globalization.CultureInfo]::InvariantCulture)
		$un = ($f.Count -lt 7) -or ($f[6] -eq '1')
		if ($un -and $bl -gt 0) { $reds += , @([double]::Parse($f[0], [Globalization.CultureInfo]::InvariantCulture), $bl) }
	}
	$bpm = 120
	$best = -1
	for ($i = 0; $i -lt $reds.Count; $i++) {
		$start = $reds[$i][0]
		$end = $lastT
		if ($i + 1 -lt $reds.Count) { $end = $reds[$i + 1][0] }
		if ($end - $start -gt $best) { $best = $end - $start; $bpm = 60000 / $reds[$i][1] }
	}

	$breaks = @()
	foreach ($e in $osu.Events) {
		if ($e -match '^(2|Break)\s*,\s*(-?\d+)\s*,\s*(-?\d+)') { $breaks += "$($Matches[2]),$($Matches[3])" }
	}

	$colors = @()
	foreach ($k in ($osu.Colours.Keys | Where-Object { $_ -match '^Combo\d+$' } | Sort-Object { [int]($_ -replace 'Combo', '') })) {
		$v = $osu.Colours[$k] -replace '\s', ''
		if ($v -match '^\d+,\d+,\d+') { $colors += ($v.Split(',')[0..2] -join ',') }
	}

	$od = Get-Field $d 'OverallDifficulty' '5'
	$sb = New-Object Text.StringBuilder
	[void]$sb.Append("{version=$(ConvertTo-LuaString (Get-Field $osu.Metadata 'Version' 'Normal'))")
	[void]$sb.Append(",hash=`"$hash`"")
	[void]$sb.Append(",hp=$(ConvertTo-LuaNumber (Get-Field $d 'HPDrainRate' '5'))")
	[void]$sb.Append(",cs=$(ConvertTo-LuaNumber (Get-Field $d 'CircleSize' '4'))")
	[void]$sb.Append(",od=$(ConvertTo-LuaNumber $od)")
	[void]$sb.Append(",ar=$(ConvertTo-LuaNumber (Get-Field $d 'ApproachRate' $od))")
	[void]$sb.Append(",sm=$(ConvertTo-LuaNumber (Get-Field $d 'SliderMultiplier' '1.4'))")
	[void]$sb.Append(",tr=$(ConvertTo-LuaNumber (Get-Field $d 'SliderTickRate' '1'))")
	[void]$sb.Append(",n=$($objects.Count),first=$(ConvertTo-LuaNumber $firstT),last=$(ConvertTo-LuaNumber $lastT),len=$(ConvertTo-LuaNumber ($lastT - $firstT))")
	[void]$sb.Append(",bpm=$(ConvertTo-LuaNumber ([Math]::Round($bpm, 2)))")
	[void]$sb.Append(",lead=$(ConvertTo-LuaNumber (Get-Field $osu.General 'AudioLeadIn' '0'))")
	[void]$sb.Append(",formatVersion=$($osu.FormatVersion),stack=$(ConvertTo-LuaNumber (Get-Field $osu.General 'StackLeniency' '0.7'))")
	if ($colors.Count -gt 0) { [void]$sb.Append(",colors=`"$($colors -join ';')`"") }
	if ($breaks.Count -gt 0) { [void]$sb.Append(",breaks=`"$($breaks -join "\n")`"") }
	[void]$sb.Append(",`ntiming=[==[`n$($osu.TimingPoints -join "`n")]==]")
	[void]$sb.Append(",`nobjects=[==[`n$($objects -join "`n")]==]}")
	return $sb.ToString()
}

function Get-InterfaceLine([string]$wow) {
	$candidates = @((Join-Path $AddonSource 'Beatcraft.toc'))
	if ($wow) { $candidates = @((Join-Path $wow 'Interface\AddOns\Beatcraft\Beatcraft.toc')) + $candidates }
	foreach ($toc in $candidates) {
		if (Test-Path -LiteralPath $toc) {
			$line = Get-Content -LiteralPath $toc | Where-Object { $_ -like '## Interface:*' } | Select-Object -First 1
			if ($line) { return $line }
		}
	}
	return '## Interface: 20506, 20505, 11508'
}

function Build-Library([string]$libRoot, [string]$wow) {
	$songsDir = Join-Path $libRoot 'Songs'
	New-Item -ItemType Directory -Path $songsDir -Force | Out-Null
	$prefix = "Interface\\AddOns\\$LibAddon\\Songs\\"
	$sb = New-Object Text.StringBuilder
	[void]$sb.Append("-- Generated by Beatcraft Manager. Do not edit; re-run the manager instead.`n")
	[void]$sb.Append("BeatcraftLibrary = { version = 1, songs = {`n")
	$count = 0; $mapCount = 0
	foreach ($dir in Get-ChildItem -LiteralPath $songsDir -Directory | Sort-Object Name) {
		$audio = Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Name -like 'audio.*' } | Select-Object -First 1
		$osuFiles = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.osu' -File | Sort-Object Name)
		if (-not $audio -or $osuFiles.Count -eq 0) { continue }
		$maps = @()
		$first = $null
		foreach ($f in $osuFiles) {
			try {
				$osu = Read-OsuFile $f.FullName
				if ($osu.Mode -ne 0) { continue }
				if (-not $first) { $first = $osu }
				$maps += (Get-MapEntry $osu (Get-FileMd5 $f.FullName))
			} catch { Write-Warn "  skipped $($dir.Name)\$($f.Name): $_" }
		}
		if ($maps.Count -eq 0) { continue }
		$m = $first.Metadata
		$id = $dir.Name
		[void]$sb.Append("{id=$(ConvertTo-LuaString $id)")
		[void]$sb.Append(",title=$(ConvertTo-LuaString (Get-Field $m 'Title' '?'))")
		[void]$sb.Append(",artist=$(ConvertTo-LuaString (Get-Field $m 'Artist' '?'))")
		[void]$sb.Append(",creator=$(ConvertTo-LuaString (Get-Field $m 'Creator' '?'))")
		[void]$sb.Append(",source=$(ConvertTo-LuaString (Get-Field $m 'Source' ''))")
		[void]$sb.Append(",tags=$(ConvertTo-LuaString (Get-Field $m 'Tags' ''))")
		[void]$sb.Append(",audio=`"$prefix$id\\$($audio.Name)`"")
		if (Test-Path -LiteralPath (Join-Path $dir.FullName 'preview.mp3')) { [void]$sb.Append(",preview=`"$prefix$id\\preview.mp3`"") }
		if (Test-Path -LiteralPath (Join-Path $dir.FullName 'bg.tga')) { [void]$sb.Append(",bg=`"$prefix$id\\bg`"") }
		$lenFile = Join-Path $dir.FullName 'length.txt'
		if (Test-Path -LiteralPath $lenFile) { [void]$sb.Append(",audioLen=$((Get-Content -LiteralPath $lenFile -Raw).Trim())") }
		[void]$sb.Append(",previewTime=$(ConvertTo-LuaNumber (Get-Field $first.General 'PreviewTime' '-1'))")
		$videoInfo = Join-Path $dir.FullName 'video\video.txt'
		if (Test-Path -LiteralPath $videoInfo) {
			$v = (Get-Content -LiteralPath $videoInfo -Raw).Trim().Split(' ')
			$videoPrefix = "$prefix$id\\video\\"
			if ($v.Count -gt 9 -and $v[9] -match '^q[a-f0-9]{12}$') { $videoPrefix += "$($v[9])\\" }
			[void]$sb.Append(",video={offset=$($v[0]),fps=$($v[1]),cols=$($v[2]),rows=$($v[3]),fw=$($v[4]),fh=$($v[5]),size=$($v[6]),sheets=$($v[7]),frames=$($v[8]),path=`"$($videoPrefix)v`"}")
		}
		$hsDir = Join-Path $dir.FullName 'hs'
		if (Test-Path -LiteralPath $hsDir) {
			$samples = @()
			foreach ($h in Get-ChildItem -LiteralPath $hsDir -File) {
				$key = [IO.Path]::GetFileNameWithoutExtension($h.Name)
				if ($h.Extension -eq '.silent') { $samples += "[`"$key`"]=`"`"" } else { $samples += "[`"$key`"]=`"$prefix$id\\hs\\$($h.Name)`"" }
			}
			if ($samples.Count -gt 0) { [void]$sb.Append(",samples={$($samples -join ',')}") }
		}
		[void]$sb.Append(",maps={`n")
		[void]$sb.Append(($maps -join ",`n"))
		[void]$sb.Append("}},`n")
		$count++; $mapCount += $maps.Count
	}
	[void]$sb.Append("} }`n")
	[IO.File]::WriteAllText((Join-Path $libRoot 'Library.lua'), $sb.ToString(), $Utf8)

	$toc = @(
		(Get-InterfaceLine $wow),
		'## Title: |cffff66aaBeatcraft|r Library',
		'## Notes: Songs imported with Beatcraft Manager. Loaded only when you open Beatcraft.',
		'## LoadOnDemand: 1',
		'## Dependencies: Beatcraft',
		'',
		'Library.lua'
	) -join "`r`n"
	[IO.File]::WriteAllText((Join-Path $libRoot "$LibAddon.toc"), $toc + "`r`n", $Utf8)
	Write-Good "Library rebuilt: $count songs, $mapCount difficulties."
	return $count
}

function Install-Addon([string]$wow) {
	if (-not (Test-Path -LiteralPath $AddonSource)) { throw "Beatcraft addon folder not found next to the manager ($AddonSource)." }
	$addons = Join-Path $wow 'Interface\AddOns'
	New-Item -ItemType Directory -Path $addons -Force | Out-Null
	$dest = Join-Path $addons 'Beatcraft'
	New-Item -ItemType Directory -Path $dest -Force | Out-Null
	Get-ChildItem -LiteralPath $AddonSource | Copy-Item -Destination $dest -Recurse -Force
	Write-Good "Installed Beatcraft to $dest"
}

function Invoke-ImportFolder([string]$wow, [string]$from) {
	$libRoot = Get-LibraryRoot $wow
	New-Item -ItemType Directory -Path $from -Force | Out-Null
	$items = @(Get-ChildItem -LiteralPath $from | Where-Object {
			($_.PSIsContainer -and $_.Name -ne 'Imported') -or $_.Extension -ieq '.osz' -or $_.Extension -ieq '.zip'
		})
	if ($items.Count -eq 0) {
		Write-Warn "Nothing to import. Put .osz files (or extracted song folders) in:"
		Write-Host "  $from"
		return
	}
	$done = Join-Path $from 'Imported'
	New-Item -ItemType Directory -Path $done -Force | Out-Null
	$ok = 0
	foreach ($item in $items) {
		Write-Info "Importing $($item.Name)"
		$result = $false
		if ($item.PSIsContainer) {
			$result = Import-SetFolder $item.FullName $libRoot
		} elseif ($item.Extension -ieq '.osz' -or $item.Extension -ieq '.zip') {
			$result = Import-Osz $item.FullName $libRoot
		} else { continue }
		if ($result) {
			$ok++
			$target = Join-Path $done $item.Name
			if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
			Move-Item -LiteralPath $item.FullName -Destination $target
		}
	}
	Write-Good "Imported $ok of $($items.Count)."
	Build-Library $libRoot $wow | Out-Null
}

function Find-OsuSongs($settings) {
	$candidates = @()
	if ($settings.OsuSongs) { $candidates += $settings.OsuSongs }
	$candidates += (Join-Path $env:LOCALAPPDATA 'osu!\Songs')
	foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
	Write-Warn 'Could not find the osu! (stable) Songs folder.'
	Write-Host 'osu!lazer users: export maps from lazer as .osz and use option 2 instead.'
	$p = Read-Host 'Paste your osu! Songs folder path (or press Enter to cancel)'
	if (-not $p) { return $null }
	if (-not (Test-Path -LiteralPath $p)) { throw "Folder not found: $p" }
	$settings.OsuSongs = $p
	Save-Settings $settings
	return $p
}

function Select-FromList($items, [string]$title) {
	try {
		return @($items | Out-GridView -Title $title -PassThru)
	} catch {
		Write-Warn 'List window unavailable; type a search word instead.'
		$q = Read-Host 'Search (leave empty for all)'
		$filtered = @($items | Where-Object { -not $q -or $_.Name -like "*$q*" })
		for ($i = 0; $i -lt $filtered.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $filtered[$i].Name) }
		$pick = Read-Host "Numbers separated by commas, or 'all'"
		if ($pick -eq 'all') { return $filtered }
		$out = @()
		foreach ($p in $pick.Split(',')) {
			$n = 0
			if ([int]::TryParse($p.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $filtered.Count) { $out += $filtered[$n - 1] }
		}
		return $out
	}
}

function Invoke-ImportOsu([string]$wow, $settings) {
	$songs = Find-OsuSongs $settings
	if (-not $songs) { return }
	$dirs = @(Get-ChildItem -LiteralPath $songs -Directory | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName } })
	Write-Info "Found $($dirs.Count) song folders. Pick the ones to import in the window (Ctrl/Shift-click for several, then OK)."
	$picked = Select-FromList $dirs 'Pick songs to import into Beatcraft'
	if ($picked.Count -eq 0) { Write-Warn 'Nothing selected.'; return }
	$libRoot = Get-LibraryRoot $wow
	$ok = 0
	foreach ($p in $picked) {
		Write-Info "Importing $($p.Name)"
		if (Import-SetFolder $p.Path $libRoot) { $ok++ }
	}
	Write-Good "Imported $ok of $($picked.Count)."
	Build-Library $libRoot $wow | Out-Null
}

function Invoke-Remove([string]$wow) {
	$libRoot = Get-LibraryRoot $wow
	$songsDir = Join-Path $libRoot 'Songs'
	if (-not (Test-Path -LiteralPath $songsDir)) { Write-Warn 'The library is empty.'; return }
	$items = @()
	foreach ($dir in Get-ChildItem -LiteralPath $songsDir -Directory) {
		$osu = Get-ChildItem -LiteralPath $dir.FullName -Filter '*.osu' | Select-Object -First 1
		$label = $dir.Name
		if ($osu) {
			$m = (Read-OsuFile $osu.FullName).Metadata
			$label = "$(Get-Field $m 'Artist' '?') - $(Get-Field $m 'Title' '?')"
		}
		$items += [pscustomobject]@{ Name = $label; Folder = $dir.FullName }
	}
	$picked = Select-FromList $items 'Pick songs to REMOVE from Beatcraft'
	foreach ($p in $picked) {
		Remove-Item -LiteralPath $p.Folder -Recurse -Force
		Write-Info "Removed $($p.Name)"
	}
	Build-Library $libRoot $wow | Out-Null
}

function Show-Menu {
	$settings = Get-Settings
	$wow = Select-Flavor $settings
	Initialize-Ffmpeg $settings -Interactive
	while ($true) {
		Write-Host ''
		Write-Title '=== Beatcraft Manager ==='
		Write-Host "WoW folder: $wow"
		$installed = Test-Path -LiteralPath (Join-Path $wow 'Interface\AddOns\Beatcraft\Beatcraft.toc')
		if ($installed) { Write-Host 'Addon: installed' -ForegroundColor Green } else { Write-Host 'Addon: not installed yet (choose 1)' -ForegroundColor Yellow }
		Write-Host ''
		Write-Host '  [1] Install / update the Beatcraft addon'
		Write-Host "  [2] Import .osz files from the Import folder"
		Write-Host '  [3] Import songs from your osu! Songs folder'
		Write-Host '  [4] Remove songs'
		Write-Host '  [5] Rebuild the song library'
		Write-Host '  [6] Choose a different WoW version'
		$ffState = 'not installed'
		if ($script:Ffmpeg) { $ffState = 'installed' }
		$vidState = 'off'
		if ($script:IncludeVideo) { $vidState = 'on' }
		Write-Host "  [7] Import videos: $vidState   (ffmpeg: $ffState)"
		Write-Host '  [Q] Quit'
		$c = (Read-Host 'Choose').Trim().ToUpper()
		try {
			switch ($c) {
				'1' { Install-Addon $wow }
				'2' { Invoke-ImportFolder $wow $ImportDir }
				'3' { Invoke-ImportOsu $wow $settings }
				'4' { Invoke-Remove $wow }
				'5' { Build-Library (Get-LibraryRoot $wow) $wow | Out-Null }
				'6' { $wow = Select-Flavor $settings -Force }
				'7' {
					if (-not $script:Ffmpeg) {
						$a = Read-Host 'Videos and hitsounds need ffmpeg (free, ~110 MB from gyan.dev). Download it now? (y/n)'
						if ($a -match '^[yY]') { $script:Ffmpeg = Install-Ffmpeg }
					} else {
						$script:IncludeVideo = -not $script:IncludeVideo
						Set-Setting $settings 'IncludeVideo' $script:IncludeVideo
						Save-Settings $settings
					}
				}
				'Q' { return }
				default { continue }
			}
			if ($c -in '2', '3', '4', '5') {
				Write-Warn 'Fully restart WoW (not just /reload) so it can see new song files.'
			}
		} catch {
			Write-Host "Error: $_" -ForegroundColor Red
		}
	}
}

if ($Action) {
	if (-not $WowPath -and -not $LibraryPath) { $WowPath = Select-Flavor (Get-Settings) }
	Initialize-Ffmpeg (Get-Settings)
	switch ($Action) {
		'install' { Install-Addon $WowPath }
		'import' {
			$from = $ImportDir
			if ($Source) { $from = $Source }
			Invoke-ImportFolder $WowPath $from
		}
		'osu' { Invoke-ImportOsu $WowPath (Get-Settings) }
		'rebuild' { Build-Library (Get-LibraryRoot $WowPath) $WowPath | Out-Null }
		default { throw "Unknown action: $Action" }
	}
} else {
	Show-Menu
}
