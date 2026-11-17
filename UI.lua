-- Blacklist: UI.lua
-- The /bl window: "My list" and "Shared" tabs, plus the add/edit dialog.

local addonName, ns = ...

local ROWS, ROW_H = 13, 24
local W, H = 600, 470
local COLS = { -- x offset, width
	name = { 8, 120 }, note = { 132, 220 }, mid = { 356, 82 }, zone = { 442, 110 },
}

local frame, rows, scroll, search, tabMine, tabShared, btnAdd, btnSync, btnAll, status, headers
local tab = "mine"
local data = {}

local function ClassColor(class, text)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text) end
	return text
end

local function Matches(e, q)
	if q == "" then return true end
	local hay = (e.name .. " " .. (e.note or "") .. " " .. (e.zone or "") .. " " .. (e.subzone or "")):lower()
	return hay:find(q, 1, true) ~= nil
end

local function BuildData()
	wipe(data)
	local db = ns.DB()
	local q = search and search:GetText():lower() or ""
	if tab == "mine" then
		for key, e in pairs(db.entries) do
			if Matches(e, q) then data[#data + 1] = { key = key, e = e } end
		end
		table.sort(data, function(a, b) return (a.e.added or 0) > (b.e.added or 0) end)
	else
		for peer, list in pairs(db.shared) do
			for key, e in pairs(list.entries) do
				if Matches(e, q) then data[#data + 1] = { key = key, e = e, peer = peer } end
			end
		end
		table.sort(data, function(a, b)
			if a.peer ~= b.peer then return a.peer < b.peer end
			return a.e.name < b.e.name
		end)
	end
end

local function Update()
	if not frame or not frame:IsShown() then return end
	BuildData()
	local db = ns.DB()
	tabMine:SetText(("My list (%d)"):format(ns.Count(db.entries)))
	local shared = 0
	for _, l in pairs(db.shared) do shared = shared + ns.Count(l.entries) end
	tabShared:SetText(("Shared (%d)"):format(shared))
	tabMine:SetEnabled(tab ~= "mine")
	tabShared:SetEnabled(tab ~= "shared")
	btnAdd:SetShown(tab == "mine")
	btnSync:SetShown(tab == "shared")
	btnAll:SetShown(tab == "shared")
	headers.mid:SetText(tab == "mine" and "Added" or "From")

	local offset = FauxScrollFrame_GetOffset(scroll)
	FauxScrollFrame_Update(scroll, #data, ROWS, ROW_H)
	for i = 1, ROWS do
		local row, d = rows[i], data[i + offset]
		row.data = d
		if d then
			local e = d.e
			row.name:SetText(ClassColor(e.class, ns.Display(e)))
			row.note:SetText(e.note ~= "" and e.note or "|cff808080no note|r")
			row.mid:SetText(tab == "mine" and date("%d/%m/%y", e.added or 0) or d.peer)
			row.zone:SetText(ns.Where(e))
			if tab == "mine" then
				row.btn:SetText("X")
				row.btn:SetWidth(24)
				row.btn:Enable()
			else
				local have = ns.Find(e.name .. "-" .. (e.realm or ""))
				row.btn:SetText(have and "Have" or "Import")
				row.btn:SetWidth(52)
				row.btn:SetEnabled(not have)
			end
			row:Show()
		else
			row:Hide()
		end
	end

	if #data == 0 then
		if tab == "mine" then
			status:SetText(search:GetText() ~= "" and "No matches." or
				"Your list is empty. Right-click a player and choose Add to Blacklist, or press Add player.")
		else
			status:SetText(search:GetText() ~= "" and "No matches." or
				"No shared lists yet. Friends running Blacklist send theirs automatically; press Sync now to ask.")
		end
	else
		status:SetText("")
	end
end
ns.OnListChanged = Update

--------------------------------------------------------------------------
-- Editor dialog
--------------------------------------------------------------------------

local editor

local function MakeEditor()
	editor = CreateFrame("Frame", "BlacklistEditor", UIParent, "BasicFrameTemplateWithInset")
	editor:SetSize(380, 190)
	editor:SetPoint("CENTER", 0, 80)
	editor:SetFrameStrata("DIALOG")
	editor:SetMovable(true)
	editor:EnableMouse(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	editor.title:SetPoint("TOP", 0, -5)
	tinsert(UISpecialFrames, "BlacklistEditor")

	local l1 = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l1:SetPoint("TOPLEFT", 16, -36)
	l1:SetText("Player (Name or Name-Realm)")
	editor.name = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	editor.name:SetSize(340, 22)
	editor.name:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 6, -2)
	editor.name:SetAutoFocus(false)
	editor.name:SetMaxLetters(60)
	editor.nameText = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	editor.nameText:SetPoint("LEFT", editor.name, "LEFT", 0, 0)

	local l2 = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l2:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -32)
	l2:SetText("Note (why they're on your list)")
	editor.note = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	editor.note:SetSize(340, 22)
	editor.note:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 6, -2)
	editor.note:SetAutoFocus(false)
	editor.note:SetMaxLetters(200)

	editor.info = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	editor.info:SetPoint("TOPLEFT", editor.note, "BOTTOMLEFT", -6, -6)
	editor.info:SetWidth(345)
	editor.info:SetJustifyH("LEFT")

	local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
	save:SetSize(90, 22)
	save:SetPoint("BOTTOMRIGHT", -12, 10)
	save:SetText("Save")
	local cancel = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
	cancel:SetSize(90, 22)
	cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() editor:Hide() end)
	editor.delete = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
	editor.delete:SetSize(90, 22)
	editor.delete:SetPoint("BOTTOMLEFT", 12, 10)
	editor.delete:SetText("Remove")
	editor.delete:SetScript("OnClick", function()
		ns.Remove(editor.full)
		ns.Print("removed " .. editor.full .. ".")
		editor:Hide()
	end)

	local function Save()
		local full = editor.full or editor.name:GetText()
		local note = editor.note:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		local existing = editor.full and ns.Find(editor.full)
		local e, err
		if existing then
			existing.note = note
			e = existing
			ns.Rebuild()
		else
			e, err = ns.Add(full, note, editor.extra)
		end
		if e then
			ns.Print(("%s %s."):format(existing and "updated" or "added", ns.Display(e)))
			editor:Hide()
		else
			ns.Print("couldn't save: " .. (err or "?"))
		end
	end
	save:SetScript("OnClick", Save)
	editor.note:SetScript("OnEnterPressed", Save)
	editor.name:SetScript("OnEnterPressed", function() editor.note:SetFocus() end)
	editor.note:SetScript("OnEscapePressed", function() editor:Hide() end)
	editor.name:SetScript("OnEscapePressed", function() editor:Hide() end)
