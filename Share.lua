-- Blacklist: Share.lua
--
-- Swaps lists with the people on your Friends list (character or Battle.net
-- friends) who also run Blacklist. Their lists land in the "Shared" tab;
-- nothing goes into your own list until you import it.
--
-- Nothing is announced: only hidden addon whispers to online friends, and
-- only lists from people on your Friends list are accepted. Each sync sends
-- the whole list, so a player your friend removes disappears from your
-- Shared tab too.
--
--   /bl share         status, and who you've synced with
--   /bl share now     sync right away
--   /bl share off|on  stop or resume sharing
--
-- When it syncs: shortly after login, when a friend comes online, once an
-- hour, and when you press Sync in the Shared tab.

local addonName, ns = ...

local PREFIX = "BList1"
local SEND_INTERVAL = 0.6
local SYNC_INTERVAL = 3600
local MIN_REQUEST_GAP = 300
local CHUNK = 200

local Plain = ns.Plain

local function S()
	local s = ns.DB().share
	s.peers = s.peers or {} -- [name] = { lastAsked, lastSync }
	if s.enabled == nil then s.enabled = true end
	return s
end

local function Short(name)
	name = Plain(name)
	if not name then return nil end
	return Ambiguate and Ambiguate(name, "none") or name:match("^[^%-]+")
end

--------------------------------------------------------------------------
-- Friends (same approach as MarketScribe)
--------------------------------------------------------------------------

local bnetID, bnetName = {}, {}

local function BNetFriends(out)
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts) then return end
	local myFaction, myProject = UnitFactionGroup("player"), WOW_PROJECT_ID
	for i = 1, BNGetNumFriends() or 0 do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
			local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
			local name = g and Short(g.characterName)
			if name and name ~= "" and Plain(g.clientProgram) == (BNET_CLIENT_WOW or "WoW") and g.isOnline ~= false
				and (not myProject or not Plain(g.wowProjectID) or Plain(g.wowProjectID) == myProject)
				and (not g.factionName or Plain(g.factionName) == myFaction) then
				out[name] = true
				local id = Plain(g.gameAccountID)
				if id then bnetID[name] = id; bnetName[id] = name end
			end
		end
	end
end

local function Friends()
	local out = {}
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			local n = info and Short(info.name)
			if n then out[n] = info.connected and true or false end
		end
	end
	pcall(BNetFriends, out)
	return out
end

local function IsFriend(name) return Friends()[name] ~= nil end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

local outbox = {}
local function Whisper(target, msg) table.insert(outbox, { target = target, msg = msg }) end

C_Timer.NewTicker(SEND_INTERVAL, function()
	local item = table.remove(outbox, 1)
	if not item then return end
	local id = bnetID[item.target]
	if id and BNSendGameData then
		pcall(BNSendGameData, id, PREFIX, item.msg)
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if send then pcall(send, PREFIX, item.msg, "WHISPER", item.target) end
end)

-- Fields are joined with ";" and percent-escaped.
local FIELDS = { "name", "realm", "added", "zone", "subzone", "class", "note" }

