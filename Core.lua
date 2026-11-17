-- Blacklist: Core.lua
--
-- Your own list of players to avoid. Each entry keeps a note, when it was
-- added and the zone you were in.
--
--   /bl                    open the window
--   /bl add [name] [note]  add a player (no name = your target)
--   /bl remove <name>      remove a player
--   /bl check <name>       is this player on your list?
--   /bl share [on|off|now] friend sync (see Share.lua)
--   /bl alerts [on|off]    Group Finder / invite / group warnings
--   /bl icons [on|off]     red X on nameplates
--   /bl debug              shows which warning hooks are active
--
-- You can also right-click a player (target, party, chat name) and choose
-- "Add to Blacklist".

local addonName, ns = ...

ns.TAG = "|cffff5050Blacklist|r: "

local function Print(msg) print(ns.TAG .. msg) end
ns.Print = Print

--------------------------------------------------------------------------
-- Saved data
--   BlacklistDB.entries[key] = { name, realm, note, added, zone, subzone,
--                                class, by, origin? }
--   key = lower-case "name-realm"
--------------------------------------------------------------------------

function ns.DB()
	BlacklistDB = BlacklistDB or {}
	local db = BlacklistDB
	db.entries = db.entries or {}
	db.shared = db.shared or {}   -- [peerName] = { received, entries = { [key] = entry } }
	db.share = db.share or {}     -- sync settings, see Share.lua
	if db.alerts == nil then db.alerts = true end
	db.version = 1
	return db
end

local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
ns.Plain = Plain

function ns.MyRealm()
	local r = GetNormalizedRealmName and GetNormalizedRealmName()
	if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
	return r
end

-- "Name", "Name-Realm" or "Name - Realm" -> "Name", "Realm" (realm may be nil)
function ns.SplitName(full)
	full = Plain(full)
	if type(full) ~= "string" then return nil end
	full = full:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if full == "" then return nil end
	local name, realm = full:match("^([^%-%s]+)%s*%-%s*(.+)$")
	if not name then name = full:match("^([^%-%s]+)") end
	if not name then return nil end
	if realm then realm = realm:gsub("%s", "") end
	if realm == "" then realm = nil end
	-- Capitalise like the game does: first letter upper, the rest lower.
	local first, rest = name:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
	if first then name = first:upper() .. rest:lower() end
	return name, realm
end

function ns.Key(name, realm)
	return (name .. "-" .. (realm or ns.MyRealm())):lower()
end

-- Index of short (realm-less) names, rebuilt whenever the list changes.
local shortIndex = {}

function ns.Rebuild()
	wipe(shortIndex)
	for key, e in pairs(ns.DB().entries) do
		local s = e.name:lower()
		shortIndex[s] = shortIndex[s] or {}
		table.insert(shortIndex[s], key)
	end
	if ns.OnListChanged then ns.OnListChanged() end
	if ns.RefreshNameplates then pcall(ns.RefreshNameplates) end
end

-- Returns the entry for a player, or nil. Accepts "Name" or "Name-Realm".
-- Every W4 realm shares one world for grouping, so a name without a realm
-- matches that name on any realm (your own realm first).
function ns.Find(full)
	local name, realm = ns.SplitName(full)
	if not name then return nil end
	local entries = ns.DB().entries
	if realm then
		return entries[ns.Key(name, realm)]
	end
	local e = entries[ns.Key(name)]
	if e then return e end
	local keys = shortIndex[name:lower()]
	return keys and entries[keys[1]]
end

-- A cheap check by short name only, for scanning tooltip text.
function ns.HasShort(short)
	return short and shortIndex[short:lower()] ~= nil
end

function ns.Zone()
	local zone = GetRealZoneText and GetRealZoneText() or GetZoneText() or ""
	local sub = GetSubZoneText and GetSubZoneText() or ""
	if sub == zone then sub = "" end
	return zone, sub
end

-- Adds or updates a player. Returns the entry, or nil and a reason.
function ns.Add(full, note, extra)
	local name, realm = ns.SplitName(full)
	if not name then return nil, "no player name given" end
	realm = realm or ns.MyRealm()
	local key = ns.Key(name, realm)
	local db = ns.DB()
	local e = db.entries[key]
	if e then
		if note and note ~= "" then e.note = note end
	else
		local zone, sub = ns.Zone()
		e = {
			name = name, realm = realm, note = note or "",
			added = time(), zone = zone, subzone = sub,
			by = UnitName("player"),
		}
		db.entries[key] = e
	end
	if extra then
		for k, v in pairs(extra) do e[k] = v end
	end
	ns.Rebuild()
	return e
end

function ns.Remove(full)
	local e = ns.Find(full)
	if not e then return false end
	ns.DB().entries[ns.Key(e.name, e.realm)] = nil
	ns.Rebuild()
	return true, e
end

function ns.Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function ns.FormatDate(t)
	return t and date("%d %b %Y %H:%M", t) or "?"
end

function ns.Where(e)
	if not e.zone or e.zone == "" then return "unknown" end
	if e.subzone and e.subzone ~= "" then return e.subzone .. ", " .. e.zone end
	return e.zone
end

function ns.Display(e)
	if e.realm and e.realm ~= ns.MyRealm() then return e.name .. "-" .. e.realm end
	return e.name
end

