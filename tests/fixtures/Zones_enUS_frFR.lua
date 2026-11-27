-- Fixture de test : meme format que WoWTranslator/Data/Zones_enUS_frFR.lua
-- (genere par tools/build_zone_data.py). UTF-8 sans BOM.
local _, WT = ...
WT.data = WT.data or {}
WT.data.enUS_frFR = {
  ["Stormwind City"] = "Hurlevent",
  ["Orgrimmar"] = "Orgrimmar",            -- nom identique dans les deux langues
  ["Ironforge"] = "Forgefer",
  ["The Deadmines"] = "Les Mortemines",
  ["Elwynn Forest"] = "Forêt d'Elwynn",   -- caracteres non ASCII
  ["Goldshire"] = "Comté-de-l'Or",
  ["Trade District"] = "Quartier commerçant",
}
