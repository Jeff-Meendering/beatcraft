local _, BC = ...

local U = BC.Util
local W = BC.Widgets

local Results = BC:Module("Results")

function Results:Create(root)
	local screen = CreateFrame("Frame", nil, root)
	screen:SetAllPoints()
	screen:Hide()
	self.screen = screen

	local panel = CreateFrame("Frame", nil, screen)
	panel:SetSize(820, 460)
	panel:SetPoint("CENTER")
	panel.bg = W.Solid(panel, "BACKGROUND", 0.03, 0.03, 0.05, 0.85)
	panel.bg:SetAllPoints()
	W.Border(panel, BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3], 0.8)

	self.title = W.Text(panel, 22, "", "OUTLINE")
	self.title:SetPoint("TOPLEFT", 24, -20)
	self.title:SetPoint("RIGHT", -24, 0)
	self.title:SetJustifyH("LEFT")
	self.title:SetWordWrap(false)
	self.sub = W.Text(panel, 13, "", "OUTLINE")
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
	self.sub:SetTextColor(0.75, 0.75, 0.8)

	self.grade = W.Text(panel, 120, "", "THICKOUTLINE")
	self.grade:SetPoint("TOPLEFT", 40, -90)

	self.score = panel:CreateFontString(nil, "OVERLAY")
	self.score:SetFont(W.NUMFONT, 44, "OUTLINE")
	self.score:SetPoint("TOPLEFT", 240, -96)
	self.newBest = W.Text(panel, 16, "", "OUTLINE")
	self.newBest:SetPoint("LEFT", self.score, "RIGHT", 16, 0)

	self.details = W.Text(panel, 16, "", "OUTLINE")
	self.details:SetPoint("TOPLEFT", self.score, "BOTTOMLEFT", 0, -16)
	self.details:SetJustifyH("LEFT")
	self.details:SetSpacing(8)

	self.board = W.Text(panel, 12, "", "OUTLINE")
	self.board:SetPoint("TOPRIGHT", -24, -96)
	self.board:SetJustifyH("LEFT")
	self.board:SetSpacing(3)
	self.board:SetWidth(250)

	local retry = W.Button(panel, "Retry  (`)", 160, 36, function()
		BC.Game:Show(BC.Play, self.map, self.mods)
	end, true)
	retry:SetPoint("BOTTOMRIGHT", -24, 20)
	local back = W.Button(panel, "Song select  (Esc)", 170, 36, function()
		BC.Game:Show(BC.SongSelect)
	end)
	back:SetPoint("RIGHT", retry, "LEFT", -10, 0)
end

function Results:Enter(map, tally, mods, rank)
	self.map, self.mods = map, mods
	self.screen:Show()
	local song = map.song
	self.title:SetText((song.title or "") .. " - " .. (song.artist or ""))
	local modStr = BC.Scoring.ModString(mods)
	self.sub:SetText("[" .. (map.version or "") .. "]  mapped by " .. (song.creator or "?") .. (modStr ~= "" and ("   +" .. modStr) or ""))

	local grade = tally:Grade()
	local c = U.GRADE_COLORS[grade] or U.GRADE_COLORS.D
	self.grade:SetText(grade)
	self.grade:SetTextColor(c[1], c[2], c[3])
	self.score:SetText(U.FormatNumber(tally.score))
	if rank == 1 then
		self.newBest:SetText("|cffffd24dNEW PERSONAL BEST!|r")
	elseif rank then
		self.newBest:SetText("|cffaaaaaa#" .. rank .. " on this map|r")
	else
		self.newBest:SetText("")
	end

	local mean, ur = tally:ErrorStats()
	local lines = {
		string.format("Accuracy  |cffffffff%s|r        Max combo  |cffffffff%dx|r / %d", U.FormatAcc(tally:Accuracy()), tally.maxCombo, BC.Play.bm and BC.Play.bm.maxCombo or 0),
		string.format("|cff66ccff300|r  %d      |cff66ff66100|r  %d      |cffffcc4d50|r  %d      |cffff4040Miss|r  %d", tally.c300, tally.c100, tally.c50, tally.miss),
		string.format("Unstable rate  |cffffffff%.1f|r      Average  |cffffffff%+.1f ms|r %s", ur, mean, math.abs(mean) < 3 and "" or (mean > 0 and "(late)" or "(early)")),
	}
	if math.abs(mean) >= 8 and #tally.errors >= 20 then
		lines[#lines + 1] = string.format("|cffaaaaaaTip: you hit %d ms %s on average. Press %s during play to adjust this map's offset.|r", math.floor(math.abs(mean) + 0.5), mean > 0 and "late" or "early", mean > 0 and "'='" or "'-'")
	end
	self.details:SetText(table.concat(lines, "\n"))
	self.details:SetTextColor(0.8, 0.8, 0.85)

	local scores = BC.db.scores[map.key] or {}
	local out = { "|cff" .. BC.ACCENT_HEX .. "Local top scores|r" }
	for i = 1, math.min(5, #scores) do
		local s = scores[i]
		out[#out + 1] = string.format("%d. %s  %s  %s", i, s.grade, U.FormatNumber(s.score), U.FormatAcc(s.acc))
	end
	out[#out + 1] = ""
	out[#out + 1] = BC.Guild:FormatTop(map.key, 5)
	self.board:SetText(table.concat(out, "\n"))
end

function Results:Leave()
	self.screen:Hide()
end

function Results:OnKey(key, down)
	if not down then
		return
	end
	if key == "ESCAPE" or key == "ENTER" then
		BC.Game:Show(BC.SongSelect)
	elseif key == "`" then
		BC.Game:Show(BC.Play, self.map, self.mods)
	end
end