-- One-line summary used in chat warnings.
function ns.Reason(e)
	local note = (e.note and e.note ~= "") and e.note or "no note"
	return ("%s (added %s, %s)"):format(note, date("%d %b", e.added or 0), ns.Where(e))
end

--------------------------------------------------------------------------
-- Adding from a unit (target, mouseover, party member)
--------------------------------------------------------------------------

function ns.AddUnit(unit, note)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil, "that isn't a player" end
	if UnitIsUnit(unit, "player") then return nil, "you can't add yourself" end
	local name, realm = UnitName(unit)
	name, realm = Plain(name), Plain(realm)
	if not name then return nil, "couldn't read the name" end
	local _, class = UnitClass(unit)
	local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
	return ns.Add(full, note, { class = Plain(class), level = Plain(UnitLevel(unit)) })
end

--------------------------------------------------------------------------
-- Right-click menu entry
--------------------------------------------------------------------------

local MENUS = {
	"MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY",
	"MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_CHAT_ROSTER",
	"MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_ENEMY_PLAYER",
	"MENU_UNIT_RAID", "MENU_LFG_FRAME_SEARCH_ENTRY", "MENU_LFG_FRAME_MEMBER_APPLY",
}

local function MenuName(context)
	if not context then return nil end
	local name = Plain(context.name)
	local server = Plain(context.server)
	if (not name or name == "") and context.unit then
		local n, r = UnitName(context.unit)
		name, server = Plain(n), Plain(r)
	end
	if not name or name == "" then return nil end
	if server and server ~= "" then name = name .. "-" .. server end
	return name
end

ns.hooks = {}

local function HookMenus()
	if not (Menu and Menu.ModifyMenu) then return end
	for _, tag in ipairs(MENUS) do
		local ok = pcall(Menu.ModifyMenu, tag, function(owner, root, context)
			local full = MenuName(context)
			if not full then return end
			local cls = context.unit and select(2, UnitClass(context.unit))
			root:CreateDivider()
			local e = ns.Find(full)
			if e then
				root:CreateButton("|cffff5050Blacklist: edit note|r", function() ns.OpenEditor(full) end)
			else
				root:CreateButton("|cffff5050Add to Blacklist|r", function()
					ns.OpenEditor(full, { class = Plain(cls) })
				end)
			end
		end)
		if ok then ns.hooks.menu = (ns.hooks.menu or 0) + 1 end
	end
end

--------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------

local function Slash(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "show" then
		ns.ToggleWindow()
	elseif cmd == "add" then
		local name, note = rest:match("^(%S+)%s*(.-)$")
		if not name then
			-- no name: open the editor for your target
			if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
				local n, r = UnitName("target")
				local _, cls = UnitClass("target")
				n, r = Plain(n), Plain(r)
				if n then
					ns.OpenEditor((r and r ~= "") and (n .. "-" .. r) or n, { class = Plain(cls), level = Plain(UnitLevel("target")) })
					return
				end
			end
			Print("target a player, or use /bl add <name> <note>.")
			return
		end
		local e, err = ns.Add(name, note)
		if e then
			Print(("added %s: %s"):format(ns.Display(e), e.note ~= "" and e.note or "no note (add one in /bl)"))
		else
			Print("couldn't add: " .. (err or "?") .. ". Use /bl add <name> <note>, or target the player.")
		end
	elseif cmd == "remove" or cmd == "del" then
		local ok, e = ns.Remove(rest)
		Print(ok and ("removed " .. ns.Display(e) .. ".") or ("%s isn't on your list."):format(rest))
	elseif cmd == "check" then
		local who = rest ~= "" and rest or (UnitExists("target") and UnitName("target"))
		local e = who and ns.Find(who)
		if e then Print(("%s is on your list: %s"):format(ns.Display(e), ns.Reason(e)))
		else Print(("%s is not on your list."):format(who or "nobody")) end
	elseif cmd == "share" then
		ns.ShareCommand(rest)
	elseif cmd == "alerts" then
		local db = ns.DB()
		if rest == "on" then db.alerts = true elseif rest == "off" then db.alerts = false end
		Print("warnings are " .. (db.alerts and "on" or "off") .. ".")
	elseif cmd == "icons" then
		local db = ns.DB()
		if rest == "on" then db.nameplates = true elseif rest == "off" then db.nameplates = false end
		if ns.RefreshNameplates then pcall(ns.RefreshNameplates) end
		Print("nameplate icons are " .. (db.nameplates ~= false and "on" or "off") .. ".")
	elseif cmd == "debug" then
		local active = {}
		for k, v in pairs(ns.hooks) do active[#active + 1] = k .. (v ~= true and ("=" .. tostring(v)) or "") end
		table.sort(active)
		Print(("%d players, %d shared lists. Hooks: %s"):format(ns.Count(ns.DB().entries), ns.Count(ns.DB().shared),
			#active > 0 and table.concat(active, ", ") or "none"))
		if ns.lastTooltipOwner then print("  last Group Finder tooltip owner: " .. ns.lastTooltipOwner) end
	else
		Print("/bl, /bl add [name] [note], /bl remove <name>, /bl check [name], /bl share, /bl alerts on|off, /bl icons on|off")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")
	ns.DB()
	ns.Rebuild()
	pcall(HookMenus)
	SLASH_BLACKLIST1 = "/bl"
	SLASH_BLACKLIST2 = "/blacklist"
	SlashCmdList.BLACKLIST = Slash
	if ns.OnLoaded then ns.OnLoaded() end
end)
