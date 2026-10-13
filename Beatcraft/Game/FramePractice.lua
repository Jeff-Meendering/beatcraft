local _, BC = ...

local W, U, Game = BC.Widgets, BC.Util, BC.Game
local Practice = BC:Module("FramePractice")
local ROUND_SECONDS = 30
local SPEED = { easy = 85, normal = 150, hard = 240 }
local COLORS = {
	{ 0.78, 0.61, 0.43 }, { 1, 0.49, 0.04 }, { 0.25, 0.78, 0.92 },
	{ 0.67, 0.83, 0.45 }, { 1, 0.96, 0.41 },
}

-- Reflect a continuous path at either boundary, even after a long frame.
local function reflect(distance, limit)
	if limit <= 0 then return 0 end
	local p = distance % (2 * limit)
	return p <= limit and p or 2 * limit - p
end

function Practice:Create(parent)
	if self.screen then return end
	local screen = CreateFrame("Frame", nil, parent)
	screen:SetAllPoints()
	screen:Hide()
	self.screen = screen
	self.title = W.Text(screen, 24, "Moving Frame Practice", "OUTLINE")
	self.instructions = W.Text(screen, 13, "")
	self.hud = W.Text(screen, 16, "", "OUTLINE")
	self.feedback = W.Text(screen, 13, "")
	self.area = CreateFrame("Frame", nil, screen)
	self.area:SetPoint("CENTER", 0, 0)
	self.area:EnableMouse(true)
	local bg = W.Solid(self.area, "BACKGROUND", 0.04, 0.05, 0.08, 0.85)
	bg:SetAllPoints()
	W.Border(self.area)
	self.area:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then Practice:Click(nil) end
	end)
	self.title:SetPoint("BOTTOM", self.area, "TOP", 0, 86)
	self.instructions:SetPoint("BOTTOM", self.area, "TOP", 0, 57)
	self.hud:SetPoint("BOTTOM", self.area, "TOP", 0, 25)
	self.feedback:SetPoint("BOTTOM", self.area, "TOP", 0, 5)

	-- Practice frames are ordinary buttons; they never target or cast on units.
	self.group = CreateFrame("Frame", nil, self.area)
	self.targets = {}
	for i = 1, 5 do
		local b = CreateFrame("Button", nil, self.group)
		b:RegisterForClicks("LeftButtonDown")
		local bg = W.Solid(b, "BACKGROUND", 0.1, 0.1, 0.14, 1)
		bg:SetAllPoints()
		W.Border(b)
		b.health = W.Solid(b, "ARTWORK", unpack(COLORS[i]))
		b.health:SetPoint("TOPLEFT", 3, -3)
		b.health:SetHeight(23)
		b.name = W.Text(b, 11, "", "OUTLINE")
		b.name:SetPoint("TOPLEFT", 6, -7)
		b.prompt = W.Text(b, 10, "", "OUTLINE")
		b.prompt:SetPoint("BOTTOMLEFT", 6, 4)
		b:SetScript("OnClick", function() Practice:Click(i) end)
		self.targets[i] = b
	end

	self.settings = {}
	local function choice(label, value, key, x, width)
		local b = W.Button(screen, label, width, 26, function()
			if Practice.running then return end
			BC.db.framePractice[key] = value
			Practice:Configure()
		end)
		b:SetPoint("TOPLEFT", self.area, "BOTTOMLEFT", x, -16)
		b.key, b.value = key, value
		self.settings[#self.settings + 1] = b
	end
	choice("Raid", "raid", "style", 0, 62)
	choice("Focus", "focus", "style", 68, 62)
	choice("Easy", "easy", "difficulty", 154, 62)
	choice("Normal", "normal", "difficulty", 222, 70)
	choice("Hard", "hard", "difficulty", 298, 62)
	self.start = W.Button(screen, "Start 30-second round", 200, 30, function() Practice:Start() end, true)
	self.start:SetPoint("TOP", self.area, "BOTTOM", 0, -58)
	local exit = W.Button(screen, "Back", 70, 30, function() Game:Close() end)
	exit:SetPoint("TOPRIGHT", self.area, "BOTTOMRIGHT", 0, -58)
	local hint = W.Text(screen, 11, "Left click only  |  Escape: exit  |  Enter: start / retry")
	hint:SetPoint("TOP", self.start, "BOTTOM", 0, -12)
	screen:SetScript("OnUpdate", function() Practice:Update() end)
end

function Practice:Open()
	if not Game:Open() then return end
	Game:Show(self)
end

function Practice:Enter()
	BC.Clock:Stop()
	Game:StopVideo()
	Game.dimScale = 1
	Game:ApplyBackground(nil, "select")
	self.area:SetSize(math.max(360, math.min(900, Game.root:GetWidth() - 60)),
		math.max(270, math.min(480, Game.root:GetHeight() - 300)))
	self.running = false
	self.hits, self.misses, self.combo, self.bestCombo = 0, 0, 0, 0
	self.screen:Show()
	self:Configure()
end

function Practice:Configure()
	local db = BC.db.framePractice
	self.hits, self.misses, self.combo, self.bestCombo = 0, 0, 0, 0
	self.start:SetLabel("Start 30-second round")
	self.start:Enable()
	if db.style ~= "focus" then db.style = "raid" end
	if not SPEED[db.difficulty] then db.difficulty = "normal" end
	self.style, self.speed = db.style, SPEED[db.difficulty]
	self.bestKey = db.style .. "-" .. db.difficulty
	local best = db.best[self.bestKey]
	self.feedback:SetText(best and string.format("Personal best: %d hits at %.1f%%", best.hits, best.acc)
		or "Choose a frame style and speed, then start.")
	self.count = self.style == "raid" and 5 or 1
	local width, height = self.style == "raid" and 116 or 220, self.style == "raid" and 44 or 64
	self.group:SetSize(width, height * self.count + (self.count - 1) * 4)
	for i, b in ipairs(self.targets) do
		b:SetSize(width, height)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.group, "TOPLEFT", 0, -(i - 1) * (height + 4))
		b.name:SetText(self.style == "raid" and ("Raid member " .. i) or "Focus target")
		b:SetShown(i <= self.count)
	end
	for _, b in ipairs(self.settings) do
		b:SetActive(db[b.key] == b.value)
		b:Enable()
	end
	self.instructions:SetText(self.style == "raid" and "Click the injured member marked CLICK as the raid frames move."
		or "Click the moving focus frame marked CLICK.")
	self.targetIndex = 1
	self:RefreshTargets()
	self:Move(0)
	self:RefreshHUD(ROUND_SECONDS)
