local _, BC = ...

local Compat = {}
BC.Compat = Compat

local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_AddOns = C_AddOns
local C_ChatInfo = C_ChatInfo
local C_SpellBook = C_SpellBook

local GetTime = GetTime
local precise = GetTimePreciseSec

function Compat.Now()
	return GetTime()
end

function Compat.PreciseNow()
	if precise then
		return precise()
	end
	return GetTime()
end

function Compat.StripRank(name)
	if type(name) ~= "string" then
		return name
	end
	return (name:gsub("%s*%([Rr]ank%s*%d+%)%s*$", ""))
end

function Compat.SpellInfo(spell)
	if spell == nil or spell == "" then
		return
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spell)
		if ok and type(info) == "table" and info.name then
			return info.name, info.iconID, (info.castTime or 0) / 1000, info.spellID
		end
	end
	if GetSpellInfo then
		local ok, name, _, icon, castTime, _, _, id = pcall(GetSpellInfo, spell)
		if ok and name then
			return name, icon, (castTime or 0) / 1000, id
		end
	end
end

local knownSpells = {}
local spellbookScanned = false

local function addKnown(name)
	if type(name) == "string" and name ~= "" then
		knownSpells[Compat.StripRank(name):lower()] = true
	end
end

local function scanModernSpellbook()
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
		if line then
			local first = (line.itemIndexOffset or 0) + 1
			local last = (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0)
			for j = first, last do
				local info = C_SpellBook.GetSpellBookItemInfo(j, bank)
				if info then
					addKnown(info.name)
				end
			end
		end
	end
end

local function scanClassicSpellbook()
	local book = BOOKTYPE_SPELL or "spell"
	for tab = 1, (GetNumSpellTabs and GetNumSpellTabs() or 0) do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for j = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
			local name
			if GetSpellBookItemName then
				name = GetSpellBookItemName(j, book)
			elseif GetSpellName then
				name = GetSpellName(j, book)
			end
			addKnown(name)
		end
	end
end

function Compat.RebuildSpellbook()
	wipe(knownSpells)
	local ok
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		ok = pcall(scanModernSpellbook)
	end
	if not ok or not next(knownSpells) then
		pcall(scanClassicSpellbook)
	end
	spellbookScanned = next(knownSpells) ~= nil
end

function Compat.IsKnown(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	if spellbookScanned then
		return knownSpells[Compat.StripRank(name):lower()] == true
	end
	return Compat.SpellInfo(name) ~= nil
end

function Compat.SpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, cd = pcall(C_Spell.GetSpellCooldown, spell)
		if ok and type(cd) == "table" then
			return cd.startTime or 0, cd.duration or 0
		end
	end
	if GetSpellCooldown then
		local ok, start, duration = pcall(GetSpellCooldown, spell)
		if ok then
			return start or 0, duration or 0
		end
	end
	return 0, 0
end

function Compat.SpellUsable(spell)
	if C_Spell and C_Spell.IsSpellUsable then
		local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, spell)
		if ok then
			return usable, noPower
		end
	end
	if IsUsableSpell then
		local ok, usable, noPower = pcall(IsUsableSpell, spell)
		if ok then
			return usable, noPower
		end
	end
	return true, false
end

function Compat.IsCurrentSpell(spell)
	local fn = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
	if not fn then
		return false
	end
	local ok, r = pcall(fn, spell)
	return ok and r and true or false
end

function Compat.SpellInRange(spell, unit)
	local fn = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
	if not fn then
		return nil
	end
	local ok, r = pcall(fn, spell, unit or "target")
	if not ok or r == nil then
		return nil
	end
	return r == true or r == 1
end

function Compat.FindAura(unit, name, filter)
	if type(name) ~= "string" or not UnitExists(unit) then
		return 0, 0
	end
	local want = name:lower()
	local now = GetTime()
	for i = 1, 40 do
		local auraName, count, expires
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
			if not a then
				break
			end
			auraName, count, expires = a.name, a.applications, a.expirationTime
		elseif UnitAura then
			local n, _, c, _, _, e = UnitAura(unit, i, filter)
			if not n then
				break
			end
			auraName, count, expires = n, c, e
		else
			break
		end
		if auraName and auraName:lower() == want then
			local remaining = 999
			if expires and expires > 0 then
				remaining = math.max(expires - now, 0.01)
			end
			if not count or count < 1 then
				count = 1
			end
			return remaining, count
		end
	end
	return 0, 0
end

function Compat.PrimaryTree()
	if not GetNumTalentTabs or not GetTalentTabInfo then
		return nil
	end
	local best, bestPoints = nil, 0
	for i = 1, GetNumTalentTabs() do
		local r = { GetTalentTabInfo(i) }
		local points
		if type(r[1]) == "number" then
			points = r[5]
		else
			points = r[3]
		end
		if type(points) == "number" and points > bestPoints then
			best, bestPoints = i, points
		end
	end
	return best
end

function Compat.PlayerCast()
	if UnitCastingInfo then
		local name, _, _, _, endMS = UnitCastingInfo("player")
		if name and endMS then
			return endMS / 1000, name, false
		end
	end
	if UnitChannelInfo then
		local name, _, _, _, endMS = UnitChannelInfo("player")
		if name and endMS then
			return endMS / 1000, name, true
		end
	end
end

function Compat.ComboPoints()
	if GetComboPoints then
		return GetComboPoints("player", "target") or 0
	end
	return UnitPower("player", 4) or 0
end

function Compat.ActionSpellName(slot)
	if not GetActionInfo then
		return
	end
	local kind, id = GetActionInfo(slot)
	if kind == "spell" then
		return (Compat.SpellInfo(id))
	elseif kind == "macro" and GetMacroSpell then
		local s = GetMacroSpell(id)
		if type(s) == "number" then
			return (Compat.SpellInfo(s))
		elseif type(s) == "string" then
			return Compat.StripRank(s)
		end
	end
end

function Compat.LoadAddOn(name)
	local fn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if not fn then
		return false, "MISSING"
	end
	return fn(name)
end

function Compat.IsAddOnLoaded(name)
	local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return fn and fn(name)
end

function Compat.RegisterPrefix(prefix)
	local fn = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
	if fn then
		fn(prefix)
	end
end

function Compat.SendAddonMessage(prefix, msg, channel, target)
	local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if fn then
		pcall(fn, prefix, msg, channel, target)
	end
end

function Compat.PlayFile(path, channel)
	local ok, willPlay, handle = pcall(PlaySoundFile, path, channel or "Master")
	if ok then
		return willPlay, handle
	end
	return false
end

function Compat.StopSound(handle)
	if handle and StopSound then
		pcall(StopSound, handle)
	end
end

function Compat.PlayKit(id, channel)
	if id and PlaySound then
		pcall(PlaySound, id, channel or "SFX")
	end
end
