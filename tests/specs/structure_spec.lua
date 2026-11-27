-- Structure de l'addon : .toc, Bindings.xml, globales, syntaxe Lua 5.1.
return function(T)
  local M = T.mock

  T.test(".toc : Interface 16001, Title, SavedVariables", function()
    local m = T.boot()
    local iface = m.toc.meta.Interface
    T.ok(iface, "## Interface absent")
    local expected = os.getenv("WT_INTERFACE") or "16001"
    T.ok((", " .. iface .. ","):find("[ ,]" .. expected .. ","),
      "## Interface doit contenir " .. expected .. " (docs/client-research.md), obtenu " .. T.show(iface))
    T.ok(m.toc.meta.Title, "## Title absent")
    T.ok(#m.savedVarNames >= 1, "## SavedVariables absent")
  end)

  T.test(".toc : Core.lua charge avant Modules/ et Config.lua", function()
    local m = T.boot()
    local coreIdx
    for i, e in ipairs(m.toc.files) do
      if e.path:lower() == "core.lua" then coreIdx = i end
    end
    T.ok(coreIdx, "Core.lua absent du .toc")
    for i, e in ipairs(m.toc.files) do
      local p = e.path:lower()
      if p:match("^modules/") or p == "config.lua" then
        T.ok(i > coreIdx, e.path .. " liste avant Core.lua")
      end
    end
  end)

  T.test("syntaxe Lua 5.1 stricte (LuaJIT accepte goto, \\x, 1LL... que le jeu refuse)", function()
    local m = T.boot({ fixtures = false })
    local all = {}
    for _, f in ipairs(m.luaSources or {}) do
      for _, p in ipairs(M.lint51(f.src)) do all[#all + 1] = f.display .. " " .. p end
    end
    for _, b in ipairs(m.bindings) do
      for _, p in ipairs(M.lint51(b.body)) do all[#all + 1] = "Bindings.xml:" .. tostring(b.name) .. " " .. p end
    end
    T.ok(#all == 0, #all .. " construction(s) hors Lua 5.1 :\n    " .. table.concat(all, "\n    ", 1, math.min(#all, 10)))
  end)

  T.oracleGuard("l'addon ne reprend pas l'oracle de test (tests/mutants/reference)", function()
    -- Regle PLAN.md : T2-T7 ne partent pas de la reference.
    local m = T.boot({ fixtures = false })
    local bad = {}
    local function scan(label, src)
      for _, marker in ipairs({ "IMPLEMENTATION DE REFERENCE", "oracle de test", "(reference de test)" }) do
        if src:find(marker, 1, true) then bad[#bad + 1] = label .. " contient \"" .. marker .. "\"" end
      end
    end
    for _, f in ipairs(m.luaSources or {}) do scan(f.display, f.src) end
    scan(M.ADDON_NAME .. ".toc", M.readFile(M.addonDir() .. "/" .. M.ADDON_NAME .. ".toc") or "")
    -- API interne de l'oracle, meme sans commentaire marqueur
    if rawget(m.WT, "_ref") ~= nil then
      bad[#bad + 1] = "WoWTranslator._ref existe apres chargement (API interne de l'oracle)"
    end
    T.ok(#bad == 0, "code de l'oracle copie dans l'addon :\n    " .. table.concat(bad, "\n    "))
  end)

  T.test("Bindings.xml : WOWTRANSLATOR_HOLD, runOnUp, categorie, hors .toc", function()
    local m = T.boot()
    T.ok(M.readFile(M.addonDir() .. "/Bindings.xml"), "WoWTranslator/Bindings.xml introuvable")
    local found
    for _, b in ipairs(m.bindings) do
      if b.name == "WOWTRANSLATOR_HOLD" then found = b end
    end
    T.ok(found, "<Binding name=\"WOWTRANSLATOR_HOLD\"> absent")
    T.eq(found.runOnUp, true, "runOnUp=\"true\" obligatoire (sinon pas de 'up')")
    T.ok(found.fn, "corps du binding non compilable")
    T.ok(found.body:find("WoWTranslator_OnHoldKey", 1, true), "le corps doit appeler WoWTranslator_OnHoldKey(keystate)")
    T.eq(found.attrs.category, "BINDING_HEADER_WOWTRANSLATOR", "category (section propre dans Raccourcis)")
    T.ok(not T.tocHas(m, "Bindings.xml"), "Bindings.xml ne doit pas etre liste dans le .toc")
  end)

  T.test("libelles du raccourci : BINDING_HEADER_ / BINDING_NAME_", function()
    local m = T.boot()
    T.eq(type(m.env.BINDING_NAME_WOWTRANSLATOR_HOLD), "string", "BINDING_NAME_WOWTRANSLATOR_HOLD")
    T.eq(type(m.env.BINDING_HEADER_WOWTRANSLATOR), "string", "BINDING_HEADER_WOWTRANSLATOR")
  end)

  T.test("chargement sans erreur Lua : enUS et frFR, fixtures et vraies donnees, carte prechargee ou non", function()
    for _, loc in ipairs({ "enUS", "frFR" }) do
      T.boot({ locale = loc })
      T.boot({ locale = loc, fixtures = false })
      T.boot({ locale = loc, worldMapPreloaded = false })
    end
  end)

  T.test("globale publique WoWTranslator = namespace ; pas de globale WT", function()
    local m = T.boot()
    T.ok(m.env.WoWTranslator == m.ns, "WoWTranslator doit etre le namespace passe aux fichiers (local _, WT = ...)")
    T.isNil(m.env.WT, "pas de globale WT (risque de collision, PLAN.md)")
  end)

  T.test("pas de fuite de globales", function()
    local m = T.boot()
    m.KeyDown(); m.SetZone("Ironforge"); m.Wait(1); m.KeyUp()
    m.RunSlash("/wt status")
    m.Logout()
    T.takeErrors(m) -- les erreurs eventuelles sont couvertes par d'autres tests
    local allowed = {}
    for _, n in ipairs(m.savedVarNames) do allowed[n] = true end
    for k in pairs(m.env) do
      if m.baseline[k] == nil and not allowed[k] then
        local ks = tostring(k)
        local ok = ks:match("^SLASH_") or ks:match("^BINDING_") or ks:match("^WoWTranslator")
          or ks:match("^WOWTRANSLATOR")
        T.ok(ok, "globale inattendue : " .. ks .. " (utiliser des locales ou le namespace)")
      end
    end
  end)
end
