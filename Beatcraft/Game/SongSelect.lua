local _, BC = ...

local U = BC.Util
local W = BC.Widgets
local Clock = BC.Clock
local Beatmap = BC.Beatmap
local Library = BC.Library
local Scoring = BC.Scoring

local Select = BC:Module("SongSelect")
local ACCENT = BC.ACCENT

local MODS = {
	{ key = "ez", label = "EZ", tip = "Easy: bigger circles, slower approach, looser timing (x0.5 score)" },
	{ key = "nf", label = "NF", tip = "No Fail: you can't fail (x0.5 score)" },
	{ key = "hr", label = "HR", tip = "Hard Rock: smaller circles, faster, stricter, flipped (x1.06)" },
	{ key = "hd", label = "HD", tip = "Hidden: no approach circles, objects fade out (x1.06)" },
}

local function starText(stars)
	return string.format("%.1f*", stars)
end

local function starColor(stars)
	if stars < 2 then
		return 0.4, 0.8, 1
	elseif stars < 3 then
		return 0.4, 1, 0.4
	elseif stars < 4.5 then
		return 1, 0.85, 0.3
	elseif stars < 6 then
		return 1, 0.4, 0.5
	end
	return 0.75, 0.4, 1
end

function Select:Create(root)
	local screen = CreateFrame("Frame", nil, root)
	screen:SetAllPoints()
	screen:Hide()
	self.screen = screen

	local listW = 460
	local right = CreateFrame("Frame", nil, screen)
	right:SetPoint("TOPRIGHT", -24, -24)
	right:SetPoint("BOTTOMRIGHT", -24, 70)
	right:SetWidth(listW)
	right.bg = W.Solid(right, "BACKGROUND", 0.03, 0.03, 0.05, 0.75)
	right.bg:SetAllPoints()
	W.Border(right)

	local search = W.EditBox(right, listW - 20, 26)
	search:SetPoint("TOP", 0, -10)
	search:SetScript("OnTextChanged", function()
		Select:ApplySearch()
	end)
	search:SetScript("OnEnterPressed", function(e)
		e:ClearFocus()
		Select:PlaySelected()
	end)
	search:SetScript("OnEscapePressed", function(e)
		if e:GetText() ~= "" then
			e:SetText("")
		else
			e:ClearFocus()
		end
	end)
	search:SetScript("OnKeyDown", function(e, key)
		if key == "UP" or key == "DOWN" then
			Select:Move(key == "UP" and -1 or 1)
		end
	end)
	self.search = search
	local placeholder = W.Text(search, 12, "Search (just start typing)")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetTextColor(0.5, 0.5, 0.55)
	search:HookScript("OnTextChanged", function(e)
		placeholder:SetShown(e:GetText() == "")
	end)

	local listH = math.max(200, (UIParent:GetHeight() or 768) - 24 - 70 - 46 - 30)
	self.listHolder = right
	local function createRow(parent)
		local row = CreateFrame("Button", nil, parent)
		row.bg = W.Solid(row, "BACKGROUND", 0.1, 0.1, 0.14, 0.9)
		row.bg:SetPoint("TOPLEFT", 0, -2)
		row.bg:SetPoint("BOTTOMRIGHT", 0, 2)
		row.stripe = W.Solid(row, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
		row.stripe:SetPoint("TOPLEFT", 0, -2)
		row.stripe:SetPoint("BOTTOMLEFT", 0, 2)
		row.stripe:SetWidth(4)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(row.bg)
		hl:SetColorTexture(1, 1, 1, 0.06)
		row.title = W.Text(row, 14, "")
		row.title:SetPoint("TOPLEFT", 12, -8)
		row.title:SetPoint("RIGHT", -70, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row.artist = W.Text(row, 11, "")
		row.artist:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
		row.artist:SetPoint("RIGHT", -70, 0)
		row.artist:SetJustifyH("LEFT")
		row.artist:SetWordWrap(false)
		row.artist:SetTextColor(0.75, 0.75, 0.8)
		row.stars = W.Text(row, 11, "")
		row.stars:SetPoint("RIGHT", -10, 6)
		row.flag = W.Text(row, 10, "")
		row.flag:SetPoint("RIGHT", -10, -9)
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", function(self)
			if Select.song == self.song then
				Select:PlaySelected()
			else
				Select:SelectSong(self.song)
			end
		end)
		return row
	end
	local function updateRow(row, song)
		row.song = song
		row.title:SetText(song.title or "?")
		row.artist:SetText((song.artist or "") .. "  //  " .. (song.creator or ""))
		local lo, hi = song.maps[1].stars, song.maps[#song.maps].stars
		row.stars:SetText(#song.maps > 1 and (starText(lo) .. " - " .. starText(hi)) or starText(lo))
		row.stars:SetTextColor(starColor(hi))
		row.flag:SetText(BC.db.playlist[song.id] and "|cffff66aaraid playlist|r" or "")
		local selected = song == Select.song
		row.stripe:SetShown(selected)
		if selected then
			row.bg:SetColorTexture(0.22, 0.12, 0.18, 0.95)
		else
			row.bg:SetColorTexture(0.1, 0.1, 0.14, 0.9)
		end
	end
	self.list = W.ScrollList(right, listW - 20, listH, 46, createRow, updateRow)
	self.list:SetPoint("TOP", search, "BOTTOM", 0, -10)
	self.count = W.Text(right, 11, "")
	self.count:SetPoint("BOTTOMLEFT", 10, 8)
	self.count:SetTextColor(0.6, 0.6, 0.65)

	local left = CreateFrame("Frame", nil, screen)
	left:SetPoint("TOPLEFT", 24, -24)
	left:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -24, 0)
	self.left = left

	local logo = left:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(BC.MEDIA .. "logo")
	logo:SetSize(40, 40)
	logo:SetPoint("TOPLEFT")
	local brand = W.Text(left, 20, "Beatcraft", "OUTLINE")
	brand:SetPoint("LEFT", logo, "RIGHT", 10, 0)

	self.title = W.Text(left, 30, "", "OUTLINE")
	self.title:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -30)
	self.title:SetPoint("RIGHT")
	self.title:SetJustifyH("LEFT")
	self.title:SetWordWrap(false)
	self.artist = W.Text(left, 18, "", "OUTLINE")
	self.artist:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
	self.artist:SetTextColor(0.85, 0.85, 0.9)
	self.mapper = W.Text(left, 12, "", "OUTLINE")
	self.mapper:SetPoint("TOPLEFT", self.artist, "BOTTOMLEFT", 0, -6)
	self.mapper:SetTextColor(0.7, 0.7, 0.75)

	self.diffButtons = {}
	for i = 1, 10 do
		local b = W.Button(left, "", 120, 40, function(btn)
			Select:SelectMap(btn.map)
		end)
		b.text:ClearAllPoints()
		b.text:SetPoint("TOP", 0, -6)
		b.stars = W.Text(b, 11, "")
		b.stars:SetPoint("BOTTOM", 0, 6)
		local col = (i - 1) % 5
		local rowI = math.floor((i - 1) / 5)
		b:SetPoint("TOPLEFT", self.mapper, "BOTTOMLEFT", col * 126, -24 - rowI * 46)
		self.diffButtons[i] = b
	end

	self.stats = W.Text(left, 14, "", "OUTLINE")
	self.stats:SetPoint("TOPLEFT", self.mapper, "BOTTOMLEFT", 0, -130)
	self.stats:SetJustifyH("LEFT")
	self.stats:SetSpacing(4)

	local modLabel = W.Text(left, 12, "Mods", "OUTLINE")
	modLabel:SetPoint("TOPLEFT", self.stats, "BOTTOMLEFT", 0, -20)
	self.modButtons = {}
	for i, m in ipairs(MODS) do
		local b = W.Button(left, m.label, 52, 28, function(btn)
			Select:ToggleMod(m.key)
		end)
		b:SetPoint("TOPLEFT", modLabel, "BOTTOMLEFT", (i - 1) * 58, -6)
		W.Tooltip(b, m.label, m.tip)
		self.modButtons[m.key] = b
	end

	self.best = W.Text(left, 13, "", "OUTLINE")
	self.best:SetPoint("TOPLEFT", modLabel, "BOTTOMLEFT", 0, -50)
	self.best:SetJustifyH("LEFT")
	self.best:SetSpacing(3)
	self.guild = W.Text(left, 12, "", "OUTLINE")
	self.guild:SetPoint("TOPLEFT", self.best, "BOTTOMLEFT", 0, -14)
	self.guild:SetJustifyH("LEFT")
	self.guild:SetSpacing(3)

	local bar = CreateFrame("Frame", nil, screen)
	bar:SetPoint("BOTTOMLEFT", 24, 18)
	bar:SetPoint("BOTTOMRIGHT", -24, 18)
	bar:SetHeight(40)
	self.playButton = W.Button(bar, "PLAY", 180, 40, function()
		Select:PlaySelected()
	end, true)
	self.playButton.text:SetFont(W.FONT, 16, "OUTLINE")
	self.playButton:SetPoint("RIGHT")
	local random = W.Button(bar, "Random (F2)", 120, 40, function()
		Select:RandomSong()
	end)
	random:SetPoint("RIGHT", self.playButton, "LEFT", -10, 0)
	self.playlistButton = W.Button(bar, "", 170, 40, function()
		Select:TogglePlaylist()
	end)
	self.playlistButton:SetPoint("RIGHT", random, "LEFT", -10, 0)
	W.Tooltip(self.playlistButton, "Raid playlist", "Songs in the raid playlist play during pulls in Raid Mode (when the playlist option is selected).")
	local back = W.Button(bar, "Close (Esc)", 120, 40, function()
		BC.Game:Close()
	end)
	back:SetPoint("LEFT")
	local options = W.Button(bar, "Options", 100, 40, function()
		BC.Options:Open()
	end)
	options:SetPoint("LEFT", back, "RIGHT", 10, 0)
	local hint = W.Text(bar, 11, "Enter play   Up/Down song   Left/Right difficulty   F2 random   type to search", "OUTLINE")
	hint:SetPoint("LEFT", options, "RIGHT", 16, 0)
	hint:SetTextColor(0.65, 0.65, 0.7)

	self.empty = W.Text(screen, 16, "", "OUTLINE")
	self.empty:SetPoint("CENTER", left, "CENTER")
	self.empty:SetWidth(520)
	self.empty:SetSpacing(6)
end

function Select:Open()
	if not BC.Game:Open() then
		return
	end
	BC.Game:Show(self)
end

function Select:Enter()
	self.screen:Show()
	self.mods = self.mods or U.CopyTable(BC.db.game.mods)

	local ok, err = Library:Load()
	BC.Game:SetDim(BC.db.game.dim * 0.8)
	if not ok or Library:Count() == 0 then
		self.left:Hide()
		self.empty:SetText(ok and "Your song library is empty.\n\nDrop .osz files into the Import folder (or point it at your osu! Songs folder) and run 'Beatcraft Manager.bat', then restart WoW." or err)
		self.empty:Show()
		self.list:SetData({})
		self.count:SetText("0 songs")
		BC.Game:SetBackground(nil)
		self.playButton:Disable()
		return
	end
	self.empty:Hide()
	self.left:Show()
	self.playButton:Enable()
	self:ApplySearch()
	local song = self.song or (BC.db.lastSong and Library:Get(BC.db.lastSong)) or Library.songs[1]
	self:SelectSong(song, BC.db.lastMap)
	self:RefreshMods()
end

function Select:Leave()
	self.search:ClearFocus()
	Clock:Stop()
	self.screen:Hide()
end

function Select:ApplySearch()
	if not Library.loaded then
		return
	end
	self.results = Library:Search(self.search:GetText())
	self.list:SetData(self.results)
	self.count:SetText(#self.results .. " / " .. Library:Count() .. " songs")
	self:EnsureVisible()
end

function Select:EnsureVisible()
	if not self.results or not self.song then
		return
	end
	for i, s in ipairs(self.results) do
		if s == self.song then
			self.list:ScrollTo(i)
			return
		end
	end
	self.list:Refresh()
end

function Select:SelectSong(song, mapKey)
	if not song then
		return
	end
	local changed = song ~= self.song
	self.song = song
	BC.db.lastSong = song.id
	local map = song.maps[1]
	for _, m in ipairs(song.maps) do
		if m.key == mapKey or (not mapKey and self.map and m.version == self.map.version) then
			map = m
		end
	end
	self.title:SetText(song.title or "?")
	self.artist:SetText(song.artist or "")
	self.mapper:SetText("mapped by " .. (song.creator or "?") .. ((song.source and song.source ~= "") and ("  -  " .. song.source) or ""))
	for i, b in ipairs(self.diffButtons) do
		local m = song.maps[i]
		if m then
			b.map = m
			b:SetLabel(m.version or "?")
			b.stars:SetText(starText(m.stars))
			b.stars:SetTextColor(starColor(m.stars))
			b:Show()
		else
			b:Hide()
		end
	end
	BC.Game:SetBackground(song.bg)
	self:SelectMap(map)
	self:EnsureVisible()
	self.playlistButton:SetLabel(BC.db.playlist[song.id] and "In raid playlist" or "Add to raid playlist")
	self.playlistButton:SetActive(BC.db.playlist[song.id] and true or false)
	if changed then
		self:SchedulePreview(song)
	end
end

function Select:SchedulePreview(song)
	self.previewToken = (self.previewToken or 0) + 1
	local token = self.previewToken
	Clock:Stop()
	C_Timer.After(0.3, function()
		if token == self.previewToken and BC.Game.screen == self then
			Clock:Play(song.preview or song.audio, 0, 0)
		end
	end)
end

function Select:SelectMap(map)
	if not map then
		return
	end
	self.map = map
	BC.db.lastMap = map.key
	for _, b in ipairs(self.diffButtons) do
		b:SetActive(b.map == map)
	end
	self:RefreshStats()
end

function Select:RefreshStats()
	local map = self.map
	if not map then
		return
	end
	local ar, od, cs, hp = Beatmap.ModdedStats(map, self.mods)
	local lines = {
		string.format("Length |cffffffff%s|r     BPM |cffffffff%d|r     Objects |cffffffff%d|r", U.FormatTime(map.len), math.floor((map.bpm or 0) + 0.5), map.n or 0),
		string.format("CS |cffffffff%.1f|r   AR |cffffffff%.1f|r   OD |cffffffff%.1f|r   HP |cffffffff%.1f|r   Stars |cffffffff~%.1f|r", cs, ar, od, hp, map.stars),
	}
	self.stats:SetText(table.concat(lines, "\n"))
	self.stats:SetTextColor(0.75, 0.75, 0.8)

	local scores = BC.db.scores[map.key]
	if scores and #scores > 0 then
		local out = { "|cff" .. BC.ACCENT_HEX .. "Your best|r" }
		for i = 1, math.min(5, #scores) do
			local s = scores[i]
			local c = U.GRADE_COLORS[s.grade] or U.GRADE_COLORS.D
			out[#out + 1] = string.format("|cff%02x%02x%02x%s|r  %s   %s   %dx %s", c[1] * 255, c[2] * 255, c[3] * 255, s.grade, U.FormatNumber(s.score), U.FormatAcc(s.acc), s.combo, s.mods ~= "" and ("+" .. s.mods) or "")
		end
		self.best:SetText(table.concat(out, "\n"))
	else
		self.best:SetText("|cff888888No scores yet on this difficulty.|r")
	end
	self.guild:SetText(BC.Guild:FormatTop(map.key, 5))
end

function Select:ToggleMod(key)
	self.mods[key] = not self.mods[key] or nil
	if key == "hr" and self.mods.hr then
		self.mods.ez = nil
	elseif key == "ez" and self.mods.ez then
		self.mods.hr = nil
	end
	BC.db.game.mods = U.CopyTable(self.mods)
	self:RefreshMods()
	self:RefreshStats()
end

function Select:RefreshMods()
	for key, b in pairs(self.modButtons) do
		b:SetActive(self.mods[key] and true or false)
	end
end

function Select:TogglePlaylist()
	if not self.song then
		return
	end
	local id = self.song.id
	BC.db.playlist[id] = not BC.db.playlist[id] or nil
	self:SelectSong(self.song, self.map and self.map.key)
	self.list:Refresh()
end

function Select:Move(delta)
	local results = self.results
	if not results or #results == 0 then
		return
	end
	local idx = 1
	for i, s in ipairs(results) do
		if s == self.song then
			idx = i
			break
		end
	end
	idx = U.Clamp(idx + delta, 1, #results)
	self:SelectSong(results[idx])
end

function Select:MoveDiff(delta)
	if not self.song or not self.map then
		return
	end
	for i, m in ipairs(self.song.maps) do
		if m == self.map then
			local n = self.song.maps[U.Clamp(i + delta, 1, #self.song.maps)]
			self:SelectMap(n)
			return
		end
	end
end

function Select:RandomSong()
	local pool = self.results and #self.results > 0 and self.results or Library.songs
	if #pool > 0 then
		self:SelectSong(pool[math.random(#pool)])
	end
end

function Select:PlaySelected()
	if not self.map then
		return
	end
	BC.Game:Show(BC.Play, self.map, U.CopyTable(self.mods))
end

local TYPEABLE = "^[A-Z0-9]$"

function Select:OnKey(key, down)
	if not down then
		return
	end
	if key == "ESCAPE" then
		BC.Game:Close()
	elseif key == "UP" or key == "DOWN" then
		self:Move(key == "UP" and -1 or 1)
	elseif key == "PAGEUP" or key == "PAGEDOWN" then
		self:Move(key == "PAGEUP" and -8 or 8)
	elseif key == "LEFT" or key == "RIGHT" then
		self:MoveDiff(key == "LEFT" and -1 or 1)
	elseif key == "ENTER" then
		self:PlaySelected()
	elseif key == "F2" then
		self:RandomSong()
	elseif key == "BACKSPACE" then
		local t = self.search:GetText()
		self.search:SetText(t:sub(1, -2))
	elseif key:match(TYPEABLE) or key == "SPACE" then
		self.search:SetFocus()
		self.search:Insert(key == "SPACE" and " " or key:lower())
	end
end

function Select:OnWheel(delta)
	self.list.offset = self.list.offset - delta * 3
	self.list:Refresh()
end
