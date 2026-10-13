local BC = Beatcraft
local L, db = BC.LiveFrames, BC.db.liveFrames
local passed, failed = 0, 0
local function check(value, message)
	if value then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function point(f)
	local p = f._points[1]
	return p and p[4], p and p[5]
end

print("== live moving frames")
math.randomseed(7)
BC.Game:Close()
MOCK.combat = false
check(L.mover and L.mover._protected and #L.buttons == 40, "secure frames are created at login")
check(MOCK.stateDrivers[L.mover] == "hide" and not db.enabled, "live frames are off by default")
check(L.buttons[1]._protected and L.buttons[1]:GetFrameRef("mover") == L.mover, "buttons are secure and reference the mover")

SlashCmdList.BEATCRAFT("live")
check(L.panel and L.panel:IsShown(), "/beat live opens the settings panel")

MOCK.groupSize = 3
MOCK.units.party1 = { name = "Healy", class = "PRIEST", hp = 40, max = 100 }
MOCK.units.party2 = { name = "Tanky", class = "WARRIOR", hp = 90, max = 100 }
L:SetEnabled(true)
check(MOCK.stateDrivers[L.mover] == "[group] show; hide", "raid style shows while grouped")
check(L.buttons[1]:GetAttribute("unit") == "player" and L.buttons[5]:GetAttribute("unit") == "party4",
	"party layout covers the player and four party slots")
check(L.buttons[1]:GetAttribute("type1") == "target" and L.buttons[1]:GetAttribute("type2") == "target",
	"clicks target by default")
MOCK.Advance(0.2)
check(not L.buttons[4]:IsShown() and L.buttons[2]:IsShown(), "unit watch hides empty party slots")
check(L.marked == L.buttons[2] and L.buttons[2].status:GetText():find("CLICK"), "the most injured member is marked")

MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
local homeX, homeY = L.mover:GetAttribute("homeX"), L.mover:GetAttribute("homeY")
L.buttons[2]:Fire("OnClick", "LeftButton", false)
local x1, y1 = point(L.mover)
check(#MOCK.blocked == 0, "clicking in combat moves frames without blocked actions")
check(x1 and (x1 ~= homeX or y1 ~= homeY), "the frames jump after a click in combat")
check(math.abs(x1 - homeX) <= 200 and math.abs(y1 - homeY) <= 120, "jumps stay within the chosen distance")
check(L.fight.hits == 1 and L.fight.combo == 1, "clicking the marked member scores")
L.buttons[1]:Fire("OnClick", "LeftButton", false)
local x2, y2 = point(L.mover)
check(L.fight.misses == 1 and L.fight.combo == 0, "clicking someone else breaks the combo")
check(x2 ~= x1 or y2 ~= y1, "every click jumps again")
L.buttons[2]:Fire("OnClick", "RightButton", false)
check(L.fight.hits == 1 and L.fight.misses == 1, "right clicks jump without scoring")
check(L.stats:GetText():find("1/2"), "stats show hits out of clicks")

db.distance = "large"
check(not L:Apply() and L.pending and L.mover:GetAttribute("rangeX") == 200, "setting changes wait for combat to end")
MOCK.groupSize = 4
MOCK.units.party3 = { name = "Late", class = "MAGE", hp = 100, max = 100 }
MOCK.FireEvent("GROUP_ROSTER_UPDATE")
MOCK.Advance(0.2)
check(L.buttons[4]:IsShown(), "unit watch shows a member who joins mid-fight")
check(not L:SetLocked(false) and db.locked, "frames cannot be unlocked in combat")
check(#MOCK.blocked == 0, "no protected frame was touched by insecure code in combat")

local printed = #MOCK.printed
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
check(#MOCK.printed > printed and MOCK.printed[#MOCK.printed]:find("1 of 2 clicks"), "a summary prints after combat")
check(not L.pending and L.mover:GetAttribute("rangeX") == 320, "pending settings apply after combat")
check(point(L.mover) == homeX and L.mover:GetAttribute("jumpX") == 0, "frames return home after combat")
check(db.bestCombo >= 1, "best combo is saved")

db.spell = "Flash Heal"
L:Apply()
check(L.buttons[2]:GetAttribute("type1") == "spell" and L.buttons[2]:GetAttribute("spell1") == "Flash Heal",
	"a left-click spell can be configured")
db.spell = ""
L:Apply()
check(L.buttons[2]:GetAttribute("type1") == "target" and L.buttons[2]:GetAttribute("spell1") == nil, "blank spell targets")

MOCK.units.party1.hp = 100
MOCK.units.party2.hp = 100
MOCK.units.player = { name = "Tester", class = "WARRIOR", hp = 100, max = 100 }
MOCK.Advance(0.2)
local hits = L.fight.hits
L.buttons[2]:Fire("OnClick", "LeftButton", false)
check(not L.marked and L.fight.hits == hits, "nobody is marked when everyone is healthy")
MOCK.units.party2.dead = true
MOCK.units.party2.hp = 0
MOCK.Advance(0.2)
check(L.marked ~= L.buttons[3] and L.buttons[3].status:GetText() == "Dead", "dead members are never marked")
MOCK.units.party2, MOCK.units.player = nil, nil

MOCK.inRaid, MOCK.groupSize = true, 12
L:Layout()
check(L.buttons[15]:GetAttribute("unit") == "raid15" and L.buttons[16]:GetAttribute("unit") == nil,
	"raids get whole columns of raid frames")
MOCK.inRaid, MOCK.groupSize = false, 4

db.style = "focus"
L:Apply()
check(MOCK.stateDrivers[L.mover] == "[@focus,exists] show; hide" and L.buttons[1]:GetAttribute("unit") == "focus"
	and L.buttons[2]:GetAttribute("unit") == nil, "focus style uses one focus frame")
MOCK.units.focus = { name = "Boss", class = "WARRIOR", hp = 100, max = 100 }
MOCK.Advance(0.2)
check(L.marked == L.buttons[1], "the focus frame is always the target")
MOCK.units.focus = nil
db.style = "raid"
L:Apply()

check(L:SetLocked(false) and L.handle:IsShown() and MOCK.stateDrivers[L.mover] == "show", "unlocking shows the drag handle")
L.mover:ClearAllPoints()
L.mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 1000, 600)
L.handle:Fire("OnDragStop")
check(db.x == 40 and db.y == 60, "dragging saves the new home position")
MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
check(db.locked and not L.handle:IsShown(), "combat locks the frames")
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
check(MOCK.stateDrivers[L.mover] == "[group] show; hide", "locking after combat restores visibility rules")
L:ResetPosition()
check(db.x == 0 and db.y == -180, "position can be reset")

BC.MainMenu:Create()
BC.MainMenu.frame:Show()
check(BC.MainMenu.live.text:GetText():find("ON"), "menu shows live frames as on")
L:SetEnabled(false)
check(MOCK.stateDrivers[L.mover] == "hide" and not L.ticker:IsShown(), "disabling hides the frames")
check(BC.MainMenu.live.text:GetText():find("OFF"), "menu updates when live frames change")
BC.MainMenu.frame:Hide()
L.panel:Hide()
MOCK.units.party1, MOCK.units.party3, MOCK.groupSize = nil, nil, 0
check(#MOCK.blocked == 0, "no blocked actions across the live frame tests")

print(string.format("%d live frame checks passed, %d failed", passed, failed))
RESULT_FAILED = (RESULT_FAILED or 0) + failed
