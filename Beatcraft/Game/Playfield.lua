-- Downtime Mode: a fullscreen osu!-style game. This file holds the shared
-- fullscreen window (keyboard/mouse capture, screen switching, auto-close)
-- and the gameplay screen. Song select and results live next to it.
local _, BC = ...

local Compat = BC.Compat
local U = BC.Util
local W = BC.Widgets
local Clock = BC.Clock
local Beatmap = BC.Beatmap
local Library = BC.Library
local Scoring = BC.Scoring

local Game = BC:Module("Game")
local Play = BC:Module("Play")

local ACCENT = BC.ACCENT
local floor, abs, sqrt, atan2, min, max = math.floor, math.abs, math.sqrt, math.atan2, math.min, math.max
local PI = math.pi

-- circle.tga / dot.tga draw their circle slightly inside the texture
local CIRCLE_TEX_SCALE = 64 / 60
local DOT_TEX_SCALE = 32 / 30

--------------------------------------------------------------------------
-- Fullscreen window
--------------------------------------------------------------------------

function Game:Create()
	if self.root then
		return true
	end
	if InCombatLockdown() then
		return false
	end
	local root = CreateFrame("Frame", "BeatcraftGame", UIParent)
	root:SetAllPoints(UIParent)
	root:SetFrameStrata("FULLSCREEN_DIALOG")
	root:EnableMouse(true)
	root:EnableMouseWheel(true)
	root:EnableKeyboard(true)
	root:SetPropagateKeyboardInput(false)
	root:Hide()
	self.root = root

	root.black = W.Solid(root, "BACKGROUND", 0, 0, 0, 1)
	root.black:SetAllPoints()
	root.bgImage = root:CreateTexture(nil, "BACKGROUND", nil, 1)
	root.bgImage:SetAllPoints()
	root.dim = W.Solid(root, "BACKGROUND", 0, 0, 0, 0.7, 2)
	root.dim:SetAllPoints()

	root:SetScript("OnKeyDown", function(_, key)
		Game:OnKey(key, true)
	end)
	root:SetScript("OnKeyUp", function(_, key)
		Game:OnKey(key, false)
	end)
	root:SetScript("OnMouseDown", function(_, button)
		Game:OnMouse(button, true)
	end)
	root:SetScript("OnMouseUp", function(_, button)
		Game:OnMouse(button, false)
	end)
	root:SetScript("OnMouseWheel", function(_, delta)
		if Game.screen and Game.screen.OnWheel then
			Game.screen:OnWheel(delta)
		end
	end)
	root:SetScript("OnHide", function()
		Clock:Stop()
		Game.screen = nil
	end)

	local toastHolder = CreateFrame("Frame", nil, root)
	toastHolder:SetAllPoints()
	toastHolder:SetFrameLevel(root:GetFrameLevel() + 2000)
	root.toast = W.Text(toastHolder, 14, "", "OUTLINE")
	root.toast:SetPoint("TOP", 0, -60)
	root:SetScript("OnUpdate", function()
		if Game.toastAt then
			local age = GetTime() - Game.toastAt
			root.toast:SetAlpha(age < 2 and 1 or max(0, 3 - age))
		end
	end)

	Play:Create(root)
	BC.SongSelect:Create(root)
	BC.Results:Create(root)
	return true
end

function Game:Toast(text)
	self.root.toast:SetText(text)
	self.root.toast:SetAlpha(1)
	self.toastAt = GetTime()
end

function Game:SetBackground(path)
	local root = self.root
	if path then
		root.bgImage:SetTexture(path)
		root.bgImage:SetTexCoord(0, 1, 0, 1)
		root.bgImage:Show()
	else
		root.bgImage:Hide()
	end
	root.black:SetAlpha(BC.db.game.hideWorld and 1 or 0.55)
end

function Game:SetDim(dim)
	self.root.dim:SetAlpha(dim)
end

function Game:IsOpen()
	return self.root and self.root:IsShown()
end

function Game:Show(screen, ...)
	if self.screen and self.screen ~= screen and self.screen.Leave then
		self.screen:Leave()
	end
	self.screen = screen
	screen:Enter(...)
end

function Game:Open()
	if InCombatLockdown() or UnitAffectingCombat("player") then
		BC:Print("Downtime Mode can't open in combat.")
		return false
	end
	if not self:Create() then
		return false
	end
	if BC.RaidMode.bm then
		BC.RaidMode:StopMusic()
	end
	BC.MainMenu:Hide()
	self.root:Show()
	return true
end

function Game:Close(reason)
	if not self:IsOpen() then
		return
	end
	if self.screen and self.screen.Leave then
		self.screen:Leave()
	end
	self.screen = nil
	Clock:Stop()
	self.root:Hide()
	if reason then
		BC:Print(reason)
	end
end

function Game:OnKey(key, down)
	if down and key == "PRINTSCREEN" then
		Screenshot()
		return
	end
	if self.screen and self.screen.OnKey then
		self.screen:OnKey(key, down)
	end
end

function Game:OnMouse(button, down)
	if self.screen and self.screen.OnMouse then
		self.screen:OnMouse(button, down)
	end
end

-- Cursor position in root coordinates.
function Game:Cursor()
	local x, y = GetCursorPosition()
	local scale = self.root:GetEffectiveScale()
	return x / scale, y / scale
end

