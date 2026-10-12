local _, BC = ...

local Scoring = BC:Module("Scoring")

local Tally = {}
Tally.__index = Tally

function Scoring.New(modMult)
	return setmetatable({
		score = 0,
		combo = 0,
		maxCombo = 0,
		c300 = 0,
		c100 = 0,
		c50 = 0,
		miss = 0,
		errors = {},
		hp = 1,
		modMult = modMult or 1,
	}, Tally)
end

function Tally:Judge(value, err, noCombo)
	if value >= 300 then
		self.c300 = self.c300 + 1
	elseif value >= 100 then
		self.c100 = self.c100 + 1
	elseif value >= 50 then
		self.c50 = self.c50 + 1
	else
		self.miss = self.miss + 1
	end
	if value > 0 then
		self.score = self.score + math.floor(value * (1 + math.max(self.combo - 1, 0) / 25) * self.modMult)
		if not noCombo then
			self:AddCombo()
		end
	elseif not noCombo then
		self:Break()
	end
	if err then
		local errs = self.errors
		errs[#errs + 1] = err
	end
end

function Tally:AddCombo()
	self.combo = self.combo + 1
	if self.combo > self.maxCombo then
		self.maxCombo = self.combo
	end
end

function Tally:Break()
	self.combo = 0
end

function Tally:Bonus(points)
	self.score = self.score + points
end

function Tally:Total()
	return self.c300 + self.c100 + self.c50 + self.miss
end

function Tally:Accuracy()
	local total = self:Total()
	if total == 0 then
		return 1
	end
	return (300 * self.c300 + 100 * self.c100 + 50 * self.c50) / (300 * total)
end

function Tally:Grade()
	local total = self:Total()
	if total == 0 then
		return "SS"
	end
	local p300, p50 = self.c300 / total, self.c50 / total
	if p300 == 1 then
		return "SS"
	elseif p300 > 0.9 and p50 < 0.01 and self.miss == 0 then
		return "S"
	elseif (p300 > 0.8 and self.miss == 0) or p300 > 0.9 then
		return "A"
	elseif (p300 > 0.7 and self.miss == 0) or p300 > 0.8 then
		return "B"
	elseif p300 > 0.6 then
		return "C"
	end
	return "D"
end

function Tally:ErrorStats()
	local errs = self.errors
	local n = #errs
	if n == 0 then
		return 0, 0
	end
	local sum = 0
	for i = 1, n do
		sum = sum + errs[i]
	end
	local mean = sum / n
	local var = 0
	for i = 1, n do
		var = var + (errs[i] - mean) ^ 2
	end
	return mean, math.sqrt(var / n) * 10
end

function Scoring.Windows(od)
	return 80 - 6 * od, 140 - 8 * od, 200 - 10 * od
end

function Scoring.ModMultiplier(mods)
	local m = 1
	if mods.hr then
		m = m * 1.06
	end
	if mods.hd then
		m = m * 1.06
	end
	if mods.ez then
		m = m * 0.5
	end
	if mods.nf then
		m = m * 0.5
	end
	return m
end

function Scoring.ModString(mods)
	local out = {}
	for _, k in ipairs({ "ez", "nf", "hr", "hd" }) do
		if mods and mods[k] then
			out[#out + 1] = k:upper()
		end
	end
	return table.concat(out, ",")
end

function Scoring.Save(mapKey, tally, mods)
	local list = BC.db.scores[mapKey] or {}
	BC.db.scores[mapKey] = list
	local rec = {
		score = tally.score,
		acc = tally:Accuracy(),
		combo = tally.maxCombo,
		grade = tally:Grade(),
		mods = Scoring.ModString(mods),
		date = time(),
		c300 = tally.c300,
		c100 = tally.c100,
		c50 = tally.c50,
		miss = tally.miss,
	}
	list[#list + 1] = rec
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	while #list > 10 do
		table.remove(list)
	end
	for i, r in ipairs(list) do
		if r == rec then
			return i, rec
		end
	end
	return nil, rec
end

function Scoring.Best(mapKey)
	local list = BC.db.scores[mapKey]
	return list and list[1]
end
