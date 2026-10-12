local addonName, BC = ...
_G.Beatcraft = BC

BC.name = addonName
BC.version = "0.1.0"
BC.ACCENT = { 1, 0.4, 0.67 }
BC.ACCENT_HEX = "ff66aa"
BC.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

--------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------

local DEFAULTS = {
	offset = 0, -- global audio offset in ms (positive = notes later)
	channel = "Master", -- sound channel used for music
	hitsound = "tick",
	minimap = { angle = 215, hide = false },
	mapOffsets = {}, -- [mapKey] = ms
	scores = {}, -- [mapKey] = { {score, acc, combo, grade, mods, date, c300, c100, c50, miss}, ... }
	guildScores = {}, -- [mapKey] = { [player] = {score, acc, grade, combo} }
	shareGuild = true,
	rotations = {}, -- [CLASS] = { [tree] = { entries } }
	playlist = {}, -- [songId] = true
	lastSong = nil,
	lastMap = nil,
	fights = {}, -- recent raid mode summaries
	game = {
		keys = { "Z", "X" },
		dim = 0.8,
		hideWorld = true,
		trail = true,
		errorBar = true,
		keyOverlay = true,
		mods = {},
		closeOnReadyCheck = true,
		closeOnQueue = true,
		closeOnWhisper = false,
	},
	raid = {
		enabled = false,
		difficulty = "normal", -- easy / normal / hard
		bonus = "off", -- off / light / full
		bonusKeys = { "Z", "X" },
		approach = 1.2, -- seconds a note takes to fall
		scale = 1,
		alpha = 1,
		locked = true,
		point = nil,
		showMode = "target", -- target / combat / always
		music = "pull", -- pull / always / off
		keepMusic = false,
		freestyle = false,
		specOverride = 0,
		playlistMode = "shuffle", -- shuffle / playlist
		scrollUp = false,
		showKeybinds = true,
		summary = true,
	},
}

local function mergeDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			mergeDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end
BC.mergeDefaults = mergeDefaults
BC.DEFAULTS = DEFAULTS

--------------------------------------------------------------------------
-- Events and internal messages
--------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventHandlers[event]
	if list then
		for i = 1, #list do
			list[i](event, ...)
		end
	end
end)

function BC:On(event, fn)
	if not eventHandlers[event] then
		eventHandlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(eventHandlers[event], fn)
end

function BC:Listen(msg, fn)
	messageHandlers[msg] = messageHandlers[msg] or {}
	table.insert(messageHandlers[msg], fn)
end

function BC:Fire(msg, ...)
	local list = messageHandlers[msg]
	if list then
		for i = 1, #list do
			list[i](msg, ...)
		end
	end
end

--------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------

local modules = {}

function BC:Module(name)
	local m = { name = name }
	BC[name] = m
	table.insert(modules, m)
	return m
end

--------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------

function BC:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff" .. BC.ACCENT_HEX .. "Beatcraft|r: " .. table.concat(parts, " "))
end

--------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------

BC:On("ADDON_LOADED", function(_, name)
	if name ~= addonName then
		return
	end
	BeatcraftDB = BeatcraftDB or {}
	mergeDefaults(BeatcraftDB, DEFAULTS)
	BC.db = BeatcraftDB
	for _, m in ipairs(modules) do
		if m.OnInit then
			m:OnInit()
		end
	end
end)

BC:On("PLAYER_LOGIN", function()
	BC.Compat.RebuildSpellbook()
	for _, m in ipairs(modules) do
		if m.OnLogin then
			m:OnLogin()
		end
	end
end)

BC:On("SPELLS_CHANGED", function()
	BC.Compat.RebuildSpellbook()
	BC:Fire("SPELLBOOK_CHANGED")
end)

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local HELP = {
	"/beat - open the Beatcraft menu",
	"/beat play - song select (out of combat)",
	"/beat raid - toggle Raid Mode",
	"/beat editor - rotation editor",
	"/beat options - settings",
	"/beat calibrate - audio offset calibration",
	"/beat unlock - move the Raid Mode lanes",
}

local function slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "menu" then
		BC.MainMenu:Toggle()
	elseif msg == "play" then
		BC.SongSelect:Open()
	elseif msg == "raid" then
		BC.RaidMode:SetEnabled(not BC.db.raid.enabled)
	elseif msg == "editor" or msg == "rotation" then
		BC.Editor:Open()
	elseif msg == "options" or msg == "config" then
		BC.Options:Open()
	elseif msg == "calibrate" then
		BC.Calibrate:Open()
	elseif msg == "unlock" or msg == "lock" then
		BC.RaidMode:SetLocked(msg == "lock")
	else
		for _, line in ipairs(HELP) do
			BC:Print(line)
		end
	end
end

SLASH_BEATCRAFT1 = "/beat"
SLASH_BEATCRAFT2 = "/beatcraft"
SLASH_BEATCRAFT3 = "/osu"
SlashCmdList.BEATCRAFT = slash
