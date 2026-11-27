-- REFERENCE (oracle de test) : /wt et SavedVariables, ecriture immediate.
-- (Le mutant M6 ecrit seulement a PLAYER_LOGOUT ; les deux doivent passer.)
local addonName, WT = ...
WT._ref.db = {}
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
  if name ~= addonName then return end
  if type(WoWTranslatorDB) ~= "table" then WoWTranslatorDB = {} end
  local l = WoWTranslatorDB.lang
  if l ~= nil and l ~= "enUS" and l ~= "frFR" then WoWTranslatorDB.lang = nil end
  WT._ref.db = WoWTranslatorDB
end)
SLASH_WOWTRANSLATOR1 = "/wt"
SlashCmdList.WOWTRANSLATOR = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  if cmd == "lang" then
    if arg == "enUS" or arg == "frFR" then
      WT._ref.db.lang = arg
      print("WoWTranslator: " .. arg)
    else
      print("Usage: /wt lang enUS|frFR")
    end
  elseif cmd == "status" then
    print("WoWTranslator: cible " .. tostring(WT._ref.targetLocale()))
  else
    print("/wt lang enUS|frFR, /wt status")
  end
end
