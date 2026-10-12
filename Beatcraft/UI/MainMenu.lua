-- The hub window opened with /beat or the minimap button.
local _, BC = ...

local U = BC.Util
local W = BC.Widgets
local Menu = BC:Module("MainMenu")

function Menu:Create()
	if self.frame then
		return
	end
	local f = W.Panel("BeatcraftMenu", UIParent, 320, 470, nil)
	f:SetPoint("CENTER", 0, 60)
	self.frame = f

	local logo = f:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(BC.MEDIA .. "logo")
	logo:SetSize(56, 56)
	logo:SetPoint("TOP", 0, -18)
	local title = W.Text(f, 22, "Beatcraft", "OUTLINE")
	title:SetPoint("TOP", logo, "BOTTOM", 0, -6)
	local ver = W.Text(f, 10, "v" .. BC.version)
	ver:SetPoint("TOP", title, "BOTTOM", 0, -2)
	ver:SetTextColor(0.6, 0.6, 0.65)
	local close = W.Button(f, "X", 22, 20, function()
		f:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)

	local y = -132
	local function add(text, onClick, primary)
		local b = W.Button(f, text, 260, 30, onClick, primary)
		b:SetPoint("TOP", 0, y)
		y = y - 36
		return b
	end
	self.play = add("Play songs (Downtime Mode)", function()
		BC.SongSelect:Open()
	end, true)
	self.raid = add("", function()
		BC.RaidMode:SetEnabled(not BC.db.raid.enabled)
		Menu:Refresh()
	end)
	add("Rotation editor", function()
		BC.Editor:Open()
	end)
	self.move = add("", function()
		BC.RaidMode:SetLocked(not BC.db.raid.locked)
		Menu:Refresh()
	end)
	add("Calibrate audio offset", function()
		BC.Calibrate:Open()
	end)
	add("Options", function()
		BC.Options:Open()
	end)

	self.status = W.Text(f, 11, "")
	self.status:SetPoint("TOP", 0, y - 4)
	self.status:SetWidth(280)
	self.status:SetSpacing(3)
	self.status:SetTextColor(0.75, 0.75, 0.8)

	f:SetScript("OnShow", function()
		Menu:Refresh()
	end)
	BC:Listen("RAID_MODE_CHANGED", function()
		if f:IsShown() then
			Menu:Refresh()
		end
	end)
end

function Menu:Refresh()
	local db = BC.db
	self.raid:SetLabel("Raid Mode: " .. (db.raid.enabled and "|cff66ff66ON|r" or "|cffff6666OFF|r"))
	self.raid:SetActive(db.raid.enabled)
	self.move:SetLabel(db.raid.locked and "Move Raid Mode lanes" or "Lock Raid Mode lanes")
	local inCombat = InCombatLockdown()
	if inCombat then
		self.play:Disable()
	else
		self.play:Enable()
	end

	local Engine = BC.Engine
	local lines = {}
	local ok, err = BC.Library:Load()
	if ok then
		lines[#lines + 1] = BC.Library:Count() .. " songs in your library"
	else
		lines[#lines + 1] = "|cffff8080" .. (err or "No songs") .. "|r"
	end
	if Engine.class then
		local spec = Engine:SpecName(Engine.class, Engine.tree) .. " " .. (BC.ClassNames[Engine.class] or "")
		if Engine.freestyle then
			lines[#lines + 1] = spec .. ": Freestyle (cast on the beat)"
		else
			lines[#lines + 1] = spec .. ": " .. #Engine.lanes .. " lanes"
		end
	end
	local last = db.fights[1]
	if last then
		lines[#lines + 1] = string.format("Last fight: %s  %s  %dx", last.grade, U.FormatAcc(last.acc), last.combo)
	end
	self.status:SetText(table.concat(lines, "\n"))
end

function Menu:Toggle()
	self:Create()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
	end
end

function Menu:Hide()
	if self.frame then
		self.frame:Hide()
	end
end