end

function Practice:RefreshTargets()
	for i = 1, self.count do
		local b = self.targets[i]
		local selected = i == self.targetIndex
		b.health:SetWidth((b:GetWidth() - 6) * (selected and 0.35 or 0.9))
		b.prompt:SetText(selected and "CLICK  -  35%" or "90%")
		b.prompt:SetTextColor(selected and 1 or 0.7, selected and 0.8 or 0.7, selected and 0.2 or 0.7)
		for _, border in ipairs(b.borders) do
			border:SetColorTexture(selected and 1 or 0.3, selected and 0.8 or 0.3, selected and 0.2 or 0.38, 1)
		end
	end
end

function Practice:Move(elapsed)
	local rangeX = math.max(0, self.area:GetWidth() - self.group:GetWidth() - 16)
	local rangeY = math.max(0, self.area:GetHeight() - self.group:GetHeight() - 16)
	self.x = 8 + reflect(rangeX * 0.35 + elapsed * self.speed, rangeX)
	self.y = 8 + reflect(rangeY * 0.45 + elapsed * self.speed * 0.63, rangeY)
	self.group:ClearAllPoints()
	self.group:SetPoint("TOPLEFT", self.area, "TOPLEFT", self.x, -self.y)
end

function Practice:Start()
	if self.running or not self.screen:IsVisible() then return end
	self.hits, self.misses, self.combo, self.bestCombo = 0, 0, 0, 0
	self.startedAt, self.running = GetTime(), true
	self.targetIndex = math.random(self.count)
	self:RefreshTargets()
	self:Move(0)
	self.start:Disable()
	for _, b in ipairs(self.settings) do b:Disable() end
	self.feedback:SetText("Follow the frames and click the highlighted target!")
	self:RefreshHUD(ROUND_SECONDS)
end

function Practice:RefreshHUD(remaining)
	local clicks = self.hits + self.misses
	local accuracy = clicks > 0 and self.hits / clicks * 100 or 0
	self.hud:SetText(string.format("%ds  |  Hits %d  |  Misses %d  |  %.1f%%  |  Combo %d",
		math.ceil(remaining), self.hits, self.misses, accuracy, self.combo))
end

function Practice:Click(index)
	if not self.running then return end
	-- Check the deadline here too so a click between updates cannot extend a round.
	if GetTime() - self.startedAt >= ROUND_SECONDS then self:Finish(); return end
	if index == self.targetIndex then
		self.hits, self.combo = self.hits + 1, self.combo + 1
		self.bestCombo = math.max(self.bestCombo, self.combo)
		if self.count > 1 then
			self.targetIndex = (self.targetIndex + math.random(1, self.count - 1) - 1) % self.count + 1
		end
		self:RefreshTargets()
		self.feedback:SetText("HIT!")
	else
		self.misses, self.combo = self.misses + 1, 0
		self.feedback:SetText("MISS - click the frame marked CLICK.")
	end
	self:RefreshHUD(ROUND_SECONDS - (GetTime() - self.startedAt))
end

function Practice:Update()
	if not self.running then return end
	local elapsed = GetTime() - self.startedAt
	if elapsed >= ROUND_SECONDS then self:Finish(); return end
	self:Move(elapsed)
	self:RefreshHUD(ROUND_SECONDS - elapsed)
end

function Practice:Finish()
	self.running = false
	self:RefreshHUD(0)
	local clicks = self.hits + self.misses
	local acc = clicks > 0 and self.hits / clicks * 100 or 0
	local bests = BC.db.framePractice.best
	local old = bests[self.bestKey]
	local record = self.hits > 0 and (not old or self.hits > old.hits or self.hits == old.hits and acc > old.acc)
	if record then
		bests[self.bestKey] = { hits = self.hits, acc = acc }
	end
	self.feedback:SetText(string.format("Round complete!%s  Best combo: %d  |  %.2f hits / second",
		record and "  |cff66ff66New personal best!|r" or "", self.bestCombo, self.hits / ROUND_SECONDS))
	self.start:SetLabel("Try again (30 seconds)")
	self.start:Enable()
	for _, b in ipairs(self.settings) do b:Enable() end
end

function Practice:Leave()
	self.running = false
	self.screen:Hide()
	W.CloseMenu()
end

function Practice:OnKey(key, down)
	if not down then return end
	if key == "ESCAPE" then
		Game:Close()
	elseif key == "ENTER" and not self.running then
		self:Start()
	end
end
