local _, BC = ...

local Compat = BC.Compat
local Cond = BC:Module("Conditions")

local function pct(cur, max)
	if not max or max <= 0 then
		return 0
	end
	return cur / max * 100
end

local function aura(unit, filter)
	return function(name)
		return (Compat.FindAura(unit, name, filter))
	end
end

local function auraStacks(unit, filter)
	return function(name)
		local _, stacks = Compat.FindAura(unit, name, filter)
		return stacks
	end
end

local function cooldown(name)
	local start, duration = Compat.SpellCooldown(name)
	if not start or not duration or duration <= 1.6 then
		return 0
	end
	return math.max(0, start + duration - GetTime())
end

local function hasForm(name)
	return (Compat.FindAura("player", name, "HELPFUL")) > 0
end

local combatStart

BC:On("PLAYER_REGEN_DISABLED", function()
	combatStart = GetTime()
end)
BC:On("PLAYER_REGEN_ENABLED", function()
	combatStart = nil
end)

Cond.HELPERS = {
	buff = aura("player", "HELPFUL"),
	buffStacks = auraStacks("player", "HELPFUL"),
	debuff = aura("target", "HARMFUL|PLAYER"),
	debuffStacks = auraStacks("target", "HARMFUL|PLAYER"),
	debuffAny = aura("target", "HARMFUL"),
	debuffAnyStacks = auraStacks("target", "HARMFUL"),
	cd = cooldown,
	ready = function(name)
		return cooldown(name) <= 0.1
	end,
	known = function(name)
		return Compat.IsKnown(name)
	end,
	usable = function(name)
		return (Compat.SpellUsable(name)) and true or false
	end,
	casting = function(name)
		local _, spell = Compat.PlayerCast()
		if not spell then
			return false
		end
		return name == nil or spell:lower() == tostring(name):lower()
	end,
	form = hasForm,
	targetIs = function(kind)
		local ct = UnitCreatureType("target")
		return ct ~= nil and ct:lower() == tostring(kind):lower()
	end,
	inRange = function(name)
		return Compat.SpellInRange(name, "target") == true
	end,
	min = math.min,
	max = math.max,
	abs = math.abs,
	floor = math.floor,
}

Cond.VARS = {
	power = function()
		return UnitPower("player")
	end,
	powerPct = function()
		return pct(UnitPower("player"), UnitPowerMax("player"))
	end,
	mana = function()
		return UnitPower("player", 0)
	end,
	manaPct = function()
		return pct(UnitPower("player", 0), UnitPowerMax("player", 0))
	end,
	rage = function()
		return UnitPower("player", 1)
	end,
	energy = function()
		return UnitPower("player", 3)
	end,
	focus = function()
		return UnitPower("player", 2)
	end,
	combo = function()
		return Compat.ComboPoints()
	end,
	hp = function()
		return pct(UnitHealth("player"), UnitHealthMax("player"))
	end,
	targetHp = function()
		if not UnitExists("target") then
			return 100
		end
		return pct(UnitHealth("target"), UnitHealthMax("target"))
	end,
	moving = function()
		return (GetUnitSpeed("player") or 0) > 0
	end,
	combat = function()
		return UnitAffectingCombat("player") and true or false
	end,
	boss = function()
		return UnitLevel("target") == -1 or UnitClassification("target") == "worldboss"
	end,
	group = function()
		return (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0) or false
	end,
	raid = function()
		return (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0) or false
	end,
	pet = function()
		return UnitExists("pet") and not UnitIsDead("pet")
	end,
	cat = function()
		return hasForm("Cat Form")
	end,
	bear = function()
		return hasForm("Bear Form") or hasForm("Dire Bear Form")
	end,
	stealthed = function()
		return IsStealthed() and true or false
	end,
	time = function()
		return combatStart and (GetTime() - combatStart) or 0
	end,
	level = function()
		return UnitLevel("player")
	end,
}

local ENV = setmetatable({}, {
	__index = function(_, k)
		local h = Cond.HELPERS[k]
		if h then
			return h
		end
		local v = Cond.VARS[k]
		if v then
			return v()
		end
		error("unknown word '" .. tostring(k) .. "'", 2)
	end,
	__newindex = function()
		error("conditions cannot assign values", 2)
	end,
})

local BLOCKED = { "function", "while", "repeat", "for", "until", "goto" }

local function always()
	return true
end

function Cond.Compile(expr)
	expr = BC.Util.Trim(expr or "")
	if expr == "" then
		return always
	end
	for _, word in ipairs(BLOCKED) do
		if expr:find("%f[%w_]" .. word .. "%f[^%w_]") then
			return nil, "'" .. word .. "' is not allowed in conditions"
		end
	end
	local fn, err = loadstring("return (" .. expr .. "\n)", "condition")
	if not fn then
		err = tostring(err):gsub('^%[string "condition"%]:%d+: ', "")
		return nil, err
	end
	setfenv(fn, ENV)
	return fn
end

function Cond.Eval(fn)
	local ok, result = pcall(fn)
	if not ok then
		return false, (tostring(result):gsub('^%[string "condition"%]:%d+: ', ""))
	end
	return result and true or false
end
