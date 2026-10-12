MOCK = {
	now = 1000,
	precise = 5000,
	frames = {},
	events = {},
	timers = {},
	unknown = {},
	sounds = {},
	stoppedSounds = {},
	bindings = {},
	addonMessages = {},
	printed = {},
	cursor = { 960, 540 },
	combat = false,
	auras = { player = {}, target = {} },
	cooldowns = {},
	power = { [0] = 5000, [1] = 60, [3] = 100 },
	powerMax = { [0] = 10000, [1] = 100, [3] = 100 },
	castInfo = nil,
	target = { exists = true, hostile = true, dead = false, hp = 100, level = 72, name = "Training Target" },
	combo = 0,
	soundHandle = 0,
	current = {},
}

function IsCurrentSpell(spell)
	local name = type(spell) == "number" and MOCK.spellById[spell] and MOCK.spellById[spell].name or spell
	return MOCK.current[name] == true
end

local unpack = unpack

local function noop() end

local KNOWN_NOOPS = {
	"SetFrameStrata", "SetToplevel", "SetClampedToScreen", "EnableMouse", "EnableMouseWheel", "EnableKeyboard",
	"SetPropagateKeyboardInput", "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
	"SetColorTexture", "SetTexture", "SetTexCoord", "SetVertexColor", "SetBlendMode", "SetDrawLayer", "SetRotation",
	"SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetSpacing", "SetFontObject",
	"SetTextInsets", "SetAutoFocus", "SetMultiLine", "SetCursorPosition", "HighlightText", "SetHighlightTexture",
	"SetThumbTexture", "SetOrientation", "SetValueStep", "SetObeyStepOnDrag", "SetScrollChild",
	"SetVerticalScroll", "RegisterForClicks", "Raise", "SetAllPoints", "SetTextHeight", "UnregisterAllEvents",
	"SetHitRectInsets", "SetMaxLetters",
}

local Widget = {}
Widget.__index = function(t, k)
	local v = rawget(Widget, k)
	if v ~= nil then
		return v
	end
	if type(k) == "string" and k:match("^%u") then
		MOCK.unknown[k] = true
		return noop
	end
end

for _, name in ipairs(KNOWN_NOOPS) do
	Widget[name] = noop
end

local function newWidget(kind, name, parent)
	local w = setmetatable({
		_kind = kind,
		_name = name,
		_parent = parent,
		_shown = true,
		_scripts = {},
		_w = 0,
		_h = 0,
		_alpha = 1,
		_scale = 1,
		_text = "",
		_level = parent and (parent._level or 0) + 1 or 0,
		_enabled = true,
		_value = 0,
		_min = 0,
		_max = 1,
		_events = {},
		_points = {},
	}, Widget)
	if name then
		_G[name] = w
	end
	table.insert(MOCK.frames, w)
	return w
end

function Widget:GetObjectType()
	return self._kind
end
function Widget:GetName()
	return self._name
end
function Widget:SetScript(event, fn)
	self._scripts[event] = fn
end
function Widget:GetScript(event)
	return self._scripts[event]
end
function Widget:HookScript(event, fn)
	local old = self._scripts[event]
	self._scripts[event] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
function Widget:Fire(event, ...)
	local fn = self._scripts[event]
	if fn then
		fn(self, ...)
	end
end
function Widget:Show()
	local was = self:IsVisible()
	self._shown = true
	if not was and self:IsVisible() then
		self:Fire("OnShow")
	end
end
function Widget:Hide()
	local was = self:IsVisible()
	self._shown = false
	if was then
		self:Fire("OnHide")
	end
end
function Widget:SetShown(v)
	if v then
		self:Show()
	else
		self:Hide()
	end
end
function Widget:IsShown()
	return self._shown
end
function Widget:IsVisible()
	local f = self
	while f do
		if not f._shown then
			return false
		end
		f = f._parent
	end
	return true
end
function Widget:SetParent(p)
	self._parent = p
end
function Widget:GetParent()
	return self._parent
end
function Widget:SetSize(w, h)
	self._w, self._h = w, h
end
function Widget:SetWidth(w)
	self._w = w
end
function Widget:SetHeight(h)
	self._h = h
end
function Widget:GetWidth()
	if self._kind == "Frame" and self._allPoints then
		return 1920
	end
	return self._w
end
function Widget:GetHeight()
	return self._h
end
function Widget:SetPoint(...)
	table.insert(self._points, { ... })
