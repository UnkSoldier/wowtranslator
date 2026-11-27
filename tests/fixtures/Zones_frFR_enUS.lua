-- Fixture de test : meme format que WoWTranslator/Data/Zones_frFR_enUS.lua
-- (genere par tools/build_zone_data.py). UTF-8 sans BOM.
local _, WT = ...
WT.data = WT.data or {}
WT.data.frFR_enUS = {
  ["Hurlevent"] = "Stormwind City",
  ["Orgrimmar"] = "Orgrimmar",            -- nom identique dans les deux langues
  ["Forgefer"] = "Ironforge",
  ["Les Mortemines"] = "The Deadmines",
  ["Forêt d'Elwynn"] = "Elwynn Forest",
  ["Comté-de-l'Or"] = "Goldshire",
  ["Quartier commerçant"] = "Trade District",
}
