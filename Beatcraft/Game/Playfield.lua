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
local floor, abs, sqrt, atan2, min, max, sin = math.floor, math.abs, math.sqrt, math.atan2, math.min, math.max, math.sin
local PI = math.pi

local CIRCLE_TEX_SCALE = 128 / 120
local DOT_TEX_SCALE = 64 / 60
local FOLLOW_TEX_SCALE = 128 / 122
local CURSOR_COLOR = { 1, 0.82, 0.38 }
local BG_MODES = { "song", "world", "blend" }
local BG_LABELS = { song = "Song background", world = "See-through (game world)", blend = "Song background over game world" }

function Game:Create()
	if self.root then
		return true
	end
	if InCombatLockdown() then
		return false
	end
	local root = CreateFrame("Frame", "BeatcraftGame", UIParent)
	root:SetAllPoints(UIParent)
	root:SetAlpha(BC.db.game.interfaceOpacity or 0.95)
	root:SetFrameStrata("FULLSCREEN_DIALOG")
	root:EnableMouse(true)
	root:EnableMouseWheel(true)
	root:EnableKeyboard(true)
	root:SetPropagateKeyboardInput(false)
	root:Hide()
	self.root = root

	root.black = W.Solid(root, "BACKGROUND", 0, 0, 0, 1, -8)
	root.black:SetAllPoints()
	root.bgImage = root:CreateTexture(nil, "BACKGROUND", nil, -6)
	root.bgImage:SetAllPoints()
	root.videoTex = {}
	for i = 1, 2 do
		local v = root:CreateTexture(nil, "BACKGROUND", nil, -4)
		v:SetAllPoints()
		v:Hide()
		root.videoTex[i] = v
	end
	root.dim = W.Solid(root, "BACKGROUND", 0, 0, 0, 1, 2)
	root.dim:SetAllPoints()
	root.dim:SetAlpha(0.75)
	root.flash = W.Solid(root, "BACKGROUND", 1, 1, 1, 1, 3)
	root.flash:SetAllPoints()
	root.flash:SetAlpha(0)
	root.flash:SetBlendMode("ADD")
	self.dimCur, self.dimTarget, self.dimScale = 0.7, 0.7, 1

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
		if Game.screen and Game.screen.Leave then
			Game.screen:Leave()
		end
		Clock:Stop()
		Game.screen = nil
	end)

	local toastHolder = CreateFrame("Frame", nil, root)
	toastHolder:SetAllPoints()
	toastHolder:SetFrameLevel(root:GetFrameLevel() + 2000)
	root.toast = W.Text(toastHolder, 14, "", "OUTLINE")
	root.toast:SetPoint("TOP", 0, -60)
	root:SetScript("OnUpdate", function(_, elapsed)
		Game:OnUpdate(elapsed or 0)
	end)

	Play:Create(root)
	BC.SongSelect:Create(root)
	BC.Results:Create(root)
	return true
end

function Game:OnUpdate(elapsed)
	local root = self.root
	if self.toastAt then
		local age = GetTime() - self.toastAt
		root.toast:SetAlpha(age < 2 and 1 or max(0, 3 - age))
	end
	local target = self.dimTarget * self.dimScale
	self.dimCur = self.dimCur + (target - self.dimCur) * min(1, elapsed * 6)
	root.dim:SetAlpha(U.Clamp(self.dimCur, 0, 1))
end

function Game:FitBackground(tex, aspect)
	local screenAspect = self.root:GetWidth() / max(1, self.root:GetHeight())
	aspect = aspect or 2
	if aspect > screenAspect then
		local crop = (1 - screenAspect / aspect) / 2
		tex:SetTexCoord(crop, 1 - crop, 0, 1)
	else
		local crop = (1 - aspect / screenAspect) / 2
		tex:SetTexCoord(0, 1, crop, 1 - crop)
	end
end

function Game:Toast(text)
	self.root.toast:SetText(text)
	self.root.toast:SetAlpha(1)
	self.toastAt = GetTime()
end

function Game:ApplyBackground(path, context)
	local root, g = self.root, BC.db.game
	self.bgPath, self.bgContext = path, context
	local song = self.screen and self.screen.song
	self:FitBackground(root.bgImage, song and song.bgAspect)
	local mode = g.bgMode
	local dim = g.dim
	if context == "select" then
		dim = dim * 0.75
	end
	if mode == "world" then
		root.black:Hide()
		root.bgImage:Hide()
		self.dimTarget = g.worldDim
	elseif mode == "blend" then
		root.black:Hide()
		self.dimTarget = g.worldDim * 0.7
		if path then
			root.bgImage:SetTexture(path)
			root.bgImage:SetAlpha(g.bgOpacity or 0.85)
			root.bgImage:Show()
		else
			root.bgImage:Hide()
		end
	else
		root.black:Show()
		self.dimTarget = dim
		if path then
			root.bgImage:SetTexture(path)
			root.bgImage:SetAlpha(1)
			root.bgImage:Show()
		else
			root.bgImage:Hide()
		end
	end
	root.flash:SetAlpha(0)
	if self.videoVisible and mode ~= "world" then root.bgImage:Hide() end
	if context == "play" then
		self.dimCur = self.dimTarget
		root.dim:SetAlpha(self.dimCur)
	end
end