end
function Widget:ClearAllPoints()
	self._points = {}
end
function Widget:GetPoint()
	local p = self._points[1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
	return "CENTER", nil, "CENTER", 0, 0
end
function Widget:GetLeft()
	return 0
end
function Widget:GetTop()
	return self._h
end
function Widget:GetCenter()
	return self._w / 2, self._h / 2
end
function Widget:SetAlpha(a)
	assert(type(a) == "number", "SetAlpha needs a number")
	self._alpha = a
end
function Widget:GetAlpha()
	return self._alpha
end
function Widget:SetScale(s)
	assert(type(s) == "number" and s > 0, "SetScale needs a positive number")
	self._scale = s
end
function Widget:GetScale()
	return self._scale
end
function Widget:GetEffectiveScale()
	return 1
end
function Widget:SetFrameLevel(l)
	assert(type(l) == "number", "SetFrameLevel needs a number")
	self._level = l
end
function Widget:GetFrameLevel()
	return self._level
end
function Widget:SetText(t)
	self._text = t == nil and "" or tostring(t)
	if self._kind == "EditBox" then
		self:Fire("OnTextChanged", false)
	end
end
function Widget:GetText()
	return self._text
end
function Widget:Insert(t)
	self._text = self._text .. t
	self:Fire("OnTextChanged", true)
end
function Widget:SetFocus()
	MOCK.focus = self
end
function Widget:ClearFocus()
	if MOCK.focus == self then
		MOCK.focus = nil
	end
end
function Widget:HasFocus()
	return MOCK.focus == self
end
function Widget:Enable()
	self._enabled = true
end
function Widget:Disable()
	self._enabled = false
end
function Widget:IsEnabled()
	return self._enabled
end
function Widget:Click(button)
	self:Fire("OnClick", button or "LeftButton", true)
end
function Widget:SetMinMaxValues(a, b)
	self._min, self._max = a, b
end
function Widget:SetValue(v)
	self._value = v
	self:Fire("OnValueChanged", v)
end
function Widget:GetValue()
	return self._value
end
function Widget:GetVerticalScroll()
	return 0
end
function Widget:GetVerticalScrollRange()
	return 0
end
function Widget:RegisterEvent(e)
	MOCK.events[e] = MOCK.events[e] or {}
	MOCK.events[e][self] = true
end
function Widget:UnregisterEvent(e)
	if MOCK.events[e] then
		MOCK.events[e][self] = nil
	end
end
function Widget:CreateTexture(name, layer)
	local t = newWidget("Texture", name, self)
	return t
end
function Widget:CreateFontString(name, layer)
	return newWidget("FontString", name, self)
end

function CreateFrame(kind, name, parent, template)
	local f = newWidget(kind, name, parent)
	if parent == nil and kind ~= "GameTooltip" then
		f._parent = UIParent
	end
	return f
end

UIParent = newWidget("Frame", "UIParent", nil)
UIParent._w, UIParent._h = 1920, 1080
WorldFrame = UIParent
Minimap = newWidget("Frame", "Minimap", UIParent)
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent)
for _, m in ipairs({ "SetOwner", "SetText", "AddLine" }) do
	Widget[m] = Widget[m] or noop
end
ChatFontNormal = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
BOOKTYPE_SPELL = "spell"
MAX_BATTLEFIELD_QUEUES = 3
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, U_CHAT_SCROLL_BUTTON = 1115 }
DEFAULT_CHAT_FRAME = {
	AddMessage = function(_, msg)
		table.insert(MOCK.printed, msg)
		if MOCK.echo then
			print("  [chat] " .. msg)
		end
	end,
}

function wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
tinsert = table.insert
tremove = table.remove
function strsplit(sep, s)
	local out = {}
	local start = 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			out[#out + 1] = s:sub(start)
			break
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
	return unpack(out)
end
function Ambiguate(n)
	return (n:gsub("%-.*", ""))
end
function GetTime()
	return MOCK.now
end
function GetTimePreciseSec()
	return MOCK.precise
end
function time()
	return 1700000000
end

C_Timer = {
	After = function(delay, fn)
		table.insert(MOCK.timers, { at = MOCK.now + delay, fn = fn })
	end,
	NewTicker = function(interval, fn)
		local ticker = { cancelled = false }
		local function schedule()
			table.insert(MOCK.timers, {
				at = MOCK.now + interval,
				fn = function()
					if not ticker.cancelled then
						fn(ticker)
						schedule()
					end
				end,
			})
		end
		schedule()
		function ticker:Cancel()
			self.cancelled = true
		end
		return ticker
	end,
}

function InCombatLockdown()
	return MOCK.combat
end
function UnitAffectingCombat()
	return MOCK.combat
end

function UnitClass(unit)
	return "Warrior", MOCK.class or "WARRIOR", 1
end
function UnitName(unit)
	if unit == "target" then
		return MOCK.target.name
	end
	return "Tester"
end
function UnitExists(unit)
	if unit == "target" then
		return MOCK.target.exists
	end
	return unit == "player"
end
function UnitCanAttack(a, b)
	return b == "target" and MOCK.target.hostile
end
function UnitIsDead(unit)
	return unit == "target" and MOCK.target.dead
end
function UnitPower(unit, kind)
	return MOCK.power[kind or 1] or 0
end
function UnitPowerMax(unit, kind)
	return MOCK.powerMax[kind or 1] or 100
end
function UnitHealth(unit)
	if unit == "target" then
		return MOCK.target.hp
	end
	return 80
end
function UnitHealthMax()
	return 100
end
function UnitLevel(unit)
	if unit == "target" then
		return MOCK.target.level
	end
	return 70
end
function UnitClassification()
	return "normal"
end
function UnitCreatureType()
	return "Humanoid"
end
function GetUnitSpeed()
	return 0
end
function IsStealthed()
	return false
end
function GetComboPoints()
	return MOCK.combo
end
function IsInGroup()
	return false
end
function IsInRaid()
	return false
end
function IsInGuild()
	return true
end
function UnitCastingInfo(unit)
	local c = MOCK.castInfo
	if c and MOCK.now < c.endT then
		return c.name, c.name, 136000, c.startT * 1000, c.endT * 1000
	end
end
function UnitChannelInfo()
	return nil
end
function UnitAura(unit, i, filter)
	local list = MOCK.auras[unit] or {}
	local a = list[i]
	if a then
		return a.name, 136000, a.count or 1, nil, a.duration or 0, a.expires or 0, "player"
	end
end

MOCK.spells = {
	{ id = 100, name = "Battle Shout", cast = 0 },
	{ id = 101, name = "Mortal Strike", cast = 0, cd = 6 },
	{ id = 102, name = "Whirlwind", cast = 0, cd = 10 },
	{ id = 103, name = "Execute", cast = 0 },
	{ id = 104, name = "Overpower", cast = 0, cd = 5 },
	{ id = 105, name = "Slam", cast = 1.5 },
	{ id = 106, name = "Heroic Strike", cast = 0, offgcd = true },
}
MOCK.spellById, MOCK.spellByName = {}, {}
for _, s in ipairs(MOCK.spells) do
	MOCK.spellById[s.id] = s
	MOCK.spellByName[s.name:lower()] = s
end

local function lookup(spell)
	if type(spell) == "number" then
		return MOCK.spellById[spell]
	end
	if type(spell) == "string" then
		return MOCK.spellByName[spell:lower()]
	end
end

function GetSpellInfo(spell)
	local s = lookup(spell)
	if s then
		return s.name, nil, 136000 + s.id, (s.cast or 0) * 1000, 0, 5, s.id
	end
end
function GetNumSpellTabs()
	return 1
end
function GetSpellTabInfo(tab)
	return "General", 1, 0, #MOCK.spells
end
function GetSpellBookItemName(i, book)
	local s = MOCK.spells[i]
	return s and s.name
end
function GetSpellCooldown(spell)
	if spell == 61304 then
		local g = MOCK.gcd
		if g and MOCK.now < g.start + g.dur then
			return g.start, g.dur, 1
		end
		return 0, 0, 1
	end
	local s = lookup(spell)
	if not s then
		return 0, 0, 1
	end
	local cd = MOCK.cooldowns[s.name]
	local g = MOCK.gcd
	local start, dur = 0, 0
	if cd and MOCK.now < cd.start + cd.dur then
		start, dur = cd.start, cd.dur
	end
	if not s.offgcd and g and MOCK.now < g.start + g.dur then
		if g.start + g.dur > start + dur then
			start, dur = g.start, g.dur
		end
	end
	return start, dur, 1
end
function IsUsableSpell(spell)
	local s = lookup(spell)
	if not s then
		return false, false
	end
	if s.name == "Overpower" then
		return MOCK.overpower == true, false
	end
	if s.name == "Execute" then
		return MOCK.target.hp < 20, false
	end
	return true, false
end
function IsSpellInRange()
	return 1
end
function GetTalentTabInfo(i)
	local points = { 41, 20, 0 }
	return i, "Tree" .. i, "", 1, points[i] or 0
end
function GetNumTalentTabs()
	return 3
end

MOCK.actions = { [1] = 101, [2] = 102, [3] = 105, [4] = 106, [5] = 100, [6] = 103, [7] = 104 }
function GetActionInfo(slot)
	local id = MOCK.actions[slot]
	if id then
		return "spell", id
	end
end
function GetBindingKey(cmd)
	local n = cmd:match("^ACTIONBUTTON(%d+)$")
	if n then
		return n
	end
end
function GetMacroSpell()
	return nil
end
function UseAction(slot)
	MOCK.lastUse = slot
end
function CastSpellByName(name) end
function CastSpellByID(id) end
function CastSpell(i, book) end

function hooksecurefunc(a, b, c)
	local tbl, name, fn
	if type(a) == "table" then
		tbl, name, fn = a, b, c
	else
		tbl, name, fn = _G, a, b
	end
	local orig = tbl[name]
	assert(orig, "hooksecurefunc: no function " .. tostring(name))
	tbl[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end

function SetOverrideBindingClick(owner, prio, key, button, mouse)
	assert(not MOCK.combat, "SetOverrideBindingClick in combat")
	MOCK.bindings[key] = button
end
function ClearOverrideBindings(owner)
	assert(not MOCK.combat, "ClearOverrideBindings in combat")
	MOCK.bindings = {}
end
function GetCVar(name)
	if name == "SpellQueueWindow" then
		return "400"
	end
end
function GetCursorPosition()
	return MOCK.cursor[1], MOCK.cursor[2]
end
function Screenshot() end
function GetRealZoneText()
	return "Test Zone"
end
function GetBattlefieldStatus()
	return "none"
end

function PlaySoundFile(path, channel)
	assert(type(path) == "string" or type(path) == "number", "PlaySoundFile path")
	MOCK.soundHandle = MOCK.soundHandle + 1
	table.insert(MOCK.sounds, { path = path, channel = channel, at = MOCK.now })
	if MOCK.failSound then
		return false
	end
	return true, MOCK.soundHandle
end
function StopSound(h)
	table.insert(MOCK.stoppedSounds, h)
end
function PlaySound(id, channel)
	assert(type(id) == "number", "PlaySound id")
end

C_AddOns = {
	LoadAddOn = function(name)
		if name == "Beatcraft_Library" then
			if not MOCK.libraryPath then
				return false, "MISSING"
			end
			local chunk = assert(loadfile(MOCK.libraryPath))
			chunk()
			return true
		end
		return false, "MISSING"
	end,
	IsAddOnLoaded = function()
		return false
	end,
}
C_ChatInfo = {
	RegisterAddonMessagePrefix = function() end,
	SendAddonMessage = function(prefix, msg, channel)
		table.insert(MOCK.addonMessages, { prefix = prefix, msg = msg, channel = channel })
	end,
}

function MOCK.FireEvent(event, ...)
	local list = MOCK.events[event]
	if not list then
		return
	end
	for f in pairs(list) do
		local fn = f._scripts.OnEvent
		if fn then
			fn(f, event, ...)
		end
	end
end

function MOCK.Advance(seconds, step)
	step = step or 1 / 60
	local remaining = seconds
	while remaining > 1e-9 do
		local dt = math.min(step, remaining)
		remaining = remaining - dt
		MOCK.now = MOCK.now + dt
		MOCK.precise = MOCK.precise + dt
		local due = {}
		for i = #MOCK.timers, 1, -1 do
			if MOCK.timers[i].at <= MOCK.now then
				table.insert(due, 1, table.remove(MOCK.timers, i))
			end
		end
		table.sort(due, function(a, b)
			return a.at < b.at
		end)
		for _, t in ipairs(due) do
			t.fn()
		end
		for _, f in ipairs(MOCK.frames) do
			local fn = f._scripts.OnUpdate
			if fn and f:IsVisible() then
				fn(f, dt)
			end
		end
		if MOCK.onTick then
			MOCK.onTick()
		end
	end
end

function MOCK.LoadAddon(dir, files)
	local ns = {}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(dir .. "/" .. file)
		if not chunk then
			error("syntax error in " .. file .. ": " .. tostring(err))
		end
		chunk("Beatcraft", ns)
	end
	return ns
end