end

-- full: player name (may be nil for a blank Add); extra: { class, level }
function ns.OpenEditor(full, extra)
	if not editor then MakeEditor() end
	local e = full and ns.Find(full)
	editor.extra = extra
	if e then
		editor.full = e.name .. "-" .. e.realm
		editor.title:SetText("Blacklist: edit note")
		editor.name:Hide()
		editor.nameText:SetText(ClassColor(e.class, ns.Display(e)))
		editor.nameText:Show()
		editor.note:SetText(e.note or "")
		local extraInfo = e.origin and (" Imported from %s (%s)."):format(e.origin, e.originZone or "?") or ""
		editor.info:SetText(("Added %s in %s.%s"):format(ns.FormatDate(e.added), ns.Where(e), extraInfo))
		editor.delete:Show()
	else
		editor.full = nil
		editor.title:SetText("Blacklist: add player")
		editor.name:Show()
		editor.nameText:Hide()
		editor.name:SetText(full or "")
		editor.note:SetText("")
		local zone, sub = ns.Zone()
		editor.info:SetText(("Will be saved with today's date and your zone (%s)."):format(sub ~= "" and (sub .. ", " .. zone) or zone))
		editor.delete:Hide()
	end
	editor:Show()
	if editor.name:IsShown() and editor.name:GetText() == "" then editor.name:SetFocus() else editor.note:SetFocus() end
end

--------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------