-- Things that should pull the player out of the game.
BC:On("PLAYER_REGEN_DISABLED", function()
	Game:Close("Entered combat - closed Downtime Mode.")
end)
BC:On("PLAYER_ENTERING_WORLD", function()
	Game:Close()
end)
BC:On("READY_CHECK", function()
	if BC.db.game.closeOnReadyCheck then
		Game:Close("Ready check!")
	end
end)
BC:On("CHAT_MSG_WHISPER", function()
	if BC.db.game.closeOnWhisper then
		Game:Close("You received a whisper.")
	end
end)
BC:On("UPDATE_BATTLEFIELD_STATUS", function()
	if not BC.db.game.closeOnQueue or not GetBattlefieldStatus then
		return
	end
	for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
		if GetBattlefieldStatus(i) == "confirm" then
			Game:Close("Your battleground queue popped!")
			return
		end
	end
end)
pcall(BC.On, BC, "LFG_PROPOSAL_SHOW", function()
	if BC.db.game.closeOnQueue then
		Game:Close("Your group finder queue popped!")
	end
end)

--------------------------------------------------------------------------
-- Gameplay screen
--------------------------------------------------------------------------

local function createCircle(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(1, 1)
	f.body = f:CreateTexture(nil, "ARTWORK")
	f.body:SetTexture(BC.MEDIA .. "circle")
	f.body:SetPoint("CENTER")
	f.overlay = f:CreateTexture(nil, "OVERLAY")
	f.overlay:SetTexture(BC.MEDIA .. "circleoverlay")
	f.overlay:SetPoint("CENTER")
	f.approach = f:CreateTexture(nil, "OVERLAY", nil, 2)
	f.approach:SetTexture(BC.MEDIA .. "approach")
	f.approach:SetPoint("CENTER")
	f.number = f:CreateFontString(nil, "OVERLAY", nil, 3)
	f.number:SetPoint("CENTER", 0, 1)
	f.arrow = f:CreateTexture(nil, "OVERLAY", nil, 4)
	f.arrow:SetTexture(BC.MEDIA .. "arrow")
	f.arrow:SetPoint("CENTER")
	f.arrow:Hide()
	return f
end

local function createSliderBody(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f.border, f.fill = {}, {}
	f.used = 0
	return f
end

local function createBurst(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY", nil, 5)
	fs:SetFont(W.NUMFONT, 26, "THICKOUTLINE")
	return fs
end

function Play:Create(root)
	local screen = CreateFrame("Frame", nil, root)
	screen:SetAllPoints()
	screen:Hide()
	self.screen = screen

	local pf = CreateFrame("Frame", nil, screen)
	self.pf = pf
	pf.border = W.Solid(pf, "BACKGROUND", 1, 1, 1, 0.03)
	pf.border:SetAllPoints()

	self.circlePool = U.NewPool(function()
		return createCircle(pf)
	end, function(f)
		f:Hide()
		f:ClearAllPoints()
		f.arrow:Hide()
	end)
	self.bodyPool = U.NewPool(function()
		return createSliderBody(pf)
	end, function(f)
		for i = 1, f.used do
			f.border[i]:Hide()
			f.fill[i]:Hide()
		end
		f.used = 0
		f:Hide()
	end)
	self.burstPool = U.NewPool(function()
		return createBurst(pf)
	end, function(fs)
		fs:Hide()
		fs:ClearAllPoints()
	end)

	-- slider ball and follow circle
	self.ball = CreateFrame("Frame", nil, pf)
	self.ball:SetSize(1, 1)
	self.ball:SetFrameLevel(pf:GetFrameLevel() + 900)
	self.ball.tex = self.ball:CreateTexture(nil, "OVERLAY")
	self.ball.tex:SetTexture(BC.MEDIA .. "circle")
	self.ball.tex:SetPoint("CENTER")
	self.ball.follow = self.ball:CreateTexture(nil, "OVERLAY", nil, 1)
	self.ball.follow:SetTexture(BC.MEDIA .. "approach")
	self.ball.follow:SetPoint("CENTER")
	self.ball:Hide()

	-- spinner
	local sp = CreateFrame("Frame", nil, pf)
	sp:SetPoint("CENTER")
	sp:SetSize(1, 1)
	sp:SetFrameLevel(pf:GetFrameLevel() + 950)
	sp.ring = sp:CreateTexture(nil, "ARTWORK")
	sp.ring:SetTexture(BC.MEDIA .. "ring")
	sp.ring:SetPoint("CENTER")
	sp.progress = sp:CreateTexture(nil, "OVERLAY")
	sp.progress:SetTexture(BC.MEDIA .. "ring")
	sp.progress:SetPoint("CENTER")
	sp.progress:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	sp.text = W.Text(sp, 28, "SPIN!", "THICKOUTLINE")
	sp.text:SetPoint("CENTER", 0, 0)
	sp.rpm = W.Text(sp, 14, "", "OUTLINE")
	sp.rpm:SetPoint("CENTER", 0, -40)
	sp.bonus = W.Text(sp, 22, "", "THICKOUTLINE")
	sp.bonus:SetPoint("CENTER", 0, 60)
	sp.bonus:SetTextColor(1, 0.9, 0.4)
	sp:Hide()
	self.spinner = sp

	-- cursor and trail, above everything else
	local cursorLayer = CreateFrame("Frame", nil, screen)
	cursorLayer:SetAllPoints()
	cursorLayer:SetFrameLevel(pf:GetFrameLevel() + 1500)
	self.cursor = cursorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	self.cursor:SetTexture(BC.MEDIA .. "cursor")
	self.cursor:SetSize(44, 44)
	self.trail = {}
	for i = 1, 14 do
		local t = cursorLayer:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetTexture(BC.MEDIA .. "cursor")
		t:SetSize(30, 30)
		t:SetBlendMode("ADD")
		self.trail[i] = t
	end
	self.trailPos = {}

	self:CreateHUD(screen)

	screen:SetScript("OnUpdate", function()
		Play:OnUpdate()
	end)
end

function Play:CreateHUD(screen)
	local hud = CreateFrame("Frame", nil, screen)
	hud:SetAllPoints()
	hud:SetFrameLevel(self.pf:GetFrameLevel() + 1000)
	self.hud = hud

	self.scoreText = hud:CreateFontString(nil, "OVERLAY")
	self.scoreText:SetFont(W.NUMFONT, 34, "OUTLINE")
	self.scoreText:SetPoint("TOPRIGHT", -20, -14)
	self.accText = hud:CreateFontString(nil, "OVERLAY")
	self.accText:SetFont(W.NUMFONT, 20, "OUTLINE")
	self.accText:SetPoint("TOPRIGHT", self.scoreText, "BOTTOMRIGHT", 0, -2)
	self.comboText = hud:CreateFontString(nil, "OVERLAY")
	self.comboText:SetFont(W.NUMFONT, 44, "THICKOUTLINE")
	self.comboText:SetPoint("BOTTOMLEFT", 20, 16)

	local hpBg = W.Solid(hud, "ARTWORK", 0.1, 0.1, 0.14, 0.8)
	hpBg:SetPoint("TOPLEFT", 20, -18)
	hpBg:SetSize(360, 10)
	self.hpFill = W.Solid(hud, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	self.hpFill:SetPoint("TOPLEFT", hpBg, "TOPLEFT")
	self.hpFill:SetHeight(10)
	self.hpWidth = 360

	local progBg = W.Solid(hud, "ARTWORK", 1, 1, 1, 0.12)
	progBg:SetPoint("TOPRIGHT", self.accText, "BOTTOMRIGHT", 0, -6)
	progBg:SetSize(160, 4)
	self.progFill = W.Solid(hud, "OVERLAY", 1, 1, 1, 0.8)
	self.progFill:SetPoint("TOPLEFT", progBg, "TOPLEFT")
	self.progFill:SetHeight(4)
	self.progWidth = 160

	-- hit error bar
	local eb = CreateFrame("Frame", nil, hud)
	eb:SetSize(260, 24)
	eb:SetPoint("BOTTOM", 0, 18)
	self.errorBar = eb
	eb.zones = {}
	for i, c in ipairs({ { 1, 0.8, 0.3 }, { 0.4, 1, 0.4 }, { 0.4, 0.8, 1 } }) do
		local z = W.Solid(eb, "ARTWORK", c[1], c[2], c[3], 0.5, i)
		z:SetPoint("CENTER")
		z:SetHeight(4)
		eb.zones[i] = z
	end
	eb.center = W.Solid(eb, "OVERLAY", 1, 1, 1, 1)
	eb.center:SetSize(2, 18)
	eb.center:SetPoint("CENTER")
	eb.ticks = {}
	for i = 1, 24 do
		local t = W.Solid(eb, "OVERLAY", 1, 1, 1, 1, 1)
		t:SetSize(2, 14)
		t:Hide()
		eb.ticks[i] = t
	end
	eb.mean = W.Text(eb, 14, "v", "OUTLINE")
	eb.nextTick = 1

	-- key overlay
	local ko = CreateFrame("Frame", nil, hud)
	ko:SetSize(44, 4 * 46)
	ko:SetPoint("RIGHT", -16, 0)
	self.keyOverlay = ko
	ko.keys = {}
	for i, label in ipairs({ "K1", "K2", "M1", "M2" }) do
		local k = CreateFrame("Frame", nil, ko)
		k:SetSize(44, 42)
		k:SetPoint("TOP", 0, -(i - 1) * 46)
		k.bg = W.Solid(k, "BACKGROUND", 0.1, 0.1, 0.14, 0.85)
		k.bg:SetAllPoints()
		W.Border(k, 0.35, 0.35, 0.42, 1)
		k.label = W.Text(k, 11, label, "OUTLINE")
		k.label:SetPoint("TOP", 0, -5)
		k.count = W.Text(k, 13, "0", "OUTLINE")
		k.count:SetPoint("BOTTOM", 0, 5)
		ko.keys[i] = k
	end

	self.breakText = W.Text(hud, 28, "", "THICKOUTLINE")
	self.breakText:SetPoint("CENTER", 0, 120)
	self.hint = W.Text(hud, 11, "Esc quit   ` retry   - / = offset", "OUTLINE")
	self.hint:SetPoint("BOTTOMRIGHT", -16, 12)
	self.hint:SetTextColor(0.7, 0.7, 0.7)
	self.introText = W.Text(hud, 22, "", "THICKOUTLINE")
	self.introText:SetPoint("CENTER", 0, 160)

	-- failed overlay
	local fail = CreateFrame("Frame", nil, hud)
	fail:SetAllPoints()
	fail:SetFrameLevel(hud:GetFrameLevel() + 50)
	fail.bg = W.Solid(fail, "BACKGROUND", 0.3, 0, 0, 0.5)
	fail.bg:SetAllPoints()
	fail.text = W.Text(fail, 48, "FAILED", "THICKOUTLINE")
	fail.text:SetPoint("CENTER", 0, 60)
	fail.text:SetTextColor(1, 0.3, 0.3)
	fail.retry = W.Button(fail, "Retry  (`)", 160, 34, function()
		Play:Retry()
	end, true)
	fail.retry:SetPoint("CENTER", -90, -20)
	fail.back = W.Button(fail, "Back  (Esc)", 160, 34, function()
		Play:Quit()
	end)
	fail.back:SetPoint("CENTER", 90, -20)
	fail:Hide()
	self.failOverlay = fail
end

--------------------------------------------------------------------------
-- Starting / stopping
--------------------------------------------------------------------------

function Play:Layout()
	local root = self.screen
	local h = root:GetHeight() * 0.8
	local s = h / 384
	self.s = s
	self.pf:SetSize(512 * s, 384 * s)
	self.pf:ClearAllPoints()
	self.pf:SetPoint("CENTER", root, "CENTER", 0, -root:GetHeight() * 0.02)
end

-- Starts a map. mods: {hr, hd, ez, nf}
function Play:Enter(map, mods)
	self.map, self.mods = map, mods or {}
	self.song = map.song
	self.screen:Show()
	self:Layout()
	self:Start()
end

function Play:Leave()
	self:Cleanup()
	Clock:Stop()
	self.screen:Hide()
end

function Play:Cleanup()
	self.circlePool:ReleaseAll()
	self.bodyPool:ReleaseAll()
	self.burstPool:ReleaseAll()
	self.ball:Hide()
	self.spinner:Hide()
	self.failOverlay:Hide()
	self.active = {}
	self.bursts = {}
end

function Play:Start()
	self:Cleanup()
	local map, mods, song = self.map, self.mods, self.song
	local bm = Library:Parse(map, mods)
	self.bm = bm
	local ar, od, cs, hp = Beatmap.ModdedStats(map, mods)
	self.preempt = Beatmap.Preempt(ar)
	self.fadeIn = min(400, self.preempt * 0.66)
	self.radius = Beatmap.Radius(cs)
	self.w300, self.w100, self.w50 = Scoring.Windows(od)
	self.hpStat = hp
	self.tally = Scoring.New(Scoring.ModMultiplier(mods))

	-- per-play state wraps the cached beatmap objects
	self.objs = {}
	for i, obj in ipairs(bm.objects) do
		self.objs[i] = setmetatable({ index = i }, { __index = obj })
	end
	self.spawnIndex = 1
	self.judgeIndex = 1
	self.held = {}
	self.keyCounts = { 0, 0, 0, 0 }
	self.failed = false
	self.finished = false
	self.lastUpdate = nil

	for _, k in ipairs(self.keyOverlay.keys) do
		k.count:SetText("0")
	end
	for _, t in ipairs(self.errorBar.ticks) do
		t:Hide()
	end
	self.errorBar.nextTick = 1
	local eb = self.errorBar
	eb.zones[1]:SetWidth(self.w50 * 2 * 0.6)
	eb.zones[2]:SetWidth(self.w100 * 2 * 0.6)
	eb.zones[3]:SetWidth(self.w300 * 2 * 0.6)
	eb.mean:Hide()
	eb:SetShown(BC.db.game.errorBar)
	self.keyOverlay:SetShown(BC.db.game.keyOverlay)

	Game:SetBackground(song.bg)
	Game:SetDim(BC.db.game.dim)

	-- give the player time to see the first object
	local leadMs = max(0, self.preempt + 800 - bm.firstTime, map.lead or 0)
	self.offset = BC.db.offset + (BC.db.mapOffsets[map.key] or 0)
	Clock:Play(song.audio, leadMs / 1000, self.offset, function()
		Game:Toast("Could not play this song's audio. If you imported it while WoW was running, restart WoW.")
	end)
	self.introText:SetText((song.title or "") .. "  [" .. (map.version or "") .. "]")
	self.introText:SetAlpha(1)
	self.startedAt = GetTime()
	self.playing = true
end

function Play:Retry()
	if not self.map then
		return
	end
	Clock:Stop()
	self:Start()
end

function Play:Quit()
	self.playing = false
	Clock:Stop()
	Game:Show(BC.SongSelect)
end

function Play:Fail()
	self.failed = true
	self.playing = false
	Clock:Stop()
	self.failOverlay:Show()
	self.ball:Hide()
	self.spinner:Hide()
end

function Play:Finish()
	self.finished = true
	self.playing = false
	local rank, rec = Scoring.Save(self.map.key, self.tally, self.mods)
	if rank == 1 then
		BC.Guild:SharePB(self.map, rec)
	end
	C_Timer.After(1.2, function()
		if Game.screen == Play and Play.finished then
			Clock:Stop()
			Game:Show(BC.Results, self.map, self.tally, self.mods, rank)
		end
	end)
end

--------------------------------------------------------------------------
-- Coordinates
--------------------------------------------------------------------------

function Play:Place(f, x, y)
	f:ClearAllPoints()
	f:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
end

-- Cursor in osu! pixels.
function Play:CursorOsu()
	local cx, cy = Game:Cursor()
	local left, top = self.pf:GetLeft(), self.pf:GetTop()
	if not left then
		return -1000, -1000, cx, cy
	end
	return (cx - left) / self.s, (top - cy) / self.s, cx, cy
end

--------------------------------------------------------------------------
-- Object visuals
--------------------------------------------------------------------------

function Play:SetupCircle(f, obj, isTail)
	local d = self.radius * 2 * self.s
	local c = obj.color
	f.body:SetSize(d * CIRCLE_TEX_SCALE, d * CIRCLE_TEX_SCALE)
	f.body:SetVertexColor(c[1], c[2], c[3])
	f.overlay:SetSize(d * CIRCLE_TEX_SCALE, d * CIRCLE_TEX_SCALE)
	f.approach:SetVertexColor(c[1], c[2], c[3])
	f.approach:SetShown(not isTail and not self.mods.hd)
	f.number:SetFont(W.NUMFONT, max(10, d * 0.42), "OUTLINE")
	f.number:SetText(isTail and "" or (obj.number or ""))
	f.baseSize = d
	f:Show()
end

function Play:SpawnObject(o)
	local level = self.pf:GetFrameLevel() + 10 + (800 - (o.index % 800))
	if o.kind == "circle" or o.kind == "slider" then
		local f = self.circlePool:Acquire()
		f:SetFrameLevel(level)
		self:SetupCircle(f, o, false)
		self:Place(f, o.x, o.y)
		o.head = f
	end
	if o.kind == "slider" then
		self:BuildSliderBody(o, self.pf:GetFrameLevel() + 2)
		local tail = self.circlePool:Acquire()
		tail:SetFrameLevel(level - 1)
		self:SetupCircle(tail, o, true)
		tail.body:SetSize(tail.baseSize * CIRCLE_TEX_SCALE * 0.9, tail.baseSize * CIRCLE_TEX_SCALE * 0.9)
		local ex, ey = Beatmap.PathAt(o.path, o.path.length)
		self:Place(tail, ex, ey)
		o.tail = tail
		if o.slides > 1 then
			tail.arrow:SetSize(tail.baseSize * 0.6, tail.baseSize * 0.6)
			local px, py = Beatmap.PathAt(o.path, max(0, o.path.length - 8))
			tail.arrow:SetRotation(atan2(-(py - ey), px - ex))
			tail.arrow:Show()
		end
		o.partsHit, o.parts, o.nextPart = 0, 1 + o.slides, 1
	elseif o.kind == "spinner" then
		o.rotation, o.lastAngle = 0, nil
		local seconds = (o.endTime - o.t) / 1000
		local od = select(2, Beatmap.ModdedStats(self.map, self.mods))
		o.required = max(1, seconds * (1.5 + 0.12 * od))
		o.bonusSpins = 0
	end
	self.active[#self.active + 1] = o
end

function Play:BuildSliderBody(o, level)
	local body = self.bodyPool:Acquire()
	body:SetFrameLevel(level)
	local d = self.radius * 2 * self.s
	local c = o.color
	local step = max(3, self.radius * 0.22)
	local count = floor(o.path.length / step) + 1
	local n = 0
	for i = 0, count do
		local dist = min(i * step, o.path.length)
		local x, y = Beatmap.PathAt(o.path, dist)
		n = n + 1
		local b, f = body.border[n], body.fill[n]
		if not b then
			b = body:CreateTexture(nil, "BACKGROUND")
			b:SetTexture(BC.MEDIA .. "dot")
			f = body:CreateTexture(nil, "BORDER")
			f:SetTexture(BC.MEDIA .. "dot")
			body.border[n], body.fill[n] = b, f
		end
		b:SetSize(d * DOT_TEX_SCALE, d * DOT_TEX_SCALE)
		b:SetVertexColor(1, 1, 1)
		f:SetSize(d * DOT_TEX_SCALE * 0.86, d * DOT_TEX_SCALE * 0.86)
		f:SetVertexColor(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3)
		b:ClearAllPoints()
		b:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
		f:ClearAllPoints()
		f:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
		b:Show()
		f:Show()
	end
	body.used = n
	body:Show()
	o.body = body
end

function Play:Despawn(o)
	if o.head then
		self.circlePool:Release(o.head)
		o.head = nil
	end
	if o.tail then
		self.circlePool:Release(o.tail)
		o.tail = nil
	end
	if o.body then
		self.bodyPool:Release(o.body)
		o.body = nil
	end
	o.gone = true
end

function Play:Burst(value, x, y)
	if value == 300 then
		return -- keep the screen clean; only show imperfect hits
	end
	local fs = self.burstPool:Acquire()
	local c = U.JUDGE_COLORS[value]
	fs:SetText(value == 0 and "X" or tostring(value))
	fs:SetTextColor(c[1], c[2], c[3])
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
	fs:Show()
	self.bursts[#self.bursts + 1] = { fs = fs, t = GetTime(), x = x, y = y }
end

function Play:AddError(err)
	local eb = self.errorBar
	local tick = eb.ticks[eb.nextTick]
	eb.nextTick = eb.nextTick % #eb.ticks + 1
	tick:ClearAllPoints()
	tick:SetPoint("CENTER", eb, "CENTER", err * 0.6, 0)
	local a = abs(err)
	local c = a <= self.w300 and U.JUDGE_COLORS[300] or a <= self.w100 and U.JUDGE_COLORS[100] or U.JUDGE_COLORS[50]
	tick:SetColorTexture(c[1], c[2], c[3], 1)
	tick.at = GetTime()
	tick:Show()
	local mean = self.tally:ErrorStats()
	eb.mean:ClearAllPoints()
	eb.mean:SetPoint("BOTTOM", eb, "CENTER", mean * 0.6, 8)
	eb.mean:Show()
end

local HITSOUNDS = {
	tick = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,
	soft = SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115,
}

function Play:Hitsound()
	local id = HITSOUNDS[BC.db.hitsound]
	if id then
		Compat.PlayKit(id, BC.db.channel)
	end
end

--------------------------------------------------------------------------
-- Judging
--------------------------------------------------------------------------

function Play:ChangeHP(delta)
	self.tally.hp = U.Clamp(self.tally.hp + delta, 0, 1)
end

function Play:JudgeCircle(o, value, err)
	o.judged = true
	o.result = value
	o.judgedAt = GetTime()
	self.tally:Judge(value, value > 0 and err or nil)
	if value > 0 then
		self:AddError(err)
		self:Hitsound()
		self:ChangeHP(value == 300 and 0.05 or value == 100 and 0.025 or 0.005)
	else
		self:ChangeHP(-(0.04 + self.hpStat * 0.012))
	end
	self:Burst(value, o.x, o.y)
end

function Play:SliderHead(o, hit, err)
	o.headDone = true
	o.headAt = GetTime()
	if hit then
		o.headErr = err
		o.partsHit = o.partsHit + 1
		self.tally:AddCombo()
		self.tally:Bonus(30)
		self:AddError(err)
		self:Hitsound()
		self:ChangeHP(0.02)
	else
		self.tally:Break()
		self:ChangeHP(-0.02)
	end
end

function Play:SliderFinal(o)
	o.judged = true
	o.judgedAt = GetTime()
	local ratio = o.partsHit / o.parts
	local value = ratio >= 1 and 300 or ratio >= 0.5 and 100 or ratio > 0 and 50 or 0
	o.result = value
	self.tally:Judge(value, nil, true)
	if value > 0 then
		self:ChangeHP(value == 300 and 0.04 or 0.015)
	else
		self:ChangeHP(-(0.04 + self.hpStat * 0.012))
	end
	self:Burst(value, o.endX, o.endY)
end

function Play:SpinnerFinal(o)
	o.judged = true
	o.judgedAt = GetTime()
	local p = o.rotation / (2 * PI) / o.required
	local value = p >= 1 and 300 or p >= 0.75 and 100 or p >= 0.25 and 50 or 0
	o.result = value
	self.tally:Judge(value)
	if value > 0 then
		self:ChangeHP(0.05)
	end
	self:Burst(value, 256, 192)
end

function Play:AnyHeld()
	for _, v in pairs(self.held) do
		if v then
			return true
		end
	end
	return false
end

-- A key or mouse button went down.
function Play:Press(t)
	local cx, cy = self:CursorOsu()
	local r = self.radius
	for _, o in ipairs(self.active) do
		local hittable = (o.kind == "circle" and not o.judged) or (o.kind == "slider" and not o.headDone)
		if hittable then
			local err = t - o.t
			if err < -self.w50 then
				-- too early for the first open object: ignore (osu! "notelock")
				if abs(err) < 400 and o.head then
					o.shakeAt = GetTime()
				end
				return
			end
			local dx, dy = cx - o.x, cy - o.y
			if dx * dx + dy * dy <= r * r then
				local a = abs(err)
				local value = a <= self.w300 and 300 or a <= self.w100 and 100 or 50
				if o.kind == "circle" then
					self:JudgeCircle(o, value, err)
				else
					self:SliderHead(o, true, err)
				end
			end
			return
		end
	end
end

--------------------------------------------------------------------------
-- Frame update
--------------------------------------------------------------------------

function Play:UpdateObjects(t, now)
	local held = self:AnyHeld()
	local cx, cy = self:CursorOsu()
	local followR = self.radius * 2.4
	local ballShown, spinnerShown = false, false

	for i = #self.active, 1, -1 do
		local o = self.active[i]
		local appearAt = o.t - self.preempt
		local fadeIn = U.Clamp((t - appearAt) / self.fadeIn, 0, 1)
		local alpha = fadeIn
		if self.mods.hd and o.kind ~= "spinner" then
			local fadeOutStart = appearAt + self.preempt * 0.4
			local fadeOutEnd = appearAt + self.preempt * 0.7
			if t > fadeOutStart then
				alpha = 1 - U.Clamp((t - fadeOutStart) / (fadeOutEnd - fadeOutStart), 0, 1)
			end
		end

		if o.kind == "circle" then
			if not o.judged and t > o.t + self.w50 then
				self:JudgeCircle(o, 0, nil)
			end
			local f = o.head
			if o.judged then
				local age = now - o.judgedAt
				if age > 0.18 or o.result == 0 then
					self:Despawn(o)
				else
					local grow = 1 + age / 0.18 * 0.4
					f.body:SetSize(f.baseSize * CIRCLE_TEX_SCALE * grow, f.baseSize * CIRCLE_TEX_SCALE * grow)
					f.overlay:SetSize(f.baseSize * CIRCLE_TEX_SCALE * grow, f.baseSize * CIRCLE_TEX_SCALE * grow)
					f.approach:Hide()
					f.number:SetText("")
					f:SetAlpha(1 - age / 0.18)
				end
			else
				self:UpdateApproach(f, o, t, alpha)
			end
		elseif o.kind == "slider" then
			-- head
			if not o.headDone and t > o.t + self.w50 then
				self:SliderHead(o, false)
			end
			local head = o.head
			if head then
				if o.headDone then
					local age = now - o.headAt
					if age > 0.15 then
						self.circlePool:Release(head)
						o.head = nil
					else
						head.approach:Hide()
						head:SetAlpha(1 - age / 0.15)
					end
				else
					self:UpdateApproach(head, o, t, alpha)
				end
			end
			if o.body then
				o.body:SetAlpha(alpha * 0.9)
				o.tail:SetAlpha(alpha)
			end
			-- ball and checkpoints
			if t >= o.t and not o.judged then
				local bx, by = Beatmap.SliderBall(o, t)
				local dx, dy = cx - bx, cy - by
				local tracking = held and (dx * dx + dy * dy <= followR * followR)
				while o.nextPart <= o.slides and t >= o.t + o.span * o.nextPart do
					if tracking then
						o.partsHit = o.partsHit + 1
						self.tally:AddCombo()
						self.tally:Bonus(30)
						self:Hitsound()
						self:ChangeHP(0.02)
					else
						self.tally:Break()
						self:ChangeHP(-0.02)
					end
					o.nextPart = o.nextPart + 1
					-- the tail shows a reverse arrow while a reverse at the tail is
					-- still ahead (reverses at the tail happen on odd parts)
					local nextOdd = o.nextPart % 2 == 1 and o.nextPart or o.nextPart + 1
					if o.tail and nextOdd >= o.slides then
						o.tail.arrow:Hide()
					end
				end
				if o.nextPart > o.slides then
					self:SliderFinal(o)
				else
					ballShown = true
					self:Place(self.ball, bx, by)
					local d = self.radius * 2 * self.s
					self.ball.tex:SetSize(d * CIRCLE_TEX_SCALE * 0.95, d * CIRCLE_TEX_SCALE * 0.95)
					local c = o.color
					self.ball.tex:SetVertexColor(min(1, c[1] + 0.35), min(1, c[2] + 0.35), min(1, c[3] + 0.35))
					local fd = tracking and d * 2.4 or d * 1.2
					self.ball.follow:SetSize(fd * CIRCLE_TEX_SCALE, fd * CIRCLE_TEX_SCALE)
					self.ball.follow:SetAlpha(tracking and 0.9 or 0)
				end
			end
			if o.judged then
				local age = now - o.judgedAt
				if age > 0.2 then
					self:Despawn(o)
				elseif o.body then
					o.body:SetAlpha((1 - age / 0.2) * 0.9)
					o.tail:SetAlpha(1 - age / 0.2)
				end
			end
		elseif o.kind == "spinner" then
			if t >= o.t - 300 and not o.judged then
				spinnerShown = true
				self:UpdateSpinner(o, t, held, cx, cy)
			end
			if not o.judged and t > o.endTime then
				self:SpinnerFinal(o)
			end
			if o.judged then
				o.gone = true
			end
		end

		if o.gone then
			table.remove(self.active, i)
		end
	end
	self.ball:SetShown(ballShown)
	if not spinnerShown then
		self.spinner:Hide()
	end
end

function Play:UpdateApproach(f, o, t, alpha)
	f:SetAlpha(alpha)
	local p = U.Clamp((o.t - t) / self.preempt, 0, 1)
	local size = f.baseSize * CIRCLE_TEX_SCALE * (1 + 3 * p)
	f.approach:SetSize(size, size)
	f.approach:SetAlpha(min(1, alpha * 1.2))
	if o.shakeAt then
		local age = GetTime() - o.shakeAt
		if age < 0.2 then
			local dx = math.sin(age * 80) * 4
			f:ClearAllPoints()
			f:SetPoint("CENTER", self.pf, "TOPLEFT", o.x * self.s + dx, -o.y * self.s)
		else
			o.shakeAt = nil
			self:Place(f, o.x, o.y)
		end
	end
end

function Play:UpdateSpinner(o, t, held, cx, cy)
	local sp = self.spinner
	if not sp:IsShown() then
		sp:Show()
		sp.bonus:SetText("")
	end
	local size = 384 * self.s * 0.85
	sp.ring:SetSize(size, size)
	local progress = U.Clamp(o.rotation / (2 * PI) / o.required, 0, 1)
	sp.progress:SetSize(size * progress, size * progress)
	sp:SetAlpha(t < o.t and 0.5 or 1)
	if t >= o.t and held then
		local dx, dy = cx - 256, cy - 192
		if dx * dx + dy * dy > 100 then
			local ang = atan2(dy, dx)
			if o.lastAngle then
				local delta = ang - o.lastAngle
				if delta > PI then
					delta = delta - 2 * PI
				elseif delta < -PI then
					delta = delta + 2 * PI
				end
				delta = min(abs(delta), 0.8)
				local before = floor(o.rotation / (2 * PI))
				o.rotation = o.rotation + delta
				local after = floor(o.rotation / (2 * PI))
				if after > before and after > o.required then
					o.bonusSpins = o.bonusSpins + 1
					self.tally:Bonus(1000)
					sp.bonus:SetText("+" .. (o.bonusSpins * 1000))
				end
			end
			o.lastAngle = ang
		end
	else
		o.lastAngle = nil
	end
	local now = GetTime()
	o.rpmSamples = o.rpmSamples or {}
	table.insert(o.rpmSamples, { now, o.rotation })
	while #o.rpmSamples > 2 and now - o.rpmSamples[1][1] > 0.5 do
		table.remove(o.rpmSamples, 1)
	end
	local first = o.rpmSamples[1]
	local span = now - first[1]
	local rpm = span > 0 and (o.rotation - first[2]) / (2 * PI) / span * 60 or 0
	sp.rpm:SetText(floor(rpm) .. " rpm")
	sp.text:SetText(progress >= 1 and "CLEAR!" or "SPIN!")
end

function Play:InBreak(t)
	for _, b in ipairs(self.bm.breaks) do
		if t >= b.s and t <= b.e then
			return b
		end
	end
end

function Play:UpdateCursor(now)
	local _, _, x, y = self:CursorOsu()
	self.cursor:ClearAllPoints()
	self.cursor:SetPoint("CENTER", self.screen, "BOTTOMLEFT", x, y)
	local pos = self.trailPos
	if BC.db.game.trail then
		table.insert(pos, 1, { x, y })
		if #pos > #self.trail then
			pos[#pos] = nil
		end
		for i, tex in ipairs(self.trail) do
			local p = pos[i]
			if p then
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", self.screen, "BOTTOMLEFT", p[1], p[2])
				tex:SetAlpha(0.5 * (1 - i / #self.trail))
				tex:Show()
			else
				tex:Hide()
			end
		end
	else
		for _, tex in ipairs(self.trail) do
			tex:Hide()
		end
	end
end

function Play:UpdateHUD(t, now)
	local tally = self.tally
	self.scoreText:SetText(string.format("%08d", tally.score))
	self.accText:SetText(U.FormatAcc(tally:Accuracy()))
	self.comboText:SetText(tally.combo > 0 and (tally.combo .. "x") or "")
	self.hpFill:SetWidth(max(1, self.hpWidth * tally.hp))
	local total = max(1, self.bm.lastTime - self.bm.firstTime)
	self.progFill:SetWidth(max(1, self.progWidth * U.Clamp((t - self.bm.firstTime) / total, 0, 1)))

	for i, tex in ipairs(self.errorBar.ticks) do
		if tex:IsShown() then
			local age = now - (tex.at or 0)
			if age > 3 then
				tex:Hide()
			else
				tex:SetAlpha(1 - age / 3)
			end
		end
	end

	local b = self:InBreak(t)
	if b then
		self.breakText:SetText(string.format("Break  %d", math.ceil((b.e - t) / 1000)))
	else
		self.breakText:SetText("")
	end
	local introAge = now - self.startedAt
	self.introText:SetAlpha(introAge < 2.5 and 1 or max(0, 1 - (introAge - 2.5)))

	for i = #self.bursts, 1, -1 do
		local burst = self.bursts[i]
		local age = now - burst.t
		if age > 0.5 then
			self.burstPool:Release(burst.fs)
			table.remove(self.bursts, i)
		else
			burst.fs:SetAlpha(1 - age / 0.5)
			burst.fs:ClearAllPoints()
			burst.fs:SetPoint("CENTER", self.pf, "TOPLEFT", burst.x * self.s, -burst.y * self.s + age * 30)
		end
	end
end


function Play:OnUpdate()
	local now = GetTime()
	self:UpdateCursor(now)
	if not self.playing then
		return
	end
	local t = Clock:Time()
	local dt = self.lastUpdate and (now - self.lastUpdate) or 0
	self.lastUpdate = now

	while self.objs[self.spawnIndex] and self.objs[self.spawnIndex].t - self.preempt <= t do
		self:SpawnObject(self.objs[self.spawnIndex])
		self.spawnIndex = self.spawnIndex + 1
	end
	self:UpdateObjects(t, now)

	-- health drain between the first and last object, outside breaks
	if t > self.bm.firstTime and t < self.bm.lastTime and not self:InBreak(t) then
		self:ChangeHP(-(0.012 + self.hpStat * 0.0045) * dt)
	end
	if self.tally.hp <= 0 and not self.mods.nf then
		self:Fail()
		return
	end

	self:UpdateHUD(t, now)

	if self.spawnIndex > #self.objs and #self.active == 0 and t > self.bm.lastTime then
		self:Finish()
	end
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

function Play:InputDown(slot)
	if self.held[slot] then
		return
	end
	self.held[slot] = true
	self.keyCounts[slot] = self.keyCounts[slot] + 1
	local k = self.keyOverlay.keys[slot]
	k.count:SetText(self.keyCounts[slot])
	k.bg:SetColorTexture(ACCENT[1] * 0.8, ACCENT[2] * 0.8, ACCENT[3] * 0.8, 0.95)
	if self.playing then
		self:Press(Clock:Time())
	end
end

function Play:InputUp(slot)
	self.held[slot] = false
	self.keyOverlay.keys[slot].bg:SetColorTexture(0.1, 0.1, 0.14, 0.85)
end

function Play:AdjustOffset(delta)
	local key = self.map.key
	local cur = (BC.db.mapOffsets[key] or 0) + delta
	BC.db.mapOffsets[key] = cur ~= 0 and cur or nil
	self.offset = BC.db.offset + cur
	Clock:SetOffset(self.offset)
	Game:Toast(string.format("Local offset: %+d ms", cur))
end

function Play:OnKey(key, down)
	local keys = BC.db.game.keys
	if key == keys[1] then
		if down then
			self:InputDown(1)
		else
			self:InputUp(1)
		end
		return
	elseif key == keys[2] then
		if down then
			self:InputDown(2)
		else
			self:InputUp(2)
		end
		return
	end
	if not down then
		return
	end
	if key == "ESCAPE" then
		self:Quit()
	elseif key == "`" then
		self:Retry()
	elseif key == "-" then
		self:AdjustOffset(-5)
	elseif key == "=" then
		self:AdjustOffset(5)
	end
end

function Play:OnMouse(button, down)
	local slot = button == "LeftButton" and 3 or button == "RightButton" and 4
	if not slot then
		return
	end
	if down then
		self:InputDown(slot)
	else
		self:InputUp(slot)
	end
end
