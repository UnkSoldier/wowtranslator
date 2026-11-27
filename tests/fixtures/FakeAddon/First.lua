-- Fixture : verifie la convention vararg, l'ordre du .toc et la sauvegarde
-- des SavedVariables a PLAYER_LOGOUT.
local name, ns = ...
ns.name = name
ns.order = { "First" }
FakeAddon_NS = ns
FakeAddonDB = { default = true }
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event, loaded)
  if event == "ADDON_LOADED" and loaded == name then
    ns.addonLoadedSelf = self
    ns.dbAtAddonLoaded = FakeAddonDB
  elseif event == "PLAYER_LOGOUT" then
    -- conception valide : on n'ecrit la config qu'a la deconnexion
    FakeAddonDB.savedAtLogout = ns.pendingValue
    FakeAddonDB.notSaved = function() end   -- non serialisable : perdu
  end
end)
