-- Blacklist: Nameplates.lua
-- Puts a red X after the name on the nameplate of anyone on your list.
-- Nameplates must be on for that player (V for enemies, Shift-V for
-- friendly players). The client doesn't let addons change friendly
-- nameplates inside dungeons, so there the icon only shows on enemies.

local addonName, ns = ...

local ICON = "Interface\\AddOns\\Blacklist\\Cross"
local SIZE = 14

local Plain = ns.Plain
local shown = {} -- unit token -> plate

local function Anchor(plate)
	local uf = plate.UnitFrame
	local name = uf and (uf.name or uf.Name)
	if name and name.IsShown and name:IsShown() and (name:GetText() or "") ~= "" then return name, "LEFT", "RIGHT", 2, 0 end
	if uf and uf.healthBar then return uf.healthBar, "BOTTOMLEFT", "TOPRIGHT", 2, 0 end
	return plate, "CENTER", "TOP", 0, 0
end

local function Hide(plate)
	if plate and plate.BlacklistX then plate.BlacklistX:Hide() end
end

local function Update(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then Hide(plate) return end
	local n, r = UnitName(unit)
	n, r = Plain(n), Plain(r)
	local e = n and ns.Find((r and r ~= "") and (n .. "-" .. r) or n)
	if not e or not ns.DB().nameplates then Hide(plate) return end
	local x = plate.BlacklistX
	if not x then
		x = plate:CreateTexture(nil, "OVERLAY", nil, 7)
		x:SetTexture(ICON)
		x:SetSize(SIZE, SIZE)
		plate.BlacklistX = x
	end
	local anchorTo, point, rel, ox, oy = Anchor(plate)
	x:ClearAllPoints()
	x:SetPoint(point, anchorTo, rel, ox, oy)
	x:Show()
	shown[unit] = plate
end

function ns.RefreshNameplates()
	for unit, plate in pairs(shown) do Hide(plate) end
	wipe(shown)
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then pcall(Update, unit) end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_NAME_UPDATE")
f:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		if ns.DB().nameplates == nil then ns.DB().nameplates = true end
		ns.hooks.nameplates = C_NamePlate and true or nil
		return
	end
	if not unit or not unit:find("^nameplate") then return end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		Hide(shown[unit] or (C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)))
		shown[unit] = nil
	else
		pcall(Update, unit)
	end
end)
