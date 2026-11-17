-- Blacklist: Alerts.lua
--
-- Warns you about players on your list:
--   * Group Finder: hovering a listing or an applicant adds a red line to the
--     tooltip with your note, and prints it in chat once.
--   * Applicants: when someone on your list applies to your listed group.
--   * Inviting: when you invite someone, or apply to a group they lead.
--   * Invited: when someone on your list invites you.
--   * Grouped: when someone on your list joins your group.
--   * Unit tooltips: hovering the player anywhere in the world.
-- Warnings only go to your own chat window, never to party chat.
-- Players only on a friend's shared list get a grey tooltip line, no chat.

local addonName, ns = ...

local RED = "|cffff4040"
local GREY = "|cff9d9d9d"
local Plain = ns.Plain

--------------------------------------------------------------------------
-- Chat warnings (each player at most once per 60 s per kind)
--------------------------------------------------------------------------

local lastWarn = {}

function ns.Warn(e, why)
	if not ns.DB().alerts then return end
	local key = ns.Key(e.name, e.realm) .. "|" .. why
	if lastWarn[key] and GetTime() - lastWarn[key] < 60 then return end
	lastWarn[key] = GetTime()
	print(ns.TAG .. RED .. ("%s %s|r - %s"):format(ns.Display(e), why, ns.Reason(e)))
end

local function WarnName(full, why)
	local e = full and ns.Find(full)
	if e then ns.Warn(e, why) end
	return e
end

-- First friend's shared list that has this player.
local function FindShared(full)
	local name, realm = ns.SplitName(full)
	if not name then return nil end
	for peer, list in pairs(ns.DB().shared) do
		for key, e in pairs(list.entries) do
			if e.name:lower() == name:lower() and (not realm or (e.realm or ""):lower() == realm:lower()) then
				return e, peer
			end
		end
	end
end

--------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------

local added = setmetatable({}, { __mode = "k" }) -- tooltip -> { [key] = true }
local busy = false

local function AddLines(tooltip, full, chatWhy)
	local e = ns.Find(full)
	added[tooltip] = added[tooltip] or {}
	if e then
		local key = ns.Key(e.name, e.realm)
		if added[tooltip][key] then return true end
		added[tooltip][key] = true
		tooltip:AddLine(RED .. "Blacklist: " .. ns.Display(e) .. "|r", 1, 1, 1)
		tooltip:AddLine(e.note ~= "" and e.note or "no note", 1, 0.55, 0.55, true)
		tooltip:AddLine(("Added %s, %s"):format(ns.FormatDate(e.added), ns.Where(e)), 0.6, 0.6, 0.6, true)
		if chatWhy then ns.Warn(e, chatWhy) end
		return true
	end
	local s, peer = FindShared(full)
	if s then
		local key = "shared|" .. s.name:lower()
		if added[tooltip][key] then return true end
		added[tooltip][key] = true
		tooltip:AddLine(GREY .. ("On %s's list: %s|r"):format(peer, s.note ~= "" and s.note or "no note"), 1, 1, 1, true)
		return true
	end
end

local function Refresh(tooltip)
	if busy then return end
	busy = true
	pcall(tooltip.Show, tooltip)
	busy = false
end

-- Is this tooltip shown for something in the Group Finder?
local function GroupFinderOwner(tooltip)
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	local depth = 0
	while owner and depth < 8 do
		local name = owner.GetName and owner:GetName()
		if name and (name:find("LFG") or name:find("GroupFinder") or name:find("PremadeGroups")) then
			return name
		end
		owner = owner.GetParent and owner:GetParent()
		depth = depth + 1
	end
end

-- Reads every line of the tooltip and checks each word that could be a
-- player name. Works for any Group Finder layout, since it only needs the
-- names to be shown in the tooltip.
local function ScanTooltip(tooltip)
	local name = tooltip.GetName and tooltip:GetName()
	if not name then return false end
	local found = false
	for i = 1, tooltip:NumLines() do
		for _, side in ipairs({ "Left", "Right" }) do
			local fs = _G[name .. "Text" .. side .. i]
			local text = fs and Plain(fs:GetText())
			if text and text ~= "" and not text:find("Blacklist", 1, true) then
				text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
				for word in text:gmatch("[^%s,:;%(%)%[%]/\"]+") do
					local short = word:match("^([^%-]+)")
					local n = short and ns.SplitName(short)
					if n and (ns.HasShort(n) or FindShared(n)) then
						if AddLines(tooltip, word, "is in the Group Finder") then found = true end
					end
				end
			end
		end
	end
	return found
end

local function OnTooltipShow(tooltip)
	if busy then return end
	local owner = GroupFinderOwner(tooltip)
	if not owner then return end
	ns.lastTooltipOwner = owner
	local ok, found = pcall(ScanTooltip, tooltip)
	if ok and found then Refresh(tooltip) end
end

