-- Vraies donnees Data/*.lua (T3) dans les deux sens.
return function(T)
  local M = T.mock

  -- Echantillon PLAN T3 : capitales, donjons ET raids, zones de depart.
  -- Noms officiels frFR.
  local SAMPLE = {
    -- capitales
    ["Stormwind City"] = "Hurlevent",
    ["Ironforge"] = "Forgefer",
    ["Darnassus"] = "Darnassus",
    ["Orgrimmar"] = "Orgrimmar",
    ["Undercity"] = "Fossoyeuse",
    ["Thunder Bluff"] = "Pitons-du-Tonnerre", -- choix de l'utilisateur (tools/overrides.json)
    -- donjons
    ["The Deadmines"] = "Les Mortemines",
    ["Ragefire Chasm"] = "Gouffre de Ragefeu",
    -- raid
    ["Molten Core"] = "Cœur du Magma",
    -- zones de depart
    ["Elwynn Forest"] = "Forêt d'Elwynn",
    ["Dun Morogh"] = "Dun Morogh",
    ["Teldrassil"] = "Teldrassil",
    ["Durotar"] = "Durotar",
    ["Mulgore"] = "Mulgore",
    ["Tirisfal Glades"] = "Clairières de Tirisfal",
  }

  -- Seuil minimal d'entrees par direction. Valeur provisoire : les seules
  -- zones et sous-zones des capitales et zones de depart depassent largement
  -- 200 noms. A remplacer par le chiffre du rapport de couverture de T1
  -- (variable d'environnement WT_MIN_ENTRIES).
  local MIN_ENTRIES = tonumber(os.getenv("WT_MIN_ENTRIES") or "") or 200

  local function boot(opts)
    opts = opts or {}
    opts.fixtures = false
    local m = T.boot(opts)
    local hasData = false
    for _, e in ipairs(m.toc.files) do
      if e.path:lower():match("^data/") then hasData = true end
    end
    T.ok(hasData, "aucun fichier Data/ dans le .toc (T3)")
    return m
  end

  local function checkTable(t, label)
    T.eq(type(t), "table", label .. " absent")
    local n = 0
    for k, v in pairs(t) do
      n = n + 1
      if type(k) ~= "string" or type(v) ~= "string" or k == "" or v == "" then
        T.ok(false, label .. " : entree invalide " .. T.show(k) .. " = " .. T.show(v))
      end
    end
    T.ok(n >= MIN_ENTRIES, label .. " : seulement " .. n .. " entrees (minimum " .. MIN_ENTRIES .. ")")
    return n
  end

  T.oracleGuard("donnees reelles : ni donnees synthetiques ni marqueur de la reference de test", function()
    local m = boot()
    local bad = {}
    for _, f in ipairs(m.luaSources or {}) do
      if f.display:lower():find("/data/", 1, true) and f.src:find("oracle de test", 1, true) then
        bad[#bad + 1] = f.display .. " : marqueur de tests/mutants/reference"
      end
    end
    for name, dict in pairs(m.WT.data or {}) do
      if type(dict) == "table" then
        local n = 0
        for k, v in pairs(dict) do
          if (type(k) == "string" and (k:match("^Zone %d+$") or k:match("^Zone FR %d+$")))
            or (type(v) == "string" and (v:match("^Zone %d+$") or v:match("^Zone FR %d+$"))) then
            n = n + 1
          end
        end
        if n > 0 then bad[#bad + 1] = name .. " : " .. n .. " entree(s) synthetique(s) \"Zone N\"" end
      end
    end
    T.ok(#bad == 0, "donnees de l'oracle de test dans Data/ :\n    " .. table.concat(bad, "\n    "))
  end)

  T.test("WT.data.enUS_frFR et WT.data.frFR_enUS : chaines non vides, taille minimale", function()
    local m = boot()
    checkTable(m.WT.data and m.WT.data.enUS_frFR, "WT.data.enUS_frFR")
    checkTable(m.WT.data and m.WT.data.frFR_enUS, "WT.data.frFR_enUS")
  end)

  -- Hypothese (relachee pour les noms natifs, tests/README.md) : une valeur du sens
  -- direct qui est un nom natif (identique dans les deux langues, liste
  -- WT.data.native_*) n'a pas d'entree inverse. Partout ailleurs, l'inverse est exige,
  -- et aucun nom natif ne doit avoir d'entree inverse.
  T.test("les deux tables sont inverses l'une de l'autre (hors noms natifs)", function()
    local m = boot()
    local d = m.WT.data
    local function check(fwd, back, fwdName, backName, native)
      native = native or {}
      local sources = {} -- valeur -> nombre de cles qui y menent
      for _, v in pairs(fwd) do sources[v] = (sources[v] or 0) + 1 end
      local bad = {}
      for k, v in pairs(fwd) do
        local r = back[v]
        if r == nil and native[v] ~= nil then
          -- nom natif : pas d'entree inverse attendue
        elseif r == nil then
          bad[#bad + 1] = fwdName .. "[" .. T.show(k) .. "] = " .. T.show(v) .. " absent de " .. backName
        elseif sources[v] == 1 and r ~= k then
          bad[#bad + 1] = backName .. "[" .. T.show(v) .. "] = " .. T.show(r) .. ", attendu " .. T.show(k)
        elseif sources[v] > 1 and fwd[r] ~= v then
          bad[#bad + 1] = "collision " .. T.show(v) .. " : " .. backName .. " pointe vers " .. T.show(r) .. " qui n'y mene pas"
        end
      end
      T.ok(#bad == 0, #bad .. " incoherence(s) :\n    " .. table.concat(bad, "\n    ", 1, math.min(#bad, 10)))
    end
    check(d.enUS_frFR, d.frFR_enUS, "enUS_frFR", "frFR_enUS", d.native_enUS_frFR)
    check(d.frFR_enUS, d.enUS_frFR, "frFR_enUS", "enUS_frFR")
    local nat = {}
    for n in pairs(d.native_frFR_enUS or {}) do
      if d.frFR_enUS[n] ~= nil then nat[#nat + 1] = n end
    end
    T.ok(#nat == 0, "nom natif avec une entree inverse : " .. table.concat(nat, ", "))
  end)

  -- Listes natives (tests/README.md, « Hypothese de data_spec : noms natifs ») :
  -- WT.data.native_enUS_frFR et native_frFR_enUS. Une liste n'est pas une table de
  -- traduction : elle ne sert qu'a exempter une valeur sans entree inverse. Donc :
  -- cle = valeur ; les deux listes sont identiques ; aucun nom natif n'a d'entree
  -- inverse ; la liste reste petite. Part maximale adaptable (comme WT_MIN_ENTRIES) :
  -- valeur provisoire, a recalibrer sur le premier rapport reel (section « Noms natifs »).
  -- Part maximale : une liste ne contient que les noms EXEMPTES (valeurs d'une entree
  -- directe, cas « collision avec identite »). Ils sont rares ; 2 % des entrees directes
  -- est une borne serree, qui garde son sens. Valeur provisoire, a recalibrer sur le
  -- premier rapport reel (section « Collisions avec identite »).
  local NATIVE_MAX_RATIO = tonumber(os.getenv("WT_NATIVE_MAX_RATIO") or "") or 0.02
  -- Borne absolue (G28), en plus de la part relative : provisoire, a recaler sur le premier
  -- rapport reel (section « Collisions avec identite »). WT_NATIVE_MAX_COUNT la remplace.
  local NATIVE_MAX_COUNT = tonumber(os.getenv("WT_NATIVE_MAX_COUNT") or "") or 30

  local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end

  -- Renvoie la liste des problemes (vide si coherent).
  -- fwd = enUS_frFR, back = frFR_enUS, nf / nb = listes natives des deux sens.
  local function nativeProblems(fwd, back, nf, nb)
    nf, nb = nf or {}, nb or {}
    local bad = {}
    -- Chaque nom liste doit etre valeur d'une entree directe (sinon la liste est gonflee)
    local vals = {}
    for _, v in pairs(fwd) do vals[v] = true end
    for n in pairs(nf) do
      if vals[n] == nil then
        bad[#bad + 1] = "liste gonflee : " .. T.show(n) .. " n'est valeur d'aucune entree directe"
      end
    end
    for n in pairs(nb) do
      if vals[n] == nil then
        bad[#bad + 1] = "liste gonflee (frFR) : " .. T.show(n) .. " n'est valeur d'aucune entree directe"
      end
    end
    for n, v in pairs(nf) do
      if v ~= n then
        bad[#bad + 1] = "native_enUS_frFR[" .. T.show(n) .. "] = " .. T.show(v) .. " (attendu identique)"
      end
    end
    for n, v in pairs(nb) do
      if v ~= n then
        bad[#bad + 1] = "native_frFR_enUS[" .. T.show(n) .. "] = " .. T.show(v) .. " (attendu identique)"
      end
    end
    for n in pairs(nf) do
      if nb[n] == nil then bad[#bad + 1] = T.show(n) .. " seulement dans native_enUS_frFR" end
    end
    for n in pairs(nb) do
      if nf[n] == nil then bad[#bad + 1] = T.show(n) .. " seulement dans native_frFR_enUS" end
      if back[n] ~= nil then bad[#bad + 1] = "nom natif " .. T.show(n) .. " a une entree dans frFR_enUS" end
    end
    if countKeys(nf) > NATIVE_MAX_COUNT then
      bad[#bad + 1] = "liste native trop grande : " .. countKeys(nf) .. " noms (maximum absolu "
        .. NATIVE_MAX_COUNT .. ", WT_NATIVE_MAX_COUNT)"
    end
    local total = countKeys(fwd)
    if total > 0 and countKeys(nf) > NATIVE_MAX_RATIO * total then
      bad[#bad + 1] = "liste native trop grande : " .. countKeys(nf) .. " nom(s) sur " .. total
        .. " entrees (maximum " .. math.floor(NATIVE_MAX_RATIO * 100 + 0.5) .. " %, WT_NATIVE_MAX_RATIO)"
    end
    return bad
  end

  T.test("listes natives : valeurs identiques, listes identiques, taille bornee", function()
    local m = boot()
    local d = m.WT.data
    local bad = nativeProblems(d.enUS_frFR, d.frFR_enUS, d.native_enUS_frFR, d.native_frFR_enUS)
    T.ok(#bad == 0, #bad .. " probleme(s) de liste native :\n    " .. table.concat(bad, "\n    "))
  end)

  -- Tables synthetiques (sans donnees du jeu) pour prouver que la verification mord.
  local function synthetic()
    local fwd, back = {}, {}
    for i = 1, 99 do
      fwd["Source " .. i] = "Cible " .. i
      back["Cible " .. i] = "Source " .. i
    end
    fwd["Source natif"] = "Natif" -- valeur native : pas d'entree inverse
    return fwd, back
  end

  T.test("listes natives : une liste coherente passe (controle des tests negatifs)", function()
    local fwd, back = synthetic()
    local bad = nativeProblems(fwd, back, { Natif = "Natif" }, { Natif = "Natif" })
    T.ok(#bad == 0, "liste coherente refusee : " .. table.concat(bad, " ; "))
  end)

  -- Cas mesure (revue 09) : 609 noms traduits et 250 noms identiques, dont 2 exemptes.
  -- Seuls les 2 exemptes sont listes : le test doit passer.
  T.test("listes natives : 609 traduits et 250 identiques, seuls les exemptes listes : accepte", function()
    local fwd, back, identical = {}, {}, {}
    for i = 1, 609 do
      fwd["Source " .. i] = "Cible " .. i
      back["Cible " .. i] = "Source " .. i
    end
    for i = 1, 250 do identical["Identique " .. i] = true end
    fwd["Source A"] = "Identique 1"  -- exemption : valeur d'une entree directe
    fwd["Source B"] = "Identique 2"
    local exempt = { ["Identique 1"] = "Identique 1", ["Identique 2"] = "Identique 2" }
    local bad = nativeProblems(fwd, back, exempt, exempt)
    T.ok(#bad == 0, "liste conforme refusee : " .. table.concat(bad, " ; "))
  end)

  T.test("listes natives : borne absolue (30 noms) en plus de la part relative", function()
    local fwd, back = {}, {}
    for i = 1, 3000 do
      fwd["Source " .. i] = "Cible " .. i
      back["Cible " .. i] = "Source " .. i
    end
    local nat31, nat30 = {}, {}
    for i = 1, 31 do
      fwd["Src nat " .. i] = "Nat " .. i
      nat31["Nat " .. i] = "Nat " .. i
      if i <= 30 then nat30["Nat " .. i] = "Nat " .. i end
    end
    T.ok(#nativeProblems(fwd, back, nat30, nat30) == 0, "30 noms (1 % des entrees) refuses")
    T.ok(#nativeProblems(fwd, back, nat31, nat31) > 0, "31 noms (1 % des entrees) : borne absolue non detectee")
  end)

  T.test("listes natives : un nom liste qui n'est valeur d'aucune entree directe est refuse", function()
    local fwd, back = synthetic()
    local bad = nativeProblems(fwd, back, { Natif = "Natif", Fantome = "Fantome" },
                               { Natif = "Natif", Fantome = "Fantome" })
    T.ok(#bad > 0, "liste gonflee (nom non valeur) non detectee")
  end)

  T.test("listes natives : une liste qui ment est refusee (valeur, listes, inverse, taille)", function()
    local fwd, back = synthetic()
    T.ok(#nativeProblems(fwd, back, { Natif = "Autre" }, { Natif = "Autre" }) > 0,
         "valeur differente de la cle non detectee")
    T.ok(#nativeProblems(fwd, back, { Natif = "Natif" }, {}) > 0,
         "listes differentes (seulement dans enUS_frFR) non detectees")
    back["Natif"] = "Source natif" -- un nom natif a aussi une entree inverse
    T.ok(#nativeProblems(fwd, back, { Natif = "Natif" }, { Natif = "Natif" }) > 0,
         "nom natif ayant une entree inverse non detecte")
    back["Natif"] = nil
    local big = {}
    for i = 1, 10 do
      big["Nom " .. i] = "Nom " .. i
      fwd["Nom " .. i] = "Traduit " .. i
      back["Traduit " .. i] = "Nom " .. i
    end
    T.ok(#nativeProblems(fwd, back, big, big) > 0, "liste trop grande non detectee")
  end)

  T.test("echantillon enUS -> frFR (client enUS)", function()
    local m = boot({ locale = "enUS" })
    for en, fr in pairs(SAMPLE) do
      local r = m.WT.Translate(en)
      if en == fr then
        T.ok(r == fr or r == nil, en .. " -> " .. T.show(r))
      else
        T.eq(r, fr, en)
      end
    end
  end)

  T.test("echantillon frFR -> enUS (client frFR)", function()
    local m = boot({ locale = "frFR", zone = "Hurlevent" })
    for en, fr in pairs(SAMPLE) do
      local r = m.WT.Translate(fr)
      if en == fr then
        T.ok(r == en or r == nil, fr .. " -> " .. T.show(r))
      else
        T.eq(r, en, fr)
      end
    end
  end)

  T.test("chaque fichier Data se charge seul, sans globale ni erreur", function()
    local m0 = boot()
    for _, e in ipairs(m0.toc.files) do
      if e.path:lower():match("^data/") then
        local m = T.newMock()
        local ns = M.loadFile(m, M.addonDir() .. "/" .. e.path, e.path, M.ADDON_NAME, {})
        T.noLuaErrors(m, e.path)
        T.eq(type(ns.data), "table", e.path .. " doit remplir WT.data")
        for k in pairs(m.env) do
          T.ok(m.baseline[k] ~= nil, e.path .. " cree la globale " .. tostring(k))
        end
      end
    end
  end)
end
