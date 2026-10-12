local BC = Beatcraft
local passed, failed = 0, 0
local function check(value, message)
	if value then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function closeEnough(a, b) return math.abs(a - b) < 0.001 end
local function map(objects, fields)
	local m = { key = "regression", ar = 5, od = 5, cs = 4, hp = 5, sm = 1.4, tr = 1, timing = "0,500,4,1,0,100,1,0", objects = objects }
	for k, v in pairs(fields or {}) do m[k] = v end
	return m
end
local B, P, G = BC.Beatmap, BC.Play, BC.Game
BC.Options.frame:Hide()
BC.Calibrate.frame:Hide()
MOCK.combat = false
G:Open()

print("== gameplay regressions")
local slider = B.Parse(map("100,100,1000,2,0,L|520:100,3,420"))
local o = slider.objects[1]
check(#o.tickDistances == 2, "slider has two ticks per span")
check(#o.events == 9 and slider.maxCombo == 10, "ticks, repeats and tail contribute to max combo")
check(o.events[1].kind == "tick" and o.events[1].t == 1500, "first tick is on the beat")
check(o.events[4].dist == 280 and o.events[5].dist == 140, "reverse span ticks run in reverse order")
check(o.events[#o.events].t == o.endTime - 36, "tail has 36 ms release leniency")
local short = B.Parse(map("100,100,1000,2,0,L|105:100,1,5"))
check(closeEnough(short.objects[1].events[1].t, 1000 + short.objects[1].span / 2), "very short slider tail remains after the head")
local overlap = B.Parse(map("100,100,1000,2,0,L|520:100,3,420\n300,200,2000,1,0"))
check(overlap.lastTime == overlap.objects[1].endTime, "long overlapping slider controls map completion time")

local stacks = B.Parse(map("100,100,1000,1,0\n100,100,1100,1,0\n100,100,1200,1,0"))
check(stacks.objects[1].stack == 2 and stacks.objects[2].stack == 1 and stacks.objects[3].stack == 0, "earlier stacked circles sit above later circles")
check(stacks.objects[1].x < stacks.objects[2].x and stacks.objects[1].y < stacks.objects[2].y, "stacks have visible position offsets")
local negative = B.Parse(map("100,100,1000,2,0,L|240:100,1,140\n240,100,1600,1,0"))
check(negative.objects[2].stack == -1 and negative.objects[2].x > 240, "circle at slider tail stacks below it")
local cacheMap = map("100,100,1000,1,0\n100,100,1500,1,0", { key = "stack-cache", ar = 10 })
local normal = BC.Library:Parse(cacheMap, {})
local easy = BC.Library:Parse(cacheMap, { ez = true })
check(normal.objects[1].stack == 0 and easy.objects[1].stack == 1, "Easy stacking uses its own cache and approach rate")
local hard = B.Parse(map("100,100,1000,1,0\n100,100,1100,1,0"), { hr = true })
check(hard.objects[1].y > hard.objects[2].y, "Hard Rock also flips stack offsets")

local reduced = BC.Scoring.New(0.5)
reduced:Judge(300)
check(reduced.score == 150, "No Fail and Easy reduce the entire score")
local increased = BC.Scoring.New(1.06)
increased:Judge(300)
check(increased.score == 318, "Hard Rock increases the entire score")

local song = BC.Library.songs[1]
local cursor = { x = 100, y = 100 }
P.CursorOsu = function() return cursor.x, cursor.y, cursor.x, cursor.y end
local function start(objects, fields)
	local m = map(objects, fields)
	m.key = m.key .. tostring(math.random(1, 1e9))
	m.song = song
	G:Show(P, m, { nf = true })
	for _, obj in ipairs(P.objs) do P:SpawnObject(obj) end
	P.spawnIndex = #P.objs + 1
	return m
end
start("100,100,1000,1,0")
P:Press(1000 + P.w50 + 1)
check(P.tally.miss == 1 and P.tally.score == 0, "late click outside window is a miss")
start("100,100,1000,1,0")
P:Press(1000 - P.w50 - 1)
check(P.tally:Total() == 0 and P.objs[1].shakeAt, "early click shakes its target without awarding score")
P:Press(1000)
check(P.tally.c300 == 1, "on-time click still hits after an early click")
P:Press(1000)
check(P.tally.c300 == 1, "one note cannot be judged twice")
start("200,100,1000,1,0\n100,100,1050,1,0")
P:Press(1050)
check(P.objs[2].judged and not P.objs[1].judged, "an unrelated circle does not swallow a click")

start("100,100,1000,2,0,L|520:100,3,420")
local runtime = P.objs[1]
P:SliderHead(runtime, true, 12)
check(#P.tally.errors == 1 and P.tally.errors[1] == 12, "slider head timing enters unstable rate statistics")
P.held[1] = true
for _, e in ipairs(runtime.events) do
	cursor.x, cursor.y = B.PathAt(runtime.path, e.dist)
	P:UpdateObjects(e.t, GetTime(), 0)
end
P:UpdateObjects(runtime.endTime, GetTime(), 0)
check(P.tally.c300 == 1 and P.tally.maxCombo == P.bm.maxCombo, "perfect tick and repeat tracking earns a full combo")

start("100,100,1000,2,0,L|520:100,1,420")
runtime = P.objs[1]
P:SliderHead(runtime, true, 0)
P.held[1] = false
P:UpdateObjects(runtime.endTime, GetTime(), 0)
check(P.tally.c50 == 1 and P.tally.maxCombo < P.bm.maxCombo, "missing slider checkpoints reduces accuracy and breaks combo")

start("256,192,1000,8,0,3000")
runtime = P.objs[1]
local hp = P.tally.hp
P:SpinnerFinal(runtime)
check(P.tally.miss == 1 and P.tally.hp < hp, "missed spinner costs health")

start("100,100,1000,1,0")
P:Pause()
check(P.paused and not P.playing and P.pauseOverlay:IsShown() and not BC.Clock.playing, "pause stops gameplay and audio together")
local count = P.keyCounts[1]
P:InputDown(1)
check(P.keyCounts[1] == count, "paused inputs do not hit notes")
P:OnKey("ENTER", true)
check(P.playing and not P.paused and not P.pauseOverlay:IsShown(), "Enter restarts paused song")
P:InputDown(1)
P:InputDown(1)
check(P.keyCounts[1] == 1, "key repeats do not produce repeated presses")
P:InputUp(1)
P:Pause()
P:OnKey("ESCAPE", true)
check(G.screen == BC.SongSelect, "Escape leaves pause menu for song select")

start("100,100,1000,1,0")
P:Finish()
P:Retry()
MOCK.Advance(1.3)
check(G.screen == P and not P.finished, "old results timer cannot end a restarted run")
G.root:Hide()
check(not P.playing and not P.screen:IsShown() and not BC.Clock.playing, "externally hiding game cleans up the active screen")

G:Open()
start("100,100,1000,1,0")
check(closeEnough(P.s, 2.25), "playfield fits a 1920 by 1080 screen")
G.root:SetAllPoints(nil)
G.root._allPoints = nil
G.root:SetSize(700, 1000)
P:Layout()
check(P.pf:GetWidth() <= 700 * 0.9 + 0.01, "playfield also fits narrow screens")
G.root:SetAllPoints(UIParent)
P:Layout()
P:Cleanup()
P.objs = {}
for i = 1, 3 do
	local obj = setmetatable({ index = 798 + i }, { __index = stacks.objects[i] })
	P.objs[i] = obj
	P:SpawnObject(obj)
end
check(P.objs[1].head:GetFrameLevel() > P.objs[2].head:GetFrameLevel() and P.objs[2].head:GetFrameLevel() > P.objs[3].head:GetFrameLevel(), "note order remains correct across object 800")
P:Cleanup()
G:Close()

BC.SongSelect:Open()
local select = BC.SongSelect
check(#select.list.data == #BC.Library.songs + #select.song.maps, "selected song expands into difficulty cards")
check(select.list.data[select.selectedIndex].map == select.map, "carousel highlights selected difficulty")
local originalSong = select.song
local extra = { id = "carousel-extra", title = "Extra", artist = "Tester", maps = {} }
for i = 1, 18 do
	extra.maps[i] = { song = extra, key = "extra-" .. i, version = "Difficulty " .. i, stars = i / 3, len = 30000, bpm = 120, n = 10 }
end
select.results = { originalSong, extra }
select:SelectSong(extra, "extra-18")
check(select.map.key == "extra-18" and select.list.data[select.selectedIndex].map == select.map, "carousel supports more than ten difficulties")
check(select.selectedIndex > select.list.offset and select.selectedIndex <= select.list.offset + select.list.numRows, "selected difficulty stays in visible scroll range")
select:SelectSong(originalSong)
select.search:SetText("zzzz-no-matches")
check(#select.list.data == 0, "search clears expanded cards when there are no matches")
select.search:SetText("")
check(#select.list.data > 0, "search restores expanded difficulty cards")
G:Close()

print(string.format("%d gameplay regressions passed, %d failed", passed, failed))
RESULT_FAILED = (RESULT_FAILED or 0) + failed
