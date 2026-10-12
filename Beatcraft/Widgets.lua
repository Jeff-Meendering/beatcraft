-- Small self-contained UI kit. Avoids Blizzard templates that differ or
-- disappear between client flavors.
local _, BC = ...

local W = {}
BC.Widgets = W

W.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
W.NUMFONT = "Fonts\\ARIALN.TTF"

local ACCENT = BC.ACCENT

local function solid(parent, layer, r, g, b, a, sub)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end
W.Solid = solid

function W.Text(parent, size, text, flags, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(W.FONT, size or 12, flags or "")
	fs:SetTextColor(1, 1, 1)
	fs:SetText(text or "")
	return fs
end

function W.Border(f, r, g, b, a)
	r, g, b, a = r or 0.25, g or 0.25, b or 0.32, a or 1
	local top = solid(f, "BORDER", r, g, b, a)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(1)
	local bottom = solid(f, "BORDER", r, g, b, a)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(1)
	local left = solid(f, "BORDER", r, g, b, a)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(1)
	local right = solid(f, "BORDER", r, g, b, a)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(1)
	f.borders = { top, bottom, left, right }
end

function W.Tooltip(owner, title, body)
	owner:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if body then
			GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
		end
		GameTooltip:Show()
	end)
	owner:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- A dark draggable window. Pass a global name to make Escape close it.
function W.Panel(name, parent, w, h, title)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bg = solid(f, "BACKGROUND", 0.05, 0.05, 0.08, 0.96)
	f.bg:SetAllPoints()
	W.Border(f)
	local strip = solid(f, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	strip:SetPoint("TOPLEFT", 1, -1)
	strip:SetPoint("TOPRIGHT", -1, -1)
	strip:SetHeight(2)
	if title then
		f.title = W.Text(f, 14, title, "OUTLINE")
		f.title:SetPoint("TOPLEFT", 12, -10)
		local close = W.Button(f, "X", 22, 20, function()
			f:Hide()
		end)
		close:SetPoint("TOPRIGHT", -6, -6)
		f.close = close
	end
	if name then
		tinsert(UISpecialFrames, name)
	end
	f:Hide()
	return f
end

function W.Button(parent, text, w, h, onClick, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 100, h or 24)
	b.bg = solid(b, "BACKGROUND", 0.15, 0.15, 0.21, 1)
	b.bg:SetAllPoints()
	W.Border(b, 0.3, 0.3, 0.38, 1)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	b.text = W.Text(b, 12, text)
	b.text:SetPoint("CENTER")
	b.primary = primary
	function b:SetActive(on)
		self.active = on
		if on or self.primary then
			self.bg:SetColorTexture(ACCENT[1] * 0.7, ACCENT[2] * 0.7, ACCENT[3] * 0.7, 1)
		else
			self.bg:SetColorTexture(0.15, 0.15, 0.21, 1)
		end
	end
	function b:SetLabel(t)
		self.text:SetText(t)
	end
	b:SetActive(false)
	b:SetScript("OnClick", function(self, button)
		if onClick then
			onClick(self, button)
		end
	end)
	b:SetScript("OnEnable", function(self)
		self.text:SetTextColor(1, 1, 1)
	end)
	b:SetScript("OnDisable", function(self)
		self.text:SetTextColor(0.45, 0.45, 0.45)
	end)
	return b
end

function W.Check(parent, label, get, set, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 240, 20)
	local box = solid(b, "ARTWORK", 0.12, 0.12, 0.17, 1)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	local fill = solid(b, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	fill:SetSize(10, 10)
	fill:SetPoint("CENTER", box, "CENTER")
	b.text = W.Text(b, 12, label)
	b.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
	b.text:SetJustifyH("LEFT")
	function b:Refresh()
		fill:SetShown(get() and true or false)
	end
	b:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
	end)
	b:Refresh()
	return b
end

function W.Slider(parent, label, minV, maxV, step, get, set, fmt, width)
	width = width or 240
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 34)
	holder.label = W.Text(holder, 12, label)
	holder.label:SetPoint("TOPLEFT")
	holder.value = W.Text(holder, 12, "")
	holder.value:SetPoint("TOPRIGHT")
	holder.value:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	local s = CreateFrame("Slider", nil, holder)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 12)
	s:SetPoint("BOTTOMLEFT", 0, 2)
	local track = solid(s, "BACKGROUND", 0.15, 0.15, 0.21, 1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	thumb:SetSize(10, 14)
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then
		s:SetObeyStepOnDrag(true)
	end
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(BC.Util.Clamp(self:GetValue() + delta * step, minV, maxV))
	end)
	local function format(v)
		if type(fmt) == "function" then
			return fmt(v)
		end
		return string.format(fmt or "%s", v)
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		holder.value:SetText(format(v))
		if not holder.refreshing then
			set(v)
		end
	end)
	function holder:Refresh()
		self.refreshing = true
		s:SetValue(get())
		holder.value:SetText(format(get()))
		self.refreshing = false
	end
	holder.slider = s
	holder:Refresh()
	return holder
