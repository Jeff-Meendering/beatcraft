local _, BC = ...

local Compat = BC.Compat
local W = BC.Widgets
local Clock = BC.Clock
local Beatmap = BC.Beatmap
local Library = BC.Library

local Cal = BC:Module("Calibrate")

local NEEDED = 24
local SKIP = 4
local METRONOME_BEAT = 0.6
local TICK = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856

function Cal:Create()
	if self.frame then
		return
	end
	local f = W.Panel("BeatcraftCalibrate", UIParent, 420, 330, "Calibrate audio offset")
	f:SetPoint("CENTER")
	self.frame = f

	local help = W.Text(f, 12, "Press SPACE (or Z / X / click here) on every beat. Keep going until the bar fills. Use headphones or speakers you normally play with.")
	help:SetPoint("TOPLEFT", 16, -40)
	help:SetPoint("RIGHT", -16, 0)
	help:SetJustifyH("LEFT")
	help:SetSpacing(3)

	self.source = W.Text(f, 11, "")
	self.source:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -8)
	self.source:SetTextColor(0.7, 0.7, 0.75)

	local pulse = f:CreateTexture(nil, "ARTWORK")
	pulse:SetTexture(BC.MEDIA .. "circle")
	pulse:SetSize(70, 70)
	pulse:SetPoint("CENTER", 0, -10)
	pulse:SetVertexColor(BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3])
	self.pulse = pulse

	local barBg = W.Solid(f, "ARTWORK", 0.15, 0.15, 0.21, 1)
	barBg:SetSize(380, 8)
	barBg:SetPoint("BOTTOM", 0, 92)
	self.bar = W.Solid(f, "OVERLAY", BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3], 1)
	self.bar:SetPoint("LEFT", barBg, "LEFT")
	self.bar:SetHeight(8)

	self.result = W.Text(f, 14, "", "OUTLINE")
	self.result:SetPoint("BOTTOM", 0, 62)

	self.apply = W.Button(f, "Apply", 120, 28, function()
		if self.measured then
			BC.db.offset = self.measured
			BC:Print(string.format("Global offset set to %+d ms.", self.measured))
			f:Hide()
		end
	end, true)
	self.apply:SetPoint("BOTTOMRIGHT", -16, 16)
	local restart = W.Button(f, "Restart", 100, 28, function()
		Cal:Start()
	end)
	restart:SetPoint("RIGHT", self.apply, "LEFT", -8, 0)
	local reset = W.Button(f, "Reset to 0", 100, 28, function()
		BC.db.offset = 0
		BC:Print("Global offset reset to 0 ms.")
	end)
	reset:SetPoint("BOTTOMLEFT", 16, 16)

	f:EnableKeyboard(true)
	f:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then
			f:Hide()
		elseif key == "SPACE" or key == "Z" or key == "X" then
			Cal:Tap()
		end
	end)
	f:SetScript("OnMouseDown", function()
		Cal:Tap()
	end)
	f:SetScript("OnShow", function()
		if not InCombatLockdown() then
			f:SetPropagateKeyboardInput(false)
		end
		Cal:Start()
	end)
	f:SetScript("OnHide", function()
		Clock:Stop()
		Cal.running = false
	end)
	f:SetScript("OnUpdate", function()
		Cal:OnUpdate()
	end)
end

function Cal:Open()
	if InCombatLockdown() then
		BC:Print("Calibrate out of combat.")
		return
	end
	BC.Game:Close()
	self:Create()
	self.frame:Show()
end

function Cal:Start()
	self.taps = {}
	self.measured = nil
	self.apply:Disable()
	self.result:SetText("")
	self.bm = nil
	Library:Load()
	local map = BC.db.lastMap and Library:Map(BC.db.lastMap)
	if not map and Library:Count() > 0 then
		map = Library:Random().maps[1]
	end
	if map then
		self.bm = Library:Parse(map)
		self.source:SetText("Song: " .. (map.song.title or "?") .. " (" .. math.floor(Beatmap.BPM(self.bm) + 0.5) .. " BPM)")
		Clock:Play(map.song.audio, 0.5, 0)
	else
		self.source:SetText("No songs imported - using a metronome tick (less accurate for music).")
		self.metroStart = Compat.PreciseNow() + 0.5
		self.nextTick = 0
	end
	self.running = true
end

function Cal:CurrentError()
	if self.bm then
		local _, err = Beatmap.NearestGrid(self.bm, Clock:Time(), 1)
		return err
	end
	local t = (Compat.PreciseNow() - self.metroStart) / METRONOME_BEAT
	return (t - math.floor(t + 0.5)) * METRONOME_BEAT * 1000
end

function Cal:Tap()
	if not self.running then
		return
	end
	local taps = self.taps
	taps[#taps + 1] = self:CurrentError()
	if #taps >= NEEDED then
		self:Finish()
	end
end

function Cal:Finish()
	self.running = false
	Clock:Stop()
	local vals = {}
	for i = SKIP + 1, #self.taps do
		vals[#vals + 1] = self.taps[i]
	end
	table.sort(vals)
	local median = vals[math.floor(#vals / 2) + 1]
	local sum, n = 0, 0
	for _, v in ipairs(vals) do
		if math.abs(v - median) < 120 then
			sum, n = sum + v, n + 1
		end
	end
	if n < 6 then
		self.result:SetText("|cffff8080Taps were too uneven. Try again.|r")
		return
	end
	self.measured = math.floor(sum / n + 0.5)
	self.result:SetText(string.format("Measured offset: |cffffffff%+d ms|r  (current %+d ms)", self.measured, BC.db.offset))
	self.apply:Enable()
end

function Cal:OnUpdate()
	if not self.running then
		self.pulse:SetAlpha(0.3)
		return
	end
	if not self.bm and self.metroStart then
		local now = Compat.PreciseNow()
		local beatTime = self.metroStart + self.nextTick * METRONOME_BEAT
		if now >= beatTime then
			Compat.PlayKit(TICK, BC.db.channel)
			self.nextTick = self.nextTick + 1
		end
	end
	local err = math.abs(self:CurrentError())
	self.pulse:SetAlpha(err < 80 and 1 - err / 80 * 0.7 or 0.3)
	self.bar:SetWidth(math.max(1, 380 * math.min(1, #self.taps / NEEDED)))
end
