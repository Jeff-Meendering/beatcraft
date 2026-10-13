local _, BC = ...

local W = BC.Widgets
local Live = BC:Module("LiveFrames")

local MAX_UNITS = 40
local PAD, GAP, HEADER = 4, 3, 18
local SIZES = { raid = { 92, 36 }, focus = { 200, 56 } }
local RANGES = { small = 110, medium = 200, large = 320 }
local DRIVERS = {
	raid = { always = "show", auto = "[group] show; hide", combat = "[combat] show; hide" },
	focus = { always = "show", auto = "[@focus,exists] show; hide", combat = "[combat,@focus,exists] show; hide" },
}

-- Runs in Blizzard's restricted environment, so it may move the protected
-- frames in combat. Only attributes, frame refs, and restricted globals are visible.
local JUMP = [[
	local mover = self:GetFrameRef("mover")
	local rx, ry = mover:GetAttribute("rangeX") or 0, mover:GetAttribute("rangeY") or 0
	if rx <= 0 then return end
	local x, y = mover:GetAttribute("jumpX") or 0, mover:GetAttribute("jumpY") or 0
	local nx, ny = x, y
	for i = 1, 8 do
		nx, ny = random(-rx, rx), random(-ry, ry)
		if abs(nx - x) + abs(ny - y) >= rx * 0.5 then break end
	end
	mover:SetAttribute("jumpX", nx)
	mover:SetAttribute("jumpY", ny)
	mover:ClearAllPoints()
	mover:SetPoint("CENTER", "$parent", "BOTTOMLEFT", mover:GetAttribute("homeX") + nx, mover:GetAttribute("homeY") + ny)
]]
Live.JUMP = JUMP

local function groupSize()
	if GetNumGroupMembers then
		return GetNumGroupMembers()
	end
	return math.max(GetNumRaidMembers and GetNumRaidMembers() or 0, (GetNumPartyMembers and GetNumPartyMembers() or 0) + 1)
end

local function inRaid()
	return (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0) or false
end

function Live:Units()
	if BC.db.liveFrames.style == "focus" then
		return { "focus" }
	end
	local units = {}
	if inRaid() then
		-- Whole columns of raid IDs, so people joining mid-fight still get a frame.
		local n = math.min(MAX_UNITS, math.max(5, math.ceil(groupSize() / 5) * 5))
		for i = 1, n do
			units[i] = "raid" .. i
		end
	else
		units[1] = "player"
		for i = 1, 4 do
			units[i + 1] = "party" .. i
		end
	end
	return units
end

local function createButton(mover, i)
	local b = CreateFrame("Button", "BeatcraftLiveFrame" .. i, mover, "SecureUnitButtonTemplate")
	b:RegisterForClicks("AnyUp")
	b:SetFrameLevel(mover:GetFrameLevel() + 2)
	local bg = W.Solid(b, "BACKGROUND", 0.08, 0.08, 0.11, 0.9)
	bg:SetAllPoints()
	W.Border(b)
	b.bar = CreateFrame("StatusBar", nil, b)
	b.bar:SetPoint("TOPLEFT", 2, -2)
	b.bar:SetPoint("BOTTOMRIGHT", -2, 2)
	b.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	b.bar:SetMinMaxValues(0, 1)
	b.name = W.Text(b.bar, 11, "", "OUTLINE")
	b.name:SetPoint("TOPLEFT", 4, -3)
	b.name:SetPoint("RIGHT", -4, 0)
	b.name:SetJustifyH("LEFT")
	b.status = W.Text(b.bar, 10, "", "OUTLINE")
	b.status:SetPoint("BOTTOMLEFT", 4, 3)
	SecureHandlerSetFrameRef(b, "mover", mover)
	SecureHandlerWrapScript(b, "OnClick", mover, JUMP)
	-- Post-hooks run after the secure click, so scoring never taints targeting or casting.
	b:HookScript("OnClick", function(self, button)
		Live:OnFrameClick(self, button)
	end)
	return b
end

