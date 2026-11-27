-- WoWTranslatorCollector (outil de developpement, hors addon) et pont vers les
-- sorties de tools/build_zone_data.py. Le collecteur tourne dans le mock avec
-- C_Map simule ; C_Timer est celui du mock (m.Tick). Aucun fichier du jeu n'est lu.
return function(T)
  local M = T.mock
  local ADDON = "WoWTranslatorCollector"
  local FILE = "WoWTranslatorCollector/Collector.lua"

  -- Monde simule : zones 1..n (nom "Zone i"), cartes 1..k (nom "Carte i")
  local function world(areaCount, mapCount)
    local w = { areas = {}, maps = {}, areaCalls = 0 }
    for i = 1, areaCount or 0 do w.areas[i] = "Zone " .. i end
    for i = 1, mapCount or 0 do
      w.maps[i] = { name = "Carte " .. i, mapType = 3, parentMapID = 0 }
    end
    return w
  end

  -- Charge le fichier du collecteur dans le mock (appele aussi pour simuler /reload :
  -- l'etat du fichier repart a zero, SavedVariables conserves dans m.env).
  local function loadCollector(m, w)
    m.env.C_Map = {
      GetAreaInfo = function(id)
        w.areaCalls = w.areaCalls + 1
        if w.raises and w.raises(id) then error("areaID inconnu " .. id, 2) end
        return w.areas[id]
      end,
      GetMapInfo = function(id)
        if w.secretInfo and w.secretInfo[id] then return w.secretInfo[id] end
        local e = w.maps[id]
        if e == nil then return nil end
        return { mapID = id, name = e.name, mapType = e.mapType, parentMapID = e.parentMapID, flags = 0 }
      end,
    }
    M.loadFile(m, M.ROOT .. "/" .. FILE, FILE, ADDON, {})
    m.FireEvent("ADDON_LOADED", ADDON)
  end

  local function db(m) return m.env.WoWTranslatorCollectorDB end
  local function slash(m, line)
    T.ok(m.RunSlash(line), "commande non reconnue : " .. line)
  end
  local function countPrinted(m, text)
    local n = 0
    for _, line in ipairs(m.printed) do
      if line:find(text, 1, true) then n = n + 1 end
    end
    return n
  end
  local function printed(m, text) return countPrinted(m, text) > 0 end
  local function ticks(m, seconds) m.Wait(seconds, 0.01) end

  T.test("collecte : lots de 250, bloc ecrit seulement a la fin, champs et compteurs", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(600, 10)
    loadCollector(m, w)
    slash(m, "/wtcollect start 1000 20")
    m.Tick(0.01)
    T.ok(w.areaCalls > 0 and w.areaCalls <= 250,
         "un tick : entre 1 et 250 appels API (obtenu " .. w.areaCalls .. ")")
    T.isNil(db(m).enUS, "aucun bloc tant que la collecte tourne")
    ticks(m, 5)
    local b = db(m).enUS
    T.ok(b ~= nil, "bloc ecrit a la fin")
    T.eq(b.complete, true, "complete")
    T.eq(b.schema, 2, "schema")
    T.eq(b.locale, "enUS", "locale")
    T.eq(b.version, "1.60.1", "version")
    T.eq(b.build, "71037", "build")
    T.eq(b.toc, 16001, "toc")
    T.eq(b.maxAreaId, 1000, "borne zones")
    T.eq(b.maxMapId, 20, "borne cartes")
    T.eq(b.areasFound, 600, "zones trouvees")
    T.eq(b.mapsFound, 10, "cartes trouvees")
    T.eq(b.maxFoundAreaId, 600, "plus grand id de zone")
    T.eq(b.maxFoundMapId, 10, "plus grand id de carte")
    T.eq(b.unknownIds, 410, "identifiants sans nom : 400 zones + 10 cartes")
    T.eq(b.secretIgnored, 0, "secrets")
    T.eq(b.emptyIgnored, 0, "vides")
    T.eq(b.areas[600], "Zone 600", "nom de zone")
    T.eq(b.maps[3].name, "Carte 3", "nom de carte")
    T.eq(b.maps[3].mapType, 3, "mapType")
  end)

  T.test("rerun : l'ancien bloc complet reste en place jusqu'a la fin de la nouvelle collecte", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(300, 10))
    slash(m, "/wtcollect start 300 10")
    ticks(m, 5)
    local old = db(m).enUS
    T.eq(old.maxAreaId, 300, "bloc initial")
    slash(m, "/wtcollect start 500 20")
    m.Tick(0.01)
    T.ok(db(m).enUS == old and db(m).enUS.maxAreaId == 300, "pendant la nouvelle collecte, l'ancien bloc est intact")
    ticks(m, 5)
    T.eq(db(m).enUS.maxAreaId, 500, "remplace a la fin")
  end)

  T.test("/reload en cours de collecte : rien d'ecrit, l'ancien bloc complet reste", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(300, 10)
    loadCollector(m, w)
    slash(m, "/wtcollect start 300 10")
    ticks(m, 5)
    local old = db(m).enUS
    slash(m, "/wtcollect start 500 20")
    m.Tick(0.01)
    -- /reload : les timers disparaissent, les SavedVariables restent, le fichier est relu
    m.timers = {}
    m.Logout()
    loadCollector(m, w)
    T.ok(db(m).enUS == old, "bloc enUS conserve apres /reload")
    T.eq(db(m).enUS.maxAreaId, 300, "bornes du bloc conserve")
    slash(m, "/wtcollect status")
    T.ok(not printed(m, "collecte en cours ("), "aucune collecte fantome apres /reload")
  end)

  T.test("valeur secrete : ignoree et comptee, jamais stockee (proxy : toute operation leve)", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(10, 2)
    w.areas[5] = m.NewSecretProxy()
    w.maps[1].name = m.NewSecretProxy()
    w.secretInfo = { [2] = m.NewSecretProxy() }
    loadCollector(m, w)
    slash(m, "/wtcollect start 10 2")
    ticks(m, 2)
    local b = db(m).enUS
    T.isNil(b.areas[5], "zone secrete non stockee")
    T.isNil(b.maps[1], "nom de carte secret non stocke")
    T.isNil(b.maps[2], "table de carte secrete non stockee")
    T.eq(b.secretIgnored, 3, "trois valeurs secretes comptees")
    T.eq(b.areasFound, 9, "les autres zones sont gardees")
  end)

  T.test("issecretvalue absent : aucune valeur n'est secrete, collecte normale", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(10, 0)
    w.areas[5] = m.MakeSecret("Zone secrete")
    loadCollector(m, w)
    m.env.issecretvalue = nil
    slash(m, "/wtcollect start 10 1")
    ticks(m, 2)
    local b = db(m).enUS
    T.eq(b.areas[5], "Zone secrete", "nom stocke")
    T.eq(b.secretIgnored, 0, "aucun secret")
  end)

  T.test("issecretvalue qui leve : traite comme secret, sans erreur Lua", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(10, 0))
    m.env.issecretvalue = function() error("appel refuse depuis du code tainte", 2) end
    slash(m, "/wtcollect start 10 1")
    ticks(m, 2)
    local b = db(m).enUS
    T.eq(b.areasFound, 0, "rien n'est garde quand la verification echoue")
    -- 10 zones + la carte 1 (absente) : la verification d'un nil echoue aussi
    T.eq(b.secretIgnored, 11, "chaque valeur est comptee comme secrete")
    T.ok(printed(m, "seulement 0 zones"), "avertissement de collecte vide")
  end)

  T.test("borne trop basse : avertissement pour les zones et pour les cartes, seulement si proche", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(950, 10))
    slash(m, "/wtcollect start 1000 20")
    ticks(m, 3)
    T.ok(printed(m, "pres de la borne 1000"), "zone 950 pres de la borne 1000 : avertissement")
    local m2 = T.newMock({ locale = "enUS" })
    loadCollector(m2, world(950, 10))
    slash(m2, "/wtcollect start 5000 20")
    ticks(m2, 3)
    T.ok(not printed(m2, "pres de la borne"), "borne 5000 : pas d'avertissement")
    local m3 = T.newMock({ locale = "enUS" })
    loadCollector(m3, world(10, 19))
    slash(m3, "/wtcollect start 10 20")
    ticks(m3, 3)
    T.ok(printed(m3, "carte trouvee a l'id 19, pres de la borne 20"), "carte 19 pres de la borne 20 : avertissement")
    local m4 = T.newMock({ locale = "enUS" })
    loadCollector(m4, world(10, 10))
    slash(m4, "/wtcollect start 1000 3000")
    ticks(m4, 3)
    T.ok(not printed(m4, "pres de la borne"), "carte 10 sur borne 3000 : pas d'avertissement")
  end)

  T.test("stop puis start : une seule chaine de minuteurs (un tick = au plus 250 appels)", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(600, 10)
    loadCollector(m, w)
    slash(m, "/wtcollect start 1000 20")
    m.Tick(0.01)
    slash(m, "/wtcollect stop")
    slash(m, "/wtcollect start 1000 20")
    w.areaCalls = 0
    m.Tick(0.01)
    T.ok(w.areaCalls <= 250, "apres stop + start, un tick fait au plus 250 appels (obtenu " .. w.areaCalls .. ")")
    ticks(m, 5)
    T.eq(db(m).enUS.areasFound, 600, "collecte complete, une fois")
    T.eq(countPrinted(m, "termine (enUS)"), 1, "un seul message de fin")
  end)

  T.test("toc absent : avertissement a la fin de collecte", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(300, 10))
    m.build = { "1.60.1", "71037", "Nov 1 2026", nil }
    slash(m, "/wtcollect start 300 10")
    ticks(m, 5)
    T.ok(printed(m, "numero d'interface (toc) absent"), "avertissement toc")
  end)

  T.test("identifiants inconnus : l'API leve, compte comme inconnu, pas d'erreur", function()
    local m = T.newMock({ locale = "enUS" })
    local w = world(400, 0)
    w.raises = function(id) return id > 50 end
    loadCollector(m, w)
    slash(m, "/wtcollect start 400 1")
    ticks(m, 3)
    local b = db(m).enUS
    T.eq(b.areasFound, 50, "zones 1..50 trouvees")
    T.eq(b.unknownIds, 351, "zones 51..400 et carte 1 inconnues")
    T.ok(not printed(m, "erreur interne"), "pas d'erreur interne")
  end)

  T.test("bornes invalides : refusees, rien ne demarre", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(10, 1))
    slash(m, "/wtcollect start 0")
    slash(m, "/wtcollect start abc")
    slash(m, "/wtcollect start 1.5")
    slash(m, "/wtcollect start 100001")
    slash(m, "/wtcollect start 10 0")
    T.eq(countPrinted(m, "valeur invalide"), 5, "cinq refus")
    slash(m, "/wtcollect stop")
    T.ok(printed(m, "aucune collecte en cours"), "rien n'a demarre")
    T.isNil(db(m).enUS, "aucun bloc")
  end)

  T.test("start, reset et stop pendant une collecte : refus, puis arret sans ecriture", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(600, 10))
    slash(m, "/wtcollect start 1000 20")
    m.Tick(0.01)
    slash(m, "/wtcollect start 1000 20")
    T.ok(printed(m, "deja en cours"), "second start refuse")
    slash(m, "/wtcollect reset")
    T.ok(printed(m, "impossible d'effacer"), "reset refuse")
    slash(m, "/wtcollect stop")
    T.ok(printed(m, "collecte arretee"), "stop annonce")
    ticks(m, 10)
    T.isNil(db(m).enUS, "arret : rien n'est ecrit")
    slash(m, "/wtcollect status")
    T.ok(not printed(m, "collecte en cours ("), "plus de collecte en cours")
  end)

  T.test("erreur Lua inattendue pendant la collecte : arret propre, rien d'ecrit", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(600, 10))
    local orig = m.env.print
    m.env.print = function(...)
      if tostring((...)):find("parcourues", 1, true) then error("erreur simulee", 0) end
      return orig(...)
    end
    slash(m, "/wtcollect start 1000 20")
    ticks(m, 5)
    T.ok(printed(m, "erreur interne"), "erreur signalee")
    T.isNil(db(m).enUS, "rien d'ecrit")
    slash(m, "/wtcollect status")
    T.ok(not printed(m, "collecte en cours ("), "collecte arretee")
  end)

  T.test("API absente : refus, aucun bloc", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(10, 1))
    m.env.C_Map = nil
    slash(m, "/wtcollect start 10 1")
    T.ok(printed(m, "API absente"), "message d'API absente")
    T.isNil(db(m).enUS, "aucun bloc")
  end)

  T.test("status : bloc incomplet signale, bloc d'un autre build signale", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(300, 10))
    slash(m, "/wtcollect start 300 10")
    ticks(m, 5)
    db(m).frFR = { areas = { [1] = "X" }, maps = {} }
    m.build = { "1.61.0", "71100", "Dec 1 2026", 16100 }
    slash(m, "/wtcollect status")
    T.ok(printed(m, "frFR : bloc INCOMPLET"), "ancien format ou incomplet signale")
    T.ok(printed(m, "autre build que le client courant"), "autre build signale")
  end)

  T.test("Collector.lua : lint Lua 5.1 et seules globales autorisees", function()
    local m = T.newMock({ locale = "enUS" })
    loadCollector(m, world(5, 1))
    local found = false
    for _, src in ipairs(m.luaSources) do
      if src.display == FILE then
        found = true
        local problems = M.lint51(src.src)
        T.eq(#problems, 0, "lint 5.1 : " .. table.concat(problems, " ; "))
      end
    end
    T.ok(found, "Collector.lua charge")
    local allowed = { C_Map = true, WoWTranslatorCollectorDB = true, SLASH_WTCOLLECT1 = true }
    local extra = {}
    for k in pairs(m.env) do
      if m.baseline[k] == nil and not allowed[k] then extra[#extra + 1] = tostring(k) end
    end
    T.eq(#extra, 0, "globales en trop : " .. table.concat(extra, ", "))
  end)

  -- Pont : les deux tables produites par build_zone_data.py depuis la fixture au format
  -- reel (tests/fixtures/collector, regeneree et verifiee par le selftest du generateur)
  -- doivent respecter les memes invariants que tests/specs/data_spec.lua.
  T.test("pont : sorties du generateur depuis la collecte : invariants de data_spec", function()
    local m = T.newMock()
    local dir = M.fixturesDir() .. "/collector"
    local dataF = M.loadFile(m, dir .. "/Zones_enUS_frFR.lua", "fixtures/collector/Zones_enUS_frFR.lua",
                             "WoWTranslator", {}).data
    local dataB = M.loadFile(m, dir .. "/Zones_frFR_enUS.lua", "fixtures/collector/Zones_frFR_enUS.lua",
                             "WoWTranslator", {}).data
    local fwd, bwd = dataF.enUS_frFR, dataB.frFR_enUS
    local native = dataF.native_enUS_frFR or {}
    local allowed = { _G = true }
    for k in pairs(m.env) do
      if m.baseline[k] == nil and not allowed[k] then T.ok(false, "globale creee par les donnees : " .. tostring(k)) end
    end

    local function count(t)
      local n = 0
      for _ in pairs(t) do n = n + 1 end
      return n
    end
    T.eq(count(fwd), 12, "entrees enUS -> frFR")
    T.eq(count(bwd), 9, "entrees frFR -> enUS")
    local nativeB = dataB.native_frFR_enUS or {}
    T.eq(count(nativeB), count(native), "listes natives de meme taille")
    for n, v in pairs(native) do
      T.eq(v, n, "liste native enUS : cle = valeur")
      T.ok(nativeB[n] ~= nil, "natif " .. n .. " present dans les deux listes")
    end

    -- Invariants de data_spec.lua (meme logique, sans reprendre ses donnees)
    -- Hypothese data_spec : une valeur qui est un nom natif n'a pas d'entree inverse
    local function check(a, b, an, bn, nat)
      local sources = {}
      for _, v in pairs(a) do sources[v] = (sources[v] or 0) + 1 end
      local bad = {}
      for k, v in pairs(a) do
        local r = b[v]
        if r == nil and nat and nat[v] ~= nil then
          -- nom natif : rien a verifier
        elseif r == nil then
          bad[#bad + 1] = an .. "[" .. T.show(k) .. "] absent de " .. bn
        elseif sources[v] == 1 and r ~= k then
          bad[#bad + 1] = bn .. "[" .. T.show(v) .. "] = " .. T.show(r) .. ", attendu " .. T.show(k)
        elseif sources[v] > 1 and a[r] ~= v then
          bad[#bad + 1] = "collision " .. T.show(v) .. " : " .. bn .. " pointe vers " .. T.show(r)
        end
      end
      T.ok(#bad == 0, #bad .. " incoherence(s) :\n    " .. table.concat(bad, "\n    "))
    end
    check(fwd, bwd, "enUS_frFR", "frFR_enUS", native)
    check(bwd, fwd, "frFR_enUS", "enUS_frFR")

    -- Valeurs attendues : zone prime sur carte, effectifs reels, identites exclues,
    -- cle brute conservee
    T.eq(fwd["Elwynn Forest"], "Forêt d'Elwynn", "zone et carte identiques : une entree")
    T.eq(fwd["Westfall Coast"], "Côte d'Ouest", "zone prime sur la carte Côte de Ponant")
    T.eq(fwd["Deadwind Pass"], "Col de la Mort-Vent", "carte seule")
    T.eq(bwd["Côte d'Ouest"], "Westfall Coast", "sens inverse : 3 identifiants contre 1")
    T.eq(bwd["Gouffre de Ragefeu"], "Ragefire Chasm", "collision : plus petit identifiant a egalite")
    T.eq(fwd["  Thousand    Needles "], "Mille Pointes", "cle brute conservee")
    T.isNil(fwd["Orgrimmar"], "nom identique : pas d'entree directe")
    T.isNil(bwd["Orgrimmar"], "nom natif Orgrimmar : pas d'entree inverse (un client frFR le garde)")
    T.ok(native["Orgrimmar"] ~= nil, "Orgrimmar est dans la liste native")
    T.eq(fwd["Orgrimmar Gate"], "Orgrimmar", "la paire Orgrimmar Gate -> Orgrimmar est gardee")
    T.isNil(fwd["Dun Morogh"], "nom identique garde sans traduction")
    T.isNil(bwd["Dun Morogh"], "nom identique garde sans traduction (sens inverse)")
  end)
end
