-- Noyau de WoWTranslator : état actif, traduction, registre de modules,
-- touche maintenue et filets de sécurité. Contrat : voir PLAN.md.
local _, WT = ...
WoWTranslator = WT
WT.data = WT.data or {}

local BINDING = "WOWTRANSLATOR_HOLD"
local POLL_INTERVAL = 0.1

-- Libellés du menu des raccourcis : à définir dès le chargement du fichier.
BINDING_HEADER_WOWTRANSLATOR = "WoWTranslator"
if GetLocale() == "frFR" then
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Afficher l'autre langue (maintenir)"
else
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Show other language (hold)"
end

---------------------------------------------------------------------------
-- Langue cible et traduction
---------------------------------------------------------------------------

-- Une entrée par langue cible : le dictionnaire à consulter.
local DICTIONARY_FOR_TARGET = {
  frFR = "enUS_frFR",
  enUS = "frFR_enUS",
}

local DEFAULT_TARGET = {
  enUS = "frFR",
  enGB = "frFR",
  frFR = "enUS",
}

local targetOverride -- nil : l'inverse de la langue du jeu

-- "enUS", "frFR", ou nil si la langue du jeu n'est pas gérée.
function WT.GetTargetLocale()
  return targetOverride or DEFAULT_TARGET[GetLocale()]
end

---------------------------------------------------------------------------
-- État et modules
---------------------------------------------------------------------------

local active = false
local generation = 0 -- change à chaque bascule
local modules = {}   -- dans l'ordre d'enregistrement
local modulesByName = {}
local safetyTicker

-- Une erreur de module est signalée sans interrompre les autres.
local function callModule(callback)
  local ok, err = pcall(callback)
  if not ok then
    geterrorhandler()(err)
  end
end

local function disarmSafetyNet()
  if safetyTicker then
    safetyTicker:Cancel()
    safetyTicker = nil
  end
end

function WT.IsActive()
  return active
end

function WT.SetActive(value)
  local wanted = value and true or false
  if wanted == active then return end

  active = wanted
  generation = generation + 1
  local current = generation
  if not active then disarmSafetyNet() end

  local method = active and "Apply" or "Restore"
  for _, module in ipairs(modules) do
    -- Un module a rebasculé l'état : cette passe est périmée.
    if generation ~= current then break end
    callModule(module.def[method])
  end
end

function WT.RegisterModule(name, def)
  if type(name) ~= "string" or type(def) ~= "table"
    or type(def.Apply) ~= "function" or type(def.Restore) ~= "function" then
    error("WoWTranslator.RegisterModule(name, { Apply = f, Restore = f })", 2)
  end
  if modulesByName[name] then
    error("WoWTranslator : module déjà enregistré : " .. name, 2)
  end

  local module = { name = name, def = def }
  modulesByName[name] = module
  modules[#modules + 1] = module
  if active then callModule(def.Apply) end
end

-- Recherche exacte. Renvoie la traduction, ou nil.
function WT.Translate(text)
  -- Avant toute autre opération sur la valeur : une valeur secrète ne
  -- supporte ni comparaison ni indexation. Une erreur vaut « secret ».
  local isSecret = issecretvalue
  if isSecret then
    local ok, secret = pcall(isSecret, text)
    if not ok or secret then return nil end
  end
  if type(text) ~= "string" then return nil end

  local target = WT.GetTargetLocale()
  local dictionary = target and WT.data[DICTIONARY_FOR_TARGET[target]]
  if not dictionary then return nil end

  local translation = dictionary[text]
  if type(translation) ~= "string" then return nil end
  return translation
end

-- Force la langue cible ("enUS" ou "frFR") ; nil revient au réglage
-- automatique. Renvoie false si la valeur est refusée. La persistance
-- appartient à Config.lua.
function WT.SetTargetLocale(locale)
  if locale ~= nil
    and (type(locale) ~= "string" or not DICTIONARY_FOR_TARGET[locale]) then
    return false
  end
  if locale ~= targetOverride then
    -- Les modules restaurent leurs originaux avant le changement.
    WT.SetActive(false)
    targetOverride = locale
  end
  return true
end

---------------------------------------------------------------------------
-- Touche maintenue et filet de sécurité
---------------------------------------------------------------------------

-- "SHIFT-F6" -> "F6" ; la touche « - » reste « - » ("SHIFT--" -> "-").
local function baseKey(binding)
  if binding:sub(-1) == "-" then return "-" end
  return binding:match("[^%-]+$")
end

-- Vrai seulement si chaque touche est explicitement relâchée.
local function allReleased(...)
  local count = select("#", ...)
  local checked = 0
  for i = 1, count do
    local binding = select(i, ...)
    if binding then
      local ok, down = pcall(IsKeyDown, baseKey(binding))
      if not ok or down ~= false then return false end
      checked = checked + 1
    end
  end
  return checked > 0
end

local function checkHeldKeys()
  if allReleased(GetBindingKey(BINDING)) then
    WT.SetActive(false)
  end
end

-- Il n'existe pas d'événement de perte de focus : tant que la touche est
-- censée être tenue, on vérifie qu'elle l'est encore.
local function armSafetyNet()
  if safetyTicker or not (IsKeyDown and GetBindingKey) then return end
  safetyTicker = C_Timer.NewTicker(POLL_INTERVAL, checkHeldKeys)
end

-- Appelée par Bindings.xml. Tout autre état que "down" désactive.
function WoWTranslator_OnHoldKey(keystate)
  if keystate == "down" then
    WT.SetActive(true)
    if active then armSafetyNet() end
  else
    WT.SetActive(false)
  end
end

-- Un relâchement manqué pendant un écran de chargement ne doit pas persister.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
  WT.SetActive(false)
end)