end

--------------------------------------------------------------------------
-- Dropdown with a shared popup menu
--------------------------------------------------------------------------

local menu, catcher

local function closeMenu()
	if menu then
		menu:Hide()
		catcher:Hide()
	end
end
W.CloseMenu = closeMenu

local function ensureMenu()
	if menu then
		return
	end
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("TOOLTIP")
	catcher:SetScript("OnClick", closeMenu)
	catcher:Hide()
	menu = CreateFrame("Frame", nil, catcher)
	menu:SetFrameStrata("TOOLTIP")
	menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
	menu.bg = solid(menu, "BACKGROUND", 0.08, 0.08, 0.12, 0.98)
	menu.bg:SetAllPoints()
	W.Border(menu, ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
	menu.items = {}
	menu:EnableMouse(true)
end

function W.ShowMenu(anchor, options, onPick, width)
	ensureMenu()
	width = width or anchor:GetWidth()
	for _, item in ipairs(menu.items) do
		item:Hide()
	end
	for i, opt in ipairs(options) do
		local item = menu.items[i]
		if not item then
			item = CreateFrame("Button", nil, menu)
			item:SetHeight(20)
			local hl = item:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)
			item.text = W.Text(item, 12, "")
			item.text:SetPoint("LEFT", 8, 0)
			menu.items[i] = item
		end
		item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
		item:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 20)
		item.text:SetText(opt.text)
		item:SetScript("OnClick", function()
			closeMenu()
			onPick(opt.value)
		end)
		item:Show()
	end
	menu:SetSize(width, #options * 20 + 2)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	catcher:Show()
	menu:Show()
end

-- options: list of {value=, text=} or a function returning one
function W.Dropdown(parent, label, options, get, set, width)
	width = width or 240
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 40)
	holder.label = W.Text(holder, 12, label)
	holder.label:SetPoint("TOPLEFT")
	local function list()
		return type(options) == "function" and options() or options
	end
	local b = W.Button(holder, "", width, 20, function(self)
		W.ShowMenu(self, list(), function(v)
			set(v)
			holder:Refresh()
		end, width)
	end)
	b:SetPoint("BOTTOMLEFT")
	b.text:ClearAllPoints()
	b.text:SetPoint("LEFT", 8, 0)
	local arrow = W.Text(b, 10, "v")
	arrow:SetPoint("RIGHT", -8, 0)
	function holder:Refresh()
		local cur = get()
		for _, opt in ipairs(list()) do
			if opt.value == cur then
				b:SetLabel(opt.text)
				return
			end
		end
		b:SetLabel(tostring(cur or ""))
	end
	holder.button = b
	holder:Refresh()
	return holder
end

--------------------------------------------------------------------------
-- Text input
--------------------------------------------------------------------------

function W.EditBox(parent, w, h)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w, h or 22)
	e:SetAutoFocus(false)
	e:SetFontObject(ChatFontNormal)
	e:SetTextInsets(6, 6, 2, 2)
	e.bg = solid(e, "BACKGROUND", 0.1, 0.1, 0.15, 1)
	e.bg:SetAllPoints()
	W.Border(e, 0.3, 0.3, 0.38, 1)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	return e
end

