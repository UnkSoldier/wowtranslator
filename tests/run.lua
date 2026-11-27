-- tests/run.lua
-- Lanceur de tests sans dependance, Lua 5.1 (ou LuaJIT).
--
--   lua5.1 tests/run.lua                 -- toute la suite
--   lua5.1 tests/run.lua core_keybinding -- seulement ce qui contient ce texte
--   lua5.1 tests/run.lua --root=CHEMIN   -- racine du projet (defaut : parent de tests/)
--   lua5.1 tests/run.lua --addon=DIR    -- dossier de l'addon a tester (defaut RACINE/WoWTranslator)
--   lua5.1 tests/run.lua --list          -- liste les tests sans les executer
--   lua5.1 tests/run.lua --oracle        -- l'addon teste est l'oracle : les garde-fous
--                                           anti-oracle (T.oracleGuard) doivent echouer (xfail)
--
-- Code de sortie : 0 si tout passe, 1 sinon.
-- Les messages sont volontairement sans accents (consoles Windows).

local SPECS = {
  "mock_selftest",
  "structure",
  "core_translate",
  "core_locale",
  "core_keybinding",
  "core_setactive",
  "core_modules",
  "core_safety",
  "hooks",
  "module_zonetext",
  "module_worldmap",
  "config",
  "data",
  "collector",
}

---------------------------------------------------------------------------
-- Arguments et chemins
---------------------------------------------------------------------------
local scriptPath = (arg and arg[0]) or "tests/run.lua"
local testsDir = scriptPath:match("^(.*)[/\\][^/\\]*$") or "."
local root = testsDir .. "/.."
local filter, listOnly, addonDir, oracleMode

