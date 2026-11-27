-- Réglages enregistrés (WoWTranslatorDB) et commande /wt.
local addonName, WT = ...

local VALID_LOCALES = { enUS = true, frFR = true }

local FRENCH = GetLocale() == "frFR"
local L = FRENCH and {
  usage = "/wt status | /wt lang <enUS|frFR|auto>",
  active = "Traduction : %s",
  on = "active",
  off = "inactive",
  game = "Langue du jeu : %s",
  target = "Langue affichée en maintenant la touche : %s",
  targetNone = "aucune (langue du jeu non gérée)",
  forced = " (forcée par /wt lang)",
  auto = " (automatique)",
  entries = "Dictionnaire %s : %d noms",
  missing = "Dictionnaire %s : absent",
  key = "Touche : %s",
  noKey = "aucune (Options > Gameplay > Raccourcis > WoWTranslator)",
  invalid = "Langue inconnue : %s. Choix : enUS, frFR ou auto.",
  set = "Langue affichée : %s.",
} or {
  usage = "/wt status | /wt lang <enUS|frFR|auto>",
  active = "Translation: %s",
  on = "on",
  off = "off",
  game = "Game language: %s",
  target = "Language shown while holding the key: %s",
  targetNone = "none (game language not supported)",
  forced = " (set with /wt lang)",
  auto = " (automatic)",
  entries = "Dictionary %s: %d names",
  missing = "Dictionary %s: missing",
  key = "Key: %s",
  noKey = "none (Options > Gameplay > Keybindings > WoWTranslator)",
  invalid = "Unknown language: %s. Choices: enUS, frFR or auto.",
  set = "Language shown: %s.",
}

local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoWTranslator|r " .. text)
end

-- Une valeur enregistrée invalide est remplacée par la valeur par défaut.
local function loadSettings()
  if type(WoWTranslatorDB) ~= "table" then WoWTranslatorDB = {} end
  local locale = WoWTranslatorDB.targetLocale
  if not (type(locale) == "string" and VALID_LOCALES[locale]) then
    locale = nil
  end
  WoWTranslatorDB.targetLocale = locale
  WT.SetTargetLocale(locale)
end

local function countEntries(name)
  local dictionary = WT.data[name]
  if type(dictionary) ~= "table" then return nil end
  local count = 0
  for _ in pairs(dictionary) do count = count + 1 end
  return count
end

local function showStatus()
  say(L.active:format(WT.IsActive() and L.on or L.off))
  say(L.game:format(tostring(GetLocale())))
  local target = WT.GetTargetLocale()
  local origin = WoWTranslatorDB and WoWTranslatorDB.targetLocale and L.forced or L.auto
  say(L.target:format((target or L.targetNone) .. origin))
  -- Dictionnaires désignés par leur nom : les listes natives n'en sont pas.
  for _, name in ipairs({ "enUS_frFR", "frFR_enUS" }) do
    local count = countEntries(name)
    say(count and L.entries:format(name, count) or L.missing:format(name))
  end
  local key1, key2 = GetBindingKey("WOWTRANSLATOR_HOLD")
  local keys = key1 and (key2 and (key1 .. ", " .. key2) or key1) or L.noKey
  say(L.key:format(keys))
end

local function setLanguage(value)
  local locale
  if value and value:lower() == "auto" then
    locale = nil
  elseif value and VALID_LOCALES[value] then
    locale = value
  else
    say(L.invalid:format(value ~= "" and value or "?"))
    return
  end
  if type(WoWTranslatorDB) ~= "table" then WoWTranslatorDB = {} end
  WoWTranslatorDB.targetLocale = locale
  WT.SetTargetLocale(locale)
  say(L.set:format((WT.GetTargetLocale() or L.targetNone) .. (locale and L.forced or L.auto)))
end

SLASH_WOWTRANSLATOR1 = "/wt"
SlashCmdList.WOWTRANSLATOR = function(input)
  local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "status" then
    showStatus()
  elseif command == "lang" then
    setLanguage(argument)
  else
    say(L.usage)
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    loadSettings()
  end
end)
