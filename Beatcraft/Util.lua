local _, BC = ...

local U = {}
BC.Util = U

local floor = math.floor

function U.Clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function U.Lerp(a, b, t)
	return a + (b - a) * t
end

function U.Round(v)
	return floor(v + 0.5)
end

function U.Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.Split(s, sep)
	local out = {}
	if s == nil or s == "" then
		return out
	end
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
	return out
end

function U.FormatNumber(n)
	local s = tostring(floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

function U.FormatTime(ms)
	if not ms or ms < 0 then
		ms = 0
	end
	local s = floor(ms / 1000)
	return string.format("%d:%02d", floor(s / 60), s % 60)
end

function U.FormatAcc(acc)
	return string.format("%.2f%%", (acc or 0) * 100)
end

function U.CopyTable(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = U.CopyTable(v)
	end
	return out
end

-- osu! default combo colours
U.COMBO_COLORS = {
	{ 1.00, 0.75, 0.00 },
	{ 0.00, 0.79, 0.00 },
	{ 0.07, 0.49, 1.00 },
	{ 0.95, 0.09, 0.22 },
}

U.JUDGE_COLORS = {
	[300] = { 0.4, 0.8, 1.0 },
	[100] = { 0.4, 1.0, 0.4 },
	[50] = { 1.0, 0.8, 0.3 },
	[0] = { 1.0, 0.25, 0.25 },
}

U.GRADE_COLORS = {
	SS = { 1.0, 0.9, 0.4 },
	S = { 1.0, 0.85, 0.2 },
	A = { 0.4, 1.0, 0.4 },
	B = { 0.3, 0.6, 1.0 },
	C = { 0.8, 0.4, 1.0 },
	D = { 1.0, 0.3, 0.3 },
}

-- Simple object pool.
local Pool = {}
Pool.__index = Pool

function U.NewPool(create, reset)
	return setmetatable({ create = create, reset = reset, free = {}, used = {} }, Pool)
end

function Pool:Acquire()
	local obj = table.remove(self.free)
	if not obj then
		obj = self.create()
	end
	self.used[obj] = true
	return obj
end

function Pool:Release(obj)
	if not self.used[obj] then
		return
	end
	self.used[obj] = nil
	if self.reset then
		self.reset(obj)
	end
	table.insert(self.free, obj)
end

function Pool:ReleaseAll()
	for obj in pairs(self.used) do
		self:Release(obj)
	end
end

-- Shortens WoW binding text: "SHIFT-1" -> "S1", "BUTTON4" -> "M4".
function U.ShortKey(key)
	if not key then
		return ""
	end
	key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
	key = key:gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
	key = key:gsub("NUMPAD", "N")
	return key
end