for i = 1, (arg and #arg or 0) do
  local a = arg[i]
  local r = a:match("^%-%-root=(.+)$")
  if r then
    root = r
    testsDir = r .. "/tests"
  elseif a:match("^%-%-addon=(.+)$") then
    addonDir = a:match("^%-%-addon=(.+)$")
  elseif a == "--oracle" then
    oracleMode = true
  elseif a == "--list" then
    listOnly = true
  elseif a == "-h" or a == "--help" then
    print("Usage: lua5.1 tests/run.lua [filtre] [--root=CHEMIN] [--addon=DOSSIER_ADDON] [--oracle] [--list]")
    os.exit(0)
  else
    filter = a
  end
end

if _VERSION ~= "Lua 5.1" then
  print("ATTENTION: interpreteur " .. tostring(_VERSION) .. " ; le client WoW utilise Lua 5.1.")
  print("           Les resultats peuvent differer (setfenv absent en 5.2+).")
end
if jit then
  print("ATTENTION: LuaJIT (" .. tostring(jit.version) .. ") accepte goto, \\x, \\u{}, 1LL..., refuses par le")
  print("           Lua 5.1 du jeu. Le test 'structure' passe le code de l'addon au lint Lua 5.1 strict.")
end
if not setfenv then
  print("ERREUR: setfenv indisponible. Lancer avec lua5.1 ou luajit.")
  os.exit(2)
end

local okMock, mock = pcall(dofile, testsDir .. "/wow_mock.lua")
if not okMock then
  print("ERREUR: impossible de charger tests/wow_mock.lua : " .. tostring(mock))
  os.exit(2)
end
mock.setRoot(root)
if addonDir then mock.setAddonDir(addonDir) end

---------------------------------------------------------------------------
-- API des specs
---------------------------------------------------------------------------
local FailMT = { __tostring = function(e) return e.msg end }
local SkipMT = { __tostring = function(e) return "skip: " .. e.reason end }

local T = { mock = mock, root = root }
local registered
local currentMocks

-- Premier cadre de pile hors de run.lua / wow_mock.lua (= ligne de la spec)
local function where()
  for level = 3, 30 do
    local info = debug.getinfo(level, "Sl")
    if not info then break end
    local src = info.short_src or ""
    if info.what ~= "C" and not src:find("run.lua", 1, true) and not src:find("wow_mock.lua", 1, true) then
      return src .. ":" .. tostring(info.currentline or "?")
    end
  end
  return "?"
end

local function fail(msg)
  error(setmetatable({ msg = msg, where = where() }, FailMT), 0)
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
T.show = show

local function prefix(msg) return msg and (msg .. " : ") or "" end

function T.test(name, fn)
  registered[#registered + 1] = { name = name, fn = fn }
end

-- Garde-fou anti-oracle : test qui doit ECHOUER quand l'addon teste est
-- l'oracle tests/mutants/reference (option --oracle) ; compte alors comme
-- "xfail" (echec attendu). S'il passe sous --oracle, c'est un echec.
function T.oracleGuard(name, fn)
  registered[#registered + 1] = { name = name, fn = fn, oracleGuard = true }
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    fail(prefix(msg) .. "attendu " .. show(expected) .. ", obtenu " .. show(actual))
  end
end

function T.neq(actual, notExpected, msg)
  if actual == notExpected then
    fail(prefix(msg) .. "valeur inattendue " .. show(actual))
  end
end

function T.ok(cond, msg)
  if not cond then fail(msg or "condition fausse") end
end

function T.isNil(v, msg)
  if v ~= nil then fail(prefix(msg) .. "attendu nil, obtenu " .. show(v)) end
end

-- v doit etre nil ou "" (FontString vide : le client peut renvoyer l'un ou l'autre)
function T.isEmpty(v, msg)
  if v ~= nil and v ~= "" then fail(prefix(msg) .. "attendu vide (nil ou \"\"), obtenu " .. show(v)) end
end

function T.noError(fn, msg)
  local ok, err = pcall(fn)
  if not ok then
    if mock.isMissing(err) then error(err, 0) end
    fail(prefix(msg) .. "erreur inattendue : " .. tostring(err))
  end
end

function T.raises(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then fail(prefix(msg) .. "une erreur etait attendue") end
  if pattern and not tostring(err):find(pattern) then
    fail(prefix(msg) .. "erreur " .. show(tostring(err)) .. " ne contient pas " .. show(pattern))
  end
end

function T.skip(reason)
  error(setmetatable({ reason = reason }, SkipMT), 0)
end

local function firstLine(s) return (tostring(s):match("^[^\n]*")) end

-- Echoue si des erreurs Lua ont ete envoyees au gestionnaire d'erreurs
function T.noLuaErrors(m, msg)
  if #m.errors > 0 then
    local lines = {}
    for i, e in ipairs(m.errors) do
      if i > 5 then lines[#lines + 1] = "    ..."; break end
      lines[#lines + 1] = "    " .. firstLine(e)
    end
    fail(prefix(msg) .. #m.errors .. " erreur(s) Lua (gestionnaire d'erreurs) :\n" .. table.concat(lines, "\n"))
  end
end

-- Recupere (et efface) les erreurs Lua attendues
function T.takeErrors(m)
  local e = m.errors
  m.errors = {}
  return e
end

-- Demarre l'addon dans un environnement neuf. Echoue si le chargement
-- produit des erreurs Lua ou si la globale WoWTranslator est absente.
-- m.WT = la table publique (globale WoWTranslator = namespace WT).
function T.boot(opts)
  local m = mock.boot(opts)
  currentMocks[#currentMocks + 1] = m
  if not (opts and opts.allowErrors) then T.noLuaErrors(m, "chargement de l'addon") end
  if type(m.env[mock.GLOBAL_NAME]) ~= "table" then
    fail("la globale " .. mock.GLOBAL_NAME .. " (table) est absente apres chargement (contrat PLAN.md)")
  end
  m.WT = m.env[mock.GLOBAL_NAME]
  return m
end

-- Environnement neuf sans addon (pour tester le mock lui-meme)
function T.newMock(opts)
  local m = mock.new(opts)
  currentMocks[#currentMocks + 1] = m
  return m
end

-- Le .toc liste-t-il ce fichier ?
function T.tocHas(m, relpath)
  for _, e in ipairs(m.toc.files) do
    if e.path:lower() == relpath:lower() then return true end
  end
  return false
end

function T.requireTocFile(m, relpath, why)
  if not T.tocHas(m, relpath) then
    T.skip(relpath .. " absent du .toc" .. (why and (" (" .. why .. ")") or ""))
  end
end

-- Module de test : compte les appels Apply/Restore et note IsActive()
function T.spyModule(m, name, behaviour)
  behaviour = behaviour or {}
  local spy = { applies = 0, restores = 0, activeInApply = {}, activeInRestore = {} }
  spy.def = {
    Apply = function()
      spy.applies = spy.applies + 1
      spy.activeInApply[#spy.activeInApply + 1] = m.WT.IsActive()
      if behaviour.applyError then error(behaviour.applyError) end
    end,
    Restore = function()
      spy.restores = spy.restores + 1
      spy.activeInRestore[#spy.activeInRestore + 1] = m.WT.IsActive()
      if behaviour.restoreError then error(behaviour.restoreError) end
    end,
  }
  m.WT.RegisterModule(name, spy.def)
  T.noLuaErrors(m, "RegisterModule(" .. name .. ")")
  return spy
end

---------------------------------------------------------------------------
-- Execution
---------------------------------------------------------------------------
local stats = { pass = 0, fail = 0, skip = 0, missing = 0, xfail = 0 }
local firstMissing, lastMissing
local failures = {}

local function classify(err)
  if type(err) == "table" then
    if getmetatable(err) == SkipMT then return "skip", err.reason end
    if mock.isMissing(err) then return "missing", err.msg end
    if getmetatable(err) == FailMT then return "fail", err.msg, err.where end
    if err.crash then return "fail", err.msg, nil, err.tb end
    return "fail", "erreur (table) : " .. tostring(err)
  end
  return "fail", tostring(err)
end

local function shortTraceback(tb)
  local out = {}
  for line in tostring(tb or ""):gmatch("[^\n]+") do
    if not line:find("run.lua", 1, true) and not line:find("[C]: in function 'xpcall'", 1, true)
      and line ~= "stack traceback:" then
      out[#out + 1] = "        " .. line:gsub("^%s+", "")
      if #out >= 8 then break end
    end
  end
  return table.concat(out, "\n")
end

print("WoWTranslator - suite de tests hors jeu (" .. tostring(_VERSION) .. ")")
print("Racine du projet : " .. root)
print("Addon teste     : " .. mock.addonDir())
if not mock.fileExists(mock.addonDir() .. "/" .. mock.ADDON_NAME .. ".toc") then
  print("NOTE: " .. mock.ADDON_NAME .. "/" .. mock.ADDON_NAME .. ".toc introuvable : les tests de l'addon vont echouer (attendu tant que l'addon n'est pas ecrit).")
end

for _, spec in ipairs(SPECS) do
  registered = {}
  local path = testsDir .. "/specs/" .. spec .. "_spec.lua"
  local chunk, lerr = loadfile(path)
  local loadOk, loadErr = false, lerr
  if chunk then
    local ok, def = pcall(chunk)
    if ok and type(def) == "function" then
      loadOk, loadErr = pcall(def, T)
    elseif ok then
      loadErr = "la spec doit renvoyer function(T)"
    else
      loadErr = def
    end
  end
  print("")
  print("[" .. spec .. "]")
  if not loadOk then
    stats.fail = stats.fail + 1
    print("  FAIL  chargement de la spec : " .. tostring(loadErr))
    failures[#failures + 1] = spec .. " (chargement)"
  end
  for _, tc in ipairs(registered) do
    local full = spec .. " " .. tc.name
    if not filter or full:find(filter, 1, true) then
      if listOnly then
        print("  -     " .. tc.name)
      else
        currentMocks = {}
        local ok, err = xpcall(tc.fn, function(e)
          if type(e) == "table" then return e end
          return { crash = true, msg = tostring(e), tb = debug.traceback("", 2) }
        end)
        if ok then
          -- erreurs Lua non verifiees par le test = echec
          for _, m in ipairs(currentMocks) do
            if #m.errors > 0 then
              ok = false
              local lines = {}
              for i, e in ipairs(m.errors) do
                if i <= 5 then lines[#lines + 1] = "    " .. firstLine(e) end
              end
              err = setmetatable({ msg = #m.errors .. " erreur(s) Lua non attendue(s) :\n" .. table.concat(lines, "\n") }, FailMT)
              break
            end
          end
        end
        -- --oracle : les garde-fous anti-oracle (T.oracleGuard) DOIVENT echouer
        local handled = false
        if tc.oracleGuard and oracleMode then
          if ok then
            ok = false
            err = setmetatable({ msg = "garde-fou anti-oracle NON declenche avec --oracle (l'addon teste n'est-il pas l'oracle ?)" }, FailMT)
          else
            local kind = classify(err)
            if kind == "fail" then
              handled = true
              stats.xfail = stats.xfail + 1
              print("  xfail " .. tc.name .. "  (echec attendu : garde-fou anti-oracle, --oracle)")
            end
          end
        end
        if handled then
          -- deja compte comme echec attendu
        elseif ok then
          stats.pass = stats.pass + 1
          print("  ok    " .. tc.name)
        else
          local kind, msg, loc, tb = classify(err)
          if kind == "skip" then
            stats.skip = stats.skip + 1
            print("  skip  " .. tc.name .. "  (" .. tostring(msg) .. ")")
          else
            stats.fail = stats.fail + 1
            failures[#failures + 1] = full
            if kind == "missing" then
              stats.missing = stats.missing + 1
              if msg ~= firstMissing and msg ~= lastMissing then
                print("  FAIL  " .. tc.name)
                print("        addon absent/incomplet : " .. tostring(msg))
              else
                print("  FAIL  " .. tc.name .. "  (addon absent/incomplet, idem)")
              end
              firstMissing = firstMissing or msg
              lastMissing = msg
            else
              print("  FAIL  " .. tc.name)
              print("        " .. tostring(msg):gsub("\n", "\n        ") .. (loc and ("  [" .. loc .. "]") or ""))
              if tb then print(shortTraceback(tb)) end
            end
          end
        end
      end
    end
  end
end

print("")
print(string.format("Resultat : %d ok, %d echec(s), %d ignore(s)", stats.pass, stats.fail, stats.skip))
if oracleMode then
  print(string.format("Mode --oracle : %d echec(s) attendu(s) (garde-fous anti-oracle), non comptes comme echecs", stats.xfail))
end
if stats.missing > 0 then
  print(string.format("dont %d echec(s) dus a l'addon absent ou incomplet (premier : %s)", stats.missing, firstMissing))
end
os.exit(stats.fail > 0 and 1 or 0)