function Game:CycleBackground()
	local g = BC.db.game
	local idx = 1
	for i, m in ipairs(BG_MODES) do
		if m == g.bgMode then
			idx = i
		end
	end
	g.bgMode = BG_MODES[idx % #BG_MODES + 1]
	self:ApplyBackground(self.bgPath, self.bgContext)
	self:Toast("Background: " .. BG_LABELS[g.bgMode] .. "   (Tab to change)")
end

function Game:StartVideo(video)
	self.video = BC.db.game.video and video or nil
	self.videoVisible = false
	self.videoSheetOf = {}
	for _, tex in ipairs(self.root.videoTex) do
		tex:Hide()
	end
end

function Game:StopVideo()
	self.video = nil
	self.videoVisible = false
	for _, tex in ipairs(self.root.videoTex) do
		tex:Hide()
	end
	self.root.bgImage:SetShown(self.bgPath ~= nil and BC.db.game.bgMode ~= "world")
end

function Game:UpdateVideo(t)
	local v = self.video
	local texs = self.root.videoTex
	local mode = BC.db.game.bgMode
	local frame = v and floor((t - v.offset) * v.fps / 1000) or -1
	if not v or mode == "world" or frame < 0 or frame >= v.frames then
		self.videoVisible = false
		self.root.bgImage:SetShown(self.bgPath ~= nil and mode ~= "world")
		texs[1]:Hide()
		texs[2]:Hide()
		return
	end
	local per = v.cols * v.rows
	local sheet = floor(frame / per) + 1
	if sheet > v.sheets then
		self.videoVisible = false
		self.root.bgImage:SetShown(self.bgPath ~= nil and mode ~= "world")
		texs[1]:Hide()
		texs[2]:Hide()
		return
	end
	local of = self.videoSheetOf
	local cur = of[2] == sheet and 2 or 1
	if of[cur] ~= sheet then
		texs[cur]:SetTexture(v.path .. string.format("%03d", sheet))
		of[cur] = sheet
	end
	local tex, other = texs[cur], texs[3 - cur]
	if sheet < v.sheets and of[3 - cur] ~= sheet + 1 then
		other:SetTexture(v.path .. string.format("%03d", sheet + 1))
		of[3 - cur] = sheet + 1
	end
	other:SetAlpha(0)
	other:Show()
	local i = frame % per
	local u0 = ((i % v.cols) * v.fw + 0.5) / v.size
	local v0 = (floor(i / v.cols) * v.fh + 0.5) / v.size
	local screenAspect = self.root:GetWidth() / max(1, self.root:GetHeight())
	local frameAspect = v.fw / v.fh
	local cropX = frameAspect > screenAspect and (1 - screenAspect / frameAspect) / 2 or 0
	local cropY = frameAspect < screenAspect and (1 - frameAspect / screenAspect) / 2 or 0
	local du, dv = (v.fw - 1) / v.size, (v.fh - 1) / v.size
	tex:SetTexCoord(u0 + du * cropX, u0 + du * (1 - cropX), v0 + dv * cropY, v0 + dv * (1 - cropY))
	tex:SetAlpha(mode == "blend" and (BC.db.game.bgOpacity or 0.85) or 1)
	self.videoVisible = true
	self.root.bgImage:Hide()
	tex:Show()
end

function Game:SetFlash(a)
	self.root.flash:SetAlpha(BC.db.game.bgMode ~= "world" and BC.db.game.kiaiFlash and a or 0)
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
	if BC.Options.frame and BC.Options.frame:IsShown() then
		if down and key == "ESCAPE" then BC.Options.frame:Hide() end
		return
	end
	if self.screen == BC.SongSelect and BC.SongSelect.search:HasFocus() then return end
	if down and key == "PRINTSCREEN" then
		Screenshot()
		return
	end
	if down and key == "TAB" then
		self:CycleBackground()
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

function Game:Cursor()
	local x, y = GetCursorPosition()
	local scale = self.root:GetEffectiveScale()
	return x / scale, y / scale
end

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
	return f
end

local function createSliderBody(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f.border, f.fill, f.ticks = {}, {}, {}
	f.used, f.visible, f.tickCount = 0, 0, 0
	f.arrows = CreateFrame("Frame", nil, f)
	f.arrows:SetAllPoints()
	f.headArrow = f.arrows:CreateTexture(nil, "OVERLAY")
	f.headArrow:SetTexture(BC.MEDIA .. "arrow")
	f.tailArrow = f.arrows:CreateTexture(nil, "OVERLAY")
	f.tailArrow:SetTexture(BC.MEDIA .. "arrow")
	return f
end

local function createBurst(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(1, 1)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFont(W.NUMFONT, 30, "THICKOUTLINE")
	f.text:SetPoint("CENTER")
	return f
end

function Play:Create(root)
	local screen = CreateFrame("Frame", nil, root)
	screen:SetAllPoints()
	screen:Hide()
	self.screen = screen

	local pf = CreateFrame("Frame", nil, screen)
	self.pf = pf
	local L = pf:GetFrameLevel()

	self.circlePool = U.NewPool(function()
		return createCircle(pf)
	end, function(f)
		f:Hide()
		f:ClearAllPoints()
		f:SetAlpha(1)
	end)
	self.bodyPool = U.NewPool(function()
		local b = createSliderBody(pf)
		b:SetFrameLevel(L + 2)
		return b
	end, function(f)
		for i = 1, f.used do
			f.border[i]:Hide()
			f.fill[i]:Hide()
		end
		for i = 1, f.tickCount do
			f.ticks[i]:Hide()
		end
		f.headArrow:Hide()
		f.tailArrow:Hide()
		f.used, f.visible, f.tickCount = 0, 0, 0
		f:Hide()
	end)

	local fp = CreateFrame("Frame", nil, pf)
	fp:SetAllPoints()
	fp:SetFrameLevel(L + 3)
	self.fpPool = U.NewPool(function()
		local t = fp:CreateTexture(nil, "ARTWORK")
		t:SetTexture(BC.MEDIA .. "followpoint")
		return t
	end, function(t)
		t:Hide()
	end)

	local fx = CreateFrame("Frame", nil, pf)
	fx:SetAllPoints()
	fx:SetFrameLevel(L + 880)
	self.lightPool = U.NewPool(function()
		local t = fx:CreateTexture(nil, "ARTWORK")
		t:SetTexture(BC.MEDIA .. "glow")
		t:SetBlendMode("ADD")
		return t
	end, function(t)
		t:Hide()
	end)
	self.burstPool = U.NewPool(function()
		local b = createBurst(fx)
		b:SetFrameLevel(L + 890)
		return b
	end, function(b)
		b:Hide()
		b:ClearAllPoints()
		b:SetScale(1)
	end)

	local ball = CreateFrame("Frame", nil, pf)
	ball:SetSize(1, 1)
	ball:SetFrameLevel(L + 900)
	ball.follow = ball:CreateTexture(nil, "ARTWORK")
	ball.follow:SetTexture(BC.MEDIA .. "follow")
	ball.follow:SetPoint("CENTER")
	ball.tex = ball:CreateTexture(nil, "OVERLAY")
	ball.tex:SetTexture(BC.MEDIA .. "ball")
	ball.tex:SetPoint("CENTER")
	ball:Hide()
	self.ball = ball

	local sp = CreateFrame("Frame", nil, pf)
	sp:SetPoint("CENTER")
	sp:SetSize(1, 1)
	sp:SetFrameLevel(L + 950)
	sp.glow = sp:CreateTexture(nil, "BACKGROUND")
	sp.glow:SetTexture(BC.MEDIA .. "glow")
	sp.glow:SetBlendMode("ADD")
	sp.glow:SetPoint("CENTER")
	sp.disc = sp:CreateTexture(nil, "ARTWORK")
	sp.disc:SetTexture(BC.MEDIA .. "spinner")
	sp.disc:SetPoint("CENTER")
	sp.approach = sp:CreateTexture(nil, "OVERLAY")
	sp.approach:SetTexture(BC.MEDIA .. "approach")
	sp.approach:SetPoint("CENTER")
	sp.text = W.Text(sp, 30, "SPIN!", "THICKOUTLINE")
	sp.text:SetPoint("CENTER", 0, 0)
	sp.rpm = W.Text(sp, 16, "", "OUTLINE")
	sp.bonus = W.Text(sp, 24, "", "THICKOUTLINE")
	sp.bonus:SetPoint("CENTER", 0, 60)
	sp.bonus:SetTextColor(1, 0.9, 0.4)
	sp:Hide()
	self.spinner = sp

	local cursorLayer = CreateFrame("Frame", nil, screen)
	cursorLayer:SetAllPoints()
	cursorLayer:SetFrameLevel(L + 1500)
	self.cursor = cursorLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	self.cursor:SetTexture(BC.MEDIA .. "cursor")
	self.cursor:SetVertexColor(CURSOR_COLOR[1], CURSOR_COLOR[2], CURSOR_COLOR[3])
	self.trail = {}
	for i = 1, 24 do
		local t = cursorLayer:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetTexture(BC.MEDIA .. "trail")
		t:SetBlendMode("ADD")
		t:SetVertexColor(CURSOR_COLOR[1], CURSOR_COLOR[2], CURSOR_COLOR[3])
		self.trail[i] = t
	end
	self.trailPos = {}
	self.cursorScale = 1

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
	self.scoreText:SetFont(W.NUMFONT, 38, "OUTLINE")
	self.scoreText:SetPoint("TOPRIGHT", -20, -10)
	self.accText = hud:CreateFontString(nil, "OVERLAY")
	self.accText:SetFont(W.NUMFONT, 22, "OUTLINE")
	self.accText:SetPoint("TOPRIGHT", self.scoreText, "BOTTOMRIGHT", 0, -2)

	local combo = CreateFrame("Frame", nil, hud)
	combo:SetSize(1, 1)
	self.comboFrame = combo
	self.comboText = combo:CreateFontString(nil, "OVERLAY")
	self.comboText:SetFont(W.NUMFONT, 48, "THICKOUTLINE")
	self.comboText:SetPoint("BOTTOMLEFT")

	local hpBg = W.Solid(hud, "ARTWORK", 0.05, 0.05, 0.08, 0.7)
	hpBg:SetPoint("TOPLEFT", 20, -18)
	hpBg:SetSize(400, 12)
	self.hpFill = W.Solid(hud, "OVERLAY", 1, 1, 1, 1)
	self.hpFill:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 2, -2)
	self.hpFill:SetHeight(8)
	self.hpWidth = 396
	self.hpGlow = hud:CreateTexture(nil, "OVERLAY", nil, 1)
	self.hpGlow:SetTexture(BC.MEDIA .. "glow")
	self.hpGlow:SetBlendMode("ADD")
	self.hpGlow:SetSize(40, 40)

	local progBg = W.Solid(hud, "ARTWORK", 1, 1, 1, 0.12)
	progBg:SetPoint("TOPRIGHT", self.accText, "BOTTOMRIGHT", 0, -6)
	progBg:SetSize(170, 4)
	self.modsText = W.Text(hud, 18, "", "THICKOUTLINE")
	self.modsText:SetPoint("TOPRIGHT", progBg, "BOTTOMRIGHT", 0, -8)
	self.modsText:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	self.progFill = W.Solid(hud, "OVERLAY", 1, 1, 1, 0.8)
	self.progFill:SetPoint("TOPLEFT", progBg, "TOPLEFT")
	self.progFill:SetHeight(4)
	self.progWidth = 170

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

	self.breakText = W.Text(hud, 30, "", "THICKOUTLINE")
	self.breakText:SetPoint("CENTER", 0, 140)
	self.hint = W.Text(hud, 11, "Esc pause   ` retry   - / = offset   Tab background", "OUTLINE")
	self.hint:SetPoint("BOTTOMRIGHT", -16, 12)
	self.hint:SetTextColor(0.7, 0.7, 0.7)
	self.introText = W.Text(hud, 24, "", "THICKOUTLINE")
	self.introText:SetPoint("CENTER", 0, 170)

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

	local pause = CreateFrame("Frame", nil, screen)
	pause:SetAllPoints()
	pause:SetFrameLevel(self.pf:GetFrameLevel() + 1600)
	pause.bg = W.Solid(pause, "BACKGROUND", 0.02, 0.02, 0.04, 0.88)
	pause.bg:SetAllPoints()
	pause.title = W.Text(pause, 44, "PAUSED", "OUTLINE")
	pause.title:SetPoint("CENTER", 0, 90)
	pause.hint = W.Text(pause, 14, "Restart to keep music and notes in sync.", "OUTLINE")
	pause.hint:SetPoint("CENTER", 0, 44)
	pause.retry = W.Button(pause, "Restart  (Enter)", 180, 40, function() Play:Retry() end, true)
	pause.retry:SetPoint("CENTER", -100, -20)
	pause.back = W.Button(pause, "Song select  (Esc)", 180, 40, function() Play:Quit() end)
	pause.back:SetPoint("CENTER", 100, -20)
	pause:Hide()
	self.pauseOverlay = pause
end

function Play:Layout()
	local root = self.screen
	local s = min(root:GetHeight() * 0.8 / 384, root:GetWidth() * 0.9 / 512)
	self.s = s
	self.pf:SetSize(512 * s, 384 * s)
	self.pf:ClearAllPoints()
	self.pf:SetPoint("CENTER", root, "CENTER", 0, -root:GetHeight() * 0.02)
end

function Play:Enter(map, mods)
	self.map, self.mods = map, mods or {}
	self.song = map.song
	self.screen:Show()
	self:Layout()
	self:Start()
end

function Play:Leave()
	self.playing = false
	self.runId = (self.runId or 0) + 1
	self:Cleanup()
	if SetCursor then
		pcall(SetCursor, nil)
	end
	Clock:Stop()
	Game.dimScale = 1
	Game.root.flash:SetAlpha(0)
	Game:StopVideo()
	self.screen:Hide()
end

function Play:Cleanup()
	self.circlePool:ReleaseAll()
	self.bodyPool:ReleaseAll()
	self.burstPool:ReleaseAll()
	self.lightPool:ReleaseAll()
	self.fpPool:ReleaseAll()
	self.ball:Hide()
	self.spinner:Hide()
	self.failOverlay:Hide()
	if self.pauseOverlay then self.pauseOverlay:Hide() end
	self.active = {}
	self.bursts = {}
	self.lights = {}
end

function Play:BuildFollowPoints()
	local pairs_ = {}
	local r = self.radius
	for i = 1, #self.objs - 1 do
		local a, b = self.objs[i], self.objs[i + 1]
		if a.kind ~= "spinner" and b.kind ~= "spinner" and not b.newCombo then
			local x1, y1 = a.x, a.y
			if a.kind == "slider" then
				x1, y1 = a.endX, a.endY
			end
			local dx, dy = b.x - x1, b.y - y1
			local dist = sqrt(dx * dx + dy * dy)
			if dist > r * 2.6 and b.t - a.endTime < 2500 then
				pairs_[#pairs_ + 1] = {
					x1 = x1, y1 = y1, dx = dx / dist, dy = dy / dist, dist = dist,
					startT = a.endTime, endT = b.t, ang = atan2(-dy, dx),
				}
			end
		end
	end
	self.followPoints = pairs_
	self.fpIndex = 1
end

function Play:Start()
	self:Cleanup()
	self.runId = (self.runId or 0) + 1
	self.paused = false
	self.trailPos = {}
	self.cursorScale = 1
	self.cursorAt = nil
	local map, mods, song = self.map, self.mods, self.song
	local bm = Library:Parse(map, mods)
	if #bm.objects == 0 then
		self:Quit()
		Game:Toast("This difficulty has no playable objects. Re-import this beatmap.")
		return
	end
	self.bm = bm
	local ar, od, cs, hp = Beatmap.ModdedStats(map, mods)
	self.preempt = Beatmap.Preempt(ar)
	self.fadeIn = self.preempt * 0.4
	self.radius = Beatmap.Radius(cs)
	self.w300, self.w100, self.w50 = Scoring.Windows(od)
	self.hpStat = hp
	self.tally = Scoring.New(Scoring.ModMultiplier(mods))

	self.objs = {}
	for i, obj in ipairs(bm.objects) do
		self.objs[i] = setmetatable({ index = i }, { __index = obj })
	end
	self:BuildFollowPoints()
	self.spawnIndex = 1
	self.held = {}
	self.keyCounts = { 0, 0, 0, 0 }
	self.failed = false
	self.finished = false
	self.lastUpdate = nil
	self.shownScore, self.shownHP = 0, 1
	self.lastCombo, self.comboPopAt = 0, 0

	for _, k in ipairs(self.keyOverlay.keys) do
		k.count:SetText("0")
		k.bg:SetColorTexture(0.1, 0.1, 0.14, 0.85)
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
	self.modsText:SetText((Scoring.ModString(mods):gsub(",", " ")))

	Game:ApplyBackground(song.bg, "play")
	Game:StartVideo(song.video)
	Game.dimScale = 1

	local leadMs = max(0, self.preempt + 800 - bm.firstTime, map.lead or 0)
	self.offset = BC.db.offset + (BC.db.mapOffsets[map.key] or 0)
	Clock:Play(song.audio, leadMs / 1000, self.offset, function()
		self:Fail()
		Game:Toast("Could not play this song's audio. If you imported it while WoW was running, restart WoW.")
	end)
	self.introText:SetText((song.title or "") .. "  [" .. (map.version or "") .. "]")
	self.introText:SetAlpha(1)
	self.startedAt = GetTime()
	self.playing = not Clock.failed
	if SetCursor then pcall(SetCursor, nil) end
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
	if SetCursor then pcall(SetCursor, nil) end
end

function Play:Pause()
	if not self.playing then return end
	self.playing = false
	self.paused = true
	Clock:Stop()
	self.held = {}
	self.pauseOverlay:Show()
	if SetCursor then pcall(SetCursor, nil) end
end

function Play:Finish()
	self.finished = true
	self.playing = false
	local rank, rec = Scoring.Save(self.map.key, self.tally, self.mods)
	if rank == 1 then
		BC.Guild:SharePB(self.map, rec)
	end
	local runId = self.runId
	C_Timer.After(1.2, function()
		if Game.screen == Play and Play.finished and Play.runId == runId then
			Clock:Stop()
			Game:Show(BC.Results, self.map, self.tally, self.mods, rank)
		end
	end)
end

function Play:Place(f, x, y)
	f:ClearAllPoints()
	f:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
end

function Play:PlaceScaled(f, x, y, scale, dy)
	f:SetScale(scale)
	f:ClearAllPoints()
	f:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s / scale, (-y * self.s + (dy or 0)) / scale)
end

function Play:CursorOsu()
	local cx, cy = Game:Cursor()
	local left, top = self.pf:GetLeft(), self.pf:GetTop()
	if not left then
		return -1000, -1000, cx, cy
	end
	return (cx - left) / self.s, (top - cy) / self.s, cx, cy
end

function Play:SetCircleSize(f, grow)
	local size = f.baseSize * CIRCLE_TEX_SCALE * (grow or 1)
	f.body:SetSize(size, size)
	f.overlay:SetSize(size, size)
end

function Play:SetupCircle(f, obj, isTail)
	local d = self.radius * 2 * self.s
	local c = obj.color
	f.baseSize = d
	self:SetCircleSize(f, isTail and 0.9 or 1)
	f.body:SetVertexColor(c[1], c[2], c[3])
	f.approach:SetVertexColor(c[1], c[2], c[3])
	f.approach:SetShown(not isTail and not self.mods.hd)
	f.number:SetFont(W.NUMFONT, max(10, d * 0.45), "OUTLINE")
	f.number:SetText(isTail and "" or (obj.number or ""))
	f.number:Show()
	f:SetAlpha(0)
	f:Show()
end

function Play:SpawnObject(o)
	local level = self.pf:GetFrameLevel() + 10 + (#self.objs - o.index) % 800
	if o.kind == "circle" or o.kind == "slider" then
		local f = self.circlePool:Acquire()
		f:SetFrameLevel(level)
		self:SetupCircle(f, o, false)
		self:Place(f, o.x, o.y)
		o.head = f
	end
	if o.kind == "slider" then
		self:BuildSliderBody(o)
		o.body:SetFrameLevel(level - 2)
		o.body.arrows:SetFrameLevel(level + 1)
		local tail = self.circlePool:Acquire()
		tail:SetFrameLevel(level - 1)
		self:SetupCircle(tail, o, true)
		local ex, ey = Beatmap.PathAt(o.path, o.path.length)
		self:Place(tail, ex, ey)
		o.tail = tail
		o.partsHit, o.parts, o.nextPart, o.nextEvent = 0, 1 + #o.events, 1, 1
		o.followScale = 0
	elseif o.kind == "spinner" then
		o.rotation, o.lastAngle = 0, nil
		local seconds = (o.endTime - o.t) / 1000
		local od = select(2, Beatmap.ModdedStats(self.map, self.mods))
		o.required = max(1, seconds * (1.5 + 0.12 * od))
		o.bonusSpins = 0
	end
	self.active[#self.active + 1] = o
	for i, active in ipairs(self.active) do
		local layer = self.pf:GetFrameLevel() + 10 + min(200, #self.active - i) * 4
		if active.head then active.head:SetFrameLevel(layer + 2) end
		if active.tail then active.tail:SetFrameLevel(layer + 1) end
		if active.body then
			active.body:SetFrameLevel(layer)
			active.body.arrows:SetFrameLevel(layer + 3)
		end
	end
end

function Play:BuildSliderBody(o)
	local body = self.bodyPool:Acquire()
	local s = self.s
	local d = self.radius * 2 * s
	local c = o.color
	local step = max(2, self.radius * 0.12, o.path.length / 640)
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
		f:SetSize(d * DOT_TEX_SCALE * 0.9, d * DOT_TEX_SCALE * 0.9)
		f:SetVertexColor(c[1] * 0.22, c[2] * 0.22, c[3] * 0.22)
		b:ClearAllPoints()
		b:SetPoint("CENTER", self.pf, "TOPLEFT", x * s, -y * s)
		f:ClearAllPoints()
		f:SetPoint("CENTER", self.pf, "TOPLEFT", x * s, -y * s)
		b:Hide()
		f:Hide()
	end
	body.used, body.visible = n, 0

	local k = 0
	for _, dist in ipairs(o.tickDistances) do
			k = k + 1
			local t = body.ticks[k]
			if not t then
				t = body:CreateTexture(nil, "ARTWORK")
				t:SetTexture(BC.MEDIA .. "dot")
				body.ticks[k] = t
			end
			local x, y = Beatmap.PathAt(o.path, dist)
			t:SetSize(d * 0.18, d * 0.18)
			t:ClearAllPoints()
			t:SetPoint("CENTER", self.pf, "TOPLEFT", x * s, -y * s)
			t.dist = dist
			t:Hide()
	end
	body.tickCount = k

	local sx, sy = o.path.x[1], o.path.y[1]
	local ex, ey = Beatmap.PathAt(o.path, o.path.length)
	local px, py = Beatmap.PathAt(o.path, max(0, o.path.length - 8))
	local qx, qy = Beatmap.PathAt(o.path, min(o.path.length, 8))
	body.tailArrow:ClearAllPoints()
	body.tailArrow:SetPoint("CENTER", self.pf, "TOPLEFT", ex * s, -ey * s)
	body.tailArrow:SetRotation(atan2(-(py - ey), px - ex))
	body.headArrow:ClearAllPoints()
	body.headArrow:SetPoint("CENTER", self.pf, "TOPLEFT", sx * s, -sy * s)
	body.headArrow:SetRotation(atan2(-(qy - sy), qx - sx))
	body.arrowSize = d * 0.55
	body:SetAlpha(0)
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

function Play:Light(x, y, color)
	local t = self.lightPool:Acquire()
	t:SetVertexColor(color[1], color[2], color[3])
	t:ClearAllPoints()
	t:SetPoint("CENTER", self.pf, "TOPLEFT", x * self.s, -y * self.s)
	t:Show()
	self.lights[#self.lights + 1] = { tex = t, t = GetTime(), size = self.radius * 2 * self.s }
end

function Play:Burst(value, x, y)
	if value == 300 then
		return
	end
	local b = self.burstPool:Acquire()
	local c = U.JUDGE_COLORS[value]
	b.text:SetText(value == 0 and "X" or tostring(value))
	b.text:SetTextColor(c[1], c[2], c[3])
	b:Show()
	self.bursts[#self.bursts + 1] = { frame = b, t = GetTime(), x = x, y = y, miss = value == 0 }
	self:PlaceScaled(b, x, y, 1.6)
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
local SAMPLE_SETS = { "normal", "soft", "drum" }
local ADDITIONS = { { 2, "-hitwhistle" }, { 4, "-hitfinish" }, { 8, "-hitclap" } }

local function playSample(samples, name, idx)
	local path = (idx > 1 and samples[name .. idx]) or samples[name]
	if path == nil then
		return nil
	end
	if path ~= "" then
		Compat.PlayFile(path, BC.db.channel)
	end
	return true
end

function Play:Hitsound(o, kind, edge)
	local mode = BC.db.hitsound
	if mode == "none" then
		return
	end
	local samples = mode == "map" and self.song.samples
	if samples and o then
		local set = SAMPLE_SETS[o.set] or "normal"
		local idx = o.sidx or 0
		local hs = o.hs or 0
		local additionSet = set
		if edge and o.edgeSounds then
			hs = tonumber(o.edgeSounds[edge]) or hs
			local normal, addition = (o.edgeSets[edge] or ""):match("(%d+):(%d+)")
			set = SAMPLE_SETS[tonumber(normal)] or set
			additionSet = SAMPLE_SETS[tonumber(addition)] or set
		end
		if kind == "tick" then
			if playSample(samples, set .. "-slidertick", idx) then return end
		else
		local played = playSample(samples, set .. "-hitnormal", idx)
		for _, add in ipairs(ADDITIONS) do
			if floor(hs / add[1]) % 2 == 1 then
				played = playSample(samples, additionSet .. add[2], idx) or played
			end
		end
		if played then
			return
		end
		end
	end
	Compat.PlayKit(HITSOUNDS[mode] or HITSOUNDS.tick, BC.db.channel)
end

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
		self:Hitsound(o)
		self:ChangeHP(value == 300 and 0.05 or value == 100 and 0.025 or 0.005)
		self:Light(o.x, o.y, o.color)
	else
		self:ChangeHP(-(0.04 + self.hpStat * 0.012))
	end
	self:Burst(value, o.x, o.y)
end

function Play:SliderHead(o, hit, err)
	o.headDone = true
	o.headAt = GetTime()
	o.headHit = hit
	if hit then
		o.headErr = err
		o.partsHit = o.partsHit + 1
		self.tally:AddCombo()
		self.tally:Bonus(30)
		self.tally.errors[#self.tally.errors + 1] = err
		self:AddError(err)
		self:Hitsound(o, "head", 1)
		self:ChangeHP(0.02)
		self:Light(o.x, o.y, o.color)
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
		self:Light(o.endX, o.endY, o.color)
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
	else
		self:ChangeHP(-(0.04 + self.hpStat * 0.012))
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

function Play:Press(t)
	local cx, cy = self:CursorOsu()
	local r = self.radius
	for _, o in ipairs(self.active) do
		local hittable = (o.kind == "circle" and not o.judged) or (o.kind == "slider" and not o.headDone)
		if hittable then
			local err = t - o.t
			local dx, dy = cx - o.x, cy - o.y
			if dx * dx + dy * dy <= r * r then
				local a = abs(err)
				if err < -self.w50 then
					if a < 400 and o.head then o.shakeAt = GetTime() end
					return
				end
				if err > self.w50 then
					if o.kind == "circle" then self:JudgeCircle(o, 0) else self:SliderHead(o, false) end
					return
				end
				local value = a <= self.w300 and 300 or a <= self.w100 and 100 or 50
				if o.kind == "circle" then
					self:JudgeCircle(o, value, err)
				else
					self:SliderHead(o, true, err)
				end
				return
			end
		end
	end
end

local function explode(self, f, age, life)
	local p = age / life
	self:SetCircleSize(f, 1 + 0.45 * (1 - (1 - p) * (1 - p)))
	f.approach:Hide()
	f.number:Hide()
	f:SetAlpha(1 - p)
end

function Play:UpdateSliderVisuals(o, t, alpha, pulse)
	local body = o.body
	body:SetAlpha(alpha >= 0.99 and 1 or alpha * alpha)
	local snake = U.Clamp((t - (o.t - self.preempt)) / (self.preempt / 3), 0, 1)
	local want = max(1, math.ceil(snake * body.used))
	if want ~= body.visible then
		for i = 1, body.used do
			local on = i <= want
			body.border[i]:SetShown(on)
			body.fill[i]:SetShown(on)
		end
		body.visible = want
	end
	local ballDist = -1
	local span = min(o.slides - 1, max(0, floor((t - o.t) / o.span)))
	if t >= o.t then ballDist = U.Clamp((t - o.t) / o.span - span, 0, 1) * o.path.length end
	for i = 1, body.tickCount do
		local tick = body.ticks[i]
		local pending = span % 2 == 0 and tick.dist > ballDist or span % 2 == 1 and tick.dist < o.path.length - ballDist
		tick:SetShown(tick.dist <= snake * o.path.length and pending)
	end
	local tailRev, headRev = false, false
	for k = o.nextPart, o.slides - 1 do
		if k % 2 == 1 then
			tailRev = true
		else
			headRev = true
		end
	end
	local size = body.arrowSize * (1 + 0.18 * pulse)
	body.tailArrow:SetSize(size, size)
	body.headArrow:SetSize(size, size)
	body.tailArrow:SetShown(tailRev and snake >= 1)
	body.headArrow:SetShown(headRev and o.headDone)
	if o.tail and not o.judged then
		o.tail:SetAlpha(snake >= 1 and alpha or 0)
	end
end

function Play:UpdateObjects(t, now, pulse)
	local held = self:AnyHeld()
	local cx, cy = self:CursorOsu()
	local followR = self.radius * 2.4
	local ballShown, spinnerShown = false, false

	for _, o in ipairs(self.active) do
		local appearAt = o.t - self.preempt
		local alpha = U.Clamp((t - appearAt) / self.fadeIn, 0, 1)
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
				local life = o.result == 0 and 0.1 or 0.24
				if age > life then
					self:Despawn(o)
				elseif o.result == 0 then
					f:SetAlpha(alpha * (1 - age / life))
				else
					explode(self, f, age, life)
				end
			else
				self:UpdateApproach(f, o, t, alpha)
			end
		elseif o.kind == "slider" then
			if not o.headDone and t > o.t + self.w50 then
				self:SliderHead(o, false)
			end
			local head = o.head
			if head then
				if o.headDone then
					local age = now - o.headAt
					local life = o.headHit and 0.24 or 0.1
					if age > life then
						self.circlePool:Release(head)
						o.head = nil
					elseif o.headHit then
						explode(self, head, age, life)
					else
						head:SetAlpha(1 - age / life)
					end
				else
					self:UpdateApproach(head, o, t, alpha)
				end
			end
			if o.body and not o.judged then
				local bodyAlpha = alpha
				if self.mods.hd then
					local fadeStart = o.t - self.preempt * 0.6
					bodyAlpha = U.Clamp((t - appearAt) / self.fadeIn, 0, 1) * (1 - U.Clamp((t - fadeStart) / max(1, o.endTime - fadeStart), 0, 1))
				end
				self:UpdateSliderVisuals(o, t, bodyAlpha, pulse)
			end
			if t >= o.t and not o.judged then
				local bx, by = Beatmap.SliderBall(o, t)
				local dx, dy = cx - bx, cy - by
				local tracking = held and (dx * dx + dy * dy <= followR * followR)
				local event = o.events[o.nextEvent]
				while event and t >= event.t do
					local ex, ey = Beatmap.PathAt(o.path, event.dist)
					local tx, ty = cx, cy
					if o.trackAt and t > o.trackAt then
						local f = U.Clamp((event.t - o.trackAt) / (t - o.trackAt), 0, 1)
						tx = o.trackX + (cx - o.trackX) * f
						ty = o.trackY + (cy - o.trackY) * f
					end
					local caught = held and (tx - ex) ^ 2 + (ty - ey) ^ 2 <= followR * followR
					if caught then
						o.partsHit = o.partsHit + 1
						self.tally:AddCombo()
						self.tally:Bonus(event.kind == "tick" and 10 or 30)
						self:Hitsound(o, event.kind, event.edge)
						self:ChangeHP(0.02)
						if event.kind == "repeat" then self:Light(ex, ey, o.color) end
					else
						self.tally:Break()
						self:ChangeHP(-0.02)
					end
					if event.kind ~= "tick" then o.nextPart = o.nextPart + 1 end
					o.nextEvent = o.nextEvent + 1
					event = o.events[o.nextEvent]
				end
				o.trackX, o.trackY, o.trackAt = cx, cy, t
				if t >= o.endTime then
					self:SliderFinal(o)
				else
					ballShown = true
					local d = self.radius * 2 * self.s
					local c = o.color
					self:Place(self.ball, bx, by)
					self.ball.tex:SetSize(d * CIRCLE_TEX_SCALE * 0.9, d * CIRCLE_TEX_SCALE * 0.9)
					self.ball.tex:SetVertexColor(min(1, c[1] + 0.3), min(1, c[2] + 0.3), min(1, c[3] + 0.3))
					local target = tracking and 1 or 0
					o.followScale = o.followScale + (target - o.followScale) * min(1, (self.visualDt or 0.016) * 22)
					local fd = d * 2.4 * FOLLOW_TEX_SCALE * (0.5 + 0.5 * o.followScale)
					self.ball.follow:SetSize(fd, fd)
					self.ball.follow:SetAlpha(o.followScale)
				end
			end
			if o.judged then
				local age = now - o.judgedAt
				local life = 0.24
				if age > life then
					self:Despawn(o)
				else
					if o.body then
						o.body:SetAlpha((1 - age / life) ^ 2)
						o.body.tailArrow:Hide()
						o.body.headArrow:Hide()
					end
					if o.tail then
						if o.result > 0 then
							explode(self, o.tail, age, life)
						else
							o.tail:SetAlpha(1 - age / life)
						end
					end
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

	end
	for i = #self.active, 1, -1 do
		if self.active[i].gone then table.remove(self.active, i) end
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
	f.approach:SetAlpha(min(0.9, alpha))
	if o.shakeAt then
		local age = GetTime() - o.shakeAt
		if age < 0.2 then
			local dx = sin(age * 80) * 4
			f:ClearAllPoints()
			f:SetPoint("CENTER", self.pf, "TOPLEFT", o.x * self.s + dx, -o.y * self.s)
		else
			o.shakeAt = nil
			self:Place(f, o.x, o.y)
		end
	end
end

function Play:UpdateFollowPoints(t)
	self.fpPool:ReleaseAll()
	local list = self.followPoints
	while list[self.fpIndex] and list[self.fpIndex].endT + 300 < t do
		self.fpIndex = self.fpIndex + 1
	end
	local s = self.s
	local size = self.radius * s * 0.9
	local spacing = 32
	for i = self.fpIndex, #list do
		local p = list[i]
		if p.startT - self.preempt > t then
			break
		end
		local duration = p.endT - p.startT
		local dist = self.radius * 1.5
		while dist < p.dist - self.radius * 1.5 do
			local f = dist / p.dist
			local fadeInAt = p.startT + f * duration - self.preempt
			local fadeOutAt = p.startT + f * duration
			local a = U.Clamp((t - fadeInAt) / 300, 0, 1) * (1 - U.Clamp((t - fadeOutAt) / 250, 0, 1))
			if a > 0.01 then
				local tex = self.fpPool:Acquire()
				local x, y = p.x1 + p.dx * dist, p.y1 + p.dy * dist
				tex:SetSize(size, size)
				tex:SetRotation(p.ang)
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", self.pf, "TOPLEFT", x * s, -y * s)
				tex:SetAlpha(a * 0.7)
				tex:Show()
			end
			dist = dist + spacing
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
	local progress = U.Clamp(o.rotation / (2 * PI) / o.required, 0, 1)
	local timeLeft = U.Clamp(1 - (t - o.t) / (o.endTime - o.t), 0, 1)
	sp.disc:SetSize(size, size)
	sp.disc:SetRotation(-o.rotation)
	sp.disc:SetVertexColor(1, 1 - 0.6 * progress, 1 - 0.33 * progress)
	sp.approach:SetSize(size * timeLeft, size * timeLeft)
	sp.approach:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	sp.glow:SetSize(size * 1.2, size * 1.2)
	sp.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	sp.glow:SetAlpha(progress * 0.6)
	sp.rpm:ClearAllPoints()
	sp.rpm:SetPoint("CENTER", sp, "CENTER", 0, -size * 0.6)
	sp:SetAlpha(t < o.t and U.Clamp(1 - (o.t - t) / 300, 0, 1) or 1)
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
	local dt = self.cursorAt and now - self.cursorAt or 0.016
	self.cursorAt = now
	local target = self:AnyHeld() and 1.18 or 1
	self.cursorScale = self.cursorScale + (target - self.cursorScale) * min(1, dt * 24)
	local size = (BC.db.game.cursorSize or 32) * self.cursorScale
	self.cursor:SetShown(not self.paused and not self.failed)
	self.cursor:SetSize(size, size)
	self.cursor:ClearAllPoints()
	self.cursor:SetPoint("CENTER", self.screen, "BOTTOMLEFT", x, y)
	local pos = self.trailPos
	if BC.db.game.trail then
		local last = pos[1]
		if last then
			local dx, dy = x - last[1], y - last[2]
			local steps = min(#self.trail, floor(sqrt(dx * dx + dy * dy) / 5))
			for i = 1, steps do
				local f = i / steps
				table.insert(pos, 1, { last[1] + dx * f, last[2] + dy * f, now })
			end
		else
			table.insert(pos, 1, { x, y, now })
		end
		while #pos > #self.trail do
			pos[#pos] = nil
		end
		for i, tex in ipairs(self.trail) do
			local p = pos[i]
			if p and now - p[3] < 0.1 and not self.paused and not self.failed then
				local k = (1 - i / (#self.trail + 1)) * (1 - (now - p[3]) / 0.1)
				local trailSize = size * 0.5 * (0.5 + 0.5 * k)
				tex:SetSize(trailSize, trailSize)
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", self.screen, "BOTTOMLEFT", p[1], p[2])
				tex:SetAlpha(0.6 * k)
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

function Play:UpdateHUD(t, now, dt, pulse, kiai)
	local tally = self.tally
	self.shownScore = self.shownScore + (tally.score - self.shownScore) * min(1, dt * 10)
	if tally.score - self.shownScore < 1 then
		self.shownScore = tally.score
	end
	self.scoreText:SetText(string.format("%08d", floor(self.shownScore + 0.5)))
	self.accText:SetText(U.FormatAcc(tally:Accuracy()))

	if tally.combo > self.lastCombo then
		self.comboPopAt = now
	end
	self.lastCombo = tally.combo
	local popAge = now - self.comboPopAt
	local scale = popAge < 0.15 and (1.25 - popAge / 0.15 * 0.25) or 1
	self.comboFrame:SetScale(scale)
	self.comboFrame:ClearAllPoints()
	self.comboFrame:SetPoint("BOTTOMLEFT", self.hud, "BOTTOMLEFT", 20 / scale, 16 / scale)
	self.comboText:SetText(tally.combo > 0 and (tally.combo .. "x") or "")

	self.shownHP = self.shownHP + (tally.hp - self.shownHP) * min(1, dt * 8)
	local w = max(1, self.hpWidth * self.shownHP)
	self.hpFill:SetWidth(w)
	if self.shownHP < 0.3 then
		local blink = 0.6 + 0.4 * sin(now * 10)
		self.hpFill:SetColorTexture(1, 0.25 * blink, 0.25 * blink, 1)
	else
		self.hpFill:SetColorTexture(1, 1, 1, 1)
	end
	self.hpGlow:ClearAllPoints()
	self.hpGlow:SetPoint("CENTER", self.hpFill, "RIGHT", 0, 0)
	self.hpGlow:SetAlpha(kiai and (0.5 + 0.5 * pulse) or 0.5)

	local total = max(1, self.bm.lastTime - self.bm.firstTime)
	self.progFill:SetWidth(max(1, self.progWidth * U.Clamp((t - self.bm.firstTime) / total, 0, 1)))

	for _, tex in ipairs(self.errorBar.ticks) do
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
	Game.dimScale = b and 0.45 or 1
	local introAge = now - self.startedAt
	self.introText:SetAlpha(introAge < 2.5 and 1 or max(0, 1 - (introAge - 2.5)))

	for i = #self.bursts, 1, -1 do
		local burst = self.bursts[i]
		local age = now - burst.t
		if age > 0.6 then
			self.burstPool:Release(burst.frame)
			table.remove(self.bursts, i)
		else
			local pop = age < 0.08 and (1.6 - age / 0.08 * 0.6) or 1
			local dy = burst.miss and -age * 50 or age * 12
			self:PlaceScaled(burst.frame, burst.x, burst.y, pop, dy)
			burst.frame:SetAlpha(age < 0.35 and 1 or 1 - (age - 0.35) / 0.25)
		end
	end
	for i = #self.lights, 1, -1 do
		local l = self.lights[i]
		local age = now - l.t
		if age > 0.35 then
			self.lightPool:Release(l.tex)
			table.remove(self.lights, i)
		else
			local p = age / 0.35
			local size = l.size * (2 + 1.2 * p) * (kiai and 1.25 or 1)
			l.tex:SetSize(size, size)
			l.tex:SetAlpha(0.55 * (1 - p))
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
	self.visualDt = dt
	self.lastUpdate = now
	local pulse = Beatmap.BeatPulse(self.bm, t)
	local kiai = t > 0 and Beatmap.InKiai(self.bm, t)
	Game:SetFlash(kiai and 0.07 * pulse * pulse or 0)

	while self.objs[self.spawnIndex] and self.objs[self.spawnIndex].t - self.preempt <= t do
		self:SpawnObject(self.objs[self.spawnIndex])
		self.spawnIndex = self.spawnIndex + 1
	end
	self:UpdateFollowPoints(t)
	self:UpdateObjects(t, now, pulse)

	if t > self.bm.firstTime and t < self.bm.lastTime and not self:InBreak(t) then
		self:ChangeHP(-(0.012 + self.hpStat * 0.0045) * dt)
	end
	if self.tally.hp <= 0 and not self.mods.nf then
		self:Fail()
		return
	end

	Game:UpdateVideo(t)
	self:UpdateHUD(t, now, dt, pulse, kiai)

	if self.spawnIndex > #self.objs and #self.active == 0 and t > self.bm.lastTime then
		self:Finish()
	end
end

function Play:InputDown(slot)
	if not self.playing then return end
	if self.held[slot] then
		return
	end
	local t = Clock:Time()
	while self.objs[self.spawnIndex] and self.objs[self.spawnIndex].t - self.preempt <= t do
		self:SpawnObject(self.objs[self.spawnIndex])
		self.spawnIndex = self.spawnIndex + 1
	end
	self:UpdateObjects(t, GetTime(), Beatmap.BeatPulse(self.bm, t))
	self.held[slot] = true
	self.keyCounts[slot] = self.keyCounts[slot] + 1
	local k = self.keyOverlay.keys[slot]
	k.count:SetText(self.keyCounts[slot])
	k.bg:SetColorTexture(ACCENT[1] * 0.8, ACCENT[2] * 0.8, ACCENT[3] * 0.8, 0.95)
	if self.playing then
		self:Press(t)
	end
end

function Play:InputUp(slot)
	if self.playing then
		local t = Clock:Time()
		self:UpdateObjects(t, GetTime(), Beatmap.BeatPulse(self.bm, t))
	end
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
	if down and key == "ESCAPE" then
		if self.playing then self:Pause() else self:Quit() end
		return
	elseif down and (key == "`" or key == "GRAVE" or key == "ENTER" and self.paused) then
		self:Retry()
		return
	end
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
	if key == "-" or key == "MINUS" then
		self:AdjustOffset(-5)
	elseif key == "=" or key == "EQUALS" then
		self:AdjustOffset(5)
	end
end

function Play:OnMouse(button, down)
	if not BC.db.game.mouseButtons then return end
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
