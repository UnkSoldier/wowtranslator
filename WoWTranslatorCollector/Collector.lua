-- WoWTranslatorCollector : OUTIL DE DEVELOPPEMENT, NE PAS DISTRIBUER.
--
-- Collecte les noms de zones (C_Map.GetAreaInfo) et de cartes (C_Map.GetMapInfo)
-- dans la langue courante du client, pour tools/build_zone_data.py.
-- Lancer une fois en enUS, une fois en frFR, avec le MEME compte.
--
-- Le bloc est construit a part et n'est range dans WoWTranslatorCollectorDB[locale]
-- qu'a la FIN de la collecte, avec complete = true. Une collecte interrompue
-- (/reload, deconnexion, /wtcollect stop, erreur) n'ecrit rien : l'ancien bloc
-- complet de la meme langue reste en place.
--
-- Commandes :
--   /wtcollect start [borneZone] [borneCarte]   collecte (defauts ci-dessous)
--   /wtcollect status                            etat des blocs enregistres
--   /wtcollect stop                              arrete (rien n'est ecrit)
--   /wtcollect reset                             efface le bloc de la langue courante
--
-- Les bornes par defaut ne sont pas documentees par Blizzard (non confirme).
-- Un identifiant sans nom est compte comme "sans nom" : c'est normal.

local addonName = ...

local SCHEMA = 2
local DEFAULT_MAX_AREA_ID = 20000 -- non confirme : aucune borne dans les docs API
local DEFAULT_MAX_MAP_ID = 3000   -- non confirme
local ABSOLUTE_MAX = 100000       -- garde-fou contre une faute de frappe
local BATCH = 250                 -- appels API par tick
local DELAY = 0.01                -- secondes entre deux ticks
local MIN_AREAS = 200             -- en dessous, la collecte est probablement fausse
local NEAR_BOUND = 0.9            -- trouve au-dela de 90 % de la borne : borne trop basse ?

local state = {
  running = false,
  run = 0,          -- jeton de collecte : chaque start en cree un, les anciennes chaines s'arretent
  phase = nil,      -- "area" puis "map"
  nextId = 1,
  limit = 0,
  maxArea = 0,
  maxMap = 0,
  locale = nil,
  work = nil,       -- bloc en construction (pas encore dans la base)
  unknown = 0,      -- identifiants sans nom (nil, erreur de l'API, type inattendu)
  secret = 0,       -- valeurs secretes ignorees
  empty = 0,        -- noms vides ignores
  lastArea = 0,     -- plus grand identifiant de zone trouve
  lastMap = 0,
}

local function say(msg)
  print("WoWTranslatorCollector : " .. msg)
end

-- Vrai si la valeur est secrete. issecretvalue peut etre absent (rien n'est
-- secret) ou lever une erreur : dans ce cas la valeur est traitee comme secrete.
local function isSecret(v)
  local isv = issecretvalue
  if not isv then return false end
  local ok, sec = pcall(isv, v)
  if not ok then return true end
  return sec and true or false
end

local function ensureDB()
  if type(WoWTranslatorCollectorDB) ~= "table" then
    WoWTranslatorCollectorDB = {}
  end
  return WoWTranslatorCollectorDB
end

local function currentLocale()
  if type(GetLocale) == "function" then
    local loc = GetLocale()
    if type(loc) == "string" and loc ~= "" then return loc end
  end
  return "unknown"
end

local function currentBuild()
  local version, build, _, toc
  if type(GetBuildInfo) == "function" then
    version, build, _, toc = GetBuildInfo()
  end
  return tostring(version or "inconnu"), tostring(build or "inconnu"), toc
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Un identifiant sans nom utilisable ne compte que dans un compteur.
local function collectArea(id)
  local ok, name = pcall(C_Map.GetAreaInfo, id)
  if not ok then
    state.unknown = state.unknown + 1
    return
  end
  if isSecret(name) then
    state.secret = state.secret + 1
    return
  end
  if name == nil or type(name) ~= "string" then
    state.unknown = state.unknown + 1
    return
  end
  if name:find("%S") == nil then
    state.empty = state.empty + 1
    return
  end
  state.work.areas[id] = name
  if id > state.lastArea then state.lastArea = id end
end

local function collectMap(id)
  local ok, info = pcall(C_Map.GetMapInfo, id)
  if not ok then
    state.unknown = state.unknown + 1
    return
  end
  if isSecret(info) then
    state.secret = state.secret + 1
    return
  end
  -- MayReturnNothing : pas de table pour un identifiant inconnu
  if type(info) ~= "table" then
    state.unknown = state.unknown + 1
    return
  end
  local name = info.name
  if isSecret(name) then
    state.secret = state.secret + 1
    return
  end
  if type(name) ~= "string" then
    state.unknown = state.unknown + 1
    return
  end
  if name:find("%S") == nil then
    state.empty = state.empty + 1
    return
  end
  local mt, pm = info.mapType, info.parentMapID
  if isSecret(mt) then mt = nil end
  if isSecret(pm) then pm = nil end
  state.work.maps[id] = { name = name, mapType = mt, parentMapID = pm }
  if id > state.lastMap then state.lastMap = id end
end

local step

local function schedule(token)
  C_Timer.After(DELAY, function() step(token) end)
end

local function finish()
  local work = state.work
  work.areasFound = countKeys(work.areas)
  work.mapsFound = countKeys(work.maps)
  work.unknownIds = state.unknown
  work.secretIgnored = state.secret
  work.emptyIgnored = state.empty
  work.maxFoundAreaId = state.lastArea
  work.maxFoundMapId = state.lastMap
  work.collectedAt = time()
  work.complete = true
  state.running = false

  -- La base n'est modifiee qu'ici : l'ancien bloc complet reste jusqu'a ce point.
  ensureDB()[state.locale] = work
  state.work = nil

  say(string.format("termine (%s) : zones %d, cartes %d, sans nom %d, secrets %d, vides %d.",
    state.locale, work.areasFound, work.mapsFound, work.unknownIds, work.secretIgnored, work.emptyIgnored))
  if work.areasFound < MIN_AREAS then
    say("ATTENTION : seulement " .. work.areasFound .. " zones. Le bloc est probablement faux : verifier le client avant de continuer.")
  end
  if work.maxFoundAreaId >= NEAR_BOUND * work.maxAreaId then
    say("ATTENTION : zone trouvee a l'id " .. work.maxFoundAreaId .. ", pres de la borne " .. work.maxAreaId
      .. ". Relancer avec /wtcollect start <plus grand>.")
  end
  if work.maxFoundMapId >= NEAR_BOUND * work.maxMapId then
    say("ATTENTION : carte trouvee a l'id " .. work.maxFoundMapId .. ", pres de la borne " .. work.maxMapId
      .. ". Relancer avec /wtcollect start <zone> <plus grand>.")
  end
  if type(work.toc) ~= "number" then
    say("ATTENTION : numero d'interface (toc) absent du client. Le generateur refusera ce bloc.")
  end
  say("verifier avec /wtcollect status, puis se deconnecter (ne pas faire /reload pendant la collecte).")
end

local function tickBody(token)
  local count = 0
  while count < BATCH and state.nextId <= state.limit do
    if state.phase == "area" then
      collectArea(state.nextId)
    else
      collectMap(state.nextId)
    end
    state.nextId = state.nextId + 1
    count = count + 1
  end
  if state.nextId > state.limit then
    if state.phase == "area" then
      say(string.format("zones parcourues, %d trouvees. Cartes en cours...", countKeys(state.work.areas)))
      state.phase = "map"
      state.nextId = 1
      state.limit = state.maxMap
      schedule(token)
    else
      finish()
    end
  else
    if state.nextId % 5000 == 1 then
      say(string.format("%s : id %d / %d", state.phase == "area" and "zones" or "cartes", state.nextId, state.limit))
    end
    schedule(token)
  end
end

-- Une chaine de minuteurs n'agit que si son jeton est le jeton courant.
-- Une erreur Lua inattendue arrete la collecte sans rien ecrire.
step = function(token)
  if token ~= state.run or not state.running then return end
  local ok, err = pcall(tickBody, token)
  if not ok then
    state.running = false
    state.work = nil
    say("erreur interne, collecte arretee, rien n'est enregistre : " .. tostring(err))
  end
end

local function startCollect(maxArea, maxMap)
  if state.running then
    say("collecte deja en cours (/wtcollect stop pour l'arreter).")
    return
  end
  if type(C_Map) ~= "table" or type(C_Map.GetAreaInfo) ~= "function" or type(C_Map.GetMapInfo) ~= "function" then
    say("API absente : C_Map.GetAreaInfo / C_Map.GetMapInfo. Arret.")
    return
  end
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
    say("API absente : C_Timer.After. Arret.")
    return
  end
  local locale = currentLocale()
  local version, build, toc = currentBuild()
  state.run = state.run + 1
  state.locale = locale
  state.maxArea = maxArea
  state.maxMap = maxMap
  state.work = {
    schema = SCHEMA,
    locale = locale,
    version = version,
    build = build,
    toc = toc,
    maxAreaId = maxArea,
    maxMapId = maxMap,
    areas = {},
    maps = {},
    complete = false,
  }
  state.running = true
  state.phase = "area"
  state.nextId = 1
  state.limit = maxArea
  state.unknown, state.secret, state.empty = 0, 0, 0
  state.lastArea, state.lastMap = 0, 0

  say(string.format("collecte en %s, build %s, bornes zones 1..%d, cartes 1..%d (bornes non confirmees).",
    locale, build, maxArea, maxMap))
  say("ne pas faire /reload ni se deconnecter pendant la collecte : rien ne serait enregistre.")
  schedule(state.run)
end

local function stopCollect()
  if not state.running then
    say("aucune collecte en cours.")
    return
  end
  state.running = false
  state.work = nil
  say("collecte arretee. Rien n'a ete enregistre ; le bloc precedent, s'il existe, est conserve.")
end

local function parseLimit(text, default)
  if text == nil or text == "" then return default end
  local n = tonumber(text)
  if not n or n < 1 or n ~= math.floor(n) or n > ABSOLUTE_MAX then
    say("valeur invalide : " .. text .. " (entier entre 1 et " .. ABSOLUTE_MAX .. ").")
    return nil
  end
  return n
end

local function showStatus()
  local db = ensureDB()
  local curVersion, curBuild = currentBuild()
  local locales = {}
  for loc, block in pairs(db) do
    if type(block) == "table" then locales[#locales + 1] = loc end
  end
  table.sort(locales)
  if #locales == 0 then say("aucun bloc enregistre.") end
  for _, loc in ipairs(locales) do
    local b = db[loc]
    if b.complete ~= true then
      say(loc .. " : bloc INCOMPLET ou ancien format, a ignorer.")
    else
      local when = "date inconnue"
      if type(b.collectedAt) == "number" and b.collectedAt > 0 then
        when = date("%Y-%m-%d %H:%M", b.collectedAt)
      end
      say(string.format("%s : build %s (%s), bornes %d / %d, zones %s, cartes %s, sans nom %s, secrets %s, date %s.",
        loc, tostring(b.build), tostring(b.version), b.maxAreaId or 0, b.maxMapId or 0,
        tostring(b.areasFound), tostring(b.mapsFound), tostring(b.unknownIds),
        tostring(b.secretIgnored), when))
      if b.build ~= curBuild or b.version ~= curVersion then
        say(loc .. " : ce bloc vient d'un autre build que le client courant (" .. curVersion .. " " .. curBuild .. ").")
      end
    end
  end
  if state.running then
    say(string.format("collecte en cours (%s, %s, id %d / %d).", state.locale, state.phase, state.nextId, state.limit))
  end
end

local function resetCurrent()
  if state.running then
    say("collecte en cours : impossible d'effacer.")
    return
  end
  local locale = currentLocale()
  ensureDB()[locale] = nil
  say("bloc " .. locale .. " efface.")
end

SLASH_WTCOLLECT1 = "/wtcollect"
SlashCmdList["WTCOLLECT"] = function(msg)
  local cmd, a, b = (msg or ""):match("^%s*(%S*)%s*(%S*)%s*(%S*)")
  cmd = string.lower(cmd or "")
  if cmd == "start" then
    local maxArea = parseLimit(a, DEFAULT_MAX_AREA_ID)
    local maxMap = parseLimit(b, DEFAULT_MAX_MAP_ID)
    if maxArea and maxMap then startCollect(maxArea, maxMap) end
  elseif cmd == "status" then
    showStatus()
  elseif cmd == "stop" then
    stopCollect()
  elseif cmd == "reset" then
    resetCurrent()
  else
    say("/wtcollect start [borneZone] [borneCarte] | status | stop | reset")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if name ~= addonName then return end
  ensureDB()
  self:UnregisterEvent("ADDON_LOADED")
end)
