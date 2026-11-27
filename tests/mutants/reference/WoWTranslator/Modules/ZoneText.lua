-- REFERENCE (oracle de test) : texte de zone, sous-zone, minimap, barre de lieu
-- d'EllesmereUIMinimap (FontString anonyme de _EBS_LocationBg, cherchee a chaque appui).
local _, WT = ...
local hooks, seen = {}, {}
local function add(fs)
  if fs and not seen[fs] then seen[fs] = true; hooks[#hooks + 1] = WT._ref.HookFontString(fs) end
end
for _, n in ipairs({ "ZoneTextString", "SubZoneTextString", "MinimapZoneText" }) do add(_G[n]) end
local group = WT._ref.Group(hooks)
local function findEllesmere()
  local bg = _G._EBS_LocationBg
  if type(bg) ~= "table" then return end
  local res = { pcall(function() return bg:GetRegions() end) }
  if not res[1] then return end
  for i = 2, #res do
    local r = res[i]
    local ok, kind = pcall(function() return r:GetObjectType() end)
    if ok and kind == "FontString" then add(r) end
  end
end
WT.RegisterModule("ZoneText", {
  Apply = function() findEllesmere(); group.Apply() end,
  Restore = group.Restore,
})