local function Esc(v)
	return (tostring(v or ""):gsub("[%%;|\r\n\t:]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Unesc(v)
	return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function ns.Encode(e)
	local parts = {}
	for i, f in ipairs(FIELDS) do parts[i] = Esc(e[f]) end
	return table.concat(parts, ";")
end

function ns.Decode(s)
	local e, i = {}, 0
	for field in (s .. ";"):gmatch("([^;]*);") do
		i = i + 1
		local key = FIELDS[i]
		if key then e[key] = Unesc(field) end
	end
	if not e.name or e.name == "" then return nil end
	e.added = tonumber(e.added) or 0
	if e.class == "" then e.class = nil end
	return e
end

local function SendList(target)
	local list = {}
	for _, e in pairs(ns.DB().entries) do list[#list + 1] = ns.Encode(e) end
	Whisper(target, "S:" .. #list)
	for i, s in ipairs(list) do
		local n = math.max(1, math.ceil(#s / CHUNK))
		for p = 1, n do
			Whisper(target, ("D:%d:%d:%d:%s"):format(i, p, n, s:sub((p - 1) * CHUNK + 1, p * CHUNK)))
		end
	end
	Whisper(target, "Z:" .. #list)
end

local function Request(name, force)
	local s = S()
	if not s.enabled then return end
	s.peers[name] = s.peers[name] or {}
	local p = s.peers[name]
	if not force and p.lastAsked and time() - p.lastAsked < MIN_REQUEST_GAP then return end
	p.lastAsked = time()
	Whisper(name, "Q")
end

function ns.SyncAll(force)
	if not S().enabled then return 0 end
	local n = 0
	for name, online in pairs(Friends()) do
		if online then Request(name, force); n = n + 1 end
	end
	return n
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

local pending = {} -- [name] = { count, parts = { [i] = { [p] = chunk, n = parts } } }

local function Finish(name)
	local inc = pending[name]
	pending[name] = nil
	if not inc then return end
	local entries = {}
	for _, chunks in pairs(inc.parts) do
		local whole = {}
		local complete = true
		for p = 1, chunks.n do
			if not chunks[p] then complete = false break end
			whole[p] = chunks[p]
		end
		local e = complete and ns.Decode(table.concat(whole))
		if e then entries[ns.Key(e.name, e.realm ~= "" and e.realm or nil)] = e end
	end
	local db = ns.DB()
	db.shared[name] = { received = time(), entries = entries }
	S().peers[name] = S().peers[name] or {}
	S().peers[name].lastSync = time()
	if ns.OnListChanged then ns.OnListChanged() end
end

local function OnMessage(msg, sender)
	local name = Short(sender)
	if not name or not S().enabled or not IsFriend(name) then return end
	local kind, body = msg:match("^(%a):?(.*)$")
	if kind == "Q" then
		SendList(name)
		Request(name) -- ask back, so both sides stay current
	elseif kind == "S" then
		pending[name] = { count = tonumber(body) or 0, parts = {} }
	elseif kind == "D" and pending[name] then
		local i, p, n, chunk = body:match("^(%d+):(%d+):(%d+):(.*)$")
		i, p, n = tonumber(i), tonumber(p), tonumber(n)
		if i and p and n then
			local parts = pending[name].parts
			parts[i] = parts[i] or { n = n }
			parts[i][p] = chunk
		end
	elseif kind == "Z" then
		Finish(name)
	end
end
ns.OnShareMessage = OnMessage -- for testing

-- Copies one player from a friend's list into yours.
function ns.Import(peer, key)
	local list = ns.DB().shared[peer]
	local src = list and list.entries[key]
	if not src then return nil end
	local mine = ns.Find(src.name .. "-" .. src.realm)
	if mine then return mine, true end -- already on your list; keep your note
	local note = src.note ~= "" and src.note or "no note"
	local e = ns.Add(src.name .. "-" .. src.realm, ("%s (from %s)"):format(note, peer), {
		class = src.class, origin = peer, originAdded = src.added,
		originZone = ns.Where(src),
	})
	return e
end

function ns.ShareCommand(rest)
	local cmd = (rest or ""):match("^(%S*)")
	local s = S()
	if cmd == "now" then
		local n = ns.SyncAll(true)
		ns.Print(("asking %d online friend(s) for their lists."):format(n))
	elseif cmd == "off" then
		s.enabled = false
		ns.Print("sharing is off.")
	elseif cmd == "on" then
		s.enabled = true
		ns.SyncAll(true)
		ns.Print("sharing is on.")
	else
		ns.Print(("sharing is %s (with your Friends list)."):format(s.enabled and "on" or "off"))
		local online = {}
		for name, on in pairs(Friends()) do if on then online[#online + 1] = name end end
		table.sort(online)
		print("  online friends it can ask: " .. (#online > 0 and table.concat(online, ", ") or "none"))
		local any = false
		for name, list in pairs(ns.DB().shared) do
			any = true
			print(("  %s: %d players, received %s"):format(name, ns.Count(list.entries), ns.FormatDate(list.received)))
		end
		if not any then print("  no friend has sent a list yet. They need Blacklist and you on their Friends list.") end
	end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local wasOnline = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("BN_CHAT_MSG_ADDON")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("BN_FRIEND_INFO_CHANGED")
f:SetScript("OnEvent", function(_, event, a, b, c, d)
	if event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
		if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
		C_Timer.After(25, function() wasOnline = Friends(); ns.SyncAll() end)
		C_Timer.NewTicker(SYNC_INTERVAL, function() ns.SyncAll() end)
	elseif event == "CHAT_MSG_ADDON" then
		if a == PREFIX and c == "WHISPER" then OnMessage(b, d) end
	elseif event == "BN_CHAT_MSG_ADDON" then
		if a ~= PREFIX then return end
		local name = bnetName[d]
		if not name then Friends(); name = bnetName[d] end
		if name then OnMessage(b, name) end
	else
		local now = Friends()
		for name, online in pairs(now) do
			if online and not wasOnline[name] then C_Timer.After(10, function() Request(name) end) end
		end
		wasOnline = now
	end
end)
