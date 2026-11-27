-- Verifie le mock lui-meme (ces tests doivent passer meme sans l'addon).
return function(T)
  local M = T.mock

  T.test("hooksecurefunc : original d'abord, hook ensuite, memes arguments", function()
    local m = T.newMock()
    local log = {}
    m.env.Foo = function(a, b) log[#log + 1] = "orig:" .. a .. b end
    m.env.hooksecurefunc("Foo", function(a, b) log[#log + 1] = "hook:" .. a .. b end)
    m.env.Foo("x", "y")
    T.eq(log[1], "orig:xy")
    T.eq(log[2], "hook:xy")
  end)

  T.test("hooksecurefunc : retours de l'original preserves (y compris nil)", function()
    local m = T.newMock()
    m.env.Foo = function() return 1, nil, "c" end
    m.env.hooksecurefunc("Foo", function() return "ignored" end)
    local n = select("#", m.env.Foo())
    local a, b, c = m.env.Foo()
    T.eq(n, 3, "nombre de retours")
    T.eq(a, 1); T.isNil(b); T.eq(c, "c")
  end)

  T.test("hooksecurefunc : methode d'objet, chaine de hooks, refus d'une non-fonction", function()
    local m = T.newMock()
    local fs = m.env.ZoneTextString
    local seen
    m.env.hooksecurefunc(fs, "SetText", function(self, t) seen = t end)
    m.env.hooksecurefunc(fs, "SetText", function() end)
    fs:SetText("abc")
    T.eq(fs:GetText(), "abc")
    T.eq(seen, "abc")
    T.ok(m.derivesFrom(fs.SetText, m.originals.FontStringSetText), "chaine de wrappers -> original")
    T.ok(not m.derivesFrom(function() end, m.originals.FontStringSetText), "fonction etrangere detectee")
    T.eq(m.methods.FontString.SetText, m.originals.FontStringSetText, "methode partagee intacte")
    T.raises(function() m.env.hooksecurefunc("NExistePas", function() end) end, "not a function")
  end)

  T.test("hooksecurefunc : un hook qui rappelle SetText sans garde boucle (detecte)", function()
    local m = T.newMock()
    local fs = m.env.ZoneTextString
    m.env.hooksecurefunc(fs, "SetText", function(self, t) self:SetText(t) end)
    T.raises(function() fs:SetText("x") end, "stack overflow")
  end)

  T.test("XML function= : ZoneText_OnEvent lie par reference (hook de la globale inoperant)", function()
    local m = T.newMock({ zone = "Stormwind City" })
    local zoneHook, minimapHook = 0, 0
    m.env.hooksecurefunc("ZoneText_OnEvent", function() zoneHook = zoneHook + 1 end)
    m.env.hooksecurefunc("Minimap_Update", function() minimapHook = minimapHook + 1 end)
    m.SetZone("Ironforge")
    T.eq(zoneHook, 0, "hooksecurefunc(\"ZoneText_OnEvent\") ne doit avoir AUCUN effet (comme en jeu)")
    T.eq(minimapHook, 1, "Minimap_Update est appele par nom : son hook fonctionne")
    T.eq(m.env.ZoneTextString:GetText(), "Ironforge", "le frame utilise toujours l'original")
  end)

  T.test("FrameXML porte : textes poses au chargement (avant les addons)", function()
    local m = T.newMock({ zone = "Stormwind City", subzone = "Trade District" })
    T.eq(m.env.SubZoneTextString:GetText(), "Trade District", "SubZoneText_OnLoad")
    T.eq(m.env.MinimapZoneText:GetText(), "Trade District", "MinimapCluster OnLoad -> Minimap_Update")
    T.eq(m.env.ZoneTextString:GetText(), "", "ZoneTextString vide (GetText jamais nil) tant qu'aucun evenement")
    T.eq(m.env.ZoneTextFrame:IsShown(), false, "FadingFrame_OnLoad cache le frame")
  end)

  T.test("FrameXML porte : ZoneText_OnEvent (nouvelle zone, sous-zone, fondu)", function()
    local m = T.newMock({ zone = "Stormwind City" })
    m.SetZone("Ironforge", "Trade District")
    T.eq(m.env.ZoneTextString:GetText(), "Ironforge")
    T.eq(m.env.SubZoneTextString:GetText(), "Trade District")
    T.eq(m.env.MinimapZoneText:GetText(), "Trade District")
    T.eq(m.env.ZoneTextFrame:IsShown(), true, "FadingFrame_Show")
    m.Wait(4)
    T.eq(m.env.ZoneTextFrame:IsShown(), false, "fondu termine apres 0,5 + 1 + 2 s")
    T.eq(m.env.SubZoneTextFrame:IsShown(), false)
  end)

  T.test("FrameXML porte : sous-zone quittee, cadre cache -> SubZoneTextString = nom de zone", function()
    local m = T.newMock({ zone = "Elwynn Forest" })
    m.SetZone("Elwynn Forest", "Goldshire")
    T.eq(m.env.SubZoneTextString:GetText(), "Goldshire")
    m.Wait(4)
    local before = m.st(m.env.ZoneTextString).setTextCount
    m.SetZone("Elwynn Forest", "")
    T.eq(m.env.SubZoneTextString:GetText(), "Elwynn Forest", "subzoneText = zoneText")
    T.eq(m.st(m.env.ZoneTextString).setTextCount, before, "ZoneTextString non reecrit (meme zone)")
  end)

  T.test("FrameXML porte : ZoneText_Clear vide trois chaines (pas PVPArenaTextString)", function()
    local m = T.newMock()
    m.env.PVPArenaTextString:SetText("x")
    m.env.ZoneText_Clear()
    T.eq(m.env.ZoneTextString:GetText(), "")
    T.eq(m.env.SubZoneTextString:GetText(), "")
    T.eq(m.env.PVPInfoTextString:GetText(), "")
    T.eq(m.env.PVPArenaTextString:GetText(), "x")
  end)

  T.test("FontString : nombre converti, table refusee, SetFormattedText sans SetText", function()
    local m = T.newMock()
    local fs = m.env.MinimapZoneText
    fs:SetText(42)
    T.eq(fs:GetText(), "42")
    -- GetText : cstring, Nilable = false (SimpleFontStringAPIDocumentation).
    -- SetText(nil) -> "" (probable, non confirme en jeu).
    fs:SetText(nil)
    T.eq(fs:GetText(), "")
    T.raises(function() fs:SetText({}) end, "Usage")
    local hooked = 0
    m.env.hooksecurefunc(fs, "SetText", function() hooked = hooked + 1 end)
    fs:SetFormattedText("%s (%d)", "Zone", 3)
    T.eq(fs:GetText(), "Zone (3)")
    T.eq(hooked, 0, "SetFormattedText ne declenche pas les hooks de SetText")
  end)

  T.test("CreateFrame : globale nommee, evenements, erreurs isolees", function()
    local m = T.newMock()
    local f1 = m.env.CreateFrame("Frame", "MyTestFrame")
    T.eq(m.env.MyTestFrame, f1)
    local got = {}
    f1:RegisterEvent("ZONE_CHANGED")
    f1:SetScript("OnEvent", function() error("boom") end)
    local f2 = m.env.CreateFrame("Frame")
    f2:RegisterEvent("ZONE_CHANGED")
    f2:SetScript("OnEvent", function(self, event, a) got[#got + 1] = { self, event, a } end)
    m.FireEvent("ZONE_CHANGED", "arg")
    T.eq(#got, 1, "le 2e frame recoit l'evenement malgre l'erreur du 1er")
    T.eq(got[1][1], f2); T.eq(got[1][2], "ZONE_CHANGED"); T.eq(got[1][3], "arg")
    local errs = T.takeErrors(m)
    T.eq(#errs, 1)
    T.ok(errs[1]:find("boom", 1, true), "erreur transmise au gestionnaire")
    f2:UnregisterEvent("ZONE_CHANGED")
    m.FireEvent("ZONE_CHANGED")
    T.eq(#got, 1, "plus rien apres UnregisterEvent")
    T.takeErrors(m)
    T.raises(function() f2:RegisterEvent("ZONE_CHANGD") end, "unknown event")
  end)

  T.test("UI Blizzard : minimap moderne, carte prechargee ou a la demande", function()
    local m = T.newMock()
    T.isNil(m.env.MinimapZoneTextButton, "pas de MinimapZoneTextButton global dans ce build")
    T.ok(m.env.MinimapCluster.ZoneTextButton, "MinimapCluster.ZoneTextButton existe")
    T.ok(m.env.WorldMapFrame and m.worldMapAreaLabel, "carte chargee au demarrage par defaut")
    local m2 = T.newMock({ worldMapPreloaded = false })
    T.isNil(m2.env.WorldMapFrame)
    m2.LoadBlizzardWorldMap()
    T.ok(m2.env.WorldMapFrame, "carte chargee a la demande")
  end)

  T.test("carte : format reel du suffixe de niveau (AreaLabelDataProvider)", function()
    local m = T.newMock()
    T.eq(m.FormatAreaLabel("Elwynn Forest", 1, 10, "|cff40c040"), "Elwynn Forest|cff40c040 (1-10)|r")
    T.eq(m.FormatAreaLabel("Ironforge", 60, 60, "|cffff2020"), "Ironforge|cffff2020 (60)|r")
    m.WorldMapHover(nil)
    T.eq(m.worldMapAreaLabel:GetText(), "", "ClearAllLabels")
  end)

  T.test("valeurs secretes : type() = string, operations interdites, issecretvalue", function()
    local m = T.newMock()
    T.eq(m.env.issecretvalue("Ironforge"), false)
    m.MakeSecret("Ironforge")
    T.eq(m.env.issecretvalue("Ironforge"), true)
    local p = m.NewSecretProxy()
    T.eq(m.env.issecretvalue(p), true)
    T.eq(m.env.type(p), "string", "type() d'un secret vu par l'addon")
    T.raises(function() return p .. "x" end, "secret")
    T.raises(function() return #p end, "secret")
    T.raises(function() return p:lower() end, "secret")
    T.raises(function() return p == m.NewSecretProxy() end, "secret")
    T.noError(function() m.env.ZoneTextString:SetText(p) end, "SetText accepte un secret")
    T.ok(rawequal(m.env.ZoneTextString:GetText(), p))
  end)

  T.test("IsKeyDown / GetBindingKey : deux touches, touche de base, modificateur non confirme", function()
    local m = T.newMock()
    T.eq(m.env.GetBindingKey("WOWTRANSLATOR_HOLD"), "F6")
    T.eq(m.env.IsKeyDown("F6"), false)
    m.keysDown.F6 = true
    T.eq(m.env.IsKeyDown("F6"), true)
    local m2 = T.newMock({ boundKey = "SHIFT-F6" })
    m2.keysDown.F6 = true
    T.eq(m2.baseKey, "F6")
    T.isNil(m2.env.IsKeyDown("SHIFT-F6"), "IsKeyDown avec modificateur : comportement non confirme -> nil")
    T.eq(m2.env.IsKeyDown("F6"), true)
    local m3 = T.newMock({ boundKeys = { "F6", "BUTTON4" } })
    local k1, k2 = m3.env.GetBindingKey("WOWTRANSLATOR_HOLD")
    T.eq(k1, "F6"); T.eq(k2, "BUTTON4")
    T.eq(M.baseKey("CTRL-SHIFT-F6"), "F6")
    T.eq(M.baseKey("SHIFT--"), "-")
    T.eq(M.baseKey("-"), "-")
    local none = T.newMock({ noBoundKey = true })
    T.isNil(none.env.GetBindingKey("WOWTRANSLATOR_HOLD"))
    T.isNil(T.newMock({ noIsKeyDown = true }).env.IsKeyDown)
  end)

  T.test("C_Timer : NewTicker (iterations, Cancel), NewTimer, After", function()
    local m = T.newMock()
    local n, got = 0, nil
    local tk = m.env.C_Timer.NewTicker(0.2, function(h) n = n + 1; got = h end)
    m.Wait(1)
    T.eq(n, 5, "5 declenchements en 1 s a 0,2 s")
    T.ok(got == tk, "le callback recoit le ticker")
    tk:Cancel()
    T.eq(tk:IsCancelled(), true)
    m.Wait(1)
    T.eq(n, 5, "plus rien apres Cancel")
    local k = 0
    m.env.C_Timer.NewTicker(0.1, function() k = k + 1 end, 3)
    m.Wait(1)
    T.eq(k, 3, "iterations respectees")
    local fired = 0
    local t = m.env.C_Timer.NewTimer(0.5, function() fired = fired + 1 end)
    t:Cancel()
    m.Wait(1)
    T.eq(fired, 0, "NewTimer annule")
  end)

  T.test("issecretvalue : modes d'erreur (AllowedWhenUntainted)", function()
    local m = T.newMock({ issecretErrors = "secret" })
    m.MakeSecret("X")
    T.eq(m.env.issecretvalue("Y"), false)
    T.raises(function() m.env.issecretvalue("X") end, "tainted")
    local m2 = T.newMock({ issecretErrors = "always" })
    T.raises(function() m2.env.issecretvalue("Y") end, "tainted")
  end)

  T.test("garde des dictionnaires : indexer avec un secret leve une erreur", function()
    local m = T.newMock()
    m.ns = { data = { enUS_frFR = { Ironforge = "Forgefer" } } }
    M.guardDictionaries(m)
    local d = m.ns.data.enUS_frFR
    T.eq(d.Ironforge, "Forgefer")
    T.isNil(d["Nowhere"])
    m.MakeSecret("Secret Zone")
    T.raises(function() return d["Secret Zone"] end, "secrete")
    T.raises(function() return d[m.NewSecretProxy()] end, "secrete")
    T.raises(function() return m.env.rawget(d, "Secret Zone") end, "rawget")
    T.eq(m.env.rawget(d, "Ironforge"), "Forgefer", "rawget normal")
    T.isNil(T.newMock({ noIssecretvalue = true }).env.issecretvalue, "mode sans issecretvalue")
    local count = 0
    for _ in pairs(d) do count = count + 1 end
    T.eq(count, 1, "pairs non affecte")
  end)

  T.test("bit : seulement les fonctions du client", function()
    local m = T.newMock()
    if m.env.bit then
      T.ok(m.env.bit.band, "band")
      T.isNil(m.env.bit.tohex, "tohex (LuaJIT) absent")
      T.isNil(m.env.bit.rol, "rol (LuaJIT) absent")
    end
    T.isNil(m.env.coroutine.isyieldable)
  end)

  T.test("parseToc : metadonnees, chemins, annotations", function()
    local toc = M.parseToc("## Interface: 16001\r\n## Title: X\n# commentaire\nCore.lua\nData\\A.lua [AllowLoadTextLocale frFR]\n")
    T.eq(toc.meta.Interface, "16001")
    T.eq(#toc.files, 2)
    T.eq(toc.files[2].path, "Data/A.lua")
    T.eq(toc.files[2].annotations.AllowLoadTextLocale, "frFR")
  end)

  T.test("lint Lua 5.1 : detecte les constructions 5.2+/LuaJIT", function()
    local bad = {
      { "for i=1,2 do goto continue end ::continue::", "goto" },
      { "local x = 7 // 2", "//" },
      { "local s = \"\\x41\"", "\\x" },
      { "local s = '\\u{48}'", "\\u" },
      { "local n = 1LL", "LL" },
      { "local a = 1 & 3", "&" },
      { "local a = 1 | 3", "|" },
      { "local a = 1 << 3", "<<" },
      { "local a = ~1", "~" },
      { "local t = table.unpack({})", "table.unpack" },
      { "local f = load('return 1')", "load" },
      { "local u = utf8.char(65)", "utf8" },
      { "print(_ENV)", "_ENV" },
      { "local n = 0x10LL", "0x..LL" },
      { "local z = 1i", "1i" },
      { "local f = 0x1p4", "0x1p4" },
      { "local h = bit.tohex(5)", "bit.tohex" },
      { "local y = coroutine.isyieldable()", "isyieldable" },
    }
    for _, case in ipairs(bad) do
      T.ok(#M.lint51(case[1]) > 0, "non detecte : " .. case[1])
    end
    local good = "-- goto // & | dans un commentaire\n--[[ goto ]] local s = \"a // b | c & goto\"\n"
      .. "local t = [[ \\x41 ]] if a ~= b then return #s end local f = loadstring('x')\n"
      .. "local u = unpack({}) local m = bit.band(1, 3)"
    local problems = M.lint51(good)
    T.eq(#problems, 0, "faux positif : " .. tostring(problems[1]))
  end)

  local function loadFake(opts)
    local m = T.newMock(opts)
    M.loadAddon(m, { addonDir = M.fixturesDir() .. "/FakeAddon", addonName = "FakeAddon", saved = opts and opts.saved })
    T.noLuaErrors(m)
    return m, m.env.FakeAddon_NS
  end

  T.test("chargeur : ordre du .toc, vararg (nom, ns partage), ADDON_LOADED", function()
    local _, ns = loadFake()
    T.ok(ns, "namespace expose par la fixture")
    T.eq(ns.name, "FakeAddon")
    T.eq(ns.secondName, "FakeAddon")
    T.eq(ns.secondSawSameNs, true)
    T.eq(table.concat(ns.order, ","), "First,Second", "OnlyFrench exclu en enUS")
    T.ok(ns.addonLoadedSelf, "ADDON_LOADED recu avec self")
    local _, nsFr = loadFake({ locale = "frFR" })
    T.eq(table.concat(nsFr.order, ","), "First,Second,OnlyFrench")
  end)

  T.test("SavedVariables : restaurees avant ADDON_LOADED ; Logout = PLAYER_LOGOUT puis ecriture filtree", function()
    local m, ns = loadFake({ saved = { FakeAddonDB = { previous = 1 } } })
    T.eq(ns.dbAtAddonLoaded and ns.dbAtAddonLoaded.previous, 1)
    ns.pendingValue = "ecrit-a-la-deconnexion"
    local saved = m.Logout()
    T.eq(saved.FakeAddonDB.previous, 1)
    T.eq(saved.FakeAddonDB.savedAtLogout, "ecrit-a-la-deconnexion", "ecriture a PLAYER_LOGOUT conservee")
    T.isNil(saved.FakeAddonDB.notSaved, "fonction non serialisee")
  end)

  T.test("bindings : keystate, runOnUp, entites XML, commentaires", function()
    local m, ns = loadFake()
    T.eq(#m.bindings, 2, "binding commente ignore")
    m.PressBinding("down", "FAKEADDON_HOLD")
    m.PressBinding("up", "FAKEADDON_HOLD")
    T.eq(table.concat(ns.keys, ","), "down,up")
    m.PressBinding("down", "FAKEADDON_TAP")
    m.PressBinding("up", "FAKEADDON_TAP")
    T.eq(ns.taps, 1, "sans runOnUp, le relachement n'est pas transmis")
    T.eq(ns.label, "ok", "&quot; decode")
  end)

  T.test("chargeur : addon absent -> erreur propre", function()
    local m = T.newMock()
    local ok, err = pcall(M.loadAddon, m, { addonDir = M.fixturesDir() .. "/NoSuchAddon", addonName = "NoSuchAddon" })
    T.eq(ok, false)
    T.ok(M.isMissing(err), "erreur de type 'addon absent'")
    T.ok(tostring(err):find("introuvable", 1, true), "message clair")
  end)

  T.test("commande slash", function()
    local m = T.newMock()
    local got
    m.env.SLASH_FOO1 = "/foo"
    m.env.SlashCmdList.FOO = function(msg) got = msg end
    T.eq(m.RunSlash("/FOO  bar baz "), true)
    T.eq(got, "bar baz")
    T.eq(m.RunSlash("/nope"), false)
  end)

  T.test("C_Timer.After et OnUpdate via Tick", function()
    local m = T.newMock()
    local fired, updates = false, 0
    m.env.C_Timer.After(1, function() fired = true end)
    local f = m.env.CreateFrame("Frame")
    f:SetScript("OnUpdate", function() updates = updates + 1 end)
    m.Tick(0.5)
    T.eq(fired, false)
    m.Tick(0.6)
    T.eq(fired, true)
    T.eq(updates, 2)
    f:Hide()
    m.Tick(0.1)
    T.eq(updates, 2, "pas d'OnUpdate pour un frame cache")
  end)

  T.test("environnement isole : string/table/math sont des copies", function()
    local m = T.newMock()
    m.env.string.wt_pollution = true
    T.isNil(string.wt_pollution, "la vraie table string n'est pas modifiee")
  end)
end
