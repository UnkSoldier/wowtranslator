-- WT.Translate : lookup dans le dictionnaire de la langue cible, jamais d'erreur.
-- m.WT = globale WoWTranslator (= namespace WT des fichiers).
return function(T)
  T.test("WoWTranslator expose IsActive, Translate, RegisterModule", function()
    local m = T.boot()
    T.eq(type(m.WT.IsActive), "function", "IsActive")
    T.eq(type(m.WT.Translate), "function", "Translate")
    T.eq(type(m.WT.RegisterModule), "function", "RegisterModule")
    T.eq(type(m.WT.data), "table", "WT.data rempli par les fichiers de donnees")
  end)

  T.test("enUS : traduction connue", function()
    local m = T.boot({ locale = "enUS" })
    T.eq(m.WT.Translate("Stormwind City"), "Hurlevent")
    T.eq(m.WT.Translate("Ironforge"), "Forgefer")
    T.eq(m.WT.Translate("The Deadmines"), "Les Mortemines")
    T.eq(m.WT.Translate("Elwynn Forest"), "Forêt d'Elwynn", "UTF-8")
  end)

  T.test("ordre Core/Data indifferent (donnees chargees avant ou apres Core)", function()
    for _, at in ipairs({ "first", "last" }) do
      local m = T.boot({ fixturesAt = at })
      T.eq(m.WT.Translate("Ironforge"), "Forgefer", "fixtures chargees en position " .. at)
    end
  end)

  T.test("nom identique dans les deux langues : Orgrimmar reste Orgrimmar", function()
    local m = T.boot({ locale = "enUS" })
    local r = m.WT.Translate("Orgrimmar")
    T.ok(r == "Orgrimmar" or r == nil, "attendu \"Orgrimmar\" ou nil, obtenu " .. T.show(r))
  end)

  T.test("nom inconnu -> nil", function()
    local m = T.boot()
    T.isNil(m.WT.Translate("Nowhere Land"))
    T.isNil(m.WT.Translate("stormwind city"), "correspondance exacte (casse)")
    T.isNil(m.WT.Translate(""), "chaine vide")
  end)

  T.test("entrees non string : jamais d'erreur, renvoie nil", function()
    local m = T.boot()
    local inputs = { { "nil", nil }, { "nombre", 42 }, { "booleen", true }, { "table", {} },
      { "fonction", function() end } }
    for _, case in ipairs(inputs) do
      local ok, r = pcall(m.WT.Translate, case[2])
      T.ok(ok, "Translate(" .. case[1] .. ") a leve une erreur : " .. tostring(r))
      T.isNil(r, "Translate(" .. case[1] .. ")")
    end
    local ok, r = pcall(m.WT.Translate)
    T.ok(ok, "Translate() sans argument a leve une erreur : " .. tostring(r))
    T.isNil(r, "Translate()")
  end)

  T.test("valeurs secretes : nil, sans erreur", function()
    local m = T.boot()
    m.MakeSecret("Ironforge")
    local ok, r = pcall(m.WT.Translate, "Ironforge")
    T.ok(ok, "erreur : " .. tostring(r))
    T.isNil(r, "Translate(valeur secrete) doit renvoyer nil (issecretvalue)")
    local p = m.NewSecretProxy() -- type() == "string" vu de l'addon
    ok, r = pcall(m.WT.Translate, p)
    T.ok(ok, "Translate(proxy secret) a leve une erreur (issecretvalue doit etre teste en premier) : " .. tostring(r))
    T.isNil(r)
  end)

  T.test("issecretvalue teste AVANT l'indexation du dictionnaire (secret absent du dictionnaire)", function()
    -- Le mock garde WT.data.* : indexer avec un secret leve une erreur.
    local m = T.boot()
    m.MakeSecret("Secret Zone")
    local ok, r = pcall(m.WT.Translate, "Secret Zone")
    T.ok(ok, "Translate a indexe le dictionnaire avec un secret avant issecretvalue : " .. tostring(r))
    T.isNil(r)
    local p = m.NewSecretProxy()
    ok, r = pcall(m.WT.Translate, p)
    T.ok(ok, "Translate(proxy) : " .. tostring(r))
    T.isNil(r)
    T.isNil(m.secretIndexed, "dictionnaire indexe avec un secret")
  end)

  T.test("issecretvalue qui leve une erreur (AllowedWhenUntainted) : pcall, traite comme secret", function()
    local m = T.boot({ issecretErrors = "secret" })
    m.MakeSecret("Ironforge")
    local ok, r = pcall(m.WT.Translate, "Ironforge")
    T.ok(ok, "Translate doit appeler issecretvalue via pcall : " .. tostring(r))
    T.isNil(r, "erreur de issecretvalue = secret")
    T.eq(m.WT.Translate("Stormwind City"), "Hurlevent", "les valeurs normales restent traduites")
    local m2 = T.boot({ issecretErrors = "always" })
    ok, r = pcall(m2.WT.Translate, "Stormwind City")
    T.ok(ok, "issecretvalue toujours en erreur : Translate ne doit pas lever : " .. tostring(r))
    T.isNil(r, "dans le doute, pas de traduction")
    m2.KeyDown(); m2.SetZone("Ironforge"); m2.KeyUp()
    T.eq(m2.env.ZoneTextString:GetText(), "Ironforge", "affichage intact, sans erreur")
  end)

  T.test("issecretvalue absent : aucune valeur secrete, la traduction fonctionne", function()
    local m = T.boot({ noIssecretvalue = true, zone = "Stormwind City" })
    T.isNil(m.env.issecretvalue)
    T.eq(m.WT.Translate("Ironforge"), "Forgefer")
    m.KeyDown()
    T.eq(m.env.ZoneTextString:GetText(), "Hurlevent", "affichage traduit sans issecretvalue")
    m.KeyUp()
  end)

  T.test("recherche EXACTE : pas de retrait de codes couleur ni de suffixe", function()
    local m = T.boot()
    T.isNil(m.WT.Translate("|cffffd100Stormwind City|r"))
    T.isNil(m.WT.Translate("Elwynn Forest|cff40c040 (1-10)|r"))
    T.isNil(m.WT.Translate(" Ironforge"), "espaces non retires")
  end)

  T.test("issecretvalue est consulte pour chaque chaine traduite", function()
    local m = T.boot()
    for _, s in ipairs({ "Ironforge", "Nowhere Land", "Orgrimmar" }) do
      local before = m.issecretCalls or 0
      m.WT.Translate(s)
      T.ok((m.issecretCalls or 0) > before, "Translate(" .. s .. ") n'appelle pas issecretvalue")
    end
  end)

  T.test("Translate ne depend pas de l'etat de la touche", function()
    local m = T.boot()
    T.eq(m.WT.Translate("Ironforge"), "Forgefer", "touche relachee")
    m.KeyDown()
    T.eq(m.WT.Translate("Ironforge"), "Forgefer", "touche tenue")
    m.KeyUp()
    T.eq(m.WT.Translate("Ironforge"), "Forgefer", "apres relachement")
  end)

  T.test("chaines avec codes couleur : jamais d'erreur", function()
    local m = T.boot()
    T.noError(function() m.WT.Translate("|cffffd100Stormwind City|r") end)
    T.noError(function() m.WT.Translate("Elwynn Forest|cff40c040 (1-10)|r") end)
  end)
end
