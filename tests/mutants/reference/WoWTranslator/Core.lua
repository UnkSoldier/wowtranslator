-- IMPLEMENTATION DE REFERENCE : ORACLE DE TEST UNIQUEMENT.
-- Sert a prouver que la suite est satisfaisable et a fabriquer les mutants
-- (tests/mutants/patches). Ce n'est PAS le code de l'addon : T2-T7 ne partent
-- pas de ce fichier (regle de PLAN.md). Les aides internes sont rangees sous
-- WT._ref (hors contrat, ne pas reproduire).
local addonName, WT = ...
WoWTranslator = WT
WT.data = WT.data or {}

local ref = {}
WT._ref = ref

local active, modules = false, {}

-- issecretvalue : peut etre absent (rien n'est secret) ; documente
-- AllowedWhenUntainted -> appel protege, erreur = secret.
local function isSecret(v)
  if not issecretvalue then return false end
  local ok, r = pcall(issecretvalue, v)
  if not ok then return true end
  return r and true or false
end
ref.isSecret = isSecret

local function norm(l) if l == "enGB" then return "enUS" end return l end
local function targetLocale()
  local o = ref.db and ref.db.lang
  if o == "enUS" or o == "frFR" then return o end
  local l = norm(GetLocale())
  if l == "enUS" then return "frFR" elseif l == "frFR" then return "enUS" end
end
ref.targetLocale = targetLocale

function WT.Translate(text)
  if isSecret(text) then return nil end
  if type(text) ~= "string" or text == "" then return nil end
  local t = targetLocale()
  if not t then return nil end
  local d = WT.data[(t == "frFR" and "enUS" or "frFR") .. "_" .. t]
  return d and d[text] or nil
end

function WT.IsActive() return active end
function WT.RegisterModule(name, def) modules[#modules + 1] = def end

local function call(f)
  if f then
    local ok, err = pcall(f)
    if not ok then geterrorhandler()(err) end
  end
end

-- Filet de securite : arme UNIQUEMENT par la touche ; toutes les touches
-- liees, touche de base ; coupe seulement si toutes renvoient exactement false.
local function baseKey(k) return k:match("^.*%-(.+)$") or k end
local function anyBoundKeyHeld()
  if not IsKeyDown then return true end
  local keys = { GetBindingKey("WOWTRANSLATOR_HOLD") }
  if #keys == 0 then return true end
  for _, k in ipairs(keys) do
    local d = IsKeyDown(baseKey(k))
    if d ~= false then return true end -- true ou nil (inconnu)
  end
  return false
end

local poll = CreateFrame("Frame")
poll:Hide()
local acc = 0
poll:SetScript("OnUpdate", function(self, elapsed)
  acc = acc + elapsed
  if acc < 0.2 then return end
  acc = 0
  if not anyBoundKeyHeld() then WT.SetActive(false) end
end)
local function armNet() acc = 0; poll:Show() end
local function disarmNet() poll:Hide() end

function WT.SetActive(on)
  on = on and true or false
  if on == active then return end
  active = on
  if not on then disarmNet() end
  for _, m in ipairs(modules) do call(on and m.Apply or m.Restore) end
end

function WoWTranslator_OnHoldKey(keystate)
  if keystate == "down" then
    WT.SetActive(true)
    if active then armNet() end
  else
    WT.SetActive(false)
  end
end

if GetLocale() == "frFR" then
  BINDING_HEADER_WOWTRANSLATOR = "WoWTranslator"
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Afficher l'autre langue (maintenir)"
else
  BINDING_HEADER_WOWTRANSLATOR = "WoWTranslator"
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Show other language (hold)"
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function() WT.SetActive(false) end)

-- Hook post-SetText avec garde anti-recursion. Un texte secret n'est ni
-- memorise ni reecrit (regle 2, client-research 5.6).
local function defaultTr(text)
  if type(text) ~= "string" or text == "" then return nil end
  return WT.Translate(text)
end
function ref.HookFontString(fs, tr)
  tr = tr or defaultTr
  local st = { busy = false }
  local function set(t) st.busy = true; fs:SetText(t); st.busy = false end
  local function try(text)
    local r = tr(text)
    if r and r ~= text then st.applied = r; set(r) end
  end
  hooksecurefunc(fs, "SetText", function(self, text)
    if st.busy then return end
    if isSecret(text) then st.original, st.applied = nil, nil; return end
    st.original, st.applied = text, nil
    if active then try(text) end
  end)
  return {
    Apply = function()
      if st.applied then return end
      local cur = fs:GetText()
      if isSecret(cur) then st.original = nil; return end
      st.original = cur
      try(cur)
    end,
    Restore = function()
      if st.applied and st.original ~= nil then
        local cur = fs:GetText()
        if not isSecret(cur) and cur == st.applied then set(st.original) end
      end
      st.applied = nil
    end,
  }
end
function ref.Group(list)
  return {
    Apply = function() for _, h in ipairs(list) do h.Apply() end end,
    Restore = function() for _, h in ipairs(list) do h.Restore() end end,
  }
end
