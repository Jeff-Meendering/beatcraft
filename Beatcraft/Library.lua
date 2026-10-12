local _, BC = ...

local Compat = BC.Compat
local Beatmap = BC.Beatmap
local Library = BC:Module("Library")

Library.ADDON = "Beatcraft_Library"
Library.songs = {}
Library.byId = {}
Library.byKey = {}

local REASONS = {
	MISSING = "No song library found. Run 'Beatcraft Manager.bat' to import songs, then restart WoW.",
	DISABLED = "The Beatcraft_Library addon is disabled. Enable it in the AddOns list at character select.",
	INTERFACE_VERSION = "Beatcraft_Library is marked out of date. Re-run the importer or tick 'Load out of date AddOns'.",
	CORRUPT = "Beatcraft_Library failed to load. Re-run the importer to rebuild it.",
}

local function titleKey(song)
	return ((song.title or "") .. " " .. (song.artist or "")):lower()
end

function Library:Load()
	if self.loaded then
		return true
	end
	if not BeatcraftLibrary then
		local ok, reason = Compat.LoadAddOn(self.ADDON)
		if not ok and not BeatcraftLibrary then
			self.error = REASONS[reason or "MISSING"] or ("Could not load song library (" .. tostring(reason) .. ").")
			return false, self.error
		end
	end
	local lib = BeatcraftLibrary
	if type(lib) ~= "table" or type(lib.songs) ~= "table" then
		self.error = REASONS.CORRUPT
		return false, self.error
	end
	local songs = {}
	for _, song in ipairs(lib.songs) do
		if type(song.maps) == "table" and #song.maps > 0 then
			for _, map in ipairs(song.maps) do
				map.song = song
				map.key = map.hash or (song.id .. ":" .. (map.version or "?"))
				map.stars = Beatmap.Stars(map)
				self.byKey[map.key] = map
			end
			table.sort(song.maps, function(a, b)
				return a.stars < b.stars
			end)
			song.search = titleKey(song) .. " " .. (song.creator or ""):lower() .. " " .. (song.tags or ""):lower()
			self.byId[song.id] = song
			songs[#songs + 1] = song
		end
	end
	table.sort(songs, function(a, b)
		return titleKey(a) < titleKey(b)
	end)
	self.songs = songs
	self.loaded = true
	return true
end

function Library:Count()
	return #self.songs
end

function Library:Get(id)
	return self.byId[id]
end

function Library:Map(key)
	return self.byKey[key]
end

function Library:Random()
	if #self.songs == 0 then
		return nil
	end
	return self.songs[math.random(#self.songs)]
end

function Library:Search(text)
	text = (text or ""):lower()
	if text == "" then
		return self.songs
	end
	local words = {}
	for w in text:gmatch("%S+") do
		words[#words + 1] = w
	end
	local out = {}
	for _, song in ipairs(self.songs) do
		local ok = true
		for _, w in ipairs(words) do
			if not song.search:find(w, 1, true) then
				ok = false
				break
			end
		end
		if ok then
			out[#out + 1] = song
		end
	end
	return out
end

local cache, cacheOrder = {}, {}

function Library:Parse(map, mods)
	local key = map.key .. ((mods and mods.hr) and ":hr" or (mods and mods.ez) and ":ez" or "")
	if cache[key] then
		return cache[key]
	end
	local bm = Beatmap.Parse(map, mods)
	cache[key] = bm
	cacheOrder[#cacheOrder + 1] = key
	if #cacheOrder > 4 then
		cache[table.remove(cacheOrder, 1)] = nil
	end
	return bm
end

function Library:RaidMap(song)
	local pick = song.maps[1]
	for _, map in ipairs(song.maps) do
		if map.stars <= 4.5 then
			pick = map
		end
	end
	return pick
end