local function HookTooltip(tooltip)
	if not tooltip or not tooltip.HookScript then return end
	tooltip:HookScript("OnShow", OnTooltipShow)
	tooltip:HookScript("OnTooltipCleared", function(t) added[t] = nil end)
	ns.hooks.tooltipScan = (ns.hooks.tooltipScan or 0) + 1
end

-- Unit tooltips (players in the world, party frames)
local function OnUnitTooltip(tooltip)
	if tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	unit = Plain(unit)
	if not unit or not UnitIsPlayer(unit) then return end
	local n, r = UnitName(unit)
	n, r = Plain(n), Plain(r)
	if not n then return end
	AddLines(tooltip, (r and r ~= "") and (n .. "-" .. r) or n)
end

--------------------------------------------------------------------------
-- Group Finder API hooks (used when the client has them)
--------------------------------------------------------------------------

local function ResultLeader(resultID)
	local info = C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(resultID)
	return info and Plain(info.leaderName)
end

local function ApplicantNames(applicantID)
	local names = {}
	if not (C_LFGList and C_LFGList.GetApplicantInfo) then return names end
	local info = C_LFGList.GetApplicantInfo(applicantID)
	for i = 1, (info and info.numMembers) or 1 do
		local n = C_LFGList.GetApplicantMemberInfo and C_LFGList.GetApplicantMemberInfo(applicantID, i)
		n = Plain(n)
		if n then names[#names + 1] = n end
	end
	return names
end

local warnedApplicant = {}

local function CheckApplicants()
	if not (C_LFGList and C_LFGList.GetApplicants) then return end
	for _, id in ipairs(C_LFGList.GetApplicants() or {}) do
		if not warnedApplicant[id] then
			for _, n in ipairs(ApplicantNames(id)) do
				if WarnName(n, "applied to your group") then warnedApplicant[id] = true end
			end
		end
	end
end

local function HookAPIs()
	local function Hook(tbl, fname, label, fn)
		if tbl and type(tbl[fname]) == "function" then
			if tbl == _G then hooksecurefunc(fname, fn) else hooksecurefunc(tbl, fname, fn) end
			ns.hooks[label] = true
		end
	end

	-- Search results: add the leader by API too, in case the tooltip hides it.
	Hook(_G, "LFGListUtil_SetSearchEntryTooltip", "searchTooltip", function(tooltip, resultID)
		local leader = ResultLeader(resultID)
		if leader and AddLines(tooltip, leader, "is in the Group Finder") then Refresh(tooltip) end
	end)
	Hook(_G, "LFGBrowseSearchEntryTooltip_UpdateAndShow", "browseTooltip", function(tooltip, resultID)
		local leader = ResultLeader(resultID)
		if leader and AddLines(tooltip, leader, "is in the Group Finder") then Refresh(tooltip) end
	end)

	-- Inviting and applying
	local function Invited(name) WarnName(name, "was just invited by you") end
	Hook(_G, "InviteUnit", "inviteUnit", Invited)
	Hook(C_PartyInfo, "InviteUnit", "partyInvite", Invited)
	Hook(C_PartyInfo, "ConfirmInviteUnit", "partyConfirm", Invited)
	Hook(C_LFGList, "InviteApplicant", "inviteApplicant", function(id)
		for _, n in ipairs(ApplicantNames(id)) do WarnName(n, "was just invited by you") end
	end)
	Hook(C_LFGList, "ApplyToGroup", "applyToGroup", function(resultID)
		WarnName(ResultLeader(resultID), "leads the group you just applied to")
	end)
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local inGroup = {}

local function CheckGroup()
	local now = {}
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local prefix = IsInRaid and IsInRaid() and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local name, realm = UnitName(unit)
			name, realm = Plain(name), Plain(realm)
			if name then
				local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
				now[full] = true
				if not inGroup[full] then WarnName(full, "is in your group") end
			end
		end
	end
	inGroup = now
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_INVITE_REQUEST")
pcall(ev.RegisterEvent, ev, "LFG_LIST_APPLICANT_LIST_UPDATED")
pcall(ev.RegisterEvent, ev, "LFG_LIST_APPLICANT_UPDATED")
ev:SetScript("OnEvent", function(_, event, a)
	if event == "PLAYER_LOGIN" then
		HookTooltip(GameTooltip)
		if ItemRefTooltip then HookTooltip(ItemRefTooltip) end
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(t) pcall(OnUnitTooltip, t) end)
			ns.hooks.unitTooltip = true
		elseif GameTooltip:HasScript("OnTooltipSetUnit") then
			GameTooltip:HookScript("OnTooltipSetUnit", function(t) pcall(OnUnitTooltip, t) end)
			ns.hooks.unitTooltip = true
		end
		pcall(HookAPIs)
		C_Timer.After(5, function() pcall(CheckGroup) end)
	elseif event == "GROUP_ROSTER_UPDATE" then
		pcall(CheckGroup)
	elseif event == "PARTY_INVITE_REQUEST" then
		WarnName(Plain(a), "invited you to a group")
	else
		pcall(CheckApplicants)
	end
end)