function Live:Create()
	if self.mover then
		return
	end
	local mover = CreateFrame("Frame", "BeatcraftLiveFrames", UIParent, "SecureHandlerBaseTemplate")
	mover:SetFrameStrata("MEDIUM")
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:Hide()
	self.mover = mover
	self.bg = W.Solid(mover, "BACKGROUND", 0.04, 0.04, 0.07, 0.55)
	self.bg:SetAllPoints()
	self.stats = W.Text(mover, 11, "", "OUTLINE")
	self.stats:SetPoint("TOPLEFT", PAD + 2, -4)

	self.buttons = {}
	for i = 1, MAX_UNITS do
		self.buttons[i] = createButton(mover, i)
	end

	-- Insecure drag handle shown only while unlocked and out of combat.
	local handle = CreateFrame("Frame", nil, mover)
	handle:SetAllPoints()
	handle:SetFrameLevel(mover:GetFrameLevel() + 10)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	local tint = W.Solid(handle, "OVERLAY", BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3], 0.25)
	tint:SetAllPoints()
	local label = W.Text(handle, 12, "Drag to move  -  lock in /beat live", "OUTLINE")
	label:SetPoint("BOTTOM", handle, "TOP", 0, 4)
	handle:SetScript("OnDragStart", function()
		if not InCombatLockdown() then
			mover:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		mover:StopMovingOrSizing()
		mover:SetUserPlaced(false)
		Live:SaveHome()
	end)
	handle:Hide()
	self.handle = handle

	self.ticker = CreateFrame("Frame")
	self.ticker.elapsed = 0
	self.ticker:SetScript("OnUpdate", function(f, dt)
		f.elapsed = f.elapsed + (dt or 0)
		if f.elapsed >= 0.1 then
			f.elapsed = 0
			Live:Refresh()
		end
	end)
	self.ticker:Hide()
	self:ResetFight()
end

function Live:ApplyClicks(b)
	local spell = BC.db.liveFrames.spell
	spell = spell and spell ~= "" and spell or nil
	b:SetAttribute("type1", spell and "spell" or "target")
	b:SetAttribute("spell1", spell)
	b:SetAttribute("type2", "target")
end

