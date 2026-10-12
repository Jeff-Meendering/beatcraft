local _, BC = ...

local U = BC.Util
local Beatmap = BC:Module("Beatmap")

local floor, abs, sqrt, atan2, cos, sin, ceil = math.floor, math.abs, math.sqrt, math.atan2, math.cos, math.sin, math.ceil
local PI2 = math.pi * 2

local function hasBit(v, b)
	return floor(v / b) % 2 == 1
end

local function lines(s)
	local out = {}
	if not s then
		return out
	end
	for line in s:gmatch("[^\r\n]+") do
		out[#out + 1] = line
	end
	return out
end

local function bezierPoint(pts, t)
	local n = #pts
	local xs, ys = {}, {}
	for i = 1, n do
		xs[i], ys[i] = pts[i][1], pts[i][2]
	end
	for k = n - 1, 1, -1 do
		for i = 1, k do
			xs[i] = xs[i] + (xs[i + 1] - xs[i]) * t
			ys[i] = ys[i] + (ys[i + 1] - ys[i]) * t
		end
	end
	return xs[1], ys[1]
end

local function polyLength(pts)
	local len = 0
	for i = 2, #pts do
		local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
		len = len + sqrt(dx * dx + dy * dy)
	end
	return len
end

local function appendPoint(out, x, y)
	local last = out[#out]
	if last and abs(last[1] - x) < 0.01 and abs(last[2] - y) < 0.01 then
		return
	end
	out[#out + 1] = { x, y }
end

local function sampleBezierSegment(seg, out)
	if #seg == 2 then
		appendPoint(out, seg[1][1], seg[1][2])
		appendPoint(out, seg[2][1], seg[2][2])
		return
	end
	local steps = U.Clamp(ceil(polyLength(seg) / 5), 4, 200)
	for i = 0, steps do
		local x, y = bezierPoint(seg, i / steps)
		appendPoint(out, x, y)
	end
end

local function sampleBezier(pts, out)
	local seg = { pts[1] }
	for i = 2, #pts do
		local p, prev = pts[i], pts[i - 1]
		if p[1] == prev[1] and p[2] == prev[2] then
			if #seg >= 2 then
				sampleBezierSegment(seg, out)
			end
			seg = { p }
		else
			seg[#seg + 1] = p
		end
	end
	if #seg >= 2 then
		sampleBezierSegment(seg, out)
	end
end

local function sampleArc(pts, out)
	local a, b, c = pts[1], pts[2], pts[3]
	local ax, ay, bx, by, cx, cy = a[1], a[2], b[1], b[2], c[1], c[2]
	local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
	if abs(d) < 1e-3 then
		return false
	end
	local aa, bb, cc = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
	local ux = (aa * (by - cy) + bb * (cy - ay) + cc * (ay - by)) / d
	local uy = (aa * (cx - bx) + bb * (ax - cx) + cc * (bx - ax)) / d
	local r = sqrt((ax - ux) ^ 2 + (ay - uy) ^ 2)
	local t0 = atan2(ay - uy, ax - ux)
	local t2 = atan2(cy - uy, cx - ux)
	local cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	local range = t2 - t0
	if cross < 0 then
		while range > 0 do
			range = range - PI2
		end
	else
		while range < 0 do
			range = range + PI2
		end
	end
	local steps = U.Clamp(ceil(abs(range) * r / 5), 8, 200)
	for i = 0, steps do
		local ang = t0 + range * i / steps
		appendPoint(out, ux + r * cos(ang), uy + r * sin(ang))
	end
	return true
end

local function sampleCatmull(pts, out)
	local n = #pts
	for i = 1, n - 1 do
		local v1 = pts[i - 1] or pts[i]
		local v2 = pts[i]
		local v3 = pts[i + 1]
		local v4 = pts[i + 2] or { 2 * v3[1] - v2[1], 2 * v3[2] - v2[2] }
		for s = 0, 50 do
			local t = s / 50
			local t2, t3 = t * t, t * t * t
			local x = 0.5 * (2 * v2[1] + (-v1[1] + v3[1]) * t + (2 * v1[1] - 5 * v2[1] + 4 * v3[1] - v4[1]) * t2 + (-v1[1] + 3 * v2[1] - 3 * v3[1] + v4[1]) * t3)
			local y = 0.5 * (2 * v2[2] + (-v1[2] + v3[2]) * t + (2 * v1[2] - 5 * v2[2] + 4 * v3[2] - v4[2]) * t2 + (-v1[2] + 3 * v2[2] - 3 * v3[2] + v4[2]) * t3)
			appendPoint(out, x, y)
		end
	end
end

local function buildPath(ctype, pts, length)
	local poly = {}
	if ctype == "L" then
		for _, p in ipairs(pts) do
			appendPoint(poly, p[1], p[2])
		end
	elseif ctype == "P" and #pts == 3 and sampleArc(pts, poly) then
	elseif ctype == "C" then
		sampleCatmull(pts, poly)
	else
		sampleBezier(pts, poly)
	end
	if #poly < 2 then
		poly = { { pts[1][1], pts[1][2] }, { pts[1][1] + 0.01, pts[1][2] } }
	end

	local xs, ys, cum = { poly[1][1] }, { poly[1][2] }, { 0 }
	local total = 0
	for i = 2, #poly do
		local dx, dy = poly[i][1] - poly[i - 1][1], poly[i][2] - poly[i - 1][2]
		local seg = sqrt(dx * dx + dy * dy)
		if length and total + seg >= length then
			local f = seg > 0 and (length - total) / seg or 0
			xs[#xs + 1] = poly[i - 1][1] + dx * f
			ys[#ys + 1] = poly[i - 1][2] + dy * f
			cum[#cum + 1] = length
			total = length
			break
		end
		total = total + seg
		xs[#xs + 1], ys[#ys + 1], cum[#cum + 1] = poly[i][1], poly[i][2], total
	end
	if length and total < length then
		local n = #xs
		local dx, dy = xs[n] - xs[n - 1], ys[n] - ys[n - 1]
		local seg = sqrt(dx * dx + dy * dy)
		if seg > 0 then
			local extra = length - total
			xs[n + 1] = xs[n] + dx / seg * extra
			ys[n + 1] = ys[n] + dy / seg * extra
			cum[n + 1] = length
			total = length
		end
	end
	return { x = xs, y = ys, cum = cum, length = total }
end

function Beatmap.PathAt(path, d)
	local cum = path.cum
	local n = #cum
	if d <= 0 then
		return path.x[1], path.y[1]
	end
	if d >= cum[n] then
		return path.x[n], path.y[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = floor((lo + hi) / 2)
		if cum[mid] < d then
			lo = mid
		else
			hi = mid
		end
	end
	local span = cum[hi] - cum[lo]
	local f = span > 0 and (d - cum[lo]) / span or 0
	return path.x[lo] + (path.x[hi] - path.x[lo]) * f, path.y[lo] + (path.y[hi] - path.y[lo]) * f
end

function Beatmap.SliderBall(obj, t)
	local progress = (t - obj.t) / obj.span
	if progress < 0 then
		progress = 0
	end
	local maxP = obj.slides
	if progress > maxP then
		progress = maxP
	end
	local span = floor(progress)
	local frac = progress - span
	if span >= obj.slides then
		span, frac = obj.slides - 1, 1
	end
	if span % 2 == 1 then
		frac = 1 - frac
	end
	return Beatmap.PathAt(obj.path, frac * obj.path.length)
end

local function parseTiming(s)
	local points = {}
	for _, line in ipairs(lines(s)) do
		local f = U.Split(line, ",")
		local t, bl = tonumber(f[1]), tonumber(f[2])
		if t and bl then
			local uninherited = f[7] == nil or f[7] == "1"
			if bl < 0 and f[7] == nil then
				uninherited = false
			end
			points[#points + 1] = {
				t = t,
				beatLength = bl,
				meter = tonumber(f[3]) or 4,
				red = uninherited and bl > 0,
				kiai = (tonumber(f[8]) or 0) % 2 == 1,
				sampleSet = tonumber(f[4]) or 0,
				sampleIndex = tonumber(f[5]) or 0,
			}
		end
	end
	return points
end

local function parseColors(s)
	local colors = {}
	if s and s ~= "" then
		for _, c in ipairs(U.Split(s, ";")) do
			local r, g, b = c:match("(%d+),(%d+),(%d+)")
			if r then
				colors[#colors + 1] = { tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255 }
			end
		end
	end
	if #colors == 0 then
		colors = U.COMBO_COLORS
	end
	return colors
end

local function sliderEvents(obj, map, sm, sv)
	obj.events, obj.tickDistances = {}, {}
	local tickDist = sm * 100 * sv / math.max(0.1, map.tr or 1)
	if (map.formatVersion or 14) < 8 then tickDist = tickDist / sv end
	local minEnd = obj.path.length / obj.span * 10
	local d = tickDist
	while d < obj.path.length - minEnd and #obj.tickDistances < 1024 do
		obj.tickDistances[#obj.tickDistances + 1] = d
		d = d + tickDist
	end
	for span = 0, obj.slides - 1 do
		for _, dist in ipairs(obj.tickDistances) do
			local p = dist / obj.path.length
			local t = obj.t + obj.span * (span + (span % 2 == 0 and p or 1 - p))
			obj.events[#obj.events + 1] = { t = t, dist = dist, kind = "tick", span = span }
		end
		if span < obj.slides - 1 then
			obj.events[#obj.events + 1] = { t = obj.t + obj.span * (span + 1), dist = span % 2 == 0 and obj.path.length or 0, kind = "repeat", span = span, edge = span + 2 }
		end
	end
	obj.events[#obj.events + 1] = { t = math.max(obj.t + (obj.endTime - obj.t) / 2, obj.endTime - 36), dist = obj.slides % 2 == 1 and obj.path.length or 0, kind = "tail", span = obj.slides - 1, edge = obj.slides + 1 }
	table.sort(obj.events, function(a, b) return a.t < b.t end)
end

function Beatmap.ApplyStacking(bm, mods)
	local objects = bm.objects
	local ar, _, cs = Beatmap.ModdedStats(bm.map, mods)
	local threshold = Beatmap.Preempt(ar) * (bm.map.stack or 0.7)
	local function near(ax, ay, bx, by)
		return (ax - bx) ^ 2 + (ay - by) ^ 2 < 9
	end
	for _, o in ipairs(objects) do o.stack = 0 end
	for i = #objects, 2, -1 do
		local current = objects[i]
		if current.stack == 0 and current.kind ~= "spinner" then
			for j = i - 1, 1, -1 do
				local prev = objects[j]
				if prev.kind ~= "spinner" then
					local endTime = current.kind == "slider" and prev.t or prev.endTime
					if current.t - endTime > threshold then break end
					if current.kind == "circle" and prev.kind == "slider" and near(prev.endX, prev.endY, current.x, current.y) then
						local offset = current.stack - prev.stack + 1
						for k = j + 1, i do
							local o = objects[k]
							if near(prev.endX, prev.endY, o.x, o.y) then o.stack = o.stack - offset end
							end
						break
					end
					local x, y = prev.x, prev.y
					if current.kind == "slider" then x, y = prev.endX or x, prev.endY or y end
					if near(x, y, current.x, current.y) then
						prev.stack = current.stack + 1
						current = prev
					end
				end
			end
		end
	end
	local scale = Beatmap.Radius(cs) / 10
	for _, o in ipairs(objects) do
		local dx, dy = -o.stack * scale, -o.stack * scale
		if mods and mods.hr then dy = -dy end
		o.x, o.y = o.x + dx, o.y + dy
		if o.path then
			for j = 1, #o.path.x do
				o.path.x[j], o.path.y[j] = o.path.x[j] + dx, o.path.y[j] + dy
			end
			o.endX, o.endY = o.endX + dx, o.endY + dy
		end
	end
end

function Beatmap.Parse(map, mods)
	local bm = {
		map = map,
		timing = parseTiming(map.timing),
		objects = {},
		breaks = {},
		colors = parseColors(map.colors),
	}
	bm.red = {}
	for _, p in ipairs(bm.timing) do
		if p.red then
			bm.red[#bm.red + 1] = p
		end
	end
	if #bm.red == 0 then
		bm.red[1] = { t = 0, beatLength = 500, meter = 4, red = true }
	end

	for _, line in ipairs(lines(map.breaks)) do
		local s, e = line:match("(%-?%d+),(%-?%d+)")
		if s then
			bm.breaks[#bm.breaks + 1] = { s = tonumber(s), e = tonumber(e) }
		end
	end

	local flip = mods and mods.hr
	local sm = math.max(0.1, map.sm or 1.4)
	local tpIndex, beatLength, sv = 1, bm.red[1].beatLength, 1
	local sampleSet, sampleIndex = 1, 0
	local combo, colorIndex, maxCombo = 0, 0, 0
	local forceNewCombo = true

	for _, line in ipairs(lines(map.objects)) do
		local f = U.Split(line, ",")
		local x, y, t, typ = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
		if x and y and t and typ then
			while bm.timing[tpIndex] and bm.timing[tpIndex].t <= t + 1 do
				local p = bm.timing[tpIndex]
				if p.red then
					beatLength, sv = p.beatLength, 1
				elseif p.beatLength < 0 then
					sv = U.Clamp(-100 / p.beatLength, 0.1, 10)
				end
				if p.sampleSet > 0 then
					sampleSet = p.sampleSet
				end
				sampleIndex = p.sampleIndex
				tpIndex = tpIndex + 1
			end
			if flip then
				y = 384 - y
			end
			local obj = { x = x, y = y, t = t, hs = tonumber(f[5]) or 0, set = sampleSet, sidx = sampleIndex }
			local isSpinner = hasBit(typ, 8)
			if hasBit(typ, 4) or forceNewCombo or isSpinner then
				colorIndex = colorIndex + 1 + (floor(typ / 16) % 8)
				combo = 0
				obj.newCombo = true
			end
			obj.beatLength = beatLength
			forceNewCombo = isSpinner
			if hasBit(typ, 2) then
				local parts = U.Split(f[6] or "", "|")
				local pts = { { x, y } }
				for i = 2, #parts do
					local px, py = parts[i]:match("^(%-?[%d%.]+):(%-?[%d%.]+)$")
					if px then
						px, py = tonumber(px), tonumber(py)
						if flip then
							py = 384 - py
						end
						pts[#pts + 1] = { px, py }
					end
				end
				obj.kind = "slider"
				obj.slides = U.Clamp(floor(tonumber(f[7]) or 1), 1, 1000)
				local length = tonumber(f[8])
				if not length or length <= 0 then
					length = polyLength(pts)
				end
				obj.path = buildPath(parts[1], pts, length)
				local pxPerBeat = sm * 100 * sv
				obj.span = math.max(1, obj.path.length / pxPerBeat * beatLength)
				obj.endTime = t + obj.span * obj.slides
				obj.endX, obj.endY = Beatmap.SliderBall(obj, obj.endTime)
				sliderEvents(obj, map, sm, sv)
				obj.edgeSounds = U.Split(f[9] or "", "|")
				obj.edgeSets = U.Split(f[10] or "", "|")
				maxCombo = maxCombo + 1 + #obj.events
			elseif isSpinner then
				obj.kind = "spinner"
				obj.x, obj.y = 256, 192
				obj.endTime = math.max(t + 1, tonumber(f[6]) or t + 1)
				maxCombo = maxCombo + 1
			elseif hasBit(typ, 1) then
				obj.kind = "circle"
				maxCombo = maxCombo + 1
			end
			if obj.kind then
				if obj.kind ~= "spinner" then
					combo = combo + 1
					obj.number = combo
				end
				obj.color = bm.colors[((colorIndex - 1) % #bm.colors) + 1]
				obj.endTime = obj.endTime or t
				bm.objects[#bm.objects + 1] = obj
			end
		end
	end

	bm.kiai = {}
	local kiaiStart
	for _, p in ipairs(bm.timing) do
		if p.kiai and not kiaiStart then
			kiaiStart = p.t
		elseif not p.kiai and kiaiStart then
			bm.kiai[#bm.kiai + 1] = { s = kiaiStart, e = p.t }
			kiaiStart = nil
		end
	end
	if kiaiStart then
		bm.kiai[#bm.kiai + 1] = { s = kiaiStart, e = math.huge }
	end

	Beatmap.ApplyStacking(bm, mods)
	bm.maxCombo = maxCombo
	bm.firstTime = bm.objects[1] and bm.objects[1].t or 0
	bm.lastTime = 0
	for _, o in ipairs(bm.objects) do bm.lastTime = math.max(bm.lastTime, o.endTime) end
	return bm
end

function Beatmap.RedAt(bm, t)
	local red = bm.red
	local cur = red[1]
	for i = 2, #red do
		if red[i].t <= t then
			cur = red[i]
		else
			break
		end
	end
	return cur
end

function Beatmap.GridAtOrBefore(bm, t, div)
	local tp = Beatmap.RedAt(bm, t)
	local step = tp.beatLength / (div or 1)
	return tp.t + floor((t - tp.t) / step) * step
end

function Beatmap.NearestGrid(bm, t, div)
	local tp = Beatmap.RedAt(bm, t)
	local step = tp.beatLength / (div or 1)
	local k = floor((t - tp.t) / step + 0.5)
	local g = tp.t + k * step
	return g, t - g
end

function Beatmap.InKiai(bm, t)
	for _, k in ipairs(bm.kiai) do
		if t >= k.s and t < k.e then
			return true
		end
	end
	return false
end

function Beatmap.BeatPulse(bm, t)
	local tp = Beatmap.RedAt(bm, t)
	local phase = ((t - tp.t) % tp.beatLength) / tp.beatLength
	return 1 - phase
end

function Beatmap.BPM(bm)
	return 60000 / bm.red[1].beatLength
end

function Beatmap.Stars(map)
	local seconds = math.max((map.len or 60000) / 1000, 1)
	local density = (map.n or 0) / seconds
	local ar, od, cs = map.ar or 5, map.od or 5, map.cs or 4
	local stars = 0.4 + density * 0.8 + math.max(0, ar - 7) * 0.25 + math.max(0, od - 7) * 0.1 + math.max(0, cs - 4) * 0.15
	return U.Clamp(stars, 0.1, 12)
end

function Beatmap.ModdedStats(map, mods)
	local ar, od, cs, hp = map.ar or map.od or 5, map.od or 5, map.cs or 4, map.hp or 5
	if mods and mods.hr then
		ar, od, hp = math.min(10, ar * 1.4), math.min(10, od * 1.4), math.min(10, hp * 1.4)
		cs = math.min(10, cs * 1.3)
	elseif mods and mods.ez then
		ar, od, cs, hp = ar * 0.5, od * 0.5, cs * 0.5, hp * 0.5
	end
	return ar, od, cs, hp
end

function Beatmap.Preempt(ar)
	if ar < 5 then
		return 1200 + 600 * (5 - ar) / 5
	end
	return 1200 - 750 * (ar - 5) / 5
end

function Beatmap.Radius(cs)
	return 54.4 - 4.48 * cs
end
