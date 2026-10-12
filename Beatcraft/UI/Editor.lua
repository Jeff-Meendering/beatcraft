local _, BC = ...

local Compat = BC.Compat
local U = BC.Util
local W = BC.Widgets
local Engine = BC.Engine
local Cond = BC.Conditions

local Editor = BC:Module("Editor")

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ROWS, ROW_H = 12, 32
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local HELP_TEXT = [[
|cffff66aaHow it works|r
Abilities are checked top to bottom. The first one whose condition is true,
that you can afford, and that is ready by the end of the global cooldown
becomes the next note. Leave the condition empty for "always".
Tick Off-GCD for abilities that don't trigger the global cooldown
(Heroic Strike, Kill Command, most trinket-style cooldowns).

|cffff66aaValues|r
power  powerPct  mana  manaPct  rage  energy  focus  combo
hp  targetHp  (percent, 0-100)
moving  combat  boss  group  raid  pet  stealthed  cat  bear
time (seconds in combat)  level

|cffff66aaFunctions|r  (names in quotes, exactly as in your spellbook)
buff("Name")            seconds left on your buff (0 if missing)
buffStacks("Name")
debuff("Name")          seconds left on YOUR debuff on the target
debuffStacks("Name")
debuffAny("Name")       any player's debuff (e.g. Sunder Armor)
debuffAnyStacks("Name")
cd("Name")              cooldown left, ignoring the GCD
ready("Name")  known("Name")  usable("Name")  inRange("Name")
casting("Name")  form("Name")  targetIs("Undead")
min(a, b)  max(a, b)  abs(x)

|cffff66aaExamples|r
combo >= 5 and debuff("Rupture") < 1
rage >= 50
targetHp < 20
boss and cd("Icy Veins") == 0
not known("Mutilate")
]]

local function copyEntries(entries)
	local out = {}
	for i, e in ipairs(entries) do
		out[i] = { spell = e.spell or "", cond = e.cond or "", off = e.off and true or nil }
	end
	return out
end

