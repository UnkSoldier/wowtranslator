-- Config.lua (T7) : /wt lang, /wt status, SavedVariables.
-- La persistance passe par m.Logout() : PLAYER_LEAVING_WORLD, PLAYER_LOGOUT,
-- puis ecriture filtree des SavedVariables (comme /reload ou la deconnexion).
return function(T)
  local function boot(opts)
    local m = T.boot(opts)
    T.requireTocFile(m, "Config.lua", "T7")
    return m
  end

  local function svName(m)
    local n = m.savedVarNames[1]
    T.ok(n, "## SavedVariables absent du .toc")
    return n
  end

  T.test("/wt est enregistre", function()
    local m = boot()
    T.eq(m.RunSlash("/wt status"), true, "aucun SLASH_*1 = \"/wt\"")
  end)

  T.test("/wt status : affiche quelque chose, sans erreur", function()
    local m = boot()
    local before = #m.printed
    m.RunSlash("/wt status")
    T.ok(#m.printed > before, "aucune sortie dans le chat")
  end)

  T.test("/wt sans argument ou inconnu : sans erreur", function()
    local m = boot()
    m.RunSlash("/wt")
    m.RunSlash("/wt n'importe quoi")
    T.noLuaErrors(m)
  end)

  T.test("SavedVariables : une table ecrite a la deconnexion", function()
    local m = boot()
    local n = svName(m)
    local saved = m.Logout()
    T.eq(type(saved[n]), "table", n .. " doit etre une table a la deconnexion")
  end)

  T.test("override : client frFR + /wt lang frFR -> anglais vers francais", function()
    local m = boot({ locale = "frFR", zone = "Hurlevent" })
    m.RunSlash("/wt lang frFR")
    T.eq(m.WT.Translate("Stormwind City"), "Hurlevent")
    T.isNil(m.WT.Translate("Hurlevent"))
  end)

  T.test("override : client enUS + /wt lang enUS -> francais vers anglais", function()
    local m = boot({ locale = "enUS" })
    m.RunSlash("/wt lang enUS")
    T.eq(m.WT.Translate("Hurlevent"), "Stormwind City")
  end)

  T.test("override : langue invalide refusee, reglage inchange", function()
    local m = boot({ locale = "enUS" })
    m.RunSlash("/wt lang deDE")
    m.RunSlash("/wt lang")
    T.noLuaErrors(m)
    T.eq(m.WT.Translate("Stormwind City"), "Hurlevent", "cible toujours frFR")
  end)

  T.test("/wt lang pendant l'appui : relachement coherent (original affiche)", function()
    local m = boot({ locale = "enUS", zone = "Stormwind City" })
    T.requireTocFile(m, "Modules/ZoneText.lua", "T4, utilise pour l'affichage")
    m.KeyDown()
    m.RunSlash("/wt lang enUS")
    m.KeyUp()
    T.eq(m.env.MinimapZoneText:GetText(), "Stormwind City", "original restaure")
    T.eq(m.WT.IsActive(), false)
    m.RunSlash("/wt lang frFR")
    m.KeyDown()
    T.eq(m.env.MinimapZoneText:GetText(), "Hurlevent", "nouvel appui avec le reglage courant")
    m.KeyUp()
  end)

  T.test("override persiste apres /reload (ecriture a PLAYER_LOGOUT acceptee)", function()
    local m = boot({ locale = "enUS" })
    m.RunSlash("/wt lang enUS")
    local saved = m.Logout()
    local m2 = boot({ locale = "enUS", saved = saved })
    T.eq(m2.WT.Translate("Hurlevent"), "Stormwind City", "override relu depuis les SavedVariables")
  end)

  T.test("SavedVariables corrompues : valeurs par defaut, sans erreur", function()
    local m0 = boot()
    local n = svName(m0)
    for _, bad in ipairs({ "garbage", 42, { lang = 42, target = {}, locale = true, targetLocale = "xxXX" } }) do
      local m = boot({ locale = "enUS", saved = { [n] = bad } })
      T.eq(m.WT.Translate("Stormwind City"), "Hurlevent", "defaut enUS -> frFR avec " .. T.show(bad))
    end
  end)
end
