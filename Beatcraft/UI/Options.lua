-- Settings window.
local _, BC = ...

local W = BC.Widgets
local Opt = BC:Module("Options")

local function raidChanged(rebuildEngine)
	local RM = BC.RaidMode
	if rebuildEngine then
		BC.Engine:Rebuild()
	else
		RM:Layout()
	end
	RM:ApplyBindings()
	RM:UpdateVisibility()
end

function Opt:Create()
	if self.frame then
		return
	end
	local f = W.Panel("BeatcraftOptions", UIParent, 960, 590, "Beatcraft options")
	f:SetPoint("CENTER")
	self.frame = f
	self.widgets = {}

	local function at(c)
		return c
	end
	local function header(c, text)
		local h = W.Text(f, 13, text, "OUTLINE")
		h:SetTextColor(BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3])
		h:SetPoint("TOPLEFT", c.x, c.y)
		c.y = c.y - 22
	end
	local function place(c, w, height)
		w:SetPoint("TOPLEFT", c.x, c.y)
		c.y = c.y - (height or w:GetHeight() + 8)
		self.widgets[#self.widgets + 1] = w
		return w
	end

	local db = BC.db
	local g = db.game
	local r = db.raid

	-- left column -------------------------------------------------------
	local L = at({ x = 16, y = -44 })
	header(L, "Sound")
	place(L, W.Dropdown(f, "Music channel (uses that WoW volume slider)", {
		{ value = "Master", text = "Master" },
		{ value = "Music", text = "Music" },
		{ value = "SFX", text = "Sound effects" },
		{ value = "Ambience", text = "Ambience" },
		{ value = "Dialog", text = "Dialog" },
	}, function()
		return db.channel
	end, function(v)
		db.channel = v
	end, 280))
	place(L, W.Dropdown(f, "Hitsounds (Downtime Mode)", {
		{ value = "none", text = "None" },
		{ value = "tick", text = "Tick" },
		{ value = "soft", text = "Soft" },
	}, function()
		return db.hitsound
	end, function(v)
		db.hitsound = v
	end, 280))
	place(L, W.Slider(f, "Global audio offset", -200, 200, 1, function()
		return db.offset
	end, function(v)
		db.offset = v
	end, "%+d ms", 280))
	local cal = W.Button(f, "Calibrate...", 120, 22, function()
		f:Hide()
		BC.Calibrate:Open()
	end)
	place(L, cal, 30)

	header(L, "Downtime Mode")
	place(L, W.KeyBind(f, "Key 1", function()
		return g.keys[1]
	end, function(v)
		g.keys[1] = v
	end, 280))
	place(L, W.KeyBind(f, "Key 2", function()
		return g.keys[2]
	end, function(v)
		g.keys[2] = v
	end, 280))
	place(L, W.Slider(f, "Background dim", 0, 1, 0.05, function()
		return g.dim
	end, function(v)
		g.dim = v
	end, function(v)
		return math.floor(v * 100 + 0.5) .. "%"
	end, 280))
	for _, item in ipairs({
		{ "hideWorld", "Hide the game world behind the playfield" },
		{ "trail", "Cursor trail" },
		{ "errorBar", "Hit error bar" },
		{ "keyOverlay", "Key overlay" },
		{ "closeOnReadyCheck", "Close on ready check" },
		{ "closeOnQueue", "Close when a queue pops" },
		{ "closeOnWhisper", "Close when whispered" },
	}) do
		local key = item[1]
		place(L, W.Check(f, item[2], function()
			return g[key]
		end, function(v)
			g[key] = v
		end, 280), 22)
	end
	place(L, W.Check(f, "Share personal bests with my guild", function()
		return db.shareGuild
	end, function(v)
		db.shareGuild = v
	end, 280), 22)
	place(L, W.Check(f, "Show minimap button", function()
		return not db.minimap.hide
	end, function(v)
		BC.Minimap:SetShown(v)
	end, 280), 22)

	-- right column ------------------------------------------------------
	local R = at({ x = 330, y = -44 })
	header(R, "Raid Mode")
	place(R, W.Check(f, "Enabled", function()
		return r.enabled
	end, function(v)
		BC.RaidMode:SetEnabled(v)
	end, 280), 22)
	place(R, W.Dropdown(f, "Timing difficulty", {
		{ value = "easy", text = "Easy (wide windows, no off-script penalty)" },
		{ value = "normal", text = "Normal" },
		{ value = "hard", text = "Hard (tight windows)" },
	}, function()
		return r.difficulty
	end, function(v)
		r.difficulty = v
	end, 290))
	place(R, W.Dropdown(f, "Song notes (extra lanes from the beatmap)", {
		{ value = "off", text = "Off" },
		{ value = "light", text = "Light (every other note)" },
		{ value = "full", text = "Full" },
	}, function()
		return r.bonus
	end, function(v)
		r.bonus = v
		raidChanged()
	end, 290))
	place(R, W.KeyBind(f, "Song note key 1", function()
		return r.bonusKeys[1]
	end, function(v)
		r.bonusKeys[1] = v
		raidChanged()
	end, 290))
	place(R, W.KeyBind(f, "Song note key 2", function()
		return r.bonusKeys[2]
	end, function(v)
		r.bonusKeys[2] = v
		raidChanged()
	end, 290))
	local warn = W.Text(f, 10, "Song note keys override those keys while Raid Mode is on.")
	warn:SetTextColor(0.65, 0.65, 0.7)
	place(R, warn, 16)
	place(R, W.Dropdown(f, "Music", {
		{ value = "pull", text = "Start when combat starts" },
		{ value = "always", text = "Play continuously" },
		{ value = "off", text = "Off (no beat snapping)" },
	}, function()
		return r.music
	end, function(v)
		r.music = v
		if v == "off" then
			BC.RaidMode:StopMusic()
		elseif v == "always" and r.enabled then
			BC.RaidMode:StartMusic()
		end
		raidChanged()
	end, 290))
	place(R, W.Dropdown(f, "Songs", {
		{ value = "shuffle", text = "Shuffle whole library" },
		{ value = "playlist", text = "Raid playlist only" },
	}, function()
		return r.playlistMode
	end, function(v)
		r.playlistMode = v
		BC.RaidMode:PickNextSong()
	end, 290))
	local T = at({ x = 650, y = -66 })
	place(T, W.Dropdown(f, "Show lanes", {
		{ value = "target", text = "With an enemy targeted or in combat" },
		{ value = "combat", text = "Only in combat" },
		{ value = "always", text = "Always" },
	}, function()
		return r.showMode
	end, function(v)
		r.showMode = v
		raidChanged()
	end, 290))
	place(T, W.Dropdown(f, "Rotation", function()
		local Engine = BC.Engine
		local names = BC.SpecNames[Engine:Class()] or {}
		local opts = { { value = 0, text = "Auto (from talents)" } }
		for i, n in ipairs(names) do
			opts[#opts + 1] = { value = i, text = n }
		end
		return opts
	end, function()
		return r.specOverride
	end, function(v)
		r.specOverride = v
		raidChanged(true)
	end, 290))
	place(T, W.Slider(f, "Note speed (seconds on screen)", 0.6, 2.0, 0.1, function()
		return r.approach
	end, function(v)
		r.approach = v
	end, "%.1fs", 290))
	place(T, W.Slider(f, "Scale", 0.6, 1.6, 0.05, function()
		return r.scale
	end, function(v)
		r.scale = v
		raidChanged()
	end, "%.2f", 290))
	place(T, W.Slider(f, "Opacity", 0.3, 1, 0.05, function()
		return r.alpha
	end, function(v)
		r.alpha = v
		raidChanged()
	end, "%.2f", 290))
	for _, item in ipairs({
		{ "keepMusic", "Keep music playing between pulls" },
		{ "scrollUp", "Notes scroll upward", true },
		{ "showKeybinds", "Show keybinds on lanes", true },
		{ "summary", "Fight summary after combat" },
		{ "freestyle", "Force Freestyle (judge every cast on the beat)", "engine" },
	}) do
		local key, mode = item[1], item[3]
		place(T, W.Check(f, item[2], function()
			return r[key]
		end, function(v)
			r[key] = v
			if mode == "engine" then
				raidChanged(true)
			elseif mode then
				raidChanged()
			end
		end, 290), 22)
	end
	local move = W.Button(f, "Move lanes", 120, 24, function()
		BC.RaidMode:SetLocked(not r.locked)
	end)
	place(T, move, 30)

	f:SetScript("OnShow", function()
		for _, w in ipairs(self.widgets) do
			if w.Refresh then
				w:Refresh()
			end
		end
	end)
end

function Opt:Open()
	self:Create()
	-- above the fullscreen game window when opened from song select
	if BC.Game:IsOpen() then
		self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
		self.frame:SetFrameLevel(BC.Game.root:GetFrameLevel() + 3000)
	else
		self.frame:SetFrameStrata("DIALOG")
	end
	self.frame:Show()
	self.frame:Raise()
end
