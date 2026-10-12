-- Raid Mode: your rotation as a rhythm game.
--
-- The rotation engine predicts the next ability and when it becomes
-- pressable. A note falls down that ability's lane, timed to land on the
-- song's beat (inside the spell queue window, so hitting the beat never
-- delays the cast). Real casts are detected from the action-bar and cast
-- hooks plus spellcast events, and judged against the note. Beatcraft never
-- casts anything itself: every cast is still a normal key press.
local _, BC = ...

local Compat = BC.Compat
local U = BC.Util
local W = BC.Widgets
local Engine = BC.Engine
local Clock = BC.Clock
local Beatmap = BC.Beatmap
local Library = BC.Library
local Scoring = BC.Scoring

local RM = BC:Module("RaidMode")

local LANE_W, LANE_GAP, LANE_H = 44, 4, 260
local LATE_LIMIT = 1.0 -- seconds after a note's time before it counts as missed
local SETTLE = 0.08 -- wait after a hit so cooldown info updates
local DIFF = { easy = 1.5, normal = 1.0, hard = 0.75 }
local LABELS = { [300] = "PERFECT", [100] = "GREAT", [50] = "GOOD" }

local ACCENT = BC.ACCENT

RM.notes = {}
RM.presses = {}
RM.castGUIDs = {}
RM.holds = {}
RM.bonusNotes = {}
RM.pressJudged = {}

local function queueWindow()
	local v = tonumber(GetCVar and GetCVar("SpellQueueWindow") or nil)
	if not v then
		return 0.4
	end
	return U.Clamp(v / 1000, 0, 0.4)
end

--------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------

local function createNote(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(LANE_W - 6, LANE_W - 6)
	f.body = f:CreateTexture(nil, "BACKGROUND")
	f.body:SetTexture(BC.MEDIA .. "note")
	f.body:SetPoint("BOTTOM", f, "CENTER", 0, 0)
	f.body:SetWidth(LANE_W * 0.45)
	f.glow = f:CreateTexture(nil, "BORDER")
	f.glow:SetTexture(BC.MEDIA .. "glow")
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(LANE_W * 1.6, LANE_W * 1.6)
	f.glow:SetBlendMode("ADD")
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 3, -3)
	f.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetTexture(BC.MEDIA .. "noteborder")
	f.border:SetAllPoints()
	return f
end

