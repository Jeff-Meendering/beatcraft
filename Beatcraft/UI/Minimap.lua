local _, BC = ...

local Mini = BC:Module("Minimap")

local RADIUS = 80

local function place(button)
	local angle = math.rad(BC.db.minimap.angle or 215)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

function Mini:OnLogin()
	if not Minimap then
		return
	end
	local b = CreateFrame("Button", "BeatcraftMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(BC.MEDIA .. "logo")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			BC.RaidMode:SetEnabled(not BC.db.raid.enabled)
		else
			BC.MainMenu:Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			BC.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			place(self)
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Beatcraft", 1, 0.4, 0.67)
		GameTooltip:AddLine("Left-click: menu", 1, 1, 1)
		GameTooltip:AddLine("Right-click: toggle Raid Mode (" .. (BC.db.raid.enabled and "on" or "off") .. ")", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	place(b)
	b:SetShown(not BC.db.minimap.hide)
	self.button = b
end

function Mini:SetShown(show)
	BC.db.minimap.hide = not show
	if self.button then
		self.button:SetShown(show)
	end
end
