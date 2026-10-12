local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. msg)
	end
end
local function section(name)
	print("== " .. name)
end

local files = {}
for line in io.lines(ADDON_DIR .. "/Beatcraft.toc") do
	if line ~= "" and not line:match("^#") then
		files[#files + 1] = (line:gsub("\\", "/"))
	end
end
MOCK.libraryPath = LIB_PATH
local BC = MOCK.LoadAddon(ADDON_DIR, files)

section("startup")
MOCK.FireEvent("ADDON_LOADED", "Beatcraft")
MOCK.FireEvent("PLAYER_LOGIN")
MOCK.FireEvent("SPELLS_CHANGED")
check(BC.db ~= nil, "saved variables initialised")
check(BC.Engine.class == "WARRIOR" and BC.Engine.tree == 1, "spec detected as Arms (got " .. tostring(BC.Engine.tree) .. ")")
check(#BC.Engine.lanes == 7, "7 lanes for the mocked Arms warrior (got " .. #BC.Engine.lanes .. ")")
check(not BC.Engine.freestyle, "not freestyle")

section("default rotations compile")
local total = 0
for class, trees in pairs(BC.RotationDefaults) do
	for tree, entries in ipairs(trees) do
		for _, e in ipairs(entries) do
			total = total + 1
			local fn, err = BC.Conditions.Compile(e.cond)
			check(fn ~= nil, class .. " " .. tree .. " " .. e.spell .. ": " .. tostring(err))
			if fn then
				local ok, runErr = BC.Conditions.Eval(fn)
				check(runErr == nil, class .. " " .. tree .. " " .. e.spell .. " runtime: " .. tostring(runErr))
			end
		end
	end
	check(#trees == 3, class .. " has 3 trees")
end
print("   " .. total .. " default entries checked")

section("condition sandbox")
local fn, err = BC.Conditions.Compile("print('x')")
local ok, runErr = BC.Conditions.Eval(fn)
check(runErr and runErr:find("unknown word"), "globals are not reachable from conditions")
fn, err = BC.Conditions.Compile("(function() while true do end end)()")
check(fn == nil, "function definitions are rejected")
fn, err = BC.Conditions.Compile("rage >=")
check(fn == nil and err, "syntax errors are reported: " .. tostring(err))
fn = BC.Conditions.Compile('rage >= 50 and buff("Battle Shout") == 0')
check(BC.Conditions.Eval(fn) == true, "condition evaluates with mocked state")

section("rotation engine")
local Engine = BC.Engine
local e, ready = Engine:Next(false, MOCK.now)
check(e and e.spell == "Battle Shout", "first suggestion is Battle Shout (got " .. tostring(e and e.spell) .. ")")
table.insert(MOCK.auras.player, { name = "Battle Shout", expires = MOCK.now + 120, duration = 120 })
e = Engine:Next(false, MOCK.now)
check(e and e.spell == "Mortal Strike", "then Mortal Strike (got " .. tostring(e and e.spell) .. ")")
local off = Engine:Next(true, MOCK.now)
check(off and off.spell == "Heroic Strike", "Heroic Strike on the off-GCD stream at 60 rage")
MOCK.power[1] = 20
check(Engine:Next(true, MOCK.now) == nil, "no Heroic Strike at 20 rage")
MOCK.power[1] = 60

section("raid mode")
local RM = BC.RaidMode
RM:SetEnabled(true)
check(BC.Library.loaded, "library loaded on demand")
check(RM.root:IsShown(), "lanes shown with a hostile target")
check(RM.nextSong ~= nil, "a song is queued for the pull")

local slotOf = {}
for slot, id in pairs(MOCK.actions) do
	slotOf[MOCK.spellById[id].name] = slot
end
local function castNow(name)
	local s = MOCK.spellByName[name:lower()]
	local guid = "Cast-" .. math.random(1, 1e9)
	MOCK.FireEvent("UNIT_SPELLCAST_SENT", "player", "target", guid, s.id)
	if s.cast and s.cast > 0 then
		MOCK.FireEvent("UNIT_SPELLCAST_START", "player", guid, s.id)
		MOCK.castInfo = { name = s.name, startT = MOCK.now, endT = MOCK.now + s.cast }
		MOCK.gcd = { start = MOCK.now, dur = 1.5 }
		C_Timer.After(s.cast, function()
			MOCK.castInfo = nil
			MOCK.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, s.id)
		end)
	else
		MOCK.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, s.id)
		if not s.offgcd then
			MOCK.gcd = { start = MOCK.now, dur = 1.5 }
		end
	end
	if s.cd then
		MOCK.cooldowns[s.name] = { start = MOCK.now, dur = s.cd }
	end
end

local queued
local function cast(name)
	local s = MOCK.spellByName[name:lower()]
	UseAction(slotOf[name])
	if s.offgcd then
		if MOCK.current[s.name] then
			return
		end
		MOCK.current[s.name] = true
		C_Timer.After(0.9, function()
			MOCK.current[s.name] = nil
			castNow(name)
		end)
		return
	end
	local readyAt = MOCK.now
	if MOCK.castInfo then
		readyAt = math.max(readyAt, MOCK.castInfo.endT)
	end
	if MOCK.gcd then
		readyAt = math.max(readyAt, MOCK.gcd.start + MOCK.gcd.dur)
	end
	local cd = MOCK.cooldowns[s.name]
	if cd then
		readyAt = math.max(readyAt, cd.start + cd.dur)
	end
	if readyAt - MOCK.now > 0.4 or queued then
		return
	end
	if readyAt <= MOCK.now then
		castNow(name)
	else
		queued = name
		C_Timer.After(readyAt - MOCK.now, function()
			queued = nil
			castNow(name)
		end)
	end
end

MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
check(RM.bm ~= nil, "music started on pull")
check(#MOCK.sounds > 0 and MOCK.sounds[#MOCK.sounds].path:find("audio.mp3"), "PlaySoundFile called with the song")

local pressed = 0
MOCK.onTick = function()
	for _, field in ipairs({ "rotNote", "offNote" }) do
		local note = RM[field]
		if note and note.state == "pending" and MOCK.now >= note.T - 0.01 and (note.lastPress or 0) < MOCK.now - 0.2 then
			note.lastPress = MOCK.now
			cast(note.spell)
			pressed = pressed + 1
		end
	end
end
MOCK.Advance(20)
MOCK.onTick = nil
local tally = RM.tally
print(string.format("   pressed %d, judged %d (300:%d 100:%d 50:%d miss:%d), acc %.1f%%, max combo %d",
	pressed, tally:Total(), tally.c300, tally.c100, tally.c50, tally.miss, tally:Accuracy() * 100, tally.maxCombo))
check(pressed >= 8 and pressed <= tally:Total() + 3, "the simulated player pressed each note about once")
check(tally:Total() >= 8, "casts were judged")
check(tally.c300 + tally.c100 >= tally:Total() * 0.8, "on-time casts are mostly PERFECT/GREAT")

local onBeat = 0
local snapped = 0
local note = RM.rotNote
if note then
	local songMs = BC.Clock:TimeAt(note.T)
	local _, errMs = BC.Beatmap.NearestGrid(RM.bm, songMs, 2)
	print(string.format("   pending note %s at song %.0f ms, %.1f ms from the half-beat grid", note.spell, songMs, errMs))
end

local before = tally.combo
RM.rotNote = nil
RM:Evaluate(MOCK.now)
if RM.rotNote and RM.rotNote.spell ~= "Whirlwind" then
	MOCK.cooldowns["Whirlwind"] = nil
	MOCK.gcd = nil
	MOCK.castInfo = nil
	castNow("Whirlwind")
	check(tally.combo == 0, "off-script cast breaks combo")
end

MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
check(#BC.db.fights == 1, "fight summary recorded")
check(RM.bm == nil, "music stops after the pull")

section("raid mode bonus lanes + freestyle")
BC.db.raid.bonus = "full"
RM:Layout()
RM:ApplyBindings()
check(MOCK.bindings.Z == "BeatcraftBonus1" and MOCK.bindings.X == "BeatcraftBonus2", "bonus keys bound out of combat")
MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
check(#RM.bonusNotes > 0, "bonus notes built from the song (" .. #RM.bonusNotes .. ")")
local hitsBefore = RM.tally:Total()
MOCK.onTick = function()
	local songNow = BC.Clock:TimeAt(MOCK.now)
	for _, b in ipairs(RM.bonusNotes) do
		if not b.done and math.abs(songNow - b.t) < 10 then
			_G["BeatcraftBonus" .. b.lane]:Click("LeftButton")
		end
	end
end
MOCK.Advance(6)
MOCK.onTick = nil
local bonusHits = 0
for _, b in ipairs(RM.bonusNotes) do
	if b.done == "hit" then
		bonusHits = bonusHits + 1
	end
end
check(bonusHits >= 5, "bonus notes hit with the bound keys (" .. bonusHits .. ")")
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
BC.db.raid.bonus = "off"
BC.db.raid.freestyle = true
Engine:Rebuild()
check(Engine.freestyle and RM.lanes[1].spec.kind == "beat", "freestyle layout")
MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
MOCK.Advance(1.0)
MOCK.gcd, MOCK.castInfo = nil, nil
castNow("Mortal Strike")
MOCK.Advance(2)
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
BC.db.raid.freestyle = false
Engine:Rebuild()
RM:SetEnabled(false)
check(next(MOCK.bindings) == nil, "bonus bindings cleared when Raid Mode is off")

section("downtime: song select")
MOCK.target.exists = false
BC.SongSelect:Open()
check(BC.Game:IsOpen(), "game window open")
check(BC.Game.screen == BC.SongSelect, "on song select")
check(BC.SongSelect.song ~= nil and BC.SongSelect.map ~= nil, "a song and map are selected")
BC.SongSelect:OnKey("RIGHT", true)
check(BC.SongSelect.map.version == "Hard", "right arrow picks the harder difficulty")
BC.SongSelect:OnKey("T", true)
check(BC.SongSelect.search:GetText() == "t", "typing goes to search")
BC.SongSelect.search:SetText("zzzz")
check(#BC.SongSelect.results == 0, "search filters")
BC.SongSelect.search:SetText("")
check(#BC.SongSelect.results == 1, "search cleared")
BC.SongSelect:ToggleMod("hr")
check(BC.SongSelect.mods.hr, "HR toggled")
BC.SongSelect:ToggleMod("hr")
MOCK.Advance(0.5)

section("downtime: autoplay")
local Play = BC.Play
local auto = { x = 256, y = 192 }
Play.CursorOsu = function()
	return auto.x, auto.y, 0, 0
end
BC.SongSelect:PlaySelected()
check(BC.Game.screen == Play and Play.playing, "playing")
local Beatmap = BC.Beatmap
local bm = Play.bm
local idx = 1
local holding = false
local spinAngle = 0
MOCK.onTick = function()
	if not Play.playing then
		return
	end
	local t = BC.Clock:Time()
	local obj = bm.objects[idx]
	if holding then
		local cur = bm.objects[idx - 1]
		if cur.kind == "slider" then
			auto.x, auto.y = Beatmap.SliderBall(cur, t)
		elseif cur.kind == "spinner" then
			spinAngle = spinAngle + 0.5
			auto.x, auto.y = 256 + math.cos(spinAngle) * 60, 192 + math.sin(spinAngle) * 60
		end
		if t > cur.endTime + 20 then
			Play:OnKey("Z", false)
			holding = false
		end
	end
	if obj and not holding and t >= obj.t - 2 then
		auto.x, auto.y = obj.x, obj.y
		if obj.kind == "spinner" then
			auto.x, auto.y = 316, 192
		end
		Play:OnKey("Z", true)
		idx = idx + 1
		if obj.kind == "circle" then
			Play:OnKey("Z", false)
		else
			holding = true
		end
	end
end
MOCK.Advance(bm.lastTime / 1000 + 6)
MOCK.onTick = nil
local tally2 = Play.tally
print(string.format("   score %d acc %.2f%% combo %d/%d grade %s (300:%d 100:%d 50:%d miss:%d)",
	tally2.score, tally2:Accuracy() * 100, tally2.maxCombo, bm.maxCombo, tally2:Grade(), tally2.c300, tally2.c100, tally2.c50, tally2.miss))
check(tally2.miss == 0, "autoplay has no misses")
check(tally2:Accuracy() > 0.97, "autoplay accuracy is high")
check(tally2.maxCombo == bm.maxCombo, "full combo equals the map's max combo")
check(BC.Game.screen == BC.Results, "results screen shown")
check(BC.db.scores[BC.SongSelect.map.key] and #BC.db.scores[BC.SongSelect.map.key] == 1, "score saved")
check(#MOCK.addonMessages == 1 and MOCK.addonMessages[1].channel == "GUILD", "personal best shared with the guild")

section("downtime: no input fails")
BC.Results:OnKey("`", true)
check(BC.Game.screen == Play and Play.playing, "retry from results")
MOCK.Advance(bm.lastTime / 1000 + 4)
check(Play.failed or (Play.tally.miss == #bm.objects), "doing nothing fails or misses everything")
Play:OnKey("ESCAPE", true)
check(BC.Game.screen == BC.SongSelect, "escape returns to song select")

section("downtime: combat closes the game")
MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
check(not BC.Game:IsOpen(), "game closed on combat")
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")

section("guild")
MOCK.FireEvent("CHAT_MSG_ADDON", "Beatcraft", "PB\t" .. BC.SongSelect.map.key .. "\t99999999\t0.9900\tS\t120", "GUILD", "Friend-Realm")
local top = BC.Guild:FormatTop(BC.SongSelect.map.key, 5)
check(top:find("Friend") and top:find("Tester"), "guild top lists both players")

section("editor")
BC.Editor:Open()
check(#BC.Editor.entries == 7, "editor loaded Arms defaults")
local text = BC.Editor:Export()
local parsed = BC.Editor.ParseText(text)
check(#parsed == 7 and parsed[7].off == true and parsed[7].cond == "rage >= 55", "export/import round trip")
BC.Editor:AddEntry()
BC.Editor.entries[#BC.Editor.entries].spell = "Slam"
BC.Editor.entries[#BC.Editor.entries].cond = "rage >"
BC.Editor:Save()
check(BC.db.rotations.WARRIOR and #BC.db.rotations.WARRIOR[1] == 8, "custom rotation saved")
check(BC.Engine.entries[8].err ~= nil, "broken condition flagged")
BC.Editor:OpenIO()
BC.Editor:ToggleHelp()
BC.Engine:ResetEntries("WARRIOR", 1)
check(BC.db.rotations.WARRIOR[1] == nil, "reset to default")
BC.Editor:Load("DRUID", 2)
check(#BC.Editor.entries == 8, "can view another class's rotation")
MOCK.Advance(0.5)

section("other windows")
BC.MainMenu:Toggle()
check(BC.MainMenu.frame:IsShown(), "main menu opens")
BC.Options:Open()
for _, w in ipairs(BC.Options.widgets) do
	if w.Refresh then
		w:Refresh()
	end
end
check(BC.Options.frame:IsShown(), "options open")
BC.Calibrate:Open()
MOCK.Advance(1)
for i = 1, 24 do
	BC.Calibrate:Tap()
	MOCK.Advance(0.5)
end
check(BC.Calibrate.measured ~= nil or BC.Calibrate.result:GetText() ~= "", "calibration produced a result")
SlashCmdList.BEATCRAFT("help")
SlashCmdList.BEATCRAFT("raid")
SlashCmdList.BEATCRAFT("raid")
SlashCmdList.BEATCRAFT("unlock")
SlashCmdList.BEATCRAFT("lock")
MOCK.Advance(1)

section("unknown widget methods used")
local names = {}
for k in pairs(MOCK.unknown) do
	names[#names + 1] = k
end
table.sort(names)
print("   " .. table.concat(names, ", "))

print(string.format("\n%d passed, %d failed", passed, failed))
RESULT_FAILED = failed
