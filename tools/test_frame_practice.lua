local BC = Beatcraft
local P, G = BC.FramePractice, BC.Game
local passed, failed = 0, 0
local function check(value, message)
	if value then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

print("== moving frame practice")
G:Close()
MOCK.combat = false
BC.db.framePractice.style, BC.db.framePractice.difficulty = "raid", "normal"
BC.Options.frame:Hide()
BC.Calibrate.frame:Hide()
-- Opening practice must not depend on a populated song library.
local load = BC.Library.Load
BC.Library.Load = function() error("practice tried to load the song library") end
SlashCmdList.BEATCRAFT("frames")
BC.Library.Load = load
check(G.screen == P and P.screen:IsVisible(), "slash command opens practice without songs")
check(P.count == 5 and P.targets[5]:IsShown(), "raid style has five simulated members")
P.targets[1]:Fire("OnClick", "LeftButton")
check(P.hits == 0, "preview clicks do not score")
P:OnKey("ENTER", true)
check(P.running and not P.start:IsEnabled(), "Enter starts a timed round")
local first, x, y = P.targetIndex, P.x, P.y
MOCK.Advance(0.5)
check(P.x ~= x and P.y ~= y, "raid frames move continuously on both axes")
P.targets[first]:Fire("OnClick", "LeftButton")
check(P.hits == 1 and P.combo == 1 and P.targetIndex ~= first, "hit scores and selects a different injured member")
P.targets[first]:Fire("OnClick", "LeftButton")
check(P.misses == 1 and P.combo == 0 and P.bestCombo == 1, "wrong member counts as a miss and breaks combo")
P.area:Fire("OnMouseDown", "RightButton")
check(P.misses == 1, "right clicks are ignored")
P.area:Fire("OnMouseDown", "LeftButton")
check(P.misses == 2 and P.hud:GetText():find("33.3%%"), "empty field counts as a miss and accuracy updates")
P:OnKey("Z", true)
check(P.hits == 1, "rhythm keys cannot score in mouse practice")
for _, elapsed in ipairs({ 0, 0.01, 1, 9, 29.99, 10000 }) do
	P:Move(elapsed)
	check(P.x >= 0 and P.x + P.group:GetWidth() <= P.area:GetWidth()
		and P.y >= 0 and P.y + P.group:GetHeight() <= P.area:GetHeight(),
		"moving frames stay within the practice area at " .. elapsed .. " seconds")
end
MOCK.Advance(30)
check(not P.running and P.start:IsEnabled() and P.feedback:GetText():find("Round complete"), "round finishes and shows results")
local best = BC.db.framePractice.best["raid-normal"]
check(best and best.hits == 1 and P.feedback:GetText():find("New personal best"), "personal best is saved per style and speed")
local hits = P.hits
P.targets[P.targetIndex]:Fire("OnClick", "LeftButton")
check(P.hits == hits, "results clicks do not score")
P:OnKey("ENTER", true)
check(P.running and P.hits == 0 and P.misses == 0 and P.combo == 0, "retry resets round statistics")
-- Click handler enforces the deadline even before the next update.
P.startedAt = MOCK.now - 30
P.targets[P.targetIndex]:Fire("OnClick", "LeftButton")
check(not P.running and P.hits == 0, "clicks at the round deadline cannot score")

P.settings[2]:Fire("OnClick")
P.settings[5]:Fire("OnClick")
check(P.style == "focus" and P.count == 1 and not P.targets[2]:IsShown(), "focus choice displays a single larger target")
check(P.speed == 240 and BC.db.framePractice.difficulty == "hard", "hard speed choice is saved")
P:Start()
MOCK.Advance(0.2)
P.targets[1]:Fire("OnClick", "LeftButton")
P.targets[1]:Fire("OnClick", "LeftButton")
check(P.hits == 2 and P.combo == 2, "focus target supports repeated moving clicks")
P.settings[1]:Fire("OnClick")
check(P.style == "focus", "settings cannot change during a round")
P:OnKey("ESCAPE", true)
check(not G:IsOpen() and not P.running and not P.screen:IsShown(), "Escape exits and stops practice")
SlashCmdList.BEATCRAFT("practice")
check(P.style == "focus" and P.speed == 240 and P.start:IsEnabled(), "alias reopens saved choices with an enabled start button")
P:Start()
MOCK.combat = true
MOCK.FireEvent("PLAYER_REGEN_DISABLED")
check(not G:IsOpen() and not P.running, "entering combat closes moving practice")
P:Open()
check(not G:IsOpen(), "practice cannot open during combat")
MOCK.combat = false
MOCK.FireEvent("PLAYER_REGEN_ENABLED")
P:Open()
P:Start()
MOCK.FireEvent("READY_CHECK")
check(not G:IsOpen() and not P.running, "ready checks close practice through the game lifecycle")
P:Open()
P:Start()
BC.SongSelect:Open()
check(G.screen == BC.SongSelect and not P.running and not P.screen:IsShown(), "switching to songs cleans up the practice screen")
G:Close()
BC.db.framePractice.style, BC.db.framePractice.difficulty = "bad", "bad"
P:Open()
check(P.style == "raid" and P.speed == 150, "invalid saved choices fall back to raid and normal")
G:Close()
print(string.format("%d frame practice checks passed, %d failed", passed, failed))
RESULT_FAILED = (RESULT_FAILED or 0) + failed
