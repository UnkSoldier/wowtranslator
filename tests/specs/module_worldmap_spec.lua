-- Modules/WorldMap.lua (T5) : libelle de zone au survol (provider.Label.Name).
-- Blizzard_WorldMap n'est pas LoadOnDemand : en jeu, la carte existe
-- probablement AVANT l'addon. Chaque test tourne dans les deux modes :
--   "prechargee"  : WorldMapFrame cree avant l'addon, aucun ADDON_LOADED ensuite ;
--   "a la demande": WorldMapFrame cree apres, avec ADDON_LOADED "Blizzard_WorldMap".
-- Formats reels (AreaLabelDataProvider.lua@forever) :
--   "Nom|cffRRGGBB (a-b)|r", "Nom|cffRRGGBB (n)|r", ou "Nom" sans niveaux ;
--   ClearAllLabels -> Name:SetText("").
return function(T)
  local MODES = {
    { label = "prechargee", preloaded = true },
    { label = "a la demande", preloaded = false },
  }

  local function boot(mode, opts)
    opts = opts or {}
    opts.worldMapPreloaded = mode.preloaded
    local m = T.boot(opts)
    T.requireTocFile(m, "Modules/WorldMap.lua", "T5")
    if not mode.preloaded then
      T.isNil(m.env.WorldMapFrame)
      m.KeyDown(); m.KeyUp() -- Apply/Restore sans carte : pas d'erreur
      m.LoadBlizzardWorldMap()
    end
    m.env.WorldMapFrame:Show()
    return m, m.worldMapAreaLabel
  end

  for _, mode in ipairs(MODES) do
    local tag = " [carte " .. mode.label .. "]"

    T.test("libelle de survol traduit pendant l'appui, restaure ensuite" .. tag, function()
      local m, label = boot(mode)
      m.KeyDown()
      m.WorldMapHover("Elwynn Forest")
      T.eq(label:GetText(), "Forêt d'Elwynn")
      m.KeyUp()
      T.eq(label:GetText(), "Elwynn Forest")
    end)

    T.test("libelle deja affiche au moment de l'appui" .. tag, function()
      local m, label = boot(mode)
      m.WorldMapHover("Ironforge")
      m.KeyDown()
      T.eq(label:GetText(), "Forgefer")
      m.WorldMapHover("Nowhere Land")
      T.eq(label:GetText(), "Nowhere Land", "inconnu laisse tel quel")
      m.KeyUp()
      T.eq(label:GetText(), "Nowhere Land", "pas de texte perime")
    end)

    T.test("suffixe de niveau reel (plage) conserve" .. tag, function()
      local m, label = boot(mode)
      m.KeyDown()
      m.WorldMapHover("Elwynn Forest", 1, 10, "|cff40c040")
      T.eq(label:GetText(), "Forêt d'Elwynn|cff40c040 (1-10)|r")
      m.KeyUp()
      T.eq(label:GetText(), "Elwynn Forest|cff40c040 (1-10)|r")
    end)

    T.test("suffixe de niveau reel (niveau unique) conserve" .. tag, function()
      local m, label = boot(mode)
      m.KeyDown()
      m.WorldMapHover("The Deadmines", 18, 18, "|cffff8040")
      T.eq(label:GetText(), "Les Mortemines|cffff8040 (18)|r")
      m.KeyUp()
      T.eq(label:GetText(), "The Deadmines|cffff8040 (18)|r")
    end)

    T.test("libelle efface (ClearAllLabels) pendant l'appui : reste vide" .. tag, function()
      local m, label = boot(mode)
      m.WorldMapHover("Ironforge")
      m.KeyDown()
      m.WorldMapHover(nil)
      T.eq(label:GetText(), "")
      m.KeyUp()
      T.eq(label:GetText(), "", "pas de retour a \"Ironforge\"")
    end)

    T.test("touche relachee : libelle non modifie" .. tag, function()
      local m, label = boot(mode)
      m.WorldMapHover("Ironforge", 1, 10)
      T.eq(label:GetText(), "Ironforge|cff40c040 (1-10)|r")
    end)

    T.test("secret opaque pose pendant l'appui : intact, sans erreur" .. tag, function()
      local m, label = boot(mode)
      m.KeyDown()
      local p = m.NewSecretProxy()
      T.noError(function() label:SetText(p) end, "hook du libelle avec un secret")
      T.ok(rawequal(label:GetText(), p), "secret laisse tel quel")
      m.KeyUp()
      T.ok(rawequal(label:GetText(), p))
    end)

    T.test("secret opaque deja affiche au moment de l'appui (Apply)" .. tag, function()
      local m, label = boot(mode)
      local p = m.NewSecretProxy()
      label:SetText(p)
      m.KeyDown()
      T.ok(rawequal(label:GetText(), p), "Apply ne touche pas un secret")
      m.KeyUp()
      T.ok(rawequal(label:GetText(), p))
    end)

    T.test("chaine secrete avec suffixe de niveau : non traduite" .. tag, function()
      local m, label = boot(mode)
      local s = m.MakeSecret(m.FormatAreaLabel("Ironforge", 1, 10, "|cff40c040"))
      m.KeyDown()
      label:SetText(s)
      T.eq(label:GetText(), s)
      m.KeyUp()
      T.eq(label:GetText(), s)
    end)

    T.test("titre de la fenetre jamais traduit" .. tag, function()
      local m = boot(mode)
      local title = m.env.WorldMapFrame.BorderFrame.TitleText
      m.env.WorldMapFrame.BorderFrame:SetTitle("Ironforge") -- meme s'il ressemble a un lieu
      m.KeyDown()
      T.eq(title:GetText(), "Ironforge")
      m.KeyUp()
    end)
  end
end
