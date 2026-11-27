-- Les hooks ne cassent jamais le SetText d'origine et ne remplacent rien.
return function(T)
  local FONTSTRINGS = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString",
    "PVPArenaTextString", "MinimapZoneText" }

  T.test("aucune fonction Blizzard remplacee (seulement hooksecurefunc)", function()
    local m = T.boot()
    m.KeyDown(); m.KeyUp()
    for k, orig in pairs(m.baseline) do
      local cur = m.env[k]
      if type(orig) == "function" and cur ~= orig then
        T.ok(m.derivesFrom(cur, orig), "la globale " .. k .. " a ete remplacee sans hooksecurefunc")
      end
    end
    T.eq(m.methods.FontString.SetText, m.originals.FontStringSetText,
      "la methode SetText partagee des FontStrings ne doit pas etre modifiee")
    local fsList = {}
    for _, n in ipairs(FONTSTRINGS) do fsList[#fsList + 1] = { n, m.env[n] } end
    if m.worldMapAreaLabel then fsList[#fsList + 1] = { "WorldMap Label.Name", m.worldMapAreaLabel } end
    for _, e in ipairs(fsList) do
      T.ok(m.derivesFrom(e[2].SetText, m.originals.FontStringSetText),
        e[1] .. ".SetText remplace sans hooksecurefunc")
    end
  end)

  T.test("scripts des frames Blizzard non remplaces (SetScript interdit, HookScript permis)", function()
    local m = T.boot()
    T.ok(#m.blizzardScripts > 0, "le mock doit lister les scripts Blizzard")
    for _, s in ipairs(m.blizzardScripts) do
      local cur = s.frame:GetScript(s.handler)
      T.ok(m.derivesFrom(cur, s.fn),
        s.frame:GetName() .. ":" .. s.handler .. " (" .. s.name .. ") remplace par SetScript")
    end
    m.SetZone("Ironforge")
    T.eq(m.env.ZoneTextString:GetText(), "Ironforge", "le comportement Blizzard marche toujours")
  end)

  T.test("touche relachee : SetText se comporte exactement comme l'original", function()
    local m = T.boot()
    for _, name in ipairs(FONTSTRINGS) do
      local fs = m.env[name]
      for _, v in ipairs({ "Stormwind City", "Nowhere Land", "", "Hurlevent" }) do
        fs:SetText(v)
        T.eq(fs:GetText(), v, name .. ":SetText(" .. T.show(v) .. ")")
      end
      fs:SetText(42)
      T.eq(fs:GetText(), "42", name .. ":SetText(42)")
      fs:SetText(nil)
      T.isEmpty(fs:GetText(), name .. ":SetText(nil)")
    end
  end)

  T.test("touche tenue : valeurs etranges sans erreur", function()
    local m = T.boot()
    m.KeyDown()
    for _, name in ipairs(FONTSTRINGS) do
      local fs = m.env[name]
      T.noError(function() fs:SetText(nil) end, name .. ":SetText(nil)")
      T.noError(function() fs:SetText(42) end, name .. ":SetText(42)")
      T.noError(function() fs:SetText("") end, name .. ":SetText(\"\")")
      T.noError(function() fs:SetText(m.NewSecretProxy()) end, name .. ":SetText(secret)")
      T.noError(function() fs:SetFormattedText("%s", "Ironforge") end, name .. ":SetFormattedText")
    end
    m.KeyUp()
  end)

  T.test("touche tenue : SetText(\"\") ignore (pas de traduction, texte vide conserve)", function()
    local m = T.boot()
    m.KeyDown()
    for _, name in ipairs(FONTSTRINGS) do
      local fs = m.env[name]
      fs:SetText("")
      T.eq(fs:GetText(), "", name)
    end
    m.KeyUp()
    for _, name in ipairs(FONTSTRINGS) do
      T.eq(m.env[name]:GetText(), "", name .. " apres relachement (pas de texte perime)")
    end
  end)

  T.test("garde anti-recursion : un SetText Blizzard = au plus 2 SetText reels", function()
    local m = T.boot()
    m.KeyDown()
    local fs = m.env.MinimapZoneText
    local before = m.st(fs).setTextCount
    fs:SetText("Ironforge")
    local delta = m.st(fs).setTextCount - before
    T.ok(delta <= 2, "SetText appele " .. delta .. " fois pour un seul appel Blizzard")
    m.KeyUp()
  end)

  T.test("valeur secrete (chaine marquee) pendant l'appui : laissee telle quelle", function()
    local m = T.boot()
    m.KeyDown()
    m.MakeSecret("Ironforge")
    m.env.MinimapZoneText:SetText("Ironforge")
    T.eq(m.env.MinimapZoneText:GetText(), "Ironforge", "ne pas traduire une valeur secrete")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "Ironforge")
  end)

  T.test("valeur secrete opaque posee pendant l'appui : intacte, sans erreur", function()
    local m = T.boot()
    m.KeyDown()
    local p = m.NewSecretProxy()
    m.env.MinimapZoneText:SetText(p)
    T.ok(rawequal(m.env.MinimapZoneText:GetText(), p), "le secret doit rester affiche tel quel")
    m.KeyUp()
    T.ok(rawequal(m.env.MinimapZoneText:GetText(), p), "toujours le secret apres relachement")
  end)

  T.test("valeur secrete opaque deja affichee au moment de l'appui (Apply)", function()
    local m = T.boot()
    local p = m.NewSecretProxy()
    m.env.MinimapZoneText:SetText(p)
    m.env.ZoneTextString:SetText(p)
    m.KeyDown()
    T.ok(rawequal(m.env.MinimapZoneText:GetText(), p), "Apply ne doit pas toucher un secret")
    T.ok(rawequal(m.env.ZoneTextString:GetText(), p))
    m.KeyUp()
    T.ok(rawequal(m.env.MinimapZoneText:GetText(), p))
  end)

  T.test("un secret n'est jamais reecrit par un module (regle 2, client-research 5.6)", function()
    -- Le mock compte les SetText recus avec une valeur secrete : seul Blizzard
    -- (le test) en pose ; un module qui le memorise puis le "restaure" est detecte.
    -- (La memorisation seule n'est pas observable hors effet.)
    local m = T.boot({ zone = "Stormwind City" })
    local fs = m.env.MinimapZoneText
    local p = m.NewSecretProxy()
    m.KeyDown()
    fs:SetText(p) -- pose pendant l'appui
    m.KeyUp()
    m.KeyDown(); m.KeyUp()
    T.eq(m.st(fs).secretSetCount, 1, "SetText(secret) rappele par l'addon")
    local q = m.NewSecretProxy()
    fs:SetText(q) -- pose hors appui
    m.KeyDown()
    fs:SetText("Ironforge")
    T.eq(fs:GetText(), "Forgefer")
    m.KeyUp()
    T.eq(fs:GetText(), "Ironforge", "le dernier texte normal est restaure, pas le secret")
    T.eq(m.st(fs).secretSetCount, 2, "aucun secret reecrit")
  end)

  T.test("un autre addon ecrit dans la FontString pendant l'appui : son texte est restaure", function()
    local m = T.boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.env.MinimapZoneText:SetText("Texte d'un autre addon")
    T.eq(m.env.MinimapZoneText:GetText(), "Texte d'un autre addon", "inconnu : laisse tel quel")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "Texte d'un autre addon", "pas de retour a \"Stormwind City\"")
    m.KeyDown()
    m.env.MinimapZoneText:SetText("Ironforge")
    T.eq(m.env.MinimapZoneText:GetText(), "Forgefer")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "Ironforge")
  end)

  T.test("PVPInfoTextString / PVPArenaTextString hors perimetre v1 : jamais modifies", function()
    local m = T.boot()
    m.env.PVPInfoTextString:SetText("Ironforge")
    m.env.PVPArenaTextString:SetText("Stormwind City")
    m.KeyDown()
    T.eq(m.env.PVPInfoTextString:GetText(), "Ironforge")
    T.eq(m.env.PVPArenaTextString:GetText(), "Stormwind City")
    m.KeyUp()
    T.eq(m.env.PVPInfoTextString:GetText(), "Ironforge")
  end)
end
