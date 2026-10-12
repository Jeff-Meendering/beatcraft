local _, BC = ...

local Compat = BC.Compat
local Clock = BC:Module("Clock")

Clock.token = 0

function Clock:Play(path, delay, offsetMs, onFail)
	self:Stop()
	delay = math.max(delay or 0, 0)
	self.token = self.token + 1
	local token = self.token
	self.path = path
	self.offset = offsetMs or 0
	self.startPrecise = Compat.PreciseNow() + delay
	self.startGT = GetTime() + delay
	self.playing = true
	self.failed = false

	local function start()
		if token ~= self.token then
			return
		end
		local late = Compat.PreciseNow() - self.startPrecise
		if late > 0 then
			self.startPrecise = self.startPrecise + late
			self.startGT = self.startGT + late
		end
		local willPlay, handle = Compat.PlayFile(path, BC.db.channel)
		self.handle = handle
		if not willPlay then
			self.failed = true
			if onFail then
				onFail()
			end
		end
	end

	if delay <= 0 then
		start()
	else
		C_Timer.After(delay, start)
	end
end

function Clock:Stop()
	self.token = self.token + 1
	if self.handle then
		Compat.StopSound(self.handle)
		self.handle = nil
	end
	self.playing = false
end

function Clock:Time()
	if not self.startPrecise then
		return 0
	end
	return (Compat.PreciseNow() - self.startPrecise) * 1000 - self.offset
end

function Clock:TimeAt(gt)
	if not self.startGT then
		return 0
	end
	return (gt - self.startGT) * 1000 - self.offset
end

function Clock:GTOf(songMs)
	return self.startGT + (songMs + self.offset) / 1000
end

function Clock:SetOffset(ms)
	self.offset = ms
end