local function RowTooltip(row)
	local d = row.data
	if not d then return end
	local e = d.e
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ClassColor(e.class, ns.Display(e)))
	GameTooltip:AddLine(e.note ~= "" and e.note or "no note", 1, 0.8, 0.8, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Added", ns.FormatDate(e.added), 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Where", ns.Where(e), 0.7, 0.7, 0.7, 1, 1, 1)
	if d.peer then
		GameTooltip:AddDoubleLine("From", d.peer, 0.7, 0.7, 0.7, 1, 1, 1)
	elseif e.origin then
		GameTooltip:AddDoubleLine("Imported from", e.origin, 0.7, 0.7, 0.7, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(d.peer and "Click Import to copy them to your list." or "Click to edit the note.", 0.5, 0.8, 1)
	GameTooltip:Show()
end

local function MakeFrame()
	frame = CreateFrame("Frame", "BlacklistFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "BlacklistFrame")
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Blacklist")

	tabMine = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabMine:SetSize(120, 22)
	tabMine:SetPoint("TOPLEFT", 12, -30)
	tabMine:SetScript("OnClick", function() tab = "mine"; FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0); Update() end)
	tabShared = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tabShared:SetSize(120, 22)
	tabShared:SetPoint("LEFT", tabMine, "RIGHT", 4, 0)
	tabShared:SetScript("OnClick", function() tab = "shared"; FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0); Update() end)

	search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetSize(140, 20)
	search:SetPoint("LEFT", tabShared, "RIGHT", 14, 0)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0); Update() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	local sl = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sl:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 0, 1)
	sl:SetText("Search")

	btnAdd = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	btnAdd:SetSize(100, 22)
	btnAdd:SetPoint("TOPRIGHT", -12, -30)
	btnAdd:SetText("Add player")
	btnAdd:SetScript("OnClick", function()
		if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
			local n, r = UnitName("target")
			local _, cls = UnitClass("target")
			n, r = ns.Plain(n), ns.Plain(r)
			if n then
				ns.OpenEditor((r and r ~= "") and (n .. "-" .. r) or n, { class = ns.Plain(cls) })
				return
			end
		end
		ns.OpenEditor(nil)
	end)
	btnSync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	btnSync:SetSize(84, 22)
	btnSync:SetPoint("TOPRIGHT", -12, -30)
	btnSync:SetText("Sync now")
	btnSync:SetScript("OnClick", function() ns.ShareCommand("now") end)
	btnAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	btnAll:SetSize(84, 22)
	btnAll:SetPoint("RIGHT", btnSync, "LEFT", -4, 0)
	btnAll:SetText("Import all")
	btnAll:SetScript("OnClick", function()
		local n = 0
		for _, d in ipairs(data) do
			local e, had = ns.Import(d.peer, d.key)
			if e and not had then n = n + 1 end
		end
		ns.Print(("imported %d player(s)%s."):format(n, search:GetText() ~= "" and " matching your search" or ""))
	end)

	headers = {}
	for key, label in pairs({ name = "Name", note = "Note", mid = "Added", zone = "Zone" }) do
		local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", 12 + COLS[key][1], -62)
		h:SetText(label)
		headers[key] = h
	end

	scroll = CreateFrame("ScrollFrame", "BlacklistScroll", frame, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -76)
	scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Update)
	end)

	rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(W - 44, ROW_H)
		row:SetPoint("TOPLEFT", 12, -76 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		if i % 2 == 0 then
			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(1, 1, 1, 0.04)
		end
		for key, col in pairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", key == "name" and "GameFontHighlight" or "GameFontHighlightSmall")
			fs:SetPoint("LEFT", col[1], 0)
			fs:SetWidth(col[2])
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			row[key] = fs
		end
		row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.btn:SetSize(24, 20)
		row.btn:SetPoint("RIGHT", -2, 0)
		row.btn:SetScript("OnClick", function()
			local d = row.data
			if not d then return end
			if d.peer then
				local e = ns.Import(d.peer, d.key)
				if e then ns.Print("imported " .. ns.Display(e) .. ".") end
			elseif IsShiftKeyDown() then
				ns.Remove(d.e.name .. "-" .. d.e.realm)
			else
				StaticPopup_Show("BLACKLIST_REMOVE", ns.Display(d.e), nil, d.e.name .. "-" .. d.e.realm)
			end
		end)
		row:SetScript("OnClick", function(self)
			local d = self.data
			if d and not d.peer then ns.OpenEditor(d.e.name .. "-" .. d.e.realm) end
		end)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end

	status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("CENTER", 0, 0)
	status:SetWidth(W - 80)

	local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	foot:SetPoint("BOTTOMLEFT", 14, 10)
	foot:SetText("Right-click any player to add them. Shift-click X removes without asking.")

	frame:SetScript("OnShow", Update)
end

function ns.ToggleWindow()
	if not frame then MakeFrame() end
	frame:SetShown(not frame:IsShown())
end

StaticPopupDialogs["BLACKLIST_REMOVE"] = {
	text = "Remove %s from your Blacklist?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data) ns.Remove(data) end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
