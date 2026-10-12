<#
Beatcraft Manager
  - installs / updates the Beatcraft addon into your WoW folder
  - imports osu! beatmaps (.osz files or your osu! Songs folder) into the
    Beatcraft_Library addon: copies the music, converts backgrounds to TGA,
    cuts short preview clips and writes the beatmap data as Lua.

Runs on stock Windows PowerShell 5.1; nothing to install.
Start it with "Beatcraft Manager.bat" (double-click).

Non-interactive use (for scripts/tests):
  -WowPath <flavor folder>  e.g. "C:\Program Files (x86)\World of Warcraft\_anniversary_"
  -LibraryPath <folder>     write the library somewhere else (testing)
  -Action install|import|osu|rebuild
  -Source <folder>          for -Action import: where the .osz files are
#>
param(
	[string]$WowPath,
	[string]$LibraryPath,
	[string]$Action,
	[string]$Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsFile = Join-Path $ScriptDir 'settings.json'
$AddonSource = Join-Path $Root 'Beatcraft'
$ImportDir = Join-Path $Root 'Import'
$LibAddon = 'Beatcraft_Library'
$Utf8 = New-Object System.Text.UTF8Encoding $false

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Info($msg) { Write-Host $msg -ForegroundColor Gray }
function Write-Good($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Title($msg) { Write-Host $msg -ForegroundColor Magenta }

#--------------------------------------------------------------------------
# Settings and WoW detection
#--------------------------------------------------------------------------

function Get-Settings {
	if (Test-Path -LiteralPath $SettingsFile) {
		try { return Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json } catch { }
	}
	return [pscustomobject]@{ WowPath = $null; OsuSongs = $null }
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

#--------------------------------------------------------------------------
# .osu parsing
#--------------------------------------------------------------------------

function Read-OsuFile([string]$path) {
	$lines = [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)
	$data = @{
		Path = $path; General = @{}; Metadata = @{}; Difficulty = @{}; Colours = @{}
		Events = New-Object System.Collections.Generic.List[string]
		TimingPoints = New-Object System.Collections.Generic.List[string]
		HitObjects = New-Object System.Collections.Generic.List[string]
	}
	$section = ''
	foreach ($raw in $lines) {
		$line = $raw.Trim()
		if ($line -eq '' -or $line.StartsWith('//')) { continue }
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

#--------------------------------------------------------------------------
# Media conversion
#--------------------------------------------------------------------------

# Writes a 32-bit uncompressed TGA (bottom-up), cropped to 2:1 and resized.
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
			# GDI rows are top-down; TGA default origin is bottom-left
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

# Walks MPEG layer III frames. Returns a list of @(offset, length, durationMs).
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

# Copies [startMs, startMs + durMs) of an MP3 into a new file. Returns
# the total song length in ms, or 0 if the file could not be parsed.
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

#--------------------------------------------------------------------------
# Importing
#--------------------------------------------------------------------------

function Get-LibraryRoot([string]$wow) {
	if ($LibraryPath) { return $LibraryPath }
	return Join-Path $wow "Interface\AddOns\$LibAddon"
}

# Imports one beatmap set folder (extracted .osz or osu! Songs folder).
function Import-SetFolder([string]$dir, [string]$libRoot) {
	$osuFiles = @(Get-ChildItem -LiteralPath $dir -Filter '*.osu' -File)
	$maps = @()
	foreach ($f in $osuFiles) {
		try {
			$m = Read-OsuFile $f.FullName
			if ($m.Mode -eq 0 -and $m.HitObjects.Count -gt 0) { $maps += $m }
		} catch { Write-Warn "  could not read $($f.Name): $_" }
	}
	$name = Split-Path -Leaf $dir
	if ($maps.Count -eq 0) {
		Write-Warn "  skipped '$name': no osu!standard difficulties"
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
		# difficulties that use a different audio file can't share this folder
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
	Write-Good ("  + {0} - {1}  ({2} difficulties)" -f (Get-Field $meta 'Artist' '?'), (Get-Field $meta 'Title' '?'), $i)
	return $true
}

function Import-Osz([string]$file, [string]$libRoot) {
	$tmp = Join-Path ([IO.Path]::GetTempPath()) ('beatcraft_' + [Guid]::NewGuid().ToString('N'))
	try {
		[IO.Compression.ZipFile]::ExtractToDirectory($file, $tmp)
		return Import-SetFolder $tmp $libRoot
	} catch {
		Write-Warn "  could not open $(Split-Path -Leaf $file): $_"
		return $false
	} finally {
		if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
	}
}

#--------------------------------------------------------------------------
# Library.lua generation
#--------------------------------------------------------------------------

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

# Keeps only the hit object fields Beatcraft uses.
function Compress-HitObject([string]$line) {
	$f = $line.Split(',')
	if ($f.Count -lt 4) { return $null }
	$type = 0
	[void][int]::TryParse($f[3], [ref]$type)
	if (($type -band 2) -ne 0) { $keep = 8 } elseif (($type -band 8) -ne 0) { $keep = 6 } else { $keep = 4 }
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

	# BPM of the longest-lasting uninherited timing point
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

#--------------------------------------------------------------------------
# Actions
#--------------------------------------------------------------------------

function Install-Addon([string]$wow) {
	if (-not (Test-Path -LiteralPath $AddonSource)) { throw "Beatcraft addon folder not found next to the manager ($AddonSource)." }
	$addons = Join-Path $wow 'Interface\AddOns'
	New-Item -ItemType Directory -Path $addons -Force | Out-Null
	$dest = Join-Path $addons 'Beatcraft'
	if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
	Copy-Item -LiteralPath $AddonSource -Destination $dest -Recurse
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
	Write-Good "Imported $ok of $($items.Count). (Imported files were moved to Import\Imported.)"
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

#--------------------------------------------------------------------------
# Entry point
#--------------------------------------------------------------------------

if ($Action) {
	if (-not $WowPath -and -not $LibraryPath) { $WowPath = Select-Flavor (Get-Settings) }
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
