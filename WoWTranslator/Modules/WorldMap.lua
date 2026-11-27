-- Carte du monde : libellé de zone affiché au survol.
-- Frames et format du libellé : docs/client-research.md §5.3.
-- Hors v1 : fil d'Ariane (NavBar) et titre de la fenêtre.
local _, WT = ...

-- "Nom|cffRRGGBB (1-10)|r" ou "Nom|cffRRGGBB (60)|r" : l'espace est dans le
-- code couleur. Sans suffixe, le libellé est le nom seul.
local LEVEL_SUFFIX = "^(.-)(|c%x%x%x%x%x%x%x%x %(%d+%-?%d*%)|r)$"

local active = false
local originals = {} -- FontString -> texte d'origine, seulement si on l'a traduit
local writing = {}   -- FontString -> true pendant nos propres SetText
local targets = {}   -- FontStrings accrochées
local hooked = {}

-- Même règle que WT.Translate : rien d'autre ne touche la valeur avant.
local function isSecret(value)
  local check = issecretvalue
  if not check then return false end
  local ok, secret = pcall(check, value)
  return not ok or secret
end

local function translateLabel(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  local name, suffix = text:match(LEVEL_SUFFIX)
  if not name then name, suffix = text, "" end
  local translation = WT.Translate(name)
  if not translation or translation == name then return nil end
  return translation .. suffix
end

local function write(fontString, text)
  writing[fontString] = true
  fontString:SetText(text)
  writing[fontString] = nil
end

-- Le texte affiché vient de changer : l'original mémorisé est périmé.
local function translate(fontString, text)
  originals[fontString] = nil
  local translation = translateLabel(text)
  if translation then
    originals[fontString] = text
    write(fontString, translation)
  end
end

local function onSetText(fontString, text)
  if active and not writing[fontString] then
    translate(fontString, text)
  end
end

local function hookLabels()
  local map = WorldMapFrame
  if not (map and map.dataProviders) then return false end
  for provider in pairs(map.dataProviders) do
    local label = type(provider) == "table" and provider.Label
    local fontString = label and label.Name
    if fontString and not hooked[fontString] then
      hooked[fontString] = true
      targets[#targets + 1] = fontString
      hooksecurefunc(fontString, "SetText", onSetText)
      if active then translate(fontString, fontString:GetText()) end
    end
  end
  return true
end

-- La carte n'est pas chargée à la demande : elle existe en général déjà.
if not hookLabels() then
  local loader = CreateFrame("Frame")
  loader:RegisterEvent("ADDON_LOADED")
  loader:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_WorldMap" and hookLabels() then
      self:UnregisterEvent("ADDON_LOADED")
    end
  end)
end

WT.RegisterModule("WorldMap", {
  Apply = function()
    active = true
    for _, fontString in ipairs(targets) do
      translate(fontString, fontString:GetText())
    end
  end,
  Restore = function()
    active = false
    for _, fontString in ipairs(targets) do
      local original = originals[fontString]
      if original then
        originals[fontString] = nil
        write(fontString, original)
      end
    end
  end,
})
