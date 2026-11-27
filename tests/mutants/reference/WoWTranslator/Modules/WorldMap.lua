-- REFERENCE (oracle de test) : libelle de survol de la carte.
-- Decoupe le suffixe de niveau "|cffRRGGBB (a-b)|r" / "|cffRRGGBB (n)|r",
-- traduit le nom seul (Translate = recherche exacte), recolle le suffixe d'origine.
local addonName, WT = ...
local hooks = {}
local function tr(text)
  if WT._ref.isSecret(text) then return nil end
  if type(text) ~= "string" or text == "" then return nil end
  local name, suffix = text:match("^(.-)(|c%x%x%x%x%x%x%x%x %(.-%)|r)$")
  if not name then name, suffix = text, "" end
  local r = WT.Translate(name)
  return r and (r .. suffix) or nil
end
local done
local function setup()
  if done or not WorldMapFrame or not WorldMapFrame.dataProviders then return end
  done = true
  for p in pairs(WorldMapFrame.dataProviders) do
    if p.Label and p.Label.Name then hooks[#hooks + 1] = WT._ref.HookFontString(p.Label.Name, tr) end
  end
end
setup()
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
  if name == "Blizzard_WorldMap" then setup() end
end)
WT.RegisterModule("WorldMap", WT._ref.Group(hooks))