-- Everything that touches protected frames lives here and only runs out of combat.
function Live:Layout()
	if InCombatLockdown() then
		self.pending = true
		return false
	end
	self:Create()
	self.pending = nil
	local db = BC.db.liveFrames
	if not SIZES[db.style] then
		db.style = "raid"
	end
	local units = db.enabled and self:Units() or {}
	local w, h = SIZES[db.style][1], SIZES[db.style][2]
	local rows = math.min(5, math.max(1, #units))
	local cols = math.max(1, math.ceil(#units / 5))
	for i, b in ipairs(self.buttons) do
		local unit = units[i]
		UnregisterUnitWatch(b)
		b:SetAttribute("unit", unit)
		b.unit = unit
		self:ApplyClicks(b)
		b:ClearAllPoints()
		b:SetSize(w, h)
		if unit then
			local col, row = math.floor((i - 1) / 5), (i - 1) % 5
			b:SetPoint("TOPLEFT", self.mover, "TOPLEFT", PAD + col * (w + GAP), -(HEADER + row * (h + GAP)))
			RegisterUnitWatch(b)
		else
			b:Hide()
		end
	end
	self.mover:SetSize(PAD * 2 + cols * w + (cols - 1) * GAP, HEADER + PAD + rows * h + (rows - 1) * GAP)
	local range = RANGES[db.distance] or RANGES.medium
	self.mover:SetAttribute("rangeX", range)
	self.mover:SetAttribute("rangeY", math.floor(range * 0.6))
	local driver = "hide"
	if db.enabled then
		driver = db.locked and (DRIVERS[db.style][db.show] or "show") or "show"
	end
	UnregisterStateDriver(self.mover, "visibility")
	RegisterStateDriver(self.mover, "visibility", driver)
	self.handle:SetShown(db.enabled and not db.locked)
	self.ticker:SetShown(db.enabled)
	self:Home()
	self:Refresh()
	return true
end

function Live:Home()
	if InCombatLockdown() then
		return
	end
	local db = BC.db.liveFrames
	local homeX = math.floor(UIParent:GetWidth() / 2 + db.x + 0.5)
	local homeY = math.floor(UIParent:GetHeight() / 2 + db.y + 0.5)
	local m = self.mover
	m:SetAttribute("homeX", homeX)
	m:SetAttribute("homeY", homeY)
	m:SetAttribute("jumpX", 0)
	m:SetAttribute("jumpY", 0)
	m:ClearAllPoints()
	m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", homeX, homeY)
end

function Live:SaveHome()
	local x, y = self.mover:GetCenter()
	if not x then
		return
	end
	local s = self.mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
	BC.db.liveFrames.x = math.floor(x * s - UIParent:GetWidth() / 2 + 0.5)
	BC.db.liveFrames.y = math.floor(y * s - UIParent:GetHeight() / 2 + 0.5)
	self:Home()
end

function Live:ResetPosition()
	BC.db.liveFrames.x, BC.db.liveFrames.y = BC.DEFAULTS.liveFrames.x, BC.DEFAULTS.liveFrames.y
	self:Home()
end

function Live:SetEnabled(on)
	BC.db.liveFrames.enabled = on and true or false
	if not on then
		BC.db.liveFrames.locked = true
	end
	return self:Apply()
end

function Live:SetLocked(locked)
	if not locked and InCombatLockdown() then
		return false
	end
	BC.db.liveFrames.locked = locked and true or false
	return self:Apply()
end

-- Applies settings now, or after combat if the protected frames are locked down.
function Live:Apply()
	BC:Fire("LIVE_FRAMES_CHANGED")
	if self:Layout() then
		return true
	end
	BC:Print("Moving raid frame changes will apply after combat.")
	return false
end

function Live:IsUsable(unit)
	return unit and UnitExists(unit) and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
		and not (UnitIsConnected and not UnitIsConnected(unit))
end

function Live:Refresh()
	if not self.mover or not BC.db.liveFrames.enabled then
		return
	end
	local focus = BC.db.liveFrames.style == "focus"
	local marked, lowest = nil, 1
	for _, b in ipairs(self.buttons) do
		local unit = b.unit
		if unit and UnitExists(unit) then
			local hp, max = UnitHealth(unit), math.max(1, UnitHealthMax(unit))
			local pct = hp / max
			b.bar:SetMinMaxValues(0, max)
			b.bar:SetValue(hp)
			local _, class = UnitClass(unit)
			local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
			b.bar:SetStatusBarColor(c and c.r or 0.3, c and c.g or 0.8, c and c.b or 0.3)
			b.name:SetText(UnitName(unit) or unit)
			if UnitIsConnected and not UnitIsConnected(unit) then
				b.pct = nil
				b.status:SetText("Offline")
			elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
				b.pct = nil
				b.status:SetText("Dead")
			else
				b.pct = pct
				b.status:SetText(math.floor(pct * 100 + 0.5) .. "%")
			end
			if self:IsUsable(unit) and (focus or pct < lowest) then
				marked, lowest = b, pct
			end
		else
			b.pct = nil
		end
	end
	self.marked = marked
	for _, b in ipairs(self.buttons) do
		local on = b == marked
		for _, border in ipairs(b.borders) do
			border:SetColorTexture(on and 1 or 0.25, on and 0.8 or 0.25, on and 0.2 or 0.32, 1)
		end
		if on then
			b.status:SetText("CLICK  " .. b.status:GetText())
		end
	end
	self:RefreshStats()
end

function Live:ResetFight()
	self.fight = { hits = 0, misses = 0, combo = 0, best = 0 }
end

function Live:RefreshStats()
	local f = self.fight
	local clicks = f.hits + f.misses
	if clicks == 0 then
		self.stats:SetText("Click the frame marked CLICK")
	else
		self.stats:SetText(string.format("Combo %d  |  %d/%d  (%d%%)", f.combo, f.hits, clicks,
			math.floor(f.hits / clicks * 100 + 0.5)))
	end
end

function Live:OnFrameClick(b, button)
	if button ~= "LeftButton" or not BC.db.liveFrames.enabled then
		return
	end
	-- Nobody needs healing, so the click only moves the frames.
	if not self.marked then
		return
	end
	local f = self.fight
	if b == self.marked then
		f.hits, f.combo = f.hits + 1, f.combo + 1
		f.best = math.max(f.best, f.combo)
		if f.best > BC.db.liveFrames.bestCombo then
			BC.db.liveFrames.bestCombo = f.best
		end
	else
		f.misses, f.combo = f.misses + 1, 0
	end
	self:RefreshStats()
end

function Live:OnCombatStart()
	if not self.mover then
		return
	end
	self:ResetFight()
	do
		-- Hiding an insecure child is still allowed after lockdown begins.
		self.handle:Hide()
		if not BC.db.liveFrames.locked then
			BC.db.liveFrames.locked = true
			self.pending = true
		end
	end
	self:RefreshStats()
end

function Live:OnCombatEnd()
	local f = self.fight
	if self.mover and BC.db.liveFrames.enabled and f.hits + f.misses > 0 then
		BC:Print(string.format("Moving frames: %d of %d clicks on the marked frame (%d%%), best combo %d.",
			f.hits, f.hits + f.misses, math.floor(f.hits / (f.hits + f.misses) * 100 + 0.5), f.best))
	end
	if self.pending or not self.mover then
		self:Layout()
	else
		self:Home()
	end
end

function Live:OnLogin()
	self:Layout()
end

BC:On("PLAYER_REGEN_DISABLED", function()
	Live:OnCombatStart()
end)
BC:On("PLAYER_REGEN_ENABLED", function()
	if BC.db then
		Live:OnCombatEnd()
	end
end)
BC:On("GROUP_ROSTER_UPDATE", function()
	if Live.mover and BC.db.liveFrames.enabled then
		Live:Layout()
	end
end)

-- Settings panel ------------------------------------------------------------

local OPTIONS = {
	style = {
		{ value = "raid", text = "Party / raid frames" },
		{ value = "focus", text = "Focus frame" },
	},
	distance = {
		{ value = "small", text = "Small hops" },
		{ value = "medium", text = "Medium hops" },
		{ value = "large", text = "Big hops" },
	},
	show = {
		{ value = "auto", text = "In a group (or with a focus)" },
		{ value = "combat", text = "Only in combat" },
		{ value = "always", text = "Always" },
	},
}

function Live:CreatePanel()
	if self.panel then
		return
	end
	local db = BC.db.liveFrames
	local f = W.Panel("BeatcraftLivePanel", UIParent, 340, 420, "Moving raid frames")
	f:SetPoint("CENTER", 0, 40)
	self.panel = f
	local widgets = {}
	local y = -40
	local function place(w, height)
		w:SetPoint("TOPLEFT", 16, y)
		y = y - height
		widgets[#widgets + 1] = w
		return w
	end
	local about = W.Text(f, 11, "Real, clickable frames that jump somewhere new every time you click them, in or out of combat. Click the frame marked CLICK (most injured) to build a combo.")
	about:SetWidth(308)
	about:SetJustifyH("LEFT")
	about:SetTextColor(0.75, 0.75, 0.8)
	place(about, 50)
	place(W.Check(f, "Enabled", function()
		return db.enabled
	end, function(v)
		Live:SetEnabled(v)
		Live:RefreshPanel()
	end, 300), 28)
	for _, key in ipairs({ "style", "distance", "show" }) do
		local label = key == "style" and "Frames" or key == "distance" and "Jump distance" or "Show"
		place(W.Dropdown(f, label, OPTIONS[key], function()
			return db[key]
		end, function(v)
			db[key] = v
			Live:Apply()
		end, 300), 48)
	end
	local spellLabel = W.Text(f, 12, "Left-click spell (blank = target)")
	place(spellLabel, 18)
	local edit = W.EditBox(f, 300, 22)
	local function saveSpell(e)
		e:ClearFocus()
		db.spell = BC.Util.Trim(e:GetText() or "")
		Live:Apply()
	end
	edit:SetScript("OnEnterPressed", saveSpell)
	edit:SetScript("OnEditFocusLost", function(e)
		if BC.Util.Trim(e:GetText() or "") ~= db.spell then
			saveSpell(e)
		end
	end)
	place(edit, 34)
	self.spellEdit = edit
	self.lockButton = W.Button(f, "", 140, 26, function()
		Live:SetLocked(not db.locked)
		Live:RefreshPanel()
	end)
	place(self.lockButton, 0)
	local reset = W.Button(f, "Reset position", 140, 26, function()
		Live:ResetPosition()
	end)
	reset:SetPoint("TOPLEFT", 176, y)
	y = y - 36
	self.panelInfo = W.Text(f, 11, "")
	self.panelInfo:SetWidth(308)
	self.panelInfo:SetJustifyH("LEFT")
	place(self.panelInfo, 30)
	self.panelWidgets = widgets
	f:SetScript("OnShow", function()
		Live:RefreshPanel()
	end)
end

function Live:RefreshPanel()
	if not self.panel then
		return
	end
	local db = BC.db.liveFrames
	for _, w in ipairs(self.panelWidgets) do
		if w.Refresh then
			w:Refresh()
		end
	end
	self.spellEdit:SetText(db.spell or "")
	self.lockButton:SetLabel(db.locked and "Move frames" or "Lock frames")
	if db.enabled and not InCombatLockdown() then
		self.lockButton:Enable()
	else
		self.lockButton:Disable()
	end
	local lines = { "Best combo: " .. db.bestCombo }
	if InCombatLockdown() then
		lines[#lines + 1] = "|cffffd060In combat: changes apply when it ends.|r"
	end
	self.panelInfo:SetText(table.concat(lines, "\n"))
end

function Live:OpenPanel()
	self:CreatePanel()
	self.panel:Show()
	self.panel:Raise()
end
