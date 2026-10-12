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
	local scale = math.min(root:GetWidth() / 1440, root:GetHeight() / 900)
	screen:SetScale(scale)
	screen:Hide()
	self.screen = screen
	local width, height = root:GetWidth() / scale, root:GetHeight() / scale
	local listW = math.min(820, width * 0.57)
	local leftW = width - listW - 70
	local function label(parent, size, value, point, x, y, w)
		local t = W.Text(parent, size, value, "OUTLINE")
		t:SetPoint(point, x, y)
		t:SetJustifyH("LEFT")
		if w then t:SetWidth(w); t:SetWordWrap(false) end
		return t
	end
	local top = CreateFrame("Frame", nil, screen)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(150)
	local bg = W.Solid(top, "BACKGROUND", 0.025, 0.025, 0.045, 0.88)
	bg:SetAllPoints()
	local stripe = W.Solid(top, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	stripe:SetPoint("BOTTOMLEFT")
	stripe:SetPoint("BOTTOMRIGHT")
	stripe:SetHeight(2)
	self.title = label(top, 30, "Select a beatmap", "TOPLEFT", 30, -20, width * 0.58)
	self.artist = label(top, 16, "", "TOPLEFT", 32, -58, width * 0.58)
	self.mapper = label(top, 13, "", "TOPLEFT", 32, -83, width * 0.58)
	self.mapper:SetTextColor(0.72, 0.75, 0.82)
	self.stats = label(top, 13, "", "TOPLEFT", 32, -108, width * 0.72)
	self.stats:SetTextColor(0.8, 0.83, 0.9)
	label(top, 13, "BEATCRAFT  /  osu!standard", "TOPRIGHT", -30, -24):SetTextColor(1, 0.65, 0.8)
	local right = CreateFrame("Frame", nil, screen)
	right:SetPoint("TOPRIGHT", -20, -170)
	right:SetPoint("BOTTOMRIGHT", -20, 130)
	right:SetWidth(listW)
	self.listHolder = right
	local search = W.EditBox(right, listW - 40, 30)
	search:SetPoint("TOPRIGHT", -10, 0)
	search:SetScript("OnTextChanged", function() Select:ApplySearch() end)
	search:SetScript("OnEnterPressed", function(e) e:ClearFocus(); Select:PlaySelected() end)
	search:SetScript("OnEscapePressed", function(e)
		if e:GetText() ~= "" then e:SetText("") else e:ClearFocus() end
	end)
	search:SetScript("OnKeyDown", function(_, key)
		if key == "UP" or key == "DOWN" then Select:MoveDiff(key == "UP" and -1 or 1) end
	end)
	self.search = search
	local placeholder = label(search, 13, "Type to search your beatmaps...", "LEFT", 10, 0)
	placeholder:SetTextColor(0.55, 0.59, 0.68)
	search:HookScript("OnTextChanged", function(e) placeholder:SetShown(e:GetText() == "") end)
	self.count = label(right, 12, "", "TOPRIGHT", -12, -38)
	self.count:SetTextColor(0.68, 0.71, 0.79)
	local function createRow(parent)
		local row = CreateFrame("Button", nil, parent)
		row.bg = W.Solid(row, "BACKGROUND", 0.08, 0.12, 0.2, 0.95)
		row.bg:SetPoint("TOPLEFT", 0, -3)
		row.bg:SetPoint("BOTTOMRIGHT", 0, 3)
		row.stripe = W.Solid(row, "ARTWORK", 1, 1, 1, 1)
		row.stripe:SetPoint("TOPLEFT", 0, -3)
		row.stripe:SetPoint("BOTTOMLEFT", 0, 3)
		row.stripe:SetWidth(4)
		row.cover = row:CreateTexture(nil, "ARTWORK")
		row.cover:SetSize(90, 60)
		row.cover:SetPoint("LEFT", 8, 0)
		row.cover:SetTexCoord(0.125, 0.875, 0, 1)
		row.cover:SetAlpha(0.6)
		row.icon = row:CreateTexture(nil, "OVERLAY")
		row.icon:SetTexture(BC.MEDIA .. "ring")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 108, 0)
		row.title = label(row, 18, "", "TOPLEFT", 150, -10)
		row.artist = label(row, 12, "", "TOPLEFT", 150, -35)
		row.artist:SetTextColor(0.73, 0.78, 0.88)
		row.stars = label(row, 13, "", "RIGHT", -16, 7)
		row.flag = label(row, 10, "", "RIGHT", -16, -14)
		local hl = W.Solid(row, "HIGHLIGHT", 1, 1, 1, 0.1)
		hl:SetAllPoints(row.bg)
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", function(self)
			if self.entry.map then Select:SelectMap(self.entry.map) else Select:SelectSong(self.entry.song) end
		end)
		row:SetScript("OnDoubleClick", function(self)
			if self.entry.map then Select:SelectMap(self.entry.map) end
			Select:PlaySelected()
		end)
		return row
	end
	local function updateRow(row, entry, index)
		row.entry = entry
		local song, map = entry.song, entry.map
		local selected = map and map == Select.map
		local indent = selected and 0 or map and 34 or 68
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", indent, -(index - Select.list.offset - 1) * 72)
		row:SetWidth(listW - indent - 12)
		row.cover:SetTexture(song.bg)
		row.cover:SetShown(song.bg ~= nil)
		row.title:SetWidth(listW - indent - 265)
		row.artist:SetWidth(listW - indent - 265)
		local stars = map and map.stars or song.maps[#song.maps].stars
		local r, g, b = starColor(stars)
		row.icon:SetVertexColor(r, g, b)
		row.stripe:SetColorTexture(r, g, b, 1)
		row.title:SetText(map and (map.version or "Normal") or (song.title or "?"))
		row.artist:SetText(map and ((song.title or "") .. "  /  " .. (song.creator or "")) or (song.artist or ""))
		row.stars:SetText(map and string.format("~%.1f *", stars) or #song.maps .. " difficulties")
		row.stars:SetTextColor(r, g, b)
		row.flag:SetText(selected and "SELECTED" or BC.db.playlist[song.id] and "RAID PLAYLIST" or "")
		row.flag:SetTextColor(1, 0.75, 0.85)
		if selected then row.bg:SetColorTexture(0.6, 0.19, 0.37, 0.96)
		elseif map then row.bg:SetColorTexture(0.13, 0.22, 0.35, 0.94)
		else row.bg:SetColorTexture(0.07, 0.1, 0.17, 0.9) end
	end
	self.list = W.ScrollList(right, listW, height - 368, 72, createRow, updateRow)
	self.list:SetPoint("TOPRIGHT", 0, -64)
	local left = CreateFrame("Frame", nil, screen)
	left:SetPoint("TOPLEFT", 30, -182)
	left:SetSize(leftW, height - 320)
	self.left = left
	self.cover = left:CreateTexture(nil, "BACKGROUND")
	self.cover:SetPoint("TOPLEFT")
	self.cover:SetSize(leftW, 150)
	self.cover:SetTexCoord(0, 1, 0.2, 0.8)
	self.cover:SetAlpha(0.55)
	local coverDim = W.Solid(left, "BORDER", 0.025, 0.025, 0.045, 0.3)
	coverDim:SetAllPoints(self.cover)
	self.difficulty = label(left, 24, "", "TOPLEFT", 18, -30, leftW - 36)
	self.rating = label(left, 16, "", "TOPLEFT", 18, -68, leftW - 36)
	self.detail = label(left, 13, "", "TOPLEFT", 18, -104, leftW - 36)
	label(left, 18, "LOCAL RANKING", "TOPLEFT", 0, -178):SetTextColor(0.85, 0.88, 0.95)
	local divider = W.Solid(left, "ARTWORK", 1, 1, 1, 0.13)
	divider:SetPoint("TOPLEFT", 0, -206)
	divider:SetSize(leftW, 1)
	self.best = label(left, 15, "", "TOPLEFT", 0, -224, leftW)
	self.best:SetWordWrap(true)
	self.best:SetSpacing(10)
	self.guild = label(left, 13, "", "BOTTOMLEFT", 0, 8, leftW)
	self.guild:SetWordWrap(true)
	self.guild:SetSpacing(4)
	self.guild:SetTextColor(0.63, 0.68, 0.78)
	local bar = CreateFrame("Frame", nil, screen)
	bar:SetPoint("BOTTOMLEFT")
	bar:SetPoint("BOTTOMRIGHT")
	bar:SetHeight(110)
	local barBg = W.Solid(bar, "BACKGROUND", 0.025, 0.025, 0.045, 0.95)
	barBg:SetAllPoints()
	local back = W.Button(bar, "<  BACK", 130, 48, function() BC.Game:Close() end, true)
	back:SetPoint("BOTTOMLEFT", 24, 22)
	self.modButtons = {}
	for i, m in ipairs(MODS) do
		local b = W.Button(bar, m.label, 48, 44, function() Select:ToggleMod(m.key) end)
		b:SetPoint("BOTTOMLEFT", 188 + (i - 1) * 54, 24)
		W.Tooltip(b, m.label, m.tip)
		self.modButtons[m.key] = b
	end
	label(bar, 11, "MODS", "BOTTOMLEFT", 188, 76):SetTextColor(0.6, 0.65, 0.75)
	local random = W.Button(bar, "RANDOM  F2", 120, 44, function() Select:RandomSong() end)
	random:SetPoint("BOTTOMLEFT", 428, 24)
	local options = W.Button(bar, "OPTIONS", 100, 44, function() BC.Options:Open() end)
	options:SetPoint("LEFT", random, "RIGHT", 8, 0)
	self.playlistButton = W.Button(bar, "RAID PLAYLIST", 130, 44, function() Select:TogglePlaylist() end)
	self.playlistButton:SetPoint("LEFT", options, "RIGHT", 8, 0)
	label(bar, 11, "Enter play  /  arrows browse  /  type to search", "BOTTOM", 40, 8):SetTextColor(0.5, 0.55, 0.65)
	self.playButton = CreateFrame("Button", nil, bar)
	self.playButton:SetSize(132, 132)
	self.playButton:SetPoint("BOTTOMRIGHT", -36, 8)
	self.playButton.ring = self.playButton:CreateTexture(nil, "BACKGROUND")
	self.playButton.ring:SetTexture(BC.MEDIA .. "circle")
	self.playButton.ring:SetAllPoints()
	self.playButton.ring:SetVertexColor(1, 0.35, 0.62)
	local rim = self.playButton:CreateTexture(nil, "BORDER")
	rim:SetTexture(BC.MEDIA .. "circleoverlay")
	rim:SetAllPoints()
	local playText = W.Text(self.playButton, 28, "PLAY", "OUTLINE")
	playText:SetPoint("CENTER", 0, 3)
	self.playButton:SetScript("OnClick", function() Select:PlaySelected() end)
	self.playButton:SetScript("OnEnter", function(b) b.ring:SetVertexColor(1, 0.55, 0.75) end)
	self.playButton:SetScript("OnLeave", function(b) b.ring:SetVertexColor(1, 0.35, 0.62) end)
	self.empty = label(screen, 18, "", "CENTER", 0, 30, 500)
	self.empty:SetWordWrap(true)
	self.empty:SetSpacing(8)
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
	if not ok or Library:Count() == 0 then
		self.left:Hide()
		self.empty:SetText(ok and "Your song library is empty.\n\nDrop .osz files into the Import folder (or point it at your osu! Songs folder) and run 'Beatcraft Manager.bat', then restart WoW." or err)
		self.empty:Show()
		self.list:SetData({})
		self.count:SetText("0 songs")
		BC.Game:ApplyBackground(nil, "select")
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
	self.previewToken = (self.previewToken or 0) + 1
	self.search:ClearFocus()
	Clock:Stop()
	self.screen:Hide()
end

function Select:ApplySearch()
	if not Library.loaded then
		return
	end
	self.results = Library:Search(self.search:GetText())
	self:RefreshDiffs()
	self:EnsureVisible()
end

function Select:EnsureVisible()
	if self.selectedIndex then
		self.list.offset = U.Clamp(self.selectedIndex - math.ceil(self.list.numRows / 2), 0, math.max(0, #self.list.data - self.list.numRows))
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
	self.cover:SetTexture(song.bg)
	self.title:SetText(song.title or "?")
	self.artist:SetText(song.artist or "")
	self.mapper:SetText("mapped by " .. (song.creator or "?") .. ((song.source and song.source ~= "") and ("  -  " .. song.source) or ""))
	BC.Game:ApplyBackground(song.bg, "select")
	self:SelectMap(map)
	self:EnsureVisible()
	self.playlistButton:SetLabel(BC.db.playlist[song.id] and "IN RAID PLAYLIST" or "RAID PLAYLIST")
	self.playlistButton:SetActive(BC.db.playlist[song.id] and true or false)
	if changed or not Clock.playing then self:SchedulePreview(song) end
end

function Select:RefreshDiffs()
	local entries, maps = {}, 0
	self.selectedIndex = nil
	for _, song in ipairs(self.results or {}) do
		entries[#entries + 1] = { song = song }
		maps = maps + #song.maps
		if song == self.song then
			for _, map in ipairs(song.maps) do
				entries[#entries + 1] = { song = song, map = map }
				if map == self.map then self.selectedIndex = #entries end
			end
		end
	end
	self.list:SetData(entries)
	self.count:SetText(string.format("%d songs  /  %d difficulties", #(self.results or {}), maps))
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
	self:RefreshDiffs()
	self:EnsureVisible()
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
	self.stats:SetText(table.concat(lines, "   /   "))
	self.difficulty:SetText(map.version or "Normal")
	self.rating:SetText(string.format("~%.1f stars", map.stars))
	self.rating:SetTextColor(starColor(map.stars))
	self.detail:SetText("osu!standard  /  " .. U.FormatTime(map.len) .. "  /  " .. math.floor(map.bpm or 0) .. " BPM")
	self.stats:SetTextColor(0.75, 0.75, 0.8)

	local scores = BC.db.scores[map.key]
	if scores and #scores > 0 then
		local out = {}
		for i = 1, math.min(5, #scores) do
			local s = scores[i]
			local c = U.GRADE_COLORS[s.grade] or U.GRADE_COLORS.D
			out[#out + 1] = string.format("|cff%02x%02x%02x%s|r  %s   %s   %dx %s", c[1] * 255, c[2] * 255, c[3] * 255, s.grade, U.FormatNumber(s.score), U.FormatAcc(s.acc), s.combo, s.mods ~= "" and ("+" .. s.mods) or "")
		end
		self.best:SetText(table.concat(out, "\n"))
	else
		self.best:SetText("|cffd5dbeaNo records set!|r\n|cff81899bComplete this difficulty to set your first score.|r")
	end
	self.guild:SetText(BC.Guild:FormatTop(map.key, 3))
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
	self.search:ClearFocus()
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