function Editor:Create()
	if self.frame then
		return
	end
	local f = W.Panel("BeatcraftEditor", UIParent, 840, 590, "Rotation editor")
	f:SetPoint("CENTER")
	self.frame = f

	self.classDrop = W.Dropdown(f, "Class", function()
		local opts = {}
		for _, c in ipairs(CLASSES) do
			opts[#opts + 1] = { value = c, text = BC.ClassNames[c] }
		end
		return opts
	end, function()
		return self.class
	end, function(v)
		self:Load(v, 1)
	end, 170)
	self.classDrop:SetPoint("TOPLEFT", 16, -40)

	self.specDrop = W.Dropdown(f, "Talent tree", function()
		local opts = {}
		for i, n in ipairs(BC.SpecNames[self.class] or {}) do
			opts[#opts + 1] = { value = i, text = n }
		end
		return opts
	end, function()
		return self.tree
	end, function(v)
		self:Load(self.class, v)
	end, 170)
	self.specDrop:SetPoint("LEFT", self.classDrop, "RIGHT", 16, 0)

	self.status = W.Text(f, 12, "")
	self.status:SetPoint("TOPLEFT", self.specDrop, "TOPRIGHT", 20, -4)
	self.preview = W.Text(f, 12, "")
	self.preview:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -6)
	self.preview:SetTextColor(0.75, 0.75, 0.8)

	local headers = { { "#", 16 }, { "Ability", 74 }, { "Condition", 266 }, { "Off-GCD", 662 } }
	for _, h in ipairs(headers) do
		local t = W.Text(f, 11, h[1])
		t:SetPoint("TOPLEFT", h[2], -96)
		t:SetTextColor(0.65, 0.65, 0.7)
	end

	local function createRow(parent)
		local row = CreateFrame("Frame", nil, parent)
		row.num = W.Text(row, 12, "")
		row.num:SetPoint("LEFT", 2, 0)
		row.num:SetWidth(20)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 26, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.spell = W.EditBox(row, 185, 24)
		row.spell:SetPoint("LEFT", 56, 0)
		row.cond = W.EditBox(row, 390, 24)
		row.cond:SetPoint("LEFT", row.spell, "RIGHT", 6, 0)
		row.off = CreateFrame("Button", nil, row)
		row.off:SetSize(22, 22)
		row.off:SetPoint("LEFT", row.cond, "RIGHT", 22, 0)
		row.off.bg = W.Solid(row.off, "ARTWORK", 0.12, 0.12, 0.17, 1)
		row.off.bg:SetAllPoints()
		row.off.fill = W.Solid(row.off, "OVERLAY", BC.ACCENT[1], BC.ACCENT[2], BC.ACCENT[3], 1)
		row.off.fill:SetPoint("TOPLEFT", 4, -4)
		row.off.fill:SetPoint("BOTTOMRIGHT", -4, 4)
		row.up = W.Button(row, "^", 24, 22, function()
			Editor:MoveEntry(row.idx, -1)
		end)
		row.up:SetPoint("LEFT", row.off, "RIGHT", 22, 0)
		row.down = W.Button(row, "v", 24, 22, function()
			Editor:MoveEntry(row.idx, 1)
		end)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
		row.del = W.Button(row, "X", 24, 22, function()
			Editor:RemoveEntry(row.idx)
		end)
		row.del:SetPoint("LEFT", row.down, "RIGHT", 4, 0)
		row.mark = CreateFrame("Frame", nil, row)
		row.mark:SetSize(20, 20)
		row.mark:SetPoint("LEFT", row.del, "RIGHT", 8, 0)
		row.mark.text = W.Text(row.mark, 14, "", "OUTLINE")
		row.mark.text:SetPoint("CENTER")
		row.mark:SetScript("OnEnter", function(m)
			if m.tip then
				GameTooltip:SetOwner(m, "ANCHOR_RIGHT")
				GameTooltip:SetText(m.tip, 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		row.mark:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		row.spell:SetScript("OnTextChanged", function(e, user)
			if user and row.idx then
				Editor.entries[row.idx].spell = e:GetText()
				Editor:MarkDirty()
				Editor:UpdateRowStatus(row, Editor.entries[row.idx])
			end
		end)
		row.cond:SetScript("OnTextChanged", function(e, user)
			if user and row.idx then
				Editor.entries[row.idx].cond = e:GetText()
				Editor:MarkDirty()
				Editor:UpdateRowStatus(row, Editor.entries[row.idx])
			end
		end)
		row.spell:SetScript("OnTabPressed", function()
			row.cond:SetFocus()
		end)
		row.off:SetScript("OnClick", function()
			local e = Editor.entries[row.idx]
			e.off = not e.off or nil
			row.off.fill:SetShown(e.off and true or false)
			Editor:MarkDirty()
		end)
		return row
	end
	local function updateRow(row, entry, idx)
		row.idx = idx
		row.num:SetText(idx)
		if not row.spell:HasFocus() then
			row.spell:SetText(entry.spell or "")
		end
		if not row.cond:HasFocus() then
			row.cond:SetText(entry.cond or "")
			row.cond:SetCursorPosition(0)
		end
		row.off.fill:SetShown(entry.off and true or false)
		self:UpdateRowStatus(row, entry)
	end
	self.list = W.ScrollList(f, 808, ROWS * ROW_H, ROW_H, createRow, updateRow)
	self.list:SetPoint("TOPLEFT", 16, -112)

	local y = -112 - ROWS * ROW_H - 14
	local bx = 16
	local function button(text, w, fn, primary)
		local b = W.Button(f, text, w, 26, fn, primary)
		b:SetPoint("TOPLEFT", bx, y)
		bx = bx + w + 8
		return b
	end
	button("Add ability", 110, function()
		Editor:AddEntry()
	end)
	self.saveButton = button("Save", 90, function()
		Editor:Save()
	end, true)
	button("Undo changes", 120, function()
		Editor:Load(Editor.class, Editor.tree)
	end)
	button("Reset to default", 130, function()
		Engine:ResetEntries(Editor.class, Editor.tree)
		Editor:Load(Editor.class, Editor.tree)
		BC:Print("Rotation reset to the default.")
	end)
	button("Import / Export", 130, function()
		Editor:OpenIO()
	end)
	button("Condition help", 130, function()
		Editor:ToggleHelp()
	end)

	local foot = W.Text(f, 11, "Abilities are tried top to bottom. Names must match your spellbook exactly. Changes apply when you press Save.")
	foot:SetPoint("BOTTOMLEFT", 16, 14)
	foot:SetTextColor(0.6, 0.6, 0.65)

	f:SetScript("OnUpdate", function(_, elapsed)
		Editor.previewTimer = (Editor.previewTimer or 0) + elapsed
		if Editor.previewTimer > 0.25 then
			Editor.previewTimer = 0
			Editor:UpdatePreview()
		end
	end)
end

function Editor:Open()
	self:Create()
	self:Load(Engine:Class(), Engine:Tree())
	self.frame:Show()
	self.frame:Raise()
end

function Editor:Load(class, tree)
	self.class, self.tree = class, tree
	local entries, custom = Engine:GetEntries(class, tree)
	self.entries = copyEntries(entries)
	self.custom = custom
	self.dirty = false
	self.classDrop:Refresh()
	self.specDrop:Refresh()
	self.list:SetData(self.entries)
	self:UpdateStatus()
end

function Editor:MarkDirty()
	if not self.dirty then
		self.dirty = true
		self:UpdateStatus()
	end
end

function Editor:UpdateStatus()
	local name = Engine:SpecName(self.class, self.tree) .. " " .. (BC.ClassNames[self.class] or "")
	local state
	if self.dirty then
		state = "|cffffcc4dunsaved changes|r"
	elseif self.custom then
		state = "|cff66ff66your custom rotation|r"
	else
		state = "|cffaaaaaadefault rotation|r"
	end
	if #self.entries == 0 then
		state = state .. "  |cffaaaaaa(empty = Freestyle mode)|r"
	end
	self.status:SetText(name .. ":  " .. state)
end

function Editor:UpdateRowStatus(row, entry)
	local mine = self.class == Engine:Class()
	local _, icon = Compat.SpellInfo(entry.spell)
	row.icon:SetTexture(icon or QUESTION)
	local _, err = Cond.Compile(entry.cond)
	local tip, mark, color
	if (entry.spell or "") == "" then
		mark, color, tip = "?", { 1, 0.8, 0.3 }, "Enter an ability name."
	elseif err then
		mark, color, tip = "!", { 1, 0.3, 0.3 }, "Condition error: " .. err
	elseif mine and not Compat.IsKnown(entry.spell) then
		mark, color, tip = "-", { 0.6, 0.6, 0.6 }, "You don't know this spell (wrong name, wrong tree, or not learned yet). It will be skipped."
	else
		local runtime
		for _, c in ipairs(Engine.entries) do
			if c.spell == entry.spell and c.cond == entry.cond and c.runtimeErr then
				runtime = c.runtimeErr
			end
		end
		if runtime and mine then
			mark, color, tip = "!", { 1, 0.5, 0.2 }, "Error while running: " .. runtime
		else
			mark, color, tip = "ok", { 0.4, 1, 0.4 }, nil
		end
	end
	row.mark.text:SetText(mark)
	row.mark.text:SetTextColor(color[1], color[2], color[3])
	row.mark.tip = tip
end

function Editor:UpdatePreview()
	if self.class ~= Engine:Class() then
		self.preview:SetText("Preview works for your own class.")
		return
	end
	if self.dirty then
		self.preview:SetText("Save to update the preview.")
		return
	end
	if self.tree ~= Engine.tree then
		self.preview:SetText("This isn't your active tree (set it under Options > Rotation).")
		return
	end
	if Engine.freestyle then
		self.preview:SetText("Freestyle: every cast is judged on the beat.")
		return
	end
	if not Engine:HasEnemyTarget() then
		self.preview:SetText("Target an enemy to preview the next ability.")
		return
	end
	local on = Engine:Next(false)
	local off = Engine:Next(true)
	self.preview:SetText("Next: |cffffffff" .. (on and on.spell or "nothing ready") .. "|r" .. (off and ("   Off-GCD: |cffffffff" .. off.spell .. "|r") or ""))
end

function Editor:AddEntry()
	table.insert(self.entries, { spell = "", cond = "" })
	self:MarkDirty()
	self.list:SetData(self.entries)
	self.list:ScrollTo(#self.entries)
	for _, row in ipairs(self.list.rows) do
		if row.idx == #self.entries and row:IsShown() then
			row.spell:SetFocus()
		end
	end
end

function Editor:RemoveEntry(idx)
	if not idx then
		return
	end
	table.remove(self.entries, idx)
	self:MarkDirty()
	self.list:SetData(self.entries)
end

function Editor:MoveEntry(idx, delta)
	local j = idx and idx + delta
	if not j or j < 1 or j > #self.entries then
		return
	end
	self.entries[idx], self.entries[j] = self.entries[j], self.entries[idx]
	self:MarkDirty()
	for _, row in ipairs(self.list.rows) do
		row.spell:ClearFocus()
		row.cond:ClearFocus()
	end
	self.list:SetData(self.entries)
end

function Editor:Save()
	local clean, errors = {}, 0
	for _, e in ipairs(self.entries) do
		local spell = U.Trim(e.spell or "")
		if spell ~= "" then
			local cond = U.Trim(e.cond or "")
			if select(2, Cond.Compile(cond)) then
				errors = errors + 1
			end
			clean[#clean + 1] = { spell = spell, cond = cond, off = e.off and true or nil }
		end
	end
	Engine:SaveEntries(self.class, self.tree, clean)
	self:Load(self.class, self.tree)
	if errors > 0 then
		BC:Print(errors .. " condition(s) have errors; those abilities will be skipped until fixed.")
	else
		BC:Print("Rotation saved.")
	end
end

function Editor:Export()
	local lines = { "# Beatcraft rotation: " .. Engine:SpecName(self.class, self.tree) .. " " .. (BC.ClassNames[self.class] or "") }
	lines[#lines + 1] = "# One ability per line:  Ability Name | condition | off"
	for _, e in ipairs(self.entries) do
		local line = (e.spell or "")
		if (e.cond or "") ~= "" or e.off then
			line = line .. " | " .. (e.cond or "")
		end
		if e.off then
			line = line .. " | off"
		end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

function Editor.ParseText(text)
	local out = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		line = U.Trim(line)
		if line ~= "" and line:sub(1, 1) ~= "#" then
			local parts = U.Split(line, "|")
			local spell = U.Trim(parts[1] or "")
			local cond = U.Trim(parts[2] or "")
			local flag = U.Trim(parts[3] or ""):lower()
			if spell ~= "" then
				out[#out + 1] = { spell = spell, cond = cond, off = (flag == "off" or flag == "offgcd") or nil }
			end
		end
	end
	return out
end

function Editor:OpenIO()
	local io = self.io
	if not io then
		io = W.Panel("BeatcraftRotationIO", UIParent, 620, 400, "Import / Export rotation")
		io:SetPoint("CENTER", 40, -20)
		io:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		local hint = W.Text(io, 11, "Copy this text to share it (Ctrl+A, Ctrl+C). To import, paste a rotation here and press Import.")
		hint:SetPoint("TOPLEFT", 16, -38)
		hint:SetTextColor(0.75, 0.75, 0.8)
		io.box = W.MultiLineEdit(io, 588, 290)
		io.box:SetPoint("TOPLEFT", 16, -58)
		local import = W.Button(io, "Import (replaces list)", 170, 26, function()
			local entries = Editor.ParseText(io.box.edit:GetText())
			if #entries == 0 then
				BC:Print("Nothing to import.")
				return
			end
			Editor.entries = entries
			Editor:MarkDirty()
			Editor.list:SetData(Editor.entries)
			io:Hide()
			BC:Print("Imported " .. #entries .. " abilities. Press Save to keep them.")
		end, true)
		import:SetPoint("BOTTOMRIGHT", -16, 14)
		self.io = io
	end
	io.box.edit:SetText(self:Export())
	io:Show()
	io:Raise()
	io.box.edit:SetFocus()
	io.box.edit:HighlightText()
end

function Editor:ToggleHelp()
	local help = self.help
	if not help then
		help = W.Panel("BeatcraftRotationHelp", UIParent, 470, 560, "Condition reference")
		help:SetPoint("LEFT", self.frame, "RIGHT", 8, 0)
		local text = W.Text(help, 12, HELP_TEXT)
		text:SetPoint("TOPLEFT", 16, -40)
		text:SetPoint("RIGHT", -16, 0)
		text:SetJustifyH("LEFT")
		text:SetSpacing(2)
		self.help = help
	end
	help:SetShown(not help:IsShown())
end
