-- Picks the next ability from the active priority list and predicts when
-- it can be pressed. Raid Mode turns those predictions into notes.
local _, BC = ...

local Compat = BC.Compat
local Cond = BC.Conditions
local Engine = BC:Module("Engine")

Engine.MAX_LANES = 8
Engine.entries = {}
Engine.lanes = {}

function Engine:Class()
	return select(2, UnitClass("player"))
end

function Engine:Tree()
	local override = BC.db.raid.specOverride or 0
	if override > 0 then
		return override
	end
	return Compat.PrimaryTree() or 1
end

-- Returns the stored entries for a class/tree and whether they are custom.
function Engine:GetEntries(class, tree)
	local custom = BC.db.rotations[class] and BC.db.rotations[class][tree]
	if custom then
		return custom, true
	end
	local defaults = BC.RotationDefaults[class] and BC.RotationDefaults[class][tree]
	return defaults or {}, false
end

function Engine:SaveEntries(class, tree, entries)
	BC.db.rotations[class] = BC.db.rotations[class] or {}
	BC.db.rotations[class][tree] = entries
	if class == self:Class() then
		self:Rebuild()
	end
end

function Engine:ResetEntries(class, tree)
	if BC.db.rotations[class] then
		BC.db.rotations[class][tree] = nil
	end
	if class == self:Class() then
		self:Rebuild()
	end
end

function Engine:SpecName(class, tree)
	local names = BC.SpecNames[class]
	return names and names[tree] or ("Tree " .. tostring(tree))
end

function Engine:Rebuild()
	local class, tree = self:Class(), self:Tree()
	self.class, self.tree = class, tree
	local entries = self:GetEntries(class, tree)
	local compiled = {}
	for _, e in ipairs(entries) do
		local fn, err = Cond.Compile(e.cond)
		compiled[#compiled + 1] = {
			spell = e.spell,
			cond = e.cond,
			off = e.off and true or false,
			fn = fn,
			err = err,
		}
	end
	self.entries = compiled

	-- One lane per distinct known spell, in priority order.
	local lanes, laneOf = {}, {}
	for _, c in ipairs(compiled) do
		local key = c.spell and c.spell:lower()
		if key and not laneOf[key] and Compat.IsKnown(c.spell) then
			if #lanes < self.MAX_LANES then
				local _, icon = Compat.SpellInfo(c.spell)
				lanes[#lanes + 1] = { spell = c.spell, icon = icon, off = c.off }
				laneOf[key] = #lanes
			else
				laneOf[key] = (#lanes % self.MAX_LANES) + 1
			end
		end
	end
	self.lanes, self.laneOf = lanes, laneOf
	self.freestyle = BC.db.raid.freestyle or #lanes == 0
	BC:Fire("ROTATION_CHANGED")
end

function Engine:LaneFor(spell)
	return spell and self.laneOf and self.laneOf[spell:lower()]
end

-- End time of the global cooldown (GetTime base); <= now when idle.
function Engine:GCDEnd(now)
	local s, d = Compat.SpellCooldown(61304)
	if s and d and d > 0 and d <= 2 then
		return s + d
	end
	for _, e in ipairs(self.entries) do
		if not e.off and e.spell then
			s, d = Compat.SpellCooldown(e.spell)
			if d and d > 0 and d <= 1.6 then
				return s + d
			end
		end
	end
	return now
end

function Engine:HasEnemyTarget()
	return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
end

-- Returns entry, readyTime for the next ability in the requested stream
-- (on-GCD when offStream is false, off-GCD otherwise), or nil.
function Engine:Next(offStream, now)
	if not self:HasEnemyTarget() then
		return nil
	end
	now = now or GetTime()
	local castEnd = Compat.PlayerCast()
	local base = now
	if not offStream then
		base = math.max(now, self:GCDEnd(now), castEnd or 0)
	end
	local fallback, fallbackReady
	for _, e in ipairs(self.entries) do
		-- skip abilities already queued (Heroic Strike, Maul, Raptor Strike)
		if e.off == offStream and e.fn and Compat.IsKnown(e.spell) and not (offStream and Compat.IsCurrentSpell(e.spell)) then
			local pass, err = Cond.Eval(e.fn)
			e.runtimeErr = err
			if pass and Compat.SpellUsable(e.spell) then
				local s, d = Compat.SpellCooldown(e.spell)
				local cdEnd = (d and d > 0) and (s + d) or now
				local ready = math.max(base, cdEnd)
				if ready <= base + 0.25 then
					return e, ready
				end
				if not fallbackReady or ready < fallbackReady then
					fallback, fallbackReady = e, ready
				end
			end
		end
	end
	if fallback and fallbackReady - now < 4 then
		return fallback, fallbackReady
	end
end

function Engine:OnLogin()
	self:Rebuild()
end

BC:Listen("SPELLBOOK_CHANGED", function()
	Engine:Rebuild()
end)

for _, ev in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
	pcall(BC.On, BC, ev, function()
		if BC.db then
			Engine:Rebuild()
		end
	end)
end
