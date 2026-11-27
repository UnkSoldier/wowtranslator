-- Modules/ZoneText.lua (T4) : ZoneTextString, SubZoneTextString, MinimapZoneText.
-- Le mock execute le vrai ZoneText_OnEvent (porte de FrameXML@forever) :
--  * ZoneTextString n'est reecrit que si la zone change (ou ZONE_CHANGED_NEW_AREA) ;
--  * SubZoneTextString recoit "" puis la sous-zone, ou le NOM DE ZONE quand on
--    quitte une sous-zone alors que ZoneTextFrame est cache ;
--  * les cadres disparaissent en fondu apres 3,5 s (m.Wait).
return function(T)
  local function boot(opts)
    local m = T.boot(opts)
    T.requireTocFile(m, "Modules/ZoneText.lua", "T4")
    return m
  end

  local function texts(m)
    return m.env.ZoneTextString:GetText(), m.env.SubZoneTextString:GetText(), m.env.MinimapZoneText:GetText()
  end

  T.test("etat initial : textes Blizzard intacts apres connexion", function()
    local m = boot({ zone = "Stormwind City" })
    local z, s, mm = texts(m)
    T.eq(z, "Stormwind City"); T.eq(s, ""); T.eq(mm, "Stormwind City")
  end)

  T.test("enUS : appui traduit zone et minimap, relachement restaure", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    local z, _, mm = texts(m)
    T.eq(z, "Hurlevent", "ZoneTextString")
    T.eq(mm, "Hurlevent", "MinimapZoneText")
    m.KeyUp()
    z, _, mm = texts(m)
    T.eq(z, "Stormwind City"); T.eq(mm, "Stormwind City")
  end)

  T.test("texte pose avant le chargement de l'addon (OnLoad Blizzard) : traduit a l'appui", function()
    -- SubZoneText_OnLoad et MinimapCluster OnLoad ecrivent avant les addons ;
    -- aucun evenement de zone ensuite (noLogin).
    local m = boot({ zone = "Stormwind City", subzone = "Trade District", noLogin = true })
    T.isEmpty(m.env.ZoneTextString:GetText(), "ZoneTextString jamais ecrit")
    m.KeyDown()
    T.eq(m.env.SubZoneTextString:GetText(), "Quartier commerçant")
    T.eq(m.env.MinimapZoneText:GetText(), "Quartier commerçant")
    T.isEmpty(m.env.ZoneTextString:GetText(), "Apply sur une FontString vide : rien")
    m.KeyUp()
    T.eq(m.env.SubZoneTextString:GetText(), "Trade District")
    T.eq(m.env.MinimapZoneText:GetText(), "Trade District")
  end)

  T.test("sous-zone traduite (SubZoneTextString et minimap)", function()
    local m = boot({ zone = "Stormwind City", subzone = "Trade District" })
    m.KeyDown()
    local z, s, mm = texts(m)
    T.eq(z, "Hurlevent"); T.eq(s, "Quartier commerçant"); T.eq(mm, "Quartier commerçant")
    m.KeyUp()
    z, s, mm = texts(m)
    T.eq(z, "Stormwind City"); T.eq(s, "Trade District"); T.eq(mm, "Trade District")
  end)

  T.test("changement de zone pendant l'appui : retraduit, puis NOUVEL original au relachement", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.SetZone("Ironforge")
    local z, _, mm = texts(m)
    T.eq(z, "Forgefer", "nouvelle zone traduite")
    T.eq(mm, "Forgefer", "minimap retraduite")
    m.KeyUp()
    z, _, mm = texts(m)
    T.eq(z, "Ironforge", "pas le texte perime \"Stormwind City\"")
    T.eq(mm, "Ironforge")
  end)

  T.test("sous-zone quittee cadre cache : SubZoneTextString recoit la zone, traduite puis restauree", function()
    local m = boot({ zone = "Elwynn Forest" })
    m.Wait(4) -- fondu du texte d'arrivee termine
    m.KeyDown()
    m.SetZone("Elwynn Forest", "Goldshire")
    local _, s, mm = texts(m)
    T.eq(s, "Comté-de-l'Or"); T.eq(mm, "Comté-de-l'Or")
    m.Wait(4)
    m.SetZone("Elwynn Forest", "")
    _, s, mm = texts(m)
    T.eq(s, "Forêt d'Elwynn", "en jeu, SubZoneTextString affiche le nom de zone (traduit pendant l'appui)")
    T.eq(mm, "Forêt d'Elwynn")
    m.KeyUp()
    local z
    z, s, mm = texts(m)
    T.eq(z, "Elwynn Forest"); T.eq(s, "Elwynn Forest"); T.eq(mm, "Elwynn Forest")
  end)

  T.test("sous-zone qui change, cadre de zone encore affiche (SetText(\"\") puis texte)", function()
    local m = boot({ zone = "Elwynn Forest" })
    m.KeyDown()
    m.SetZone("Elwynn Forest", "Goldshire")
    T.eq(m.env.SubZoneTextString:GetText(), "Comté-de-l'Or")
    m.SetZone("Elwynn Forest", "")
    T.eq(m.env.SubZoneTextString:GetText(), "", "cadre de zone visible : la sous-zone reste vide")
    T.eq(m.env.MinimapZoneText:GetText(), "Forêt d'Elwynn")
    m.KeyUp()
    T.eq(m.env.SubZoneTextString:GetText(), "")
    T.eq(m.env.MinimapZoneText:GetText(), "Elwynn Forest")
  end)

  T.test("appui apres le fondu : les FontStrings cachees sont quand meme coherentes", function()
    local m = boot({ zone = "Stormwind City" })
    m.Wait(4)
    T.eq(m.env.ZoneTextFrame:IsShown(), false)
    m.KeyDown()
    T.eq(m.env.MinimapZoneText:GetText(), "Hurlevent", "la minimap reste visible et traduite")
    m.KeyUp()
    T.eq(m.env.ZoneTextString:GetText(), "Stormwind City")
  end)

  T.test("nom inconnu : laisse tel quel, pendant et apres", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.SetZone("Nowhere Land")
    local z, _, mm = texts(m)
    T.eq(z, "Nowhere Land"); T.eq(mm, "Nowhere Land")
    m.KeyUp()
    z, _, mm = texts(m)
    T.eq(z, "Nowhere Land"); T.eq(mm, "Nowhere Land")
  end)

  T.test("zone connue + sous-zone inconnue", function()
    local m = boot({ zone = "Ironforge", subzone = "Secret Room" })
    m.KeyDown()
    local z, s, mm = texts(m)
    T.eq(z, "Forgefer"); T.eq(s, "Secret Room"); T.eq(mm, "Secret Room")
    m.KeyUp()
    z = texts(m)
    T.eq(z, "Ironforge")
  end)

  T.test("nom identique (Orgrimmar) : affiche Orgrimmar", function()
    local m = boot({ zone = "Orgrimmar" })
    m.KeyDown()
    T.eq(m.env.ZoneTextString:GetText(), "Orgrimmar")
    m.KeyUp()
    T.eq(m.env.ZoneTextString:GetText(), "Orgrimmar")
  end)

  T.test("client frFR : Hurlevent -> Stormwind City", function()
    local m = boot({ locale = "frFR", zone = "Hurlevent", subzone = "Quartier commerçant" })
    m.KeyDown()
    local z, s, mm = texts(m)
    T.eq(z, "Stormwind City"); T.eq(s, "Trade District"); T.eq(mm, "Trade District")
    m.KeyUp()
    z, s = texts(m)
    T.eq(z, "Hurlevent"); T.eq(s, "Quartier commerçant")
  end)

  T.test("client enUS : un texte deja francais n'est pas touche", function()
    local m = boot({ zone = "Hurlevent" })
    m.KeyDown()
    T.eq(m.env.ZoneTextString:GetText(), "Hurlevent")
    m.KeyUp()
  end)

  T.test("touche relachee : un changement de zone n'est pas traduit", function()
    local m = boot({ zone = "Stormwind City" })
    m.SetZone("Ironforge")
    T.eq(m.env.ZoneTextString:GetText(), "Ironforge")
    T.eq(m.env.MinimapZoneText:GetText(), "Ironforge")
  end)

  T.test("auto-repeat : les originaux ne sont pas ecrases par la traduction", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown(); m.KeyDown(); m.KeyDown()
    T.eq(m.env.ZoneTextString:GetText(), "Hurlevent")
    m.KeyUp()
    T.eq(m.env.ZoneTextString:GetText(), "Stormwind City")
  end)

  T.test("ecran de chargement pendant l'appui : originaux, puis 'up' tardif sans effet", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.LoadingScreen("Ironforge")
    T.eq(m.WT.IsActive(), false)
    local z, _, mm = texts(m)
    T.eq(z, "Ironforge"); T.eq(mm, "Ironforge")
    m.KeyUp()
    z, _, mm = texts(m)
    T.eq(z, "Ironforge", "le 'up' tardif ne restaure pas \"Stormwind City\"")
    T.eq(mm, "Ironforge")
    m.KeyDown()
    T.eq(m.env.ZoneTextString:GetText(), "Forgefer", "nouvel appui fonctionne")
    m.KeyUp()
  end)

  T.test("perte de focus ('up' perdu) : le filet IsKeyDown restaure les textes", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    T.eq(m.env.MinimapZoneText:GetText(), "Hurlevent")
    m.LoseKeyUp()
    m.Wait(1)
    T.eq(m.env.MinimapZoneText:GetText(), "Stormwind City")
  end)

  T.test("PLAYER_LEAVING_WORLD seul pendant l'appui : textes d'origine", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.FireEvent("PLAYER_LEAVING_WORLD")
    T.eq(m.env.ZoneTextString:GetText(), "Stormwind City")
    T.eq(m.env.MinimapZoneText:GetText(), "Stormwind City")
  end)

  T.test("ZoneText_Clear pendant l'appui puis relachement : pas de texte perime", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.env.ZoneText_Clear()
    m.KeyUp()
    T.isEmpty(m.env.ZoneTextString:GetText())
  end)

  T.test("Minimap_Update appele pendant l'appui : retraduit", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown()
    m.zone.minimap = "The Deadmines"
    m.env.Minimap_Update()
    T.eq(m.env.MinimapZoneText:GetText(), "Les Mortemines")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "The Deadmines")
  end)

  -- EllesmereUIMinimap (EUI_Minimap_Apply.lua, EUI_Minimap_Info.lua) : cache
  -- MinimapZoneText, cree un cadre expose en _EBS_LocationBg avec une FontString
  -- anonyme, et la remplit sur les evenements de zone (sans reecrire un texte
  -- identique au precedent, compare a la valeur Blizzard).
  local function ellesmere(m)
    local env = m.env
    env.MinimapZoneText:Hide()
    local bg = env.CreateFrame("Frame", nil, env.Minimap)
    local fs = bg:CreateFontString(nil, "OVERLAY")
    local last
    local function update()
      local text = env.GetZoneText() or ""
      if text == last then return end
      last = text
      fs:SetText(text)
    end
    for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
      bg:RegisterEvent(ev)
    end
    bg:SetScript("OnEvent", update)
    env._EBS_LocationBg = bg
    update()
    return fs
  end

  T.test("EllesmereUIMinimap : barre de lieu traduite pendant l'appui, restauree ensuite", function()
    local m = boot({ zone = "Stormwind City" })
    local fs = ellesmere(m)
    T.eq(fs:GetText(), "Stormwind City")
    m.KeyDown()
    T.eq(fs:GetText(), "Hurlevent")
    m.KeyUp()
    T.eq(fs:GetText(), "Stormwind City")
  end)

  T.test("EllesmereUIMinimap : changement de zone pendant l'appui, puis nouvel original", function()
    local m = boot({ zone = "Stormwind City" })
    local fs = ellesmere(m)
    m.KeyDown()
    m.SetZone("Ironforge")
    T.eq(fs:GetText(), "Forgefer")
    m.KeyUp()
    T.eq(fs:GetText(), "Ironforge")
    m.SetZone("Stormwind City")
    T.eq(fs:GetText(), "Stormwind City", "touche relachee : pas de traduction")
  end)

  T.test("EllesmereUIMinimap configure apres un premier appui : trouve au suivant", function()
    local m = boot({ zone = "Stormwind City" })
    m.KeyDown(); m.KeyUp()
    local fs = ellesmere(m)
    m.KeyDown()
    T.eq(fs:GetText(), "Hurlevent")
    m.KeyUp()
    T.eq(fs:GetText(), "Stormwind City")
  end)

  T.test("_EBS_LocationBg inattendu (Ellesmere modifie) : aucune erreur", function()
    for _, value in ipairs({ 42, "x", {}, { GetRegions = function() error("boom") end } }) do
      local m = boot({ zone = "Stormwind City" })
      m.env._EBS_LocationBg = value
      m.KeyDown()
      T.eq(m.env.MinimapZoneText:GetText(), "Hurlevent", "le reste fonctionne")
      m.KeyUp()
      T.noLuaErrors(m)
    end
  end)

  T.test("minimap cachee (ex. EllesmereUIMinimap) : aucune erreur", function()
    local m = boot({ zone = "Stormwind City" })
    m.env.MinimapCluster.ZoneTextButton:Hide()
    m.KeyDown()
    m.SetZone("Ironforge")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "Ironforge")
  end)
end
