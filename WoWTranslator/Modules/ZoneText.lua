-- Texte d'arrivée dans une zone et texte de la minimap.
-- Frames et pièges : docs/client-research.md §5.1 et §5.2.
local _, WT = ...

local active = false
local originals = {} -- FontString -> texte d'origine, seulement si on l'a traduit
local writing = {}   -- FontString -> true pendant nos propres SetText
local targets = {}   -- FontStrings accrochées

local function write(fontString, text)
  writing[fontString] = true
  fontString:SetText(text)
  writing[fontString] = nil
end

-- Le texte affiché vient de changer : l'original mémorisé est périmé.
-- WT.Translate renvoie nil pour un texte vide, inconnu ou secret : un tel
-- texte n'est donc ni mémorisé, ni réécrit, ni comparé ici.
local function translate(fontString, text)
  originals[fontString] = nil
  local translation = WT.Translate(text)
  if translation and translation ~= text then
    originals[fontString] = text
    write(fontString, translation)
  end
end

local function onSetText(fontString, text)
  if active and not writing[fontString] then
    translate(fontString, text)
  end
end

local function onSetFormattedText(fontString)
  if active and not writing[fontString] then
    translate(fontString, fontString:GetText())
  end
end

-- Hooks de méthode sur l'instance : ZoneText_OnEvent est lié par référence au
-- chargement du XML, un hook sur la globale n'aurait aucun effet.
local hooked = {}

local function hook(fontString)
  if not fontString or hooked[fontString] then return end
  hooked[fontString] = true
  targets[#targets + 1] = fontString
  hooksecurefunc(fontString, "SetText", onSetText)
  hooksecurefunc(fontString, "SetFormattedText", onSetFormattedText)
end

hook(ZoneTextString)
hook(SubZoneTextString) -- reçoit aussi le nom de zone
hook(MinimapZoneText)

-- EllesmereUIMinimap cache MinimapZoneText et affiche le lieu dans sa propre
-- FontString, sans nom global. Son cadre parent est exposé en _EBS_LocationBg
-- (EUI_Minimap_Apply.lua) et n'est créé qu'une fois la minimap configurée :
-- on le cherche à chaque appui. Si Ellesmere change, rien n'est trouvé et
-- seule cette compatibilité cesse de fonctionner.
local function hookEllesmere()
  local frame = _EBS_LocationBg
  if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return end
  local regions = { pcall(frame.GetRegions, frame) }
  if not regions[1] then return end
  for i = 2, #regions do
    local region = regions[i]
    if type(region) == "table" and type(region.GetObjectType) == "function"
      and region:GetObjectType() == "FontString" then
      hook(region)
    end
  end
end

WT.RegisterModule("ZoneText", {
  Apply = function()
    active = true
    hookEllesmere()
    -- Le texte peut avoir été posé avant le chargement de l'addon.
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