function W.MultiLineEdit(parent, w, h)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(w, h)
	holder.bg = solid(holder, "BACKGROUND", 0.1, 0.1, 0.15, 1)
	holder.bg:SetAllPoints()
	W.Border(holder, 0.3, 0.3, 0.38, 1)
	local sf = CreateFrame("ScrollFrame", nil, holder)
	sf:SetPoint("TOPLEFT", 6, -6)
	sf:SetPoint("BOTTOMRIGHT", -6, 6)
	local e = CreateFrame("EditBox", nil, sf)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetFontObject(ChatFontNormal)
	e:SetWidth(w - 14)
	e:SetHeight(h)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	sf:SetScrollChild(e)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(BC.Util.Clamp(self:GetVerticalScroll() - delta * 24, 0, range))
	end)
	e:SetScript("OnCursorChanged", function(_, _, y, _, ch)
		local scroll = sf:GetVerticalScroll()
		local height = sf:GetHeight()
		y = -y
		if y < scroll then
			sf:SetVerticalScroll(y)
		elseif y + ch > scroll + height then
			sf:SetVerticalScroll(y + ch - height)
		end
	end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function()
		e:SetFocus()
	end)
	holder.edit = e
	return holder
end

-- Click, then press a key to bind it.
function W.KeyBind(parent, label, get, set, width)
	width = width or 240
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 22)
	holder.label = W.Text(holder, 12, label)
	holder.label:SetPoint("LEFT")
	local b
	local function stop()
		b.listening = false
		b:EnableKeyboard(false)
		holder:Refresh()
	end
	b = W.Button(holder, "", 90, 20, function(self)
		if InCombatLockdown() then
			return
		end
		self.listening = true
		self:SetLabel("press key")
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end)
	b:SetPoint("RIGHT")
	b:SetScript("OnKeyDown", function(self, key)
		if not self.listening then
			return
		end
		if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then
			return
		end
		if key ~= "ESCAPE" then
			set(key)
		end
		stop()
	end)
	b:SetScript("OnHide", function(self)
		if self.listening then
			stop()
		end
	end)
	function holder:Refresh()
		b:SetLabel(get() or "-")
	end
	holder:Refresh()
	return holder
end

--------------------------------------------------------------------------
-- Virtual scrolling list
--------------------------------------------------------------------------

function W.ScrollList(parent, w, h, rowH, createRow, updateRow)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f:EnableMouseWheel(true)
	f.data = {}
	f.offset = 0
	f.rows = {}
	f.numRows = math.floor(h / rowH)
	for i = 1, f.numRows do
		local row = createRow(f, i)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
		row:SetSize(w - 10, rowH)
		f.rows[i] = row
	end
	local track = CreateFrame("Button", nil, f)
	track:SetPoint("TOPRIGHT")
	track:SetPoint("BOTTOMRIGHT")
	track:SetWidth(6)
	local trackTex = solid(track, "BACKGROUND", 0.12, 0.12, 0.17, 1)
	trackTex:SetAllPoints()
	local thumb = solid(track, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
	thumb:SetWidth(6)

	local function maxOffset()
		return math.max(0, #f.data - f.numRows)
	end

	function f:Refresh()
		self.offset = BC.Util.Clamp(self.offset, 0, maxOffset())
		for i, row in ipairs(self.rows) do
			local idx = self.offset + i
			local item = self.data[idx]
			if item ~= nil then
				row:Show()
				updateRow(row, item, idx)
			else
				row:Hide()
			end
		end
		local total = #self.data
		if total <= self.numRows then
			thumb:Hide()
		else
			thumb:Show()
			local th = math.max(20, h * self.numRows / total)
			thumb:SetHeight(th)
			thumb:ClearAllPoints()
			thumb:SetPoint("TOP", track, "TOP", 0, -(h - th) * self.offset / maxOffset())
		end
	end

	function f:SetData(data)
		self.data = data or {}
		self:Refresh()
	end

	function f:ScrollTo(idx)
		if idx <= self.offset then
			self.offset = idx - 1
		elseif idx > self.offset + self.numRows then
			self.offset = idx - self.numRows
		end
		self:Refresh()
	end

	f:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta * 3
		self:Refresh()
	end)
	track:SetScript("OnClick", function(self)
		local _, cy = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		local top = self:GetTop()
		local frac = BC.Util.Clamp((top - cy / scale) / h, 0, 1)
		f.offset = math.floor(frac * maxOffset() + 0.5)
		f:Refresh()
	end)
	return f
end

function W.Divider(parent, w)
	local t = solid(parent, "ARTWORK", 0.25, 0.25, 0.32, 1)
	t:SetSize(w, 1)
	return t
end
