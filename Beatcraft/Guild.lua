local _, BC = ...

local Compat = BC.Compat
local U = BC.Util
local Guild = BC:Module("Guild")

local PREFIX = "Beatcraft"

function Guild:OnInit()
	Compat.RegisterPrefix(PREFIX)
end

local function store(mapKey, player, score, acc, grade, combo)
	local all = BC.db.guildScores
	all[mapKey] = all[mapKey] or {}
	local cur = all[mapKey][player]
	if not cur or score > cur.score then
		all[mapKey][player] = { score = score, acc = acc, grade = grade, combo = combo, date = time() }
	end
end

function Guild:SharePB(map, rec)
	local me = UnitName("player")
	store(map.key, me, rec.score, rec.acc, rec.grade, rec.combo)
	if not BC.db.shareGuild or not IsInGuild() or not map.hash then
		return
	end
	local msg = table.concat({ "PB", map.hash, rec.score, string.format("%.4f", rec.acc), rec.grade, rec.combo }, "\t")
	Compat.SendAddonMessage(PREFIX, msg, "GUILD")
end

BC:On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
	if prefix ~= PREFIX or channel ~= "GUILD" then
		return
	end
	local kind, hash, score, acc, grade, combo = strsplit("\t", msg)
	if kind ~= "PB" or not hash then
		return
	end
	score, acc, combo = tonumber(score), tonumber(acc), tonumber(combo)
	if not score or not acc then
		return
	end
	local name = Ambiguate and Ambiguate(sender, "short") or sender
	store(hash, name, score, acc, grade or "?", combo or 0)
end)

function Guild:FormatTop(mapKey, n)
	local entries = {}
	for player, s in pairs(BC.db.guildScores[mapKey] or {}) do
		entries[#entries + 1] = { player = player, s = s }
	end
	if #entries == 0 then
		return "|cff888888No guild scores yet.|r"
	end
	table.sort(entries, function(a, b)
		return a.s.score > b.s.score
	end)
	local out = { "|cff" .. BC.ACCENT_HEX .. "Guild top|r" }
	for i = 1, math.min(n, #entries) do
		local e = entries[i]
		out[#out + 1] = string.format("%d. %s  %s  %s", i, e.player, U.FormatNumber(e.s.score), U.FormatAcc(e.s.acc))
	end
	return table.concat(out, "\n")
end