function RM:CreateFrames()
	local root = CreateFrame("Frame", "BeatcraftRaidFrame", UIParent)
	root:SetFrameStrata("MEDIUM")
	root:SetClampedToScreen(true)
	root:SetMovable(true)
	root:RegisterForDrag("LeftButton")
	root:SetScript("OnDragStart", function(f)
		if not BC.db.raid.locked then
			f:StartMoving()
		end
	end)
	root:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint()
		BC.db.raid.point = { point, relPoint, x, y }
	end)
	root:Hide()
	self.root = root

	root.unlockBg = W.Solid(root, "BACKGROUND", ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
	root.unlockBg:SetAllPoints()
	root.unlockText = W.Text(root, 12, "Drag to move  -  /beat lock when done", "OUTLINE")
	root.unlockText:SetPoint("BOTTOM", root, "TOP", 0, 4)

	-- container the lanes and notes live in
	self.field = CreateFrame("Frame", nil, root)
	self.field:SetPoint("BOTTOMLEFT", 0, 0)

	self.combo = W.Text(root, 22, "", "THICKOUTLINE")
	self.judge = W.Text(root, 16, "", "OUTLINE")
	self.acc = W.Text(root, 11, "", "OUTLINE")
	self.songText = W.Text(root, 10, "", "OUTLINE")
	self.songText:SetTextColor(0.8, 0.8, 0.8)
	self.info = W.Text(root, 11, "", "OUTLINE")
	self.info:SetTextColor(0.85, 0.85, 0.85)

	self.lanes = {}
	self.notePool = U.NewPool(function()
		return createNote(self.field)
	end, function(f)
		f:Hide()
		f:ClearAllPoints()
		f:SetScale(1)
		f:SetAlpha(1)
	end)

	-- Hidden buttons the bonus keys are bound to (CLICK bindings).
	self.bindOwner = CreateFrame("Frame")
	for i = 1, 2 do
		local b = CreateFrame("Button", "BeatcraftBonus" .. i, UIParent)
		b:RegisterForClicks("AnyDown")
		b:SetScript("OnClick", function()
			RM:OnBonusKey(i)
		end)
		b:Hide()
	end

	root:SetScript("OnUpdate", function()
		RM:OnUpdate()
	end)
	root:SetScript("OnHide", function()
		RM:ClearNotes()
	end)
end

local function createLane(parent)
	local lane = CreateFrame("Frame", nil, parent)
	lane.bg = lane:CreateTexture(nil, "BACKGROUND")
	lane.bg:SetTexture(BC.MEDIA .. "lane")
	lane.bg:SetAllPoints()
	lane.bg:SetVertexColor(0.08, 0.08, 0.12)
	lane.receptor = CreateFrame("Frame", nil, lane)
	lane.receptor:SetSize(LANE_W - 4, LANE_W - 4)
	lane.icon = lane.receptor:CreateTexture(nil, "ARTWORK")
	lane.icon:SetPoint("TOPLEFT", 4, -4)
	lane.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	lane.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	lane.icon:SetAlpha(0.45)
	lane.ring = lane.receptor:CreateTexture(nil, "OVERLAY")
	lane.ring:SetTexture(BC.MEDIA .. "noteborder")
	lane.ring:SetAllPoints()
	lane.ring:SetVertexColor(0.6, 0.6, 0.7)
	lane.flash = lane.receptor:CreateTexture(nil, "OVERLAY")
	lane.flash:SetTexture(BC.MEDIA .. "glow")
	lane.flash:SetPoint("CENTER")
	lane.flash:SetSize(LANE_W * 2, LANE_W * 2)
	lane.flash:SetBlendMode("ADD")
	lane.flash:SetAlpha(0)
	lane.key = W.Text(lane.receptor, 10, "", "OUTLINE")
	lane.key:SetPoint("BOTTOMRIGHT", -2, 2)
	lane.flashAt = 0
	return lane
end

-- Builds lanes for the current rotation (or the freestyle lane) plus bonus lanes.
function RM:Layout()
	if not self.root then
		return
	end
	local db = BC.db.raid
	local up = db.scrollUp
	local specs = {}
	if Engine.freestyle then
		specs[1] = { kind = "beat", width = LANE_W * 3 }
	else
		for i, l in ipairs(Engine.lanes) do
			specs[#specs + 1] = { kind = "rot", index = i, spell = l.spell, icon = l.icon, off = l.off, width = LANE_W }
		end
	end
	self.bonusLaneStart = nil
	if db.bonus ~= "off" and db.music ~= "off" then
		for i = 1, 2 do
			specs[#specs + 1] = { kind = "bonus", index = i, width = LANE_W, gapBefore = i == 1 and 12 or nil }
		end
	end

	local x = 0
	for i, spec in ipairs(specs) do
		local lane = self.lanes[i] or createLane(self.field)
		self.lanes[i] = lane
		lane.spec = spec
		x = x + (spec.gapBefore or 0)
		lane:ClearAllPoints()
		lane:SetPoint("BOTTOMLEFT", self.field, "BOTTOMLEFT", x, 0)
		lane:SetSize(spec.width, LANE_H + LANE_W)
		lane.bg:SetTexCoord(0, 1, up and 1 or 0, up and 0 or 1)
		lane.receptor:ClearAllPoints()
		lane.receptor:SetPoint(up and "TOP" or "BOTTOM", lane, up and "TOP" or "BOTTOM", 0, up and -2 or 2)
		lane.receptor:SetWidth(spec.kind == "beat" and spec.width - 4 or LANE_W - 4)
		if spec.kind == "rot" then
			lane.icon:SetTexture(spec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			lane.icon:Show()
			lane.ring:SetVertexColor(spec.off and 1 or 0.6, spec.off and 0.8 or 0.6, spec.off and 0.3 or 0.7)
		elseif spec.kind == "bonus" then
			lane.icon:Hide()
			lane.ring:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
			if not self.bonusLaneStart then
				self.bonusLaneStart = i
			end
		else
			lane.icon:Hide()
			lane.ring:SetVertexColor(1, 1, 1)
		end
		lane.key:SetText("")
		lane:Show()
		x = x + spec.width + LANE_GAP
	end
	for i = #specs + 1, #self.lanes do
		self.lanes[i]:Hide()
	end
	self.numLanes = #specs
	local width = math.max(x - LANE_GAP, LANE_W * 3)
	self.field:SetSize(width, LANE_H + LANE_W)
	self.root:SetSize(width, LANE_H + LANE_W + 34)
	self.field:ClearAllPoints()
	self.field:SetPoint(up and "TOPLEFT" or "BOTTOMLEFT", self.root, up and "TOPLEFT" or "BOTTOMLEFT", 0, 0)

	self.combo:ClearAllPoints()
	self.combo:SetPoint("CENTER", self.field, "CENTER", 0, up and -40 or 40)
	self.judge:ClearAllPoints()
	self.judge:SetPoint("CENTER", self.field, "CENTER", 0, up and -10 or 10)
	local hudAnchor = up and "BOTTOM" or "TOP"
	self.acc:ClearAllPoints()
	self.acc:SetPoint(hudAnchor .. "RIGHT", self.root, hudAnchor .. "RIGHT", 0, up and 4 or -4)
	self.songText:ClearAllPoints()
	self.songText:SetPoint(hudAnchor .. "LEFT", self.root, hudAnchor .. "LEFT", 0, up and 4 or -4)
	self.songText:SetWidth(width - 60)
	self.songText:SetJustifyH("LEFT")
	self.songText:SetWordWrap(false)
	self.info:ClearAllPoints()
	self.info:SetPoint("CENTER", self.field, "CENTER", 0, 0)
	if Engine.freestyle then
		self.info:SetText(#Engine.lanes == 0 and "Freestyle: cast on the beat" or "")
	else
		self.info:SetText("")
	end

	self.root:SetScale(db.scale)
	self.root:SetAlpha(db.alpha)
	self:ApplyPosition()
	self:UpdateKeybinds()
	self:ClearNotes()
end

function RM:ApplyPosition()
	local p = BC.db.raid.point
	self.root:ClearAllPoints()
	if p then
		self.root:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		self.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
	end
end

--------------------------------------------------------------------------
-- Keybind labels on receptors
--------------------------------------------------------------------------

local function bindingForSlot(slot)
	local cmd
	if slot <= 12 then
		cmd = "ACTIONBUTTON" .. slot
	elseif slot >= 25 and slot <= 36 then
		cmd = "MULTIACTIONBAR3BUTTON" .. (slot - 24)
	elseif slot >= 37 and slot <= 48 then
		cmd = "MULTIACTIONBAR4BUTTON" .. (slot - 36)
	elseif slot >= 49 and slot <= 60 then
		cmd = "MULTIACTIONBAR2BUTTON" .. (slot - 48)
	elseif slot >= 61 and slot <= 72 then
		cmd = "MULTIACTIONBAR1BUTTON" .. (slot - 60)
	elseif slot >= 73 then
		cmd = "ACTIONBUTTON" .. ((slot - 73) % 12 + 1)
	end
	return cmd and GetBindingKey(cmd)
end

function RM:UpdateKeybinds()
	if not self.lanes or not BC.db.raid.showKeybinds then
		return
	end
	local keys = {}
	for slot = 1, 120 do
		local name = Compat.ActionSpellName(slot)
		if name then
			local key = name:lower()
			if not keys[key] then
				local bind = bindingForSlot(slot)
				if bind then
					keys[key] = bind
				end
			end
		end
	end
	for i = 1, (self.numLanes or 0) do
		local lane = self.lanes[i]
		if lane.spec.kind == "rot" then
			lane.key:SetText(U.ShortKey(keys[lane.spec.spell:lower()]))
		elseif lane.spec.kind == "bonus" then
			lane.key:SetText(U.ShortKey(BC.db.raid.bonusKeys[lane.spec.index]))
		end
	end
end

--------------------------------------------------------------------------
-- Enable / visibility
--------------------------------------------------------------------------

function RM:SetEnabled(on)
	BC.db.raid.enabled = on and true or false
	if on then
		Library:Load()
		Engine:Rebuild()
		self:PickNextSong()
		BC:Print("Raid Mode |cff66ff66on|r. Target an enemy to see your lanes. Spec: " .. Engine:SpecName(Engine.class, Engine.tree) .. (Engine.freestyle and " (Freestyle)" or ""))
	else
		self:StopMusic()
		BC:Print("Raid Mode |cffff6666off|r.")
	end
	self:ApplyBindings()
	self:UpdateVisibility()
	BC:Fire("RAID_MODE_CHANGED", on)
end

function RM:SetLocked(locked)
	BC.db.raid.locked = locked
	if not locked and not BC.db.raid.enabled then
		BC:Print("Showing Raid Mode lanes so you can move them.")
	end
	self:UpdateVisibility()
end

function RM:ShouldShow()
	local db = BC.db.raid
	if not db.locked then
		return true
	end
	if not db.enabled then
		return false
	end
	if db.showMode == "always" then
		return true
	end
	local inCombat = UnitAffectingCombat("player")
	if db.showMode == "combat" then
		return inCombat
	end
	return inCombat or Engine:HasEnemyTarget()
end

function RM:UpdateVisibility()
	if not self.root then
		return
	end
	local locked = BC.db.raid.locked
	self.root:EnableMouse(not locked)
	self.root.unlockBg:SetShown(not locked)
	self.root.unlockText:SetShown(not locked)
	if self:ShouldShow() then
		if not self.root:IsShown() then
			self.tally = self.tally or Scoring.New()
			self.root:Show()
		end
	else
		self.root:Hide()
	end
end

-- Bonus keys are bound with override bindings, which can only change out
-- of combat; changes requested in combat are applied afterwards.
function RM:ApplyBindings()
	if InCombatLockdown() then
		self.bindingsPending = true
		return
	end
	self.bindingsPending = false
	ClearOverrideBindings(self.bindOwner)
	local db = BC.db.raid
	if db.enabled and db.bonus ~= "off" and db.music ~= "off" then
		for i = 1, 2 do
			local key = db.bonusKeys[i]
			if key and key ~= "" then
				SetOverrideBindingClick(self.bindOwner, true, key, "BeatcraftBonus" .. i, "LeftButton")
			end
		end
	end
end

--------------------------------------------------------------------------
-- Music
--------------------------------------------------------------------------

function RM:PickNextSong()
	if not Library.loaded or Library:Count() == 0 or BC.db.raid.music == "off" then
		self.nextSong = nil
		return
	end
	local pool = {}
	if BC.db.raid.playlistMode == "playlist" then
		for id in pairs(BC.db.playlist) do
			local song = Library:Get(id)
			if song then
				pool[#pool + 1] = song
			end
		end
	end
	if #pool == 0 then
		pool = Library.songs
	end
	local pick = pool[math.random(#pool)]
	if #pool > 1 and self.song and pick == self.song then
		pick = pool[math.random(#pool)]
	end
	self.nextSong = pick
	-- parse ahead of time so starting music on pull does not hitch
	self.nextBM = Library:Parse(Library:RaidMap(pick))
end

function RM:StartMusic()
	if BC.db.raid.music == "off" then
		return
	end
	if not self.nextSong then
		self:PickNextSong()
	end
	local song = self.nextSong
	if not song then
		return
	end
	local map = Library:RaidMap(song)
	self.song, self.map, self.bm = song, map, self.nextBM or Library:Parse(map)
	self.nextSong, self.nextBM = nil, nil
	local offset = BC.db.offset + (BC.db.mapOffsets[map.key] or 0)
	Clock:Play(song.audio, 0, offset, function()
		BC:Print("Could not play '" .. (song.title or "?") .. "'. If you imported it while WoW was running, restart the game.")
	end)
	self.musicEnd = GetTime() + (self.bm.lastTime + 2500) / 1000
	self.songText:SetText((song.title or "") .. " - " .. (song.artist or ""))
	self:BuildBonusNotes()
end

function RM:StopMusic()
	if self.bm then
		Clock:Stop()
	end
	self.song, self.map, self.bm = nil, nil, nil
	self.musicEnd = nil
	wipe(self.bonusNotes)
	if self.songText then
		self.songText:SetText("")
	end
end

function RM:MusicPlaying()
	return self.bm ~= nil and Clock.playing and not Clock.failed
end

function RM:UpdateMusic(now)
	if self.musicEnd and now > self.musicEnd then
		self:StopMusic()
		local db = BC.db.raid
		if db.music == "always" or UnitAffectingCombat("player") then
			self:PickNextSong()
			C_Timer.After(1, function()
				if db.enabled and not self.bm and (db.music == "always" or UnitAffectingCombat("player")) then
					self:StartMusic()
				end
			end)
		end
	end
end

--------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------

function RM:ClearNotes()
	for note in pairs(self.notes) do
		self.notePool:Release(note.frame)
	end
	wipe(self.notes)
	wipe(self.holds)
	self.rotNote, self.offNote = nil, nil
	for _, b in ipairs(self.bonusNotes) do
		if b.frame then
			self.notePool:Release(b.frame)
			b.frame = nil
		end
	end
end

-- Hit time for an ability that becomes ready at `ready`: the latest beat
-- subdivision inside the spell queue window, so pressing on the beat
-- queues the cast without delaying it.
function RM:PlanTime(ready, now)
	local T = ready
	if self:MusicPlaying() then
		local g = Beatmap.GridAtOrBefore(self.bm, Clock:TimeAt(ready), 2)
		local gT = Clock:GTOf(g)
		if ready - gT <= queueWindow() then
			T = gT
		end
	end
	return math.max(T, now)
end

function RM:Spawn(entry, ready, off, now)
	local laneIndex = Engine:LaneFor(entry.spell)
	local lane = laneIndex and self.lanes[laneIndex]
	if not lane or lane.spec.kind ~= "rot" then
		return nil
	end
	local _, icon, castTime = Compat.SpellInfo(entry.spell)
	local f = self.notePool:Acquire()
	f.icon:SetTexture(icon or lane.spec.icon)
	f.icon:Show()
	if off then
		f.border:SetVertexColor(1, 0.8, 0.3)
	else
		f.border:SetVertexColor(1, 1, 1)
	end
	f.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	f.glow:SetAlpha(0)
	local note = {
		frame = f,
		lane = lane,
		spell = entry.spell,
		key = entry.spell:lower(),
		T = self:PlanTime(ready, now),
		castTime = (not off and castTime and castTime > 0) and castTime or 0,
		state = "pending",
		off = off,
	}
	if note.castTime > 0 then
		f.body:SetVertexColor(lane.spec.off and 1 or 0.55, 0.55, 0.75, 0.7)
		f.body:Show()
	else
		f.body:Hide()
	end
	self.notes[note] = true
	return note
end

function RM:Finish(note, state, now)
	note.state = state
	note.doneAt = now
	if state == "hit" then
		note.frame.glow:SetAlpha(1)
	end
	if note == self.rotNote then
		self.rotNote = nil
	elseif note == self.offNote then
		self.offNote = nil
	end
end

function RM:Evaluate(now)
	if Engine.freestyle then
		return
	end
	for _, off in ipairs({ false, true }) do
		local field = off and "offNote" or "rotNote"
		local note = self[field]
		if note and note.state == "pending" then
			if now > note.T + LATE_LIMIT then
				self:ShowJudge("MISS", 0)
				self.tally:Judge(0)
				self:Finish(note, "miss", now)
			elseif now < note.T - 0.12 then
				-- still falling: follow changes in the rotation (procs, target swaps)
				local entry, ready = Engine:Next(off, now)
				if not entry then
					self:Finish(note, "cancel", now)
				elseif entry.spell ~= note.spell then
					self:Finish(note, "cancel", now)
					self[field] = self:Spawn(entry, ready, off, now)
				else
					local T = self:PlanTime(ready, now)
					if math.abs(T - note.T) > 0.08 then
						note.T = T
					end
				end
			end
		end
		if not self[field] and now >= (self.nextSpawnAt or 0) then
			local entry, ready = Engine:Next(off, now)
			if entry then
				self[field] = self:Spawn(entry, ready, off, now)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Bonus lanes (song notes)
--------------------------------------------------------------------------

function RM:BuildBonusNotes()
	wipe(self.bonusNotes)
	local db = BC.db.raid
	if db.bonus == "off" or not self.bm then
		return
	end
	local keepEvery = db.bonus == "light" and 2 or 1
	local count = 0
	for _, obj in ipairs(self.bm.objects) do
		if obj.kind ~= "spinner" then
			count = count + 1
			if count % keepEvery == 0 then
				self.bonusNotes[#self.bonusNotes + 1] = { t = obj.t, lane = obj.x < 256 and 1 or 2 }
			end
		end
	end
	self.bonusIndex = 1
end

function RM:BonusWindow()
	return 0.25 * (DIFF[BC.db.raid.difficulty] or 1)
end

function RM:OnBonusKey(i)
	if not self.root or not self.root:IsShown() or not self:MusicPlaying() then
		return
	end
	local laneIndex = self.bonusLaneStart and (self.bonusLaneStart + i - 1)
	local lane = laneIndex and self.lanes[laneIndex]
	if lane then
		lane.flashAt = GetTime()
	end
	local now = GetTime()
	local songNow = Clock:TimeAt(now)
	local window = self:BonusWindow() * 1000
	for k = self.bonusIndex or 1, #self.bonusNotes do
		local b = self.bonusNotes[k]
		if b.t - songNow > window then
			break
		end
		if not b.done and b.lane == i then
			local err = songNow - b.t
			if math.abs(err) <= window then
				b.done = "hit"
				b.doneAt = now
				self:JudgeError(err / 1000, lane)
				return
			end
		end
	end
end

function RM:UpdateBonus(now)
	if #self.bonusNotes == 0 or not self:MusicPlaying() then
		return
	end
	local songNow = Clock:TimeAt(now)
	local window = self:BonusWindow() * 1000
	local k = self.bonusIndex or 1
	-- advance past finished notes and mark misses
	while self.bonusNotes[k] do
		local b = self.bonusNotes[k]
		if not b.done and songNow - b.t > window then
			b.done = "miss"
			b.doneAt = now
			self.tally:Judge(0)
			self:ShowJudge("MISS", 0)
		end
		if b.done and (not b.frame) and songNow - b.t > window then
			k = k + 1
		else
			break
		end
	end
	self.bonusIndex = k

	local approachMs = BC.db.raid.approach * 1000
	local up = BC.db.raid.scrollUp
	for j = k, #self.bonusNotes do
		local b = self.bonusNotes[j]
		local dt = b.t - songNow
		if dt > approachMs then
			break
		end
		local lane = self.lanes[(self.bonusLaneStart or 1) + b.lane - 1]
		if lane then
			if b.done and b.doneAt and now - b.doneAt > 0.15 then
				if b.frame then
					self.notePool:Release(b.frame)
					b.frame = nil
				end
			elseif not b.done or b.done == "hit" then
				if not b.frame then
					b.frame = self.notePool:Acquire()
					b.frame.icon:Hide()
					b.frame.body:Hide()
					b.frame.border:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
					b.frame.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
				end
				local f = b.frame
				local y = math.max(dt, -100) / approachMs * LANE_H
				f:ClearAllPoints()
				f:SetPoint("CENTER", lane.receptor, "CENTER", 0, up and -y or y)
				f.glow:SetAlpha(b.done == "hit" and 1 or 0.25)
				f:SetAlpha(b.done == "hit" and math.max(0, 1 - (now - b.doneAt) / 0.15) or 1)
				f:Show()
			end
		end
	end
end

--------------------------------------------------------------------------
-- Input: presses and casts
--------------------------------------------------------------------------

function RM:RecordPress(name, t)
	if not self.root or not self.root:IsShown() or not name then
		return
	end
	local key = Compat.StripRank(name):lower()
	local list = self.presses[key]
	if not list then
		list = {}
		self.presses[key] = list
	end
	t = t or GetTime()
	list[#list + 1] = t
	while list[1] and t - list[1] > 2 do
		table.remove(list, 1)
	end
	-- Off-GCD abilities are judged on the key press itself: "next swing"
	-- abilities only report success when the swing lands, seconds later.
	local note = self.offNote
	if note and note.state == "pending" and note.key == key and not Engine.freestyle then
		self:JudgeError(t - note.T, note.lane)
		self:Finish(note, "hit", t)
		self.pressJudged[key] = t
		wipe(list)
	end
end

-- Picks the press that most likely triggered a cast seen at eventT: the
-- earliest press inside the spell queue window (plus latency allowance),
-- else the latest recent press, else the event time itself.
function RM:PressTimeFor(key, eventT)
	local list = self.presses[key]
	if not list or #list == 0 then
		return eventT
	end
	local lower = eventT - queueWindow() - 0.3
	local latest
	for _, t in ipairs(list) do
		if t <= eventT + 0.01 then
			if t >= lower then
				wipe(list)
				return t
			end
			latest = t
		end
	end
	if latest and eventT - latest < 1 then
		wipe(list)
		return latest
	end
	return eventT
end

function RM:JudgeError(errSeconds, lane)
	local m = DIFF[BC.db.raid.difficulty] or 1
	local a = math.abs(errSeconds) * 1000
	local value
	if a <= 60 * m then
		value = 300
	elseif a <= 130 * m then
		value = 100
	elseif a <= 250 * m then
		value = 50
	else
		value = 0
	end
	self.tally:Judge(value, value > 0 and errSeconds * 1000 or nil)
	local label = LABELS[value] or (errSeconds < 0 and "EARLY" or "LATE")
	self:ShowJudge(label, value)
	if lane and value > 0 then
		lane.flashAt = GetTime()
	end
	if value > 0 then
		self:PlayHitsound()
	end
	return value
end

function RM:PlayHitsound()
	-- Raid Mode stays quiet unless the player asked for hitsounds.
end

function RM:OnCast(kind, castGUID, spellID)
	if not self.root or not self.root:IsShown() then
		return
	end
	local now = GetTime()
	if castGUID and self.castGUIDs[castGUID] then
		-- second event for a cast we already judged (cast-time spells)
		if kind == "SUCCEEDED" then
			local hold = self.holds[castGUID]
			if hold then
				self.holds[castGUID] = nil
				self.tally:AddCombo()
				self.tally:Bonus(50)
				self:Finish(hold, "hit", now)
			end
		end
		return
	end
	local name = Compat.SpellInfo(spellID)
	if not name then
		return
	end
	local key = name:lower()
	-- Already judged when the key was pressed (off-GCD abilities).
	local judgedAt = self.pressJudged[key]
	if judgedAt and now - judgedAt < 5 then
		self.pressJudged[key] = nil
		return
	end
	-- Channels can report both CHANNEL_START and SUCCEEDED; judge once.
	if self.lastCastKey == key and now - (self.lastCastAt or 0) < 0.25 then
		return
	end
	self.lastCastKey, self.lastCastAt = key, now
	if castGUID then
		self.castGUIDs[castGUID] = now
	end
	local pressT = self:PressTimeFor(key, now)

	if Engine.freestyle then
		self:JudgeFreestyle(pressT)
		return
	end

	local note
	if self.rotNote and self.rotNote.state == "pending" and self.rotNote.key == key then
		note = self.rotNote
	elseif self.offNote and self.offNote.state == "pending" and self.offNote.key == key then
		note = self.offNote
	end
	if note then
		self:JudgeError(pressT - note.T, note.lane)
		self.nextSpawnAt = now + SETTLE
		if kind == "START" and note.castTime > 0 and castGUID then
			note.state = "holding"
			note.holdUntil = now + note.castTime
			self.holds[castGUID] = note
			if note == self.rotNote then
				self.rotNote = nil
			end
		else
			self:Finish(note, "hit", now)
		end
	elseif BC.db.raid.difficulty ~= "easy" then
		-- A rotation ability pressed instead of the suggested one in the
		-- same stream (on-GCD vs off-GCD).
		local laneIndex = Engine:LaneFor(name)
		local lane = laneIndex and self.lanes[laneIndex]
		local stream = lane and lane.spec.kind == "rot" and (lane.spec.off and "offNote" or "rotNote")
		local pending = stream and self[stream]
		if pending and pending.state == "pending" then
			self.tally:Break()
			self:ShowJudge("OFF-SCRIPT", 50)
			self:Finish(pending, "cancel", now)
			self.nextSpawnAt = now + SETTLE
		end
	end
end

function RM:OnCastFailed(castGUID)
	local hold = castGUID and self.holds[castGUID]
	if hold then
		self.holds[castGUID] = nil
		self.tally:Break()
		self:ShowJudge("INTERRUPTED", 0)
		self:Finish(hold, "miss", GetTime())
	end
end

function RM:JudgeFreestyle(pressT)
	if not self:MusicPlaying() then
		return
	end
	local songT = Clock:TimeAt(pressT)
	local _, errMs = Beatmap.NearestGrid(self.bm, songT, 2)
	self:JudgeError(errMs / 1000, self.lanes[1])
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

function RM:ShowJudge(label, value)
	self.judgeLabel, self.judgeAt = label, GetTime()
	local c = U.JUDGE_COLORS[value] or U.JUDGE_COLORS[0]
	if label == "OFF-SCRIPT" then
		c = { 1, 0.6, 0.2 }
	end
	self.judge:SetText(label)
	self.judge:SetTextColor(c[1], c[2], c[3])
end

function RM:RenderNotes(now)
	local approach = BC.db.raid.approach
	local up = BC.db.raid.scrollUp
	for note in pairs(self.notes) do
		local f = note.frame
		local lane = note.lane
		if note.state == "pending" then
			local dt = note.T - now
			local y = dt / approach * LANE_H
			if y > LANE_H then
				f:Hide()
			else
				y = math.max(y, -20)
				f:ClearAllPoints()
				f:SetPoint("CENTER", lane.receptor, "CENTER", 0, up and -y or y)
				f:SetAlpha(U.Clamp((LANE_H - y) / (LANE_H * 0.15), 0, 1) * (dt < 0 and math.max(0.3, 1 + dt) or 1))
				if note.castTime > 0 then
					f.body:SetHeight(note.castTime / approach * LANE_H)
					f.body:ClearAllPoints()
					f.body:SetPoint(up and "TOP" or "BOTTOM", f, "CENTER", 0, 0)
				end
				f:Show()
			end
		elseif note.state == "holding" then
			f:ClearAllPoints()
			f:SetPoint("CENTER", lane.receptor, "CENTER", 0, 0)
			local remaining = math.max(note.holdUntil - now, 0)
			f.body:SetHeight(math.max(remaining / approach * LANE_H, 1))
			f.glow:SetAlpha(0.5 + 0.3 * math.sin(now * 12))
			lane.flashAt = now
			if now > note.holdUntil + 1.5 then
				-- never got a success/fail event; let it go quietly
				self:Finish(note, "cancel", now)
			end
		else
			local age = now - (note.doneAt or now)
			local life = 0.25
			if age >= life then
				self.notes[note] = nil
				self.notePool:Release(f)
			else
				f:SetAlpha(1 - age / life)
				if note.state == "hit" then
					f:SetScale(1 + age * 1.2)
				end
			end
		end
	end
end


function RM:RenderBeatLane(now)
	local lane = self.lanes[1]
	if not lane or lane.spec.kind ~= "beat" then
		return
	end
	self.beatMarkers = self.beatMarkers or {}
	for _, m in ipairs(self.beatMarkers) do
		m:Hide()
	end
	if not self:MusicPlaying() then
		return
	end
	local approachMs = BC.db.raid.approach * 1000
	local songNow = Clock:TimeAt(now)
	local tp = Beatmap.RedAt(self.bm, songNow)
	local step = tp.beatLength
	local first = tp.t + math.ceil((songNow - tp.t) / step) * step
	local up = BC.db.raid.scrollUp
	local i = 0
	local t = first
	while t - songNow <= approachMs and i < 16 do
		i = i + 1
		local m = self.beatMarkers[i]
		if not m then
			m = lane:CreateTexture(nil, "ARTWORK")
			m:SetColorTexture(1, 1, 1, 0.7)
			m:SetHeight(3)
			self.beatMarkers[i] = m
		end
		local y = (t - songNow) / approachMs * LANE_H
		m:ClearAllPoints()
		m:SetPoint("LEFT", lane.receptor, "LEFT", 4, up and -y or y)
		m:SetPoint("RIGHT", lane.receptor, "RIGHT", -4, up and -y or y)
		local beatIndex = math.floor((t - tp.t) / step + 0.5)
		m:SetAlpha(beatIndex % (tp.meter or 4) == 0 and 1 or 0.45)
		m:Show()
		t = t + step
	end
	-- pulse the receptor on each beat
	local _, err = Beatmap.NearestGrid(self.bm, songNow, 1)
	if math.abs(err) < 60 then
		lane.flashAt = math.max(lane.flashAt, now - 0.05)
	end
end

function RM:OnUpdate()
	local now = GetTime()
	if not self.tally then
		self.tally = Scoring.New()
	end
	self:UpdateMusic(now)
	if now - (self.lastEval or 0) > 0.05 then
		self.lastEval = now
		self:Evaluate(now)
	end
	self:RenderNotes(now)
	self:UpdateBonus(now)
	if Engine.freestyle then
		self:RenderBeatLane(now)
	end

	for i = 1, (self.numLanes or 0) do
		local lane = self.lanes[i]
		local age = now - lane.flashAt
		lane.flash:SetAlpha(age < 0.2 and (1 - age / 0.2) * 0.8 or 0)
	end

	local tally = self.tally
	if tally.combo >= 2 then
		self.combo:SetText(tally.combo .. "x")
		self.combo:SetAlpha(0.85)
	else
		self.combo:SetText("")
	end
	if tally:Total() > 0 then
		self.acc:SetText(U.FormatAcc(tally:Accuracy()))
	else
		self.acc:SetText("")
	end
	if self.judgeAt then
		local age = now - self.judgeAt
		self.judge:SetAlpha(age < 0.6 and 1 - age / 0.6 or 0)
	end
end

--------------------------------------------------------------------------
-- Fight summary
--------------------------------------------------------------------------

function RM:ShowSummary(tally)
	if not BC.db.raid.summary or tally:Total() < 5 then
		return
	end
	local grade = tally:Grade()
	local rec = {
		date = time(),
		grade = grade,
		acc = tally:Accuracy(),
		combo = tally.maxCombo,
		score = tally.score,
		zone = GetRealZoneText and GetRealZoneText() or "",
		target = self.fightTarget,
	}
	table.insert(BC.db.fights, 1, rec)
	while #BC.db.fights > 30 do
		table.remove(BC.db.fights)
	end

	local toast = self.toast
	if not toast then
		toast = CreateFrame("Frame", nil, UIParent)
		toast:SetSize(340, 64)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
		toast:SetFrameStrata("HIGH")
		toast.bg = W.Solid(toast, "BACKGROUND", 0.05, 0.05, 0.08, 0.9)
		toast.bg:SetAllPoints()
		W.Border(toast, ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
		toast.grade = W.Text(toast, 34, "", "THICKOUTLINE")
		toast.grade:SetPoint("LEFT", 14, 0)
		toast.title = W.Text(toast, 13, "", "OUTLINE")
		toast.title:SetPoint("TOPLEFT", 70, -10)
		toast.line = W.Text(toast, 11, "")
		toast.line:SetPoint("TOPLEFT", 70, -30)
		toast.line2 = W.Text(toast, 11, "")
		toast.line2:SetPoint("TOPLEFT", 70, -45)
		toast:SetScript("OnUpdate", function(f)
			local age = GetTime() - f.shownAt
			if age > 10 then
				f:Hide()
			elseif age > 9 then
				f:SetAlpha(10 - age)
			end
		end)
		self.toast = toast
	end
	local c = U.GRADE_COLORS[grade] or U.GRADE_COLORS.D
	toast.grade:SetText(grade)
	toast.grade:SetTextColor(c[1], c[2], c[3])
	toast.title:SetText("Fight complete" .. (self.fightTarget and (": " .. self.fightTarget) or ""))
	toast.line:SetText(string.format("%s accuracy   %dx max combo   %s pts", U.FormatAcc(rec.acc), rec.combo, U.FormatNumber(rec.score)))
	toast.line2:SetText(string.format("|cff66ccff%d|r perfect  |cff66ff66%d|r great  |cffffcc4d%d|r good  |cffff4040%d|r miss", tally.c300, tally.c100, tally.c50, tally.miss))
	toast.shownAt = GetTime()
	toast:SetAlpha(1)
	toast:Show()
end

--------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------

function RM:InstallHooks()
	hooksecurefunc("UseAction", function(slot)
		RM:RecordPress(Compat.ActionSpellName(slot))
	end)
	hooksecurefunc("CastSpellByName", function(name)
		if type(name) == "string" then
			RM:RecordPress(name)
		end
	end)
	if CastSpellByID then
		hooksecurefunc("CastSpellByID", function(id)
			RM:RecordPress((Compat.SpellInfo(id)))
		end)
	end
	if CastSpell then
		hooksecurefunc("CastSpell", function(index, book)
			local name
			if GetSpellBookItemName then
				name = GetSpellBookItemName(index, book)
			elseif GetSpellName then
				name = GetSpellName(index, book)
			end
			RM:RecordPress(name)
		end)
	end
end

function RM:OnLogin()
	self:CreateFrames()
	self:InstallHooks()
	self:Layout()
	if BC.db.raid.enabled then
		Library:Load()
		self:PickNextSong()
	end
	self:ApplyBindings()
	self:UpdateVisibility()
end

BC:Listen("ROTATION_CHANGED", function()
	RM:Layout()
	RM:UpdateVisibility()
end)

BC:On("PLAYER_TARGET_CHANGED", function()
	RM:UpdateVisibility()
end)

BC:On("PLAYER_REGEN_DISABLED", function()
	if not BC.db.raid.enabled then
		return
	end
	RM.tally = Scoring.New()
	RM.fightTarget = UnitExists("target") and UnitName("target") or nil
	if BC.db.raid.music ~= "off" and not RM.bm then
		RM:StartMusic()
	end
	RM:UpdateVisibility()
end)

BC:On("PLAYER_REGEN_ENABLED", function()
	if RM.bindingsPending then
		RM:ApplyBindings()
	end
	if not BC.db.raid.enabled then
		return
	end
	if RM.tally then
		RM:ShowSummary(RM.tally)
	end
	if BC.db.raid.music == "pull" and not BC.db.raid.keepMusic then
		RM:StopMusic()
		RM:PickNextSong()
	end
	RM:UpdateVisibility()
end)

BC:On("UNIT_SPELLCAST_SENT", function(_, unit, _, _, spellID)
	if unit == "player" and spellID then
		local name = Compat.SpellInfo(spellID)
		if name then
			local list = RM.presses[name:lower()]
			local last = list and list[#list]
			if not last or GetTime() - last > queueWindow() + 0.1 then
				RM:RecordPress(name)
			end
		end
	end
end)

BC:On("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
	if unit == "player" then
		RM:OnCast("START", castGUID, spellID)
	end
end)

BC:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, castGUID, spellID)
	if unit == "player" then
		RM:OnCast("CHANNEL", castGUID, spellID)
	end
end)

BC:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
	if unit == "player" then
		RM:OnCast("SUCCEEDED", castGUID, spellID)
	end
end)

BC:On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID)
	if unit == "player" then
		RM:OnCastFailed(castGUID)
	end
end)

BC:On("UNIT_SPELLCAST_FAILED", function(_, unit, castGUID)
	if unit == "player" then
		RM:OnCastFailed(castGUID)
	end
end)

BC:On("UPDATE_BINDINGS", function()
	RM:UpdateKeybinds()
end)

BC:On("ACTIONBAR_SLOT_CHANGED", function()
	if RM.root and RM.root:IsShown() then
		RM:UpdateKeybinds()
	end
end)

-- Old cast GUIDs are pruned periodically.
C_Timer.NewTicker(10, function()
	local now = GetTime()
	for guid, t in pairs(RM.castGUIDs) do
		if now - t > 10 then
			RM.castGUIDs[guid] = nil
		end
	end
end)

