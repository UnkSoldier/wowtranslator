-- tests/wow_mock.lua
-- Mock minimal mais fidele de l'API WoW pour executer WoWTranslator hors du jeu.
--
-- Client vise : WoW: Forever, build 1.60.1 (71037), ## Interface: 16001, moteur
-- moderne "Mainline", type de jeu "camelot" (voir docs/client-research.md).
-- Lua 5.1 (comme tous les clients WoW).
--
-- Principes :
--  * chaque M.new() cree un environnement global isole (setfenv) ;
--  * les fichiers de l'addon sont charges dans l'ordre du .toc, avec la
--    convention vararg `local addonName, ns = ...` ;
--  * les erreurs Lua levees par un script (OnEvent, OnUpdate, binding, fichier,
--    timer) vont au gestionnaire d'erreurs (geterrorhandler), comme en jeu ;
--  * hooksecurefunc a la vraie semantique post-hook ;
--  * le code FrameXML utile (ZoneText.lua, FadingFrame.lua, Minimap_Update) est
--    PORTE depuis wow-ui-source@forever (build 71037) et execute dans
--    l'environnement, avec les scripts XML `function="..."` lies PAR REFERENCE
--    au chargement (un hooksecurefunc sur la globale n'a donc aucun effet sur
--    le frame, comme en jeu).
--
-- Ce fichier doit rester du Lua 5.1 pur (pas de goto, pas de //, pas d'utf8).

local M = {}

local unpack = unpack or table.unpack
local loadstring = loadstring or load
local setfenv = setfenv

local function pack(...) return { n = select("#", ...), ... } end
M.pack = pack

M.ROOT = "."
M.ADDON_NAME = "WoWTranslator"
M.GLOBAL_NAME = "WoWTranslator"   -- seule globale publique (PLAN.md, contrat)
M.GAME_TYPE = "camelot"           -- type de jeu de WoW: Forever
M.BOUND_KEY = "F6"                -- touche liee a WOWTRANSLATOR_HOLD dans le mock

function M.setRoot(root) M.ROOT = root end
-- M.ADDON_DIR : dossier de l'addon a tester (defaut ROOT/WoWTranslator ;
-- run.lua --addon=CHEMIN, utilise par tests/mutants/)
function M.setAddonDir(dir) M.ADDON_DIR = dir end
function M.addonDir() return M.ADDON_DIR or (M.ROOT .. "/" .. M.ADDON_NAME) end

-- Touche de base d'un raccourci (modificateurs retires) :
-- "SHIFT-F6" -> "F6", "CTRL-SHIFT-F6" -> "F6", "SHIFT--" -> "-", "-" -> "-"
function M.baseKey(key)
  return key:match("^.*%-(.+)$") or key
end
function M.fixturesDir() return M.ROOT .. "/tests/fixtures" end

---------------------------------------------------------------------------
-- Erreur "propre" quand l'addon est absent ou incomplet
---------------------------------------------------------------------------
local MissingMT = { __tostring = function(e) return e.msg end }
function M.missing(msg)
  error(setmetatable({ wt_missing = true, msg = msg }, MissingMT), 0)
end
function M.isMissing(e)
  return type(e) == "table" and rawget(e, "wt_missing") == true
end

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end -- BOM UTF-8
  return s
end
M.readFile = readFile

function M.fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
M.trim = trim

local function deepcopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local c = {}
  seen[v] = c
  for k, x in pairs(v) do c[deepcopy(k, seen)] = deepcopy(x, seen) end
  return c
end
M.deepcopy = deepcopy

local function shallowcopy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function splitList(s)
  local out = {}
  for item in (s or ""):gmatch("[^,]+") do
    item = trim(item)
    if item ~= "" then out[#out + 1] = item end
  end
  return out
end
M.splitList = splitList

-- Serialisation des SavedVariables telle que le client la fait : seules les
-- chaines, nombres, booleens et tables sont ecrits (fonctions, userdata et
-- valeurs secretes sont perdus) ; les cles doivent etre chaine/nombre/booleen.
local function serializeSV(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" then return v end
  if t ~= "table" or depth > 50 then return nil end
  local c = {}
  for k, x in pairs(v) do
    local kt = type(k)
    if kt == "string" or kt == "number" or kt == "boolean" then
      local sx = serializeSV(x, depth + 1)
      if sx ~= nil then c[k] = sx end
    end
  end
  return c
end
M.serializeSV = serializeSV

---------------------------------------------------------------------------
-- Garde-fou syntaxe Lua 5.1 stricte.
-- Les tests tournent souvent sous LuaJIT, qui accepte des choses que le Lua
-- 5.1 du jeu refuse (goto, \x, \u{}, 1LL, ...). Ce lint signale ces
-- constructions dans le code de l'addon (commentaires et chaines retires).
---------------------------------------------------------------------------
local LINT_CHECKS = {
  { "[^%w_]goto[^%w_]", "goto (Lua 5.2+ / LuaJIT)" },
  { "::[%a_][%w_]*::", "label ::nom:: (Lua 5.2+ / LuaJIT)" },
  { "//", "division entiere // (Lua 5.3+)" },
  { "[^%w_]%d+[uU]?[lL][lL][^%w_]", "litteral 64 bits LL/ULL (LuaJIT)" },
  { "[^%w_]0[xX]%x+[uU]?[lL][lL][^%w_]", "litteral hexadecimal 64 bits LL/ULL (LuaJIT)" },
  { "[^%w_]%d+%.?%d*[iI][^%w_]", "litteral imaginaire 1i (LuaJIT)" },
  { "[^%w_]0[xX]%x*%.?%x*[pP][%+%-]?%d", "flottant hexadecimal 0x1p4 (Lua 5.2+ / LuaJIT)" },
  { "[^%w_]bit%s*%.%s*tohex[^%w_]", "bit.tohex (LuaJIT, absent du client)" },
  { "[^%w_]bit%s*%.%s*rol[^%w_]", "bit.rol (LuaJIT, absent du client)" },
  { "[^%w_]bit%s*%.%s*ror[^%w_]", "bit.ror (LuaJIT, absent du client)" },
  { "[^%w_]bit%s*%.%s*bswap[^%w_]", "bit.bswap (LuaJIT, absent du client)" },
  { "[^%w_]bit%s*%.%s*tobit[^%w_]", "bit.tobit (LuaJIT, absent du client)" },
  { "[^%w_]coroutine%s*%.%s*isyieldable[^%w_]", "coroutine.isyieldable (5.3+)" },
  { "&", "operateur bit a bit & (Lua 5.3+)" },
  { "|", "operateur bit a bit | (Lua 5.3+)" },
  { "<<", "decalage << (Lua 5.3+)" },
  { ">>", "decalage >> (Lua 5.3+)" },
  { "~[^=]", "operateur ~ (Lua 5.3+)" },
  { "[^%w_]bit32[^%w_]", "bit32 (Lua 5.2) : utiliser bit" },
  { "[^%w_]utf8%s*%.", "bibliotheque utf8 (Lua 5.3+)" },
  { "[^%w_]table%s*%.%s*unpack[^%w_]", "table.unpack (5.2+) : utiliser unpack" },
  { "[^%w_]table%s*%.%s*pack[^%w_]", "table.pack (5.2+)" },
  { "[^%w_]table%s*%.%s*move[^%w_]", "table.move (5.3+)" },
  { "[^%w_]math%s*%.%s*type[^%w_]", "math.type (5.3+)" },
  { "[^%w_]string%s*%.%s*pack[^%w_]", "string.pack (5.3+)" },
  { "[^%w_]_ENV[^%w_]", "_ENV (5.2+)" },
  { "[^%w_%.:]load%s*%(", "load() : en 5.1 n'accepte qu'une fonction, utiliser loadstring" },
  { "[^%w_%.:]require%s*[%(\"']", "require absent du client" },
  { "[^%w_%.:]jit%s*%.", "jit (LuaJIT seulement)" },
  { "[^%w_]ffi[^%w_]", "ffi (LuaJIT seulement)" },
}

function M.lint51(src)
  local problems = {}
  local function lineOf(pos)
    local _, nl = src:sub(1, pos):gsub("\n", "")
    return nl + 1
  end
  local function add(pos, msg) problems[#problems + 1] = "ligne " .. lineOf(pos) .. " : " .. msg end
  local out = {}
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i, i + 1) == "--" then
      local eqs = src:match("^%-%-%[(=*)%[", i)
      local stop
      if eqs then
        local close = "]" .. eqs .. "]"
        local e = src:find(close, i + 4 + #eqs, true)
        stop = e and (e + #close - 1) or n
      else
        stop = (src:find("\n", i, true) or (n + 1)) - 1
      end
      out[#out + 1] = (src:sub(i, stop):gsub("[^\n]", " "))
      i = stop + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eqs = src:match("^%[(=*)%[", i)
      local close = "]" .. eqs .. "]"
      local e = src:find(close, i + 2 + #eqs, true)
      local stop = e and (e + #close - 1) or n
      out[#out + 1] = (src:sub(i, stop):gsub("[^\n]", " "))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          local nx = src:sub(j + 1, j + 1)
          if nx == "x" then add(j, "echappement \\x dans une chaine (Lua 5.2+ / LuaJIT)")
          elseif nx == "u" then add(j, "echappement \\u{} dans une chaine (Lua 5.3+ / LuaJIT)")
          elseif nx == "z" then add(j, "echappement \\z dans une chaine (Lua 5.2+)") end
          j = j + 2
        elseif d == c or d == "\n" then
          break
        else
          j = j + 1
        end
      end
      out[#out + 1] = (src:sub(i, j):gsub("[^\n]", " "))
      i = j + 1
    else
      local _, e = src:find("^[^%-%[\"']+", i)
      e = e or i
      out[#out + 1] = src:sub(i, e)
      i = e + 1
    end
  end
  local code = "\n" .. table.concat(out) .. "\n"
  for _, chk in ipairs(LINT_CHECKS) do
    local init = 1
    while true do
      local s, e = code:find(chk[1], init)
      if not s then break end
      add(math.max(s - 1, 1), chk[2])
      init = e
      if init <= s then init = s + 1 end
    end
  end
  return problems
end

---------------------------------------------------------------------------
-- Parsing .toc (avec annotations modernes [AllowLoadTextLocale x] etc.)
---------------------------------------------------------------------------
function M.parseToc(content)
  local toc = { meta = {}, files = {} }
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    line = trim((line:gsub("\r", "")))
    local key, value = line:match("^##%s*([^:]+):%s*(.-)$")
    if key then
      toc.meta[trim(key)] = value
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      local entry = { annotations = {} }
      for aname, aval in line:gmatch("%[(%a+)%s*([^%]]*)%]") do
        entry.annotations[aname] = trim(aval)
      end
      local path = trim((line:gsub("%[[^%]]*%]", "")))
      entry.path = (path:gsub("\\", "/"))
      toc.files[#toc.files + 1] = entry
    end
  end
  return toc
end

local function listHas(csv, value)
  for _, v in ipairs(splitList(csv)) do
    if v:lower() == value:lower() then return true end
  end
  return false
end

local function tocEntryAllowed(entry, locale)
  local a = entry.annotations
  if a.AllowLoadTextLocale and not listHas(a.AllowLoadTextLocale, locale) then return false end
  if a.AllowLoadGameType and not listHas(a.AllowLoadGameType, M.GAME_TYPE) then return false end
  if a.ExcludeLoadGameType and listHas(a.ExcludeLoadGameType, M.GAME_TYPE) then return false end
  return true
end

---------------------------------------------------------------------------
-- Parsing Bindings.xml
---------------------------------------------------------------------------
local function xmlDecode(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

function M.parseBindings(content)
  local list = {}
  content = content:gsub("<!%-%-.-%-%->", "")
  for attrs, body in content:gmatch("<Binding%s+([^>]-)>(.-)</Binding>") do
    local b = { attrs = {} }
    for k, v in attrs:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do b.attrs[k] = v end
    local cdata = body:match("<!%[CDATA%[(.-)%]%]>")
    b.body = cdata or xmlDecode(body)
    b.name = b.attrs.name
    b.runOnUp = (b.attrs.runOnUp == "true")
    list[#list + 1] = b
  end
  return list
end

---------------------------------------------------------------------------
-- Evenements connus (RegisterEvent sur un evenement inconnu leve une erreur
-- dans le client moderne). Si un evenement reel manque, l'ajouter ici.
---------------------------------------------------------------------------
M.KNOWN_EVENTS = {}
for _, ev in ipairs({
  "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
  "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "SETTINGS_LOADED",
  "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
  "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
  "MODIFIER_STATE_CHANGED", "CINEMATIC_START", "CINEMATIC_STOP",
  "PLAY_MOVIE", "STOP_MOVIE", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
  "UPDATE_INSTANCE_INFO", "LFG_UPDATE", "GROUP_ROSTER_UPDATE",
  "WORLD_MAP_OPEN", "WORLD_MAP_CLOSE", "NEW_WMO_CHUNK", "MINIMAP_UPDATE_ZOOM",
  "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP", "PLAYER_STARTED_MOVING",
  "PLAYER_STOPPED_MOVING", "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING",
  "AUTOFOLLOW_BEGIN", "AUTOFOLLOW_END",
}) do M.KNOWN_EVENTS[ev] = true end

local FRAME_TYPES = {
  Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true,
  Slider = true, StatusBar = true, GameTooltip = true, Cooldown = true, Minimap = true,
  MessageFrame = true, ScrollingMessageFrame = true, Model = true, PlayerModel = true,
}

---------------------------------------------------------------------------
-- Code FrameXML porte depuis wow-ui-source@forever (build 1.60.1.71037) :
--   Blizzard_FrameXMLUtil/FadingFrame.lua (fonctions utilisees)
--   Blizzard_FrameXML/Mainline/ZoneText.lua (SetZoneText, ZoneText_OnLoad,
--     ZoneText_OnEvent, SubZoneText_OnLoad, ZoneText_Clear) -- copie fidele
--   Blizzard_Minimap/Mainline/Minimap.lua (Minimap_Update, l. 169)
-- Execute dans l'environnement du mock : les globales sont celles du jeu.
---------------------------------------------------------------------------
local BLIZZARD_SRC = [==[
SANCTUARY_TERRITORY = "(Sanctuary)";
FREE_FOR_ALL_TERRITORY = "(Free for All PvP)";
FACTION_CONTROLLED_TERRITORY = "(%s Territory)";
CONTESTED_TERRITORY = "(Contested Territory)";
COMBAT_ZONE = "(Combat Zone)";
FONT_COLOR_CODE_CLOSE = "|r";

function FadingFrame_SetFadeInTime(fadingFrame, time) fadingFrame.fadeInTime = time; end
function FadingFrame_SetHoldTime(fadingFrame, time) fadingFrame.holdTime = time; end
function FadingFrame_SetFadeOutTime(fadingFrame, time) fadingFrame.fadeOutTime = time; end
function FadingFrame_OnLoad(fadingFrame)
	assert(fadingFrame);
	fadingFrame.fadeInTime = 0;
	fadingFrame.holdTime = 0;
	fadingFrame.fadeOutTime = 0;
	fadingFrame:Hide();
end
function FadingFrame_Show(fadingFrame)
	assert(fadingFrame);
	fadingFrame.startTime = GetTime();
	fadingFrame:Show();
end
function FadingFrame_OnUpdate(fadingFrame)
	assert(fadingFrame);
	local elapsed = GetTime() - fadingFrame.startTime;
	local fadeInTime = fadingFrame.fadeInTime;
	if ( elapsed < fadeInTime ) then
		fadingFrame:SetAlpha(elapsed / fadeInTime);
		return;
	end
	local holdTime = fadingFrame.holdTime;
	if ( elapsed < (fadeInTime + holdTime) ) then
		fadingFrame:SetAlpha(1.0);
		return;
	end
	local fadeOutTime = fadingFrame.fadeOutTime;
	if ( elapsed < (fadeInTime + holdTime + fadeOutTime) ) then
		fadingFrame:SetAlpha(1.0 - ((elapsed - holdTime - fadeInTime) / fadeOutTime));
		return;
	end
	fadingFrame:Hide();
end

ZoneFadeInDuration = 0.5;
ZoneHoldDuration = 1.0;
ZoneFadeOutDuration = 2.0;
ZonePVPType = nil;

function SetZoneText(showZone)
	local pvpType, isSubZonePvP, factionName = C_PvP.GetZonePVPInfo();
	PVPArenaTextString:SetText("");
	PVPInfoTextString:SetText("");
	local pvpTextString = PVPInfoTextString;
	if ( isSubZonePvP ) then
		pvpTextString = PVPArenaTextString;
	end

	if ( pvpType == "sanctuary" ) then
		pvpTextString:SetText(SANCTUARY_TERRITORY);
		pvpTextString:SetTextColor(0.41, 0.8, 0.94);
		ZoneTextString:SetTextColor(0.41, 0.8, 0.94);
		SubZoneTextString:SetTextColor(0.41, 0.8, 0.94);
	elseif ( pvpType == "arena" ) then
		pvpTextString:SetText(FREE_FOR_ALL_TERRITORY);
		pvpTextString:SetTextColor(1.0, 0.1, 0.1);
		ZoneTextString:SetTextColor(1.0, 0.1, 0.1);
		SubZoneTextString:SetTextColor(1.0, 0.1, 0.1);
	elseif ( pvpType == "friendly" ) then
		if (factionName and factionName ~= "") then
			pvpTextString:SetFormattedText(FACTION_CONTROLLED_TERRITORY, factionName);
			pvpTextString:SetTextColor(0.1, 1.0, 0.1);
		end
		ZoneTextString:SetTextColor(0.1, 1.0, 0.1);
		SubZoneTextString:SetTextColor(0.1, 1.0, 0.1);
	elseif ( pvpType == "hostile" ) then
		if (factionName and factionName ~= "") then
			pvpTextString:SetFormattedText(FACTION_CONTROLLED_TERRITORY, factionName);
			pvpTextString:SetTextColor(1.0, 0.1, 0.1);
		end
		ZoneTextString:SetTextColor(1.0, 0.1, 0.1);
		SubZoneTextString:SetTextColor(1.0, 0.1, 0.1);
	elseif ( pvpType == "contested" ) then
		pvpTextString:SetText(CONTESTED_TERRITORY);
		pvpTextString:SetTextColor(1.0, 0.7, 0);
		ZoneTextString:SetTextColor(1.0, 0.7, 0);
		SubZoneTextString:SetTextColor(1.0, 0.7, 0);
	elseif ( pvpType == "combat" ) then
		pvpTextString = PVPArenaTextString;
		pvpTextString:SetText(COMBAT_ZONE);
		pvpTextString:SetTextColor(1.0, 0.1, 0.1);
		ZoneTextString:SetTextColor(1.0, 0.1, 0.1);
		SubZoneTextString:SetTextColor(1.0, 0.1, 0.1);
	else
		ZoneTextString:SetTextColor(1.0, 0.9294, 0.7607);
		SubZoneTextString:SetTextColor(1.0, 0.9294, 0.7607);
	end

	if ( ZonePVPType ~= pvpType ) then
		ZonePVPType = pvpType;
	elseif ( not showZone ) then
		PVPInfoTextString:SetText("");
		SubZoneTextString:SetPoint("TOP", "ZoneTextString", "BOTTOM", 0, 0);
	end

	if ( PVPInfoTextString:GetText() == "" ) then
		SubZoneTextString:SetPoint("TOP", "ZoneTextString", "BOTTOM", 0, 0);
	else
		SubZoneTextString:SetPoint("TOP", "PVPInfoTextString", "BOTTOM", 0, 0);
	end
end

function ZoneText_OnLoad(self)
	FadingFrame_OnLoad(self);
	FadingFrame_SetFadeInTime(self, ZoneFadeInDuration);
	FadingFrame_SetHoldTime(self, ZoneHoldDuration);
	FadingFrame_SetFadeOutTime(self, ZoneFadeOutDuration);
	self:RegisterEvent("ZONE_CHANGED");
	self:RegisterEvent("ZONE_CHANGED_INDOORS");
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA");
	self.zoneText = "";
	ZonePVPType = nil;
end

function ZoneText_OnEvent(self, event, ...)
	local showZoneText = false;
	local zoneText = GetZoneText();
	if ( (zoneText ~= self.zoneText) or (event == "ZONE_CHANGED_NEW_AREA") ) then
		self.zoneText = zoneText;
		ZoneTextString:SetText( zoneText );
		showZoneText = true;
		SetZoneText( showZoneText );
		if ( not EventToastManagerFrame:IsCurrentlyToasting() ) then
			FadingFrame_Show( self );
		end
	end

	local subzoneText = GetSubZoneText();
	if ( subzoneText == "" and not showZoneText) then
		subzoneText = zoneText;
	end
	SubZoneTextString:SetText( "" );

	if ( subzoneText == zoneText ) then
		showZoneText = false;
		if ( not self:IsShown() ) then
			SubZoneTextString:SetText( subzoneText );
			SetZoneText( showZoneText );
			if ( not EventToastManagerFrame:IsCurrentlyToasting() ) then
				FadingFrame_Show( SubZoneTextFrame );
			end
		end
	else
		if (self:IsShown()) then
			showZoneText = true;
		end
		SubZoneTextString:SetText( subzoneText );
		SetZoneText( showZoneText );
		if ( not EventToastManagerFrame:IsCurrentlyToasting() ) then
			FadingFrame_Show( SubZoneTextFrame );
		end
	end
end

function SubZoneText_OnLoad(self)
	FadingFrame_OnLoad(self);
	FadingFrame_SetFadeInTime(self, ZoneFadeInDuration);
	FadingFrame_SetHoldTime(self, ZoneHoldDuration);
	FadingFrame_SetFadeOutTime(self, ZoneFadeOutDuration);
	PVPArenaTextString:SetTextColor(1.0, 0.1, 0.1);
	SetZoneText(true);
	SubZoneTextString:SetText(GetSubZoneText());
end

function ZoneText_Clear()
	ZoneTextString:SetText("");
	SubZoneTextString:SetText("");
	PVPInfoTextString:SetText("");
end

function Minimap_Update()
	MinimapZoneText:SetText(GetMinimapZoneText());
	local pvpType = C_PvP.GetZonePVPInfo();
	if ( pvpType == "sanctuary" ) then
		MinimapZoneText:SetTextColor(0.41, 0.8, 0.94);
	else
		MinimapZoneText:SetTextColor(1.0, 0.82, 0.0);
	end
end

-- MinimapClusterMixin:OnLoad (simplifie) : Minimap_Update appele PAR NOM
function MinimapCluster_OnLoad(self)
	Minimap_Update();
	self:RegisterEvent("ZONE_CHANGED");
	self:RegisterEvent("ZONE_CHANGED_INDOORS");
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA");
	self:RegisterEvent("SETTINGS_LOADED");
end
-- MinimapClusterMixin:OnEvent (Minimap.lua:405-410) ; CheckTutorials omis (sans effet ici)
function MinimapCluster_OnEvent(self, event, ...)
	if event == "SETTINGS_LOADED" then
		-- self:CheckTutorials();
	end
	Minimap_Update();
end
]==]

---------------------------------------------------------------------------
-- Creation d'un environnement
---------------------------------------------------------------------------
-- opts.locale            : valeur de GetLocale() (defaut "enUS")
-- opts.zone, opts.subzone: lieu initial
-- opts.noIsKeyDown       : retire IsKeyDown (mode "IsKeyDown absent")
-- opts.noBoundKey        : GetBindingKey renvoie nil (aucune touche liee)
-- opts.boundKey          : touche liee (defaut "F6" ; ex. "SHIFT-F6")
-- opts.worldMapPreloaded : false = carte chargee a la demande plus tard
--                          (defaut true : Blizzard_WorldMap n'est pas
--                          LoadOnDemand, donc charge AVANT l'addon)
function M.new(opts)
  opts = opts or {}
  local mock = {
    locale = opts.locale or "enUS",
    build = opts.build or { "1.60.1", "71037", "Nov 1 2026", 16001 },
    errors = {},
    printed = {},
    frames = {},
    eventRegs = {},
    hookWrappers = setmetatable({}, { __mode = "k" }),
    state = setmetatable({}, { __mode = "k" }),
    secrets = {},
    secretProxies = setmetatable({}, { __mode = "k" }),
    time = 0,
    timers = {},
    bindings = {},
    inCombat = false,
    keysDown = {},
    isKeyDownCalls = 0,
    zone = { zone = opts.zone or "Stormwind City", subzone = opts.subzone or "", minimap = nil, pvpType = nil },
    setTextCalls = 0,
    loadedAddOns = {},
    blizzardScripts = {},
  }
  local env = {}
  mock.env = env
  env._G = env

  local function st(obj) return mock.state[obj] end
  mock.st = st

  mock.errorHandler = function(err)
    mock.errors[#mock.errors + 1] = tostring(err)
  end

  local function dispatch(f, ...)
    local args = pack(...)
    local ok, err = xpcall(function() return f(unpack(args, 1, args.n)) end,
      function(e) return debug.traceback(tostring(e), 2) end)
    if not ok then mock.errorHandler(err) end
    return ok
  end
  mock.dispatch = dispatch

  -------------------------------------------------------------------------
  -- Bibliotheque standard exposee par le client (pas d'io, os, debug, require)
  -------------------------------------------------------------------------
  for _, k in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall",
    "select", "tonumber", "tostring", "unpack", "rawget", "rawset", "rawequal",
    "setmetatable", "getmetatable", "getfenv", "setfenv", "collectgarbage" }) do
    env[k] = _G[k]
  end
  -- type() : une valeur secrete garde son type apparent "string" (moteur 12.x)
  env.type = function(v)
    if mock.secretProxies[v] then return "string" end
    return type(v)
  end
  env.string = shallowcopy(string)
  env.table = shallowcopy(table)
  env.math = shallowcopy(math)
  env.coroutine = {}
  for _, k in ipairs({ "create", "resume", "running", "status", "wrap", "yield" }) do
    env.coroutine[k] = coroutine[k] -- Lua 5.1 seulement (pas d'isyieldable)
  end
  -- Le client fournit une lib "bit" restreinte : on n'expose pas les extras
  -- LuaJIT (tohex, rol, ror, bswap, tobit).
  if bit then
    env.bit = {}
    for _, k in ipairs({ "band", "bor", "bxor", "bnot", "lshift", "rshift", "arshift" }) do
      env.bit[k] = bit[k]
    end
    env.bit.mod = math.fmod
  end
  env.loadstring = function(s, name)
    local f, e = loadstring(s, name)
    if f then setfenv(f, env) end
    return f, e
  end
  env.strsub, env.strlen, env.strlower, env.strupper = string.sub, string.len, string.lower, string.upper
  env.strfind, env.strmatch, env.gsub, env.gmatch = string.find, string.match, string.gsub, string.gmatch
  env.format, env.strrep, env.strbyte, env.strchar, env.strrev = string.format, string.rep, string.byte, string.char, string.reverse
  env.tinsert, env.tremove, env.sort, env.getn = table.insert, table.remove, table.sort, table.getn
  env.abs, env.floor, env.ceil, env.max, env.min = math.abs, math.floor, math.ceil, math.max, math.min
  env.mod, env.sqrt, env.random = math.fmod, math.sqrt, math.random
  env.date, env.time = os.date, os.time
  env.debugstack = function() return debug.traceback("", 2) end
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.table.wipe = env.wipe
  env.strtrim = function(s, chars)
    if chars then
      local set = "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
      return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
    end
    return trim(s)
  end
  env.strsplit = function(delim, str, pieces)
    local out = {}
    local pattern = "[" .. delim:gsub("[%]%^%-%%]", "%%%0") .. "]"
    local start = 1
    while true do
      if pieces and #out == pieces - 1 then break end
      local s, e = str:find(pattern, start)
      if not s then break end
      out[#out + 1] = str:sub(start, s - 1)
      start = e + 1
    end
    out[#out + 1] = str:sub(start)
    return unpack(out)
  end
  env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
  env.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
  env.Mixin = function(obj, ...)
    for i = 1, select("#", ...) do
      for k, v in pairs((select(i, ...))) do obj[k] = v end
    end
    return obj
  end
  env.CreateFromMixins = function(...) return env.Mixin({}, ...) end

  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    mock.printed[#mock.printed + 1] = table.concat(t, " ")
  end

  env.geterrorhandler = function() return mock.errorHandler end
  env.seterrorhandler = function(f)
    if type(f) ~= "function" then error("Usage: seterrorhandler(errfunc)", 2) end
    mock.errorHandler = f
  end
  env.securecall = function(f, ...)
    if type(f) == "string" then f = env[f] end
    local args = pack(...)
    local r = pack(xpcall(function() return f(unpack(args, 1, args.n)) end,
      function(e) return debug.traceback(tostring(e), 2) end))
    if r[1] then return unpack(r, 2, r.n) end
    mock.errorHandler(r[2])
  end
  env.issecure = function() return false end
  env.issecurevariable = function() return false, nil end

  -------------------------------------------------------------------------
  -- Valeurs secretes (moteur 12.x, semantique exacte non confirmee).
  -- Modele : type() renvoie "string" ; toute operation interceptable en Lua
  -- 5.1 (indexation/methode, .., #, <, appel, == entre deux secrets) leve une
  -- erreur. Limite : `secret == "x"` et `t[secret]` ne sont PAS interceptables
  -- (renvoient false / nil sans erreur). D'ou la regle : issecretvalue en premier.
  -- mock.MakeSecret("x") marque une chaine PAR VALEUR (toutes ses occurrences).
  -------------------------------------------------------------------------
  -- issecretvalue est documente `SecretArguments = "AllowedWhenUntainted"` :
  -- appele par du code tainte avec un secret, il pourrait lever une erreur.
  -- Regle (PLAN.md) : l'appeler via pcall, une erreur compte comme "secret".
  -- opts.issecretErrors = "secret" (erreur si l'argument est secret) ou
  -- "always" (erreur a chaque appel) pour exercer cette regle.
  mock.checkedSecrets = setmetatable({}, { __mode = "k" })
  local function isSecret(v)
    if type(v) == "string" then return mock.secrets[v] == true end
    return mock.secretProxies[v] == true
  end
  mock.isSecret = isSecret
  env.issecretvalue = function(v)
    mock.issecretCalls = (mock.issecretCalls or 0) + 1
    local secret = isSecret(v)
    if secret then mock.checkedSecrets[v] = true end
    if opts.issecretErrors == "always" or (opts.issecretErrors == "secret" and secret) then
      error("issecretvalue: secret argument not allowed from tainted code", 2)
    end
    return secret
  end
  -- opts.noIssecretvalue : client sans valeurs secretes (fonction absente) ;
  -- aucune valeur n'est alors secrete et la traduction doit fonctionner.
  if opts.noIssecretvalue then env.issecretvalue = nil end
  -- rawget surveille aussi les dictionnaires gardes (voir M.guardDictionaries)
  mock.guardedDicts = setmetatable({}, { __mode = "k" })
  env.rawget = function(t, k)
    if mock.guardedDicts[t] and isSecret(k) then
      mock.secretIndexed = (mock.secretIndexed or 0) + 1
      error("dictionnaire WT.data lu (rawget) avec une valeur secrete (issecretvalue doit etre teste AVANT)", 2)
    end
    return rawget(t, k)
  end
  function mock.MakeSecret(s) mock.secrets[s] = true; return s end
  -- Une seule fonction partagee : en Lua 5.1, __eq n'est appele que si les deux
  -- operandes ont le MEME metamethode.
  local function boom() error("attempt to perform an operation on a secret value", 2) end
  local function secretToString() return "<secret>" end
  function mock.NewSecretProxy()
    local p = newproxy(true)
    local mt = getmetatable(p)
    mt.__index = boom; mt.__newindex = boom; mt.__concat = boom; mt.__len = boom
    mt.__eq = boom; mt.__lt = boom; mt.__le = boom; mt.__call = boom
    mt.__tostring = secretToString
    mock.secretProxies[p] = true
    return p
  end

  -------------------------------------------------------------------------
  -- API diverses
  -------------------------------------------------------------------------
  env.GetLocale = function() return mock.locale end
  env.GetBuildInfo = function() return unpack(mock.build) end
  env.GetTime = function() return mock.time end
  env.InCombatLockdown = function() return mock.inCombat end
  -- Touches liees : GetBindingKey renvoie jusqu'a DEUX touches.
  -- opts.boundKeys = { "F6", "BUTTON4" } (ou opts.boundKey = "SHIFT-F6").
  -- La touche physique est la touche de base, sans modificateur :
  -- "SHIFT-F6" -> "F6", "CTRL-SHIFT-F6" -> "F6", "SHIFT--" -> "-", "-" -> "-".
  mock.boundKeys = opts.boundKeys or { opts.boundKey or M.BOUND_KEY }
  if opts.noBoundKey then mock.boundKeys = {} end
  mock.baseKeys = {}
  for i, k in ipairs(mock.boundKeys) do mock.baseKeys[i] = M.baseKey(k) end
  mock.boundKey, mock.baseKey = mock.boundKeys[1], mock.baseKeys[1]
  env.GetBindingKey = function(command)
    if command == "WOWTRANSLATOR_HOLD" then return mock.boundKeys[1], mock.boundKeys[2] end
    return nil
  end
  -- IsKeyDown(key [, excludeBindingState]) existe en Forever (AngleurForever.lua,
  -- qui interroge la touche de BASE). Avec un modificateur ("SHIFT-F6") le
  -- comportement n'est pas confirme : le mock renvoie nil (pessimiste), ce qui
  -- impose de retirer les modificateurs avant l'appel. opts.noIsKeyDown retire
  -- la fonction (mode degrade).
  if not opts.noIsKeyDown then
    env.IsKeyDown = function(key)
      mock.isKeyDownCalls = mock.isKeyDownCalls + 1
      if type(key) ~= "string" then return nil end
      if opts.isKeyDownUnknown then return nil end -- etat inconnu
      if opts.unknownKeys and opts.unknownKeys[key] then return nil end
      if key:find("^%u+%-.") then return nil end
      return mock.keysDown[key] == true
    end
  end
  -- C_Timer : After, NewTimer, NewTicker (objets :Cancel() / :IsCancelled(),
  -- le callback recoit l'objet). Pilote par mock.Tick : au plus un declenchement
  -- par timer et par Tick (comme une frame).
  local TimerHandle = {}
  TimerHandle.__index = TimerHandle
  function TimerHandle:Cancel() self._cancelled = true end
  function TimerHandle:IsCancelled() return self._cancelled == true end
  local function addTimer(delay, cb, interval, iterations, usage)
    if type(delay) ~= "number" or type(cb) ~= "function" then error(usage, 3) end
    local h = setmetatable({}, TimerHandle)
    mock.timers[#mock.timers + 1] = { at = mock.time + delay, cb = cb, interval = interval,
      remaining = iterations, handle = h }
    return h
  end
  env.C_Timer = {
    After = function(delay, cb)
      addTimer(delay, cb, nil, 1, "Usage: C_Timer.After(seconds, callback)")
    end,
    NewTimer = function(delay, cb)
      local h = addTimer(delay, cb, nil, 1, "Usage: C_Timer.NewTimer(seconds, callback)")
      mock.timers[#mock.timers].isHandleCallback = true
      return h
    end,
    NewTicker = function(interval, cb, iterations)
      return addTimer(interval, cb, interval, iterations, "Usage: C_Timer.NewTicker(seconds, callback [, iterations])")
    end,
  }
  env.C_AddOns = {
    IsAddOnLoaded = function(name) return mock.loadedAddOns[name] == true, mock.loadedAddOns[name] == true end,
    IsAddOnLoadOnDemand = function() return false end,
    LoadAddOn = function(name)
      if name == "Blizzard_WorldMap" then mock.LoadBlizzardWorldMap(); return true end
      return false, "MISSING"
    end,
  }
  env.C_PvP = { GetZonePVPInfo = function() return mock.zone.pvpType, false, nil end }
  env.SlashCmdList = {}

  env.GetZoneText = function() return mock.zone.zone end
  env.GetRealZoneText = function() return mock.zone.zone end
  env.GetSubZoneText = function() return mock.zone.subzone end
  env.GetAreaText = function() return mock.zone.zone end
  env.GetMinimapZoneText = function()
    local z = mock.zone
    if z.minimap then return z.minimap end
    if z.subzone ~= "" then return z.subzone end
    return z.zone
  end
  env.IsInInstance = function() return false, "none" end

  -------------------------------------------------------------------------
  -- Objets d'interface
  -------------------------------------------------------------------------
  local Methods = {}
  mock.methods = Methods

  local R = {}
  function R:GetName() return st(self).name end
  function R:GetParent() return st(self).parent end
  function R:GetObjectType() return st(self).kind end
  function R:IsObjectType(t)
    local k = st(self).kind
    if t == k or t == "Region" or t == "UIObject" or t == "ScriptObject" then return true end
    if t == "Frame" and FRAME_TYPES[k] then return true end
    return false
  end
  function R:IsForbidden() return false end
  function R:IsShown() return st(self).shown end
  function R:IsVisible()
    local s = st(self)
    while s do
      if not s.shown then return false end
      if not s.parent then return true end
      s = st(s.parent)
    end
    return true
  end
  function R:Show()
    local s = st(self)
    if not s.shown then
      s.shown = true
      if s.scripts and s.scripts.OnShow then dispatch(s.scripts.OnShow, self) end
    end
  end
  function R:Hide()
    local s = st(self)
    if s.shown then
      s.shown = false
      if s.scripts and s.scripts.OnHide then dispatch(s.scripts.OnHide, self) end
    end
  end
  function R:SetShown(v) if v then self:Show() else self:Hide() end end
  function R:SetParent(p) st(self).parent = p end
  function R:SetAlpha(a) st(self).alpha = a end
  function R:GetAlpha() return st(self).alpha end
  function R:SetWidth(w) st(self).width = w end
  function R:SetHeight(h) st(self).height = h end
  function R:SetSize(w, h) st(self).width = w; st(self).height = h end
  function R:GetWidth() return st(self).width end
  function R:GetHeight() return st(self).height end
  function R:GetSize() return st(self).width, st(self).height end
  for _, noop in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata",
    "SetFrameLevel", "EnableMouse", "EnableKeyboard", "SetMovable", "SetClampedToScreen",
    "SetDrawLayer", "SetIgnoreParentAlpha", "SetScale", "SetVertexColor" }) do
    R[noop] = function() end
  end

  local FS = shallowcopy(R)
  function FS:SetText(text)
    local t = type(text)
    if t == "number" then
      text = tostring(text)
    elseif t ~= "string" and t ~= "nil" and not mock.secretProxies[text] then
      error("Usage: " .. (st(self).name or "FontString") .. ":SetText([text])", 2)
    end
    local s = st(self)
    s.text = text
    s.setTextCount = s.setTextCount + 1
    if mock.isSecret(text) then s.secretSetCount = (s.secretSetCount or 0) + 1 end
    mock.setTextCalls = mock.setTextCalls + 1
  end
  -- SimpleFontStringAPIDocumentation : GetText -> cstring, Nilable = false
  function FS:GetText()
    local t = st(self).text
    if t == nil then return "" end
    return t
  end
  -- Fonction C distincte : ne passe PAS par SetText (un hook sur SetText ne la voit pas)
  function FS:SetFormattedText(fmt, ...)
    st(self).text = string.format(fmt, ...)
  end
  function FS:SetTextColor(r, g, b, a) st(self).color = { r, g, b, a } end
  function FS:GetTextColor() local c = st(self).color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
  function FS:SetFont(f, size, flags) st(self).font = { f, size, flags }; return true end
  function FS:GetFont() local f = st(self).font or { "Fonts\\FRIZQT__.TTF", 12, "" }; return f[1], f[2], f[3] end
  function FS:SetFontObject(o) st(self).fontObject = o end
  function FS:GetFontObject() return st(self).fontObject end
  function FS:GetStringWidth() local t = st(self).text; return type(t) == "string" and #t * 6 or 0 end
  for _, noop in ipairs({ "SetJustifyH", "SetJustifyV", "SetNonSpaceWrap", "SetWordWrap",
    "SetShadowColor", "SetShadowOffset", "SetMaxLines" }) do
    FS[noop] = function() end
  end
  Methods.FontString = FS

  local TX = shallowcopy(R)
  for _, noop in ipairs({ "SetTexture", "SetTexCoord", "SetAtlas", "SetColorTexture" }) do
    TX[noop] = function() end
  end
  Methods.Texture = TX

  local F = shallowcopy(R)
  local function newObject(kind, methods, name, parent)
    local obj = setmetatable({}, { __index = methods })
    if type(name) == "string" and parent and name:find("$parent", 1, true) then
      name = name:gsub("%$parent", st(parent).name or "")
    end
    mock.state[obj] = { kind = kind, name = name, parent = parent, shown = true, scripts = {},
      events = {}, alpha = 1, width = 0, height = 0, setTextCount = 0 }
    if type(name) == "string" then env[name] = obj end
    return obj
  end

  function F:SetScript(handler, fn)
    if type(handler) ~= "string" or (fn ~= nil and type(fn) ~= "function") then
      error("Usage: " .. (st(self).name or "Frame") .. ":SetScript(\"type\", function)", 2)
    end
    st(self).scripts[handler] = fn
  end
  function F:GetScript(handler) return st(self).scripts[handler] end
  function F:HookScript(handler, fn)
    local s = st(self)
    local orig = s.scripts[handler]
    if orig then
      local wrapper = function(...)
        local r = pack(orig(...))
        fn(...)
        return unpack(r, 1, r.n)
      end
      mock.hookWrappers[wrapper] = { orig = orig, hook = fn }
      s.scripts[handler] = wrapper
    else
      s.scripts[handler] = fn
    end
  end
  function F:RegisterEvent(ev)
    if type(ev) ~= "string" then error("Usage: frame:RegisterEvent(\"event\")", 2) end
    if not M.KNOWN_EVENTS[ev] then
      error("Attempt to register unknown event \"" .. ev .. "\" (si l'evenement existe, l'ajouter a M.KNOWN_EVENTS dans tests/wow_mock.lua)", 2)
    end
    local s = st(self)
    if not s.events[ev] then
      s.events[ev] = true
      local list = mock.eventRegs[ev] or {}
      mock.eventRegs[ev] = list
      list[#list + 1] = self
    end
    return true
  end
  function F:UnregisterEvent(ev)
    local s = st(self)
    if s.events[ev] then
      s.events[ev] = nil
      local list = mock.eventRegs[ev]
      for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
    end
  end
  function F:UnregisterAllEvents()
    local evs = {}
    for ev in pairs(st(self).events) do evs[#evs + 1] = ev end
    for _, ev in ipairs(evs) do self:UnregisterEvent(ev) end
  end
  function F:IsEventRegistered(ev) return st(self).events[ev] == true end
  function F:CreateFontString(name)
    local fs = newObject("FontString", FS, name, self)
    local s = st(self)
    s.regions = s.regions or {}
    s.regions[#s.regions + 1] = fs
    return fs
  end
  function F:GetRegions() return unpack(st(self).regions or {}) end
  function F:CreateTexture(name) return newObject("Texture", TX, name, self) end
  Methods.Frame = F

  env.CreateFrame = function(ftype, name, parent)
    if type(ftype) ~= "string" then
      error("Usage: CreateFrame(\"frameType\" [, \"name\"] [, parent] [, \"template\"])", 2)
    end
    if not FRAME_TYPES[ftype] then error("CreateFrame: Unknown frame type '" .. ftype .. "'", 2) end
    local f = newObject(ftype, F, name, parent)
    mock.frames[#mock.frames + 1] = f
    return f
  end

  -------------------------------------------------------------------------
  -- hooksecurefunc : post-hook. Original d'abord, puis le hook avec les memes
  -- arguments ; retours de l'original preserves ; erreur du hook propagee.
  -------------------------------------------------------------------------
  env.hooksecurefunc = function(a, b, c)
    local tbl, name, hook
    if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = env, a, b end
    if type(name) ~= "string" or type(hook) ~= "function" then
      error("Usage: hooksecurefunc([table,] \"functionName\", hookfunc)", 2)
    end
    local orig = tbl[name]
    if type(orig) ~= "function" then
      error("hooksecurefunc(): " .. name .. " is not a function", 2)
    end
    local wrapper = function(...)
      local r = pack(orig(...))
      hook(...)
      return unpack(r, 1, r.n)
    end
    mock.hookWrappers[wrapper] = { orig = orig, hook = hook }
    tbl[name] = wrapper
  end
  function mock.isHookWrapper(fn) return mock.hookWrappers[fn] ~= nil end
  -- fn est-il `orig`, ou une chaine de hooks (hooksecurefunc/HookScript) qui y remonte ?
  function mock.derivesFrom(fn, orig)
    local cur, guard = fn, 0
    while cur ~= orig and mock.hookWrappers[cur] and guard < 100 do
      cur = mock.hookWrappers[cur].orig
      guard = guard + 1
    end
    return cur == orig
  end

  -------------------------------------------------------------------------
  -- Evenements et temps
  -------------------------------------------------------------------------
  function mock.FireEvent(ev, ...)
    local list = mock.eventRegs[ev]
    if not list then return end
    local copy = {}
    for i, f in ipairs(list) do copy[i] = f end
    for _, f in ipairs(copy) do
      local s = st(f)
      if s.events[ev] and s.scripts.OnEvent then dispatch(s.scripts.OnEvent, f, ev, ...) end
    end
  end

  -- Avance le temps : OnUpdate des frames visibles, puis timers C_Timer
  function mock.Tick(elapsed)
    elapsed = elapsed or 0.1
    mock.time = mock.time + elapsed
    local frames = {}
    for i, f in ipairs(mock.frames) do frames[i] = f end
    for _, f in ipairs(frames) do
      local s = st(f)
      if s.scripts.OnUpdate and f:IsVisible() then dispatch(s.scripts.OnUpdate, f, elapsed) end
    end
    local due, rest = {}, {}
    for _, t in ipairs(mock.timers) do
      if t.handle._cancelled then
        -- annule : retire
      elseif t.at <= mock.time + 1e-9 then
        due[#due + 1] = t
      else
        rest[#rest + 1] = t
      end
    end
    mock.timers = rest
    for _, t in ipairs(due) do
      if not t.handle._cancelled then
        if t.interval or t.isHandleCallback then
          dispatch(t.cb, t.handle)
        else
          dispatch(t.cb)
        end
        if t.remaining then t.remaining = t.remaining - 1 end
        if t.interval and not t.handle._cancelled and (t.remaining == nil or t.remaining > 0) then
          t.at = t.at + t.interval
          if t.at <= mock.time then t.at = mock.time + t.interval end
          mock.timers[#mock.timers + 1] = t
        end
      end
    end
  end
  -- Laisse passer `seconds` secondes par pas de `step`
  function mock.Wait(seconds, step)
    step = step or 0.1
    local n = math.floor(seconds / step + 0.5)
    for _ = 1, n do mock.Tick(step) end
  end

  -------------------------------------------------------------------------
  -- UI Blizzard (Mainline / camelot)
  -------------------------------------------------------------------------
  local CF = env.CreateFrame
  local UIParent = CF("Frame", "UIParent")
  CF("Frame", "WorldFrame")
  local toast = CF("Frame", "EventToastManagerFrame", UIParent)
  function toast:IsCurrentlyToasting() return false end

  -- Code FrameXML porte (definit les fonctions globales)
  do
    local chunk = assert(loadstring(BLIZZARD_SRC, "=FrameXML(mock)"))
    setfenv(chunk, env)
    chunk()
  end

  -- Lie un script comme le fait XML `<OnX function="Nom"/>` : par REFERENCE,
  -- resolue maintenant ; un hook ulterieur de la globale n'a aucun effet.
  local function bindXmlScript(frame, handler, globalName)
    local fn = env[globalName]
    frame:SetScript(handler, fn)
    mock.blizzardScripts[#mock.blizzardScripts + 1] = { frame = frame, handler = handler, fn = fn, name = globalName }
  end

  -- ZoneText.xml
  local ztf = CF("Frame", "ZoneTextFrame", UIParent)
  ztf:CreateFontString("ZoneTextString", "OVERLAY")
  ztf:CreateFontString("PVPInfoTextString", "OVERLAY")
  bindXmlScript(ztf, "OnEvent", "ZoneText_OnEvent")
  bindXmlScript(ztf, "OnUpdate", "FadingFrame_OnUpdate")
  local sztf = CF("Frame", "SubZoneTextFrame", UIParent)
  sztf:CreateFontString("SubZoneTextString", "OVERLAY")
  sztf:CreateFontString("PVPArenaTextString", "OVERLAY")
  bindXmlScript(sztf, "OnUpdate", "FadingFrame_OnUpdate")

  -- Minimap (MinimapCluster.ZoneTextButton, MinimapZoneText global ; pas de
  -- MinimapZoneTextButton global dans ce build)
  local cluster = CF("Frame", "MinimapCluster", UIParent)
  CF("Minimap", "Minimap", cluster)
  local ztb = CF("Button", nil, cluster)
  cluster.ZoneTextButton = ztb
  ztb:CreateFontString("MinimapZoneText", "OVERLAY")
  bindXmlScript(cluster, "OnEvent", "MinimapCluster_OnEvent")

  -- OnLoad (avant tout addon), dans l'ordre du XML
  env.ZoneText_OnLoad(ztf)
  env.SubZoneText_OnLoad(sztf)
  env.MinimapCluster_OnLoad(cluster)

  -- GameTooltip minimal
  local tip = CF("GameTooltip", "GameTooltip", UIParent)
  tip:Hide()
  tip.lines = {}
  function tip:SetOwner(owner) self.owner = owner; env.wipe(self.lines) end
  function tip:AddLine(text) self.lines[#self.lines + 1] = text end
  function tip:SetText(text) env.wipe(self.lines); self.lines[1] = text end
  function tip:ClearLines() env.wipe(self.lines) end
  function tip:NumLines() return #self.lines end
  function tip:GetOwner() return self.owner end

  local chat = CF("Frame", "ChatFrame1", UIParent)
  function chat:AddMessage(msg) mock.printed[#mock.printed + 1] = tostring(msg) end
  env.DEFAULT_CHAT_FRAME = chat

  -- Carte du monde (Blizzard_WorldMap, PAS LoadOnDemand d'apres
  -- Blizzard_WorldMap_Mainline.toc@forever : chargee au demarrage, avant
  -- l'addon). Libelle de survol = provider.Label.Name (AreaLabelDataProvider).
  function mock.LoadBlizzardWorldMap()
    if mock.loadedAddOns.Blizzard_WorldMap then return end
    local wm = CF("Frame", "WorldMapFrame", UIParent)
    wm:Hide()
    wm.BorderFrame = CF("Frame", nil, wm)
    wm.BorderFrame.TitleText = wm.BorderFrame:CreateFontString(nil)
    function wm.BorderFrame:SetTitle(t) self.TitleText:SetText(t) end
    wm.BorderFrame:SetTitle("World Map")
    local provider = {}
    provider.Label = CF("Frame", nil, wm)
    provider.Label.Name = provider.Label:CreateFontString(nil)
    provider.Label.Description = provider.Label:CreateFontString(nil)
    wm.dataProviders = { [provider] = true }
    mock.worldMapAreaLabel = provider.Label.Name
    wm.NavBar = CF("Frame", nil, wm)
    wm.NavBar.buttons = {}
    function wm.NavBar:Refresh() end
    env.NavBar_AddButton = function(self, info)
      local b = CF("Button", nil, self)
      b.text = b:CreateFontString(nil)
      b.text:SetText(info and info.name)
      self.buttons[#self.buttons + 1] = b
      return b
    end
    mock.loadedAddOns.Blizzard_WorldMap = true
    mock.FireEvent("ADDON_LOADED", "Blizzard_WorldMap")
  end

  -- Imite AreaLabelFrameMixin (AreaLabelDataProvider.lua@forever) :
  --  survol avec niveaux -> name..color.." ("..min.."-"..max..")"..FONT_COLOR_CODE_CLOSE
  --  un seul niveau      -> name..color.." ("..max..")"..FONT_COLOR_CODE_CLOSE
  --  rien sous la souris -> ClearAllLabels : Name:SetText("")
  function mock.FormatAreaLabel(name, minLevel, maxLevel, colorCode)
    if not minLevel then return name end
    colorCode = colorCode or "|cff40c040"
    if minLevel ~= maxLevel then
      return name .. colorCode .. " (" .. minLevel .. "-" .. maxLevel .. ")" .. "|r"
    end
    return name .. colorCode .. " (" .. maxLevel .. ")" .. "|r"
  end
  function mock.WorldMapHover(name, minLevel, maxLevel, colorCode)
    local label = mock.worldMapAreaLabel
    if name == nil then
      label:SetText("")
    else
      label:SetText(mock.FormatAreaLabel(name, minLevel, maxLevel, colorCode))
    end
  end

  if opts.worldMapPreloaded ~= false then mock.LoadBlizzardWorldMap() end

  -------------------------------------------------------------------------
  -- Scenarios
  -------------------------------------------------------------------------
  function mock.SetZone(zone, subzone, minimap)
    local newArea = (zone ~= mock.zone.zone)
    mock.zone = { zone = zone, subzone = subzone or "", minimap = minimap, pvpType = mock.zone.pvpType }
    if newArea then mock.FireEvent("ZONE_CHANGED_NEW_AREA") else mock.FireEvent("ZONE_CHANGED") end
  end

  function mock.LoadingScreen(zone, subzone)
    mock.FireEvent("PLAYER_LEAVING_WORLD")
    mock.FireEvent("LOADING_SCREEN_ENABLED")
    mock.zone = { zone = zone, subzone = subzone or "", pvpType = mock.zone.pvpType }
    mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    mock.FireEvent("ZONE_CHANGED_NEW_AREA")
    mock.FireEvent("LOADING_SCREEN_DISABLED")
  end

  -- Raccourci clavier : execute le corps du <Binding> comme le client.
  -- keystate "up" n'est transmis que si runOnUp="true".
  function mock.PressBinding(keystate, name)
    local b
    for _, x in ipairs(mock.bindings) do
      if (name and x.name == name) or (not name and x.runOnUp) then b = x; break end
    end
    if not b and not name then b = mock.bindings[1] end
    if not b then
      M.missing("Bindings.xml : aucun <Binding" .. (name and (" name=\"" .. name .. "\"") or "") .. "> trouve")
    end
    if not b.fn then return false end
    if keystate == "up" and not b.runOnUp then return false end
    return dispatch(b.fn, keystate)
  end
  -- KeyDown(i) / KeyUp(i) : enfonce / relache la i-eme touche liee (defaut 1)
  -- et execute le binding. Sans touche liee, seul le binding est execute.
  function mock.KeyDown(i)
    local k = mock.baseKeys[i or 1]
    if k then mock.keysDown[k] = true end
    return mock.PressBinding("down", "WOWTRANSLATOR_HOLD")
  end
  function mock.KeyUp(i)
    local k = mock.baseKeys[i or 1]
    if k then mock.keysDown[k] = false end
    return mock.PressBinding("up", "WOWTRANSLATOR_HOLD")
  end
  -- Relachement physique dont le client n'envoie pas le "up" (perte de focus,
  -- champ de saisie...) : touche(s) relachee(s), le binding ne tourne pas.
  -- Sans argument : toutes les touches.
  function mock.LoseKeyUp(i)
    if i then
      mock.keysDown[mock.baseKeys[i]] = false
    else
      for _, k in ipairs(mock.baseKeys) do mock.keysDown[k] = false end
    end
  end

  function mock.RunSlash(line)
    local cmd, rest = line:match("^(/%S+)%s*(.-)%s*$")
    if not cmd then return false end
    cmd = cmd:lower()
    for key, handler in pairs(env.SlashCmdList) do
      local i = 1
      while env["SLASH_" .. key .. i] do
        if tostring(env["SLASH_" .. key .. i]):lower() == cmd then
          dispatch(handler, rest, nil)
          return true
        end
        i = i + 1
      end
    end
    return false
  end

  -- Deconnexion / /reload : PLAYER_LEAVING_WORLD puis PLAYER_LOGOUT, puis
  -- ecriture des SavedVariables (serialisation filtree comme le client).
  -- Renvoie la table a passer a `saved` au demarrage suivant.
  function mock.Logout()
    mock.FireEvent("PLAYER_LEAVING_WORLD")
    mock.FireEvent("PLAYER_LOGOUT")
    local out = {}
    for _, n in ipairs(mock.savedVarNames or {}) do out[n] = serializeSV(env[n]) end
    return out
  end
  mock.Reload = mock.Logout

  mock.baseline = {}
  for k, v in pairs(env) do mock.baseline[k] = v end
  mock.originals = { FontStringSetText = FS.SetText }

  return mock
end

---------------------------------------------------------------------------
-- Chargeur d'addon
---------------------------------------------------------------------------
local function loadLuaFile(mock, path, display)
  local src = readFile(path)
  if not src then M.missing(display .. " introuvable (liste dans le .toc)") end
  mock.luaSources = mock.luaSources or {}
  mock.luaSources[#mock.luaSources + 1] = { display = display, src = src }
  local chunk, err = loadstring(src, "@" .. display)
  if not chunk then
    mock.errorHandler(err)
    return
  end
  setfenv(chunk, mock.env)
  mock.dispatch(chunk, mock.addonName, mock.ns)
end
M.loadLuaFile = loadLuaFile

local loadXmlFile
loadXmlFile = function(mock, path, display)
  local src = readFile(path)
  if not src then M.missing(display .. " introuvable (liste dans le .toc)") end
  local dir = path:match("^(.*)/[^/]*$") or "."
  local ddir = display:match("^(.*)/[^/]*$") or "."
  for tag, file in src:gmatch("<(%a+)%s+file%s*=%s*\"([^\"]+)\"") do
    file = file:gsub("\\", "/")
    if tag == "Script" then
      loadLuaFile(mock, dir .. "/" .. file, ddir .. "/" .. file)
    elseif tag == "Include" then
      loadXmlFile(mock, dir .. "/" .. file, ddir .. "/" .. file)
    end
  end
end

-- Regle "issecretvalue en PREMIER" (PLAN.md) : les dictionnaires WT.data.*
-- recoivent un __index qui leve une erreur si on y cherche une valeur secrete
-- (chaine marquee par MakeSecret et absente du dictionnaire, ou proxy opaque).
-- Une implementation correcte n'indexe jamais avec un secret. pairs() et les
-- cles presentes ne sont pas affectes. Limite : `secret == "x"` reste
-- non detectable en Lua 5.1.
function M.guardDictionaries(mock)
  local data = mock.ns and rawget(mock.ns, "data")
  if type(data) ~= "table" then return end
  for _, dict in pairs(data) do
    if type(dict) == "table" and getmetatable(dict) == nil then
      mock.guardedDicts[dict] = true
      setmetatable(dict, { __index = function(_, key)
        if mock.isSecret(key) then
          mock.secretIndexed = (mock.secretIndexed or 0) + 1
          error("dictionnaire WT.data indexe avec une valeur secrete (issecretvalue doit etre teste AVANT)", 2)
        end
        return nil
      end })
    end
  end
end

local function applySaved(mock, saved)
  if not saved then return end
  for _, n in ipairs(mock.savedVarNames) do
    if saved[n] ~= nil then mock.env[n] = deepcopy(saved[n]) end
  end
end

-- opts.addonDir, opts.addonName : addon a charger (defaut WoWTranslator)
-- opts.fixtures : fichiers qui remplacent les entrees Data/ du .toc
-- opts.fixturesAt : nil (a la place de Data/), "first" ou "last"
-- opts.saved    : SavedVariables de la session precedente (cf. mock.Logout)
function M.loadAddon(mock, opts)
  opts = opts or {}
  local name = opts.addonName or M.ADDON_NAME
  local dir = opts.addonDir or M.addonDir()
  local tocSrc = readFile(dir .. "/" .. name .. ".toc")
  if not tocSrc then
    M.missing(name .. "/" .. name .. ".toc introuvable (l'addon n'est pas encore ecrit ?)")
  end
  local toc = M.parseToc(tocSrc)
  mock.toc = toc
  mock.addonName = name
  mock.addonDir = dir
  mock.ns = mock.ns or {}
  mock.savedVarNames = splitList(toc.meta.SavedVariables)
  for _, n in ipairs(splitList(toc.meta.SavedVariablesPerCharacter)) do
    mock.savedVarNames[#mock.savedVarNames + 1] = n
  end

  local fixtureFiles = {}
  for _, fx in ipairs(opts.fixtures or {}) do
    fixtureFiles[#fixtureFiles + 1] = { path = fx, display = "tests/fixtures/" .. (fx:match("([^/\\]+)$") or fx) }
  end
  local files, inserted = {}, false
  if opts.fixtures and opts.fixturesAt == "first" then
    for _, f in ipairs(fixtureFiles) do files[#files + 1] = f end
    inserted = true
  end
  for _, entry in ipairs(toc.files) do
    if tocEntryAllowed(entry, mock.locale) then
      if opts.fixtures and entry.path:lower():match("^data/") then
        if not inserted and opts.fixturesAt == nil then
          for _, f in ipairs(fixtureFiles) do files[#files + 1] = f end
          inserted = true
        end
      else
        files[#files + 1] = { path = dir .. "/" .. entry.path, display = name .. "/" .. entry.path }
      end
    end
  end
  if opts.fixtures and not inserted then
    for _, f in ipairs(fixtureFiles) do files[#files + 1] = f end
  end
  for _, f in ipairs(files) do
    if not M.fileExists(f.path) then M.missing(f.display .. " introuvable (liste dans le .toc)") end
  end

  local svFirst = toc.meta.LoadSavedVariablesFirst == "1"
  if svFirst then applySaved(mock, opts.saved) end
  for _, f in ipairs(files) do
    if f.path:lower():match("%.xml$") then loadXmlFile(mock, f.path, f.display)
    else loadLuaFile(mock, f.path, f.display) end
  end

  mock.bindings = {}
  local bsrc = readFile(dir .. "/Bindings.xml")
  if bsrc then
    for _, b in ipairs(M.parseBindings(bsrc)) do
      local fn, err = loadstring("return function(keystate) " .. b.body .. "\nend",
        "=" .. name .. "/Bindings.xml:" .. tostring(b.name))
      if fn then
        setfenv(fn, mock.env)
        b.fn = fn()
      else
        mock.errorHandler(err)
      end
      mock.bindings[#mock.bindings + 1] = b
    end
  end

  if not svFirst then applySaved(mock, opts.saved) end
  M.guardDictionaries(mock)
  mock.loadedAddOns[name] = true
  mock.FireEvent("ADDON_LOADED", name)
  return mock
end

function M.loadFile(mock, path, display, addonName, ns)
  mock.addonName = addonName or mock.addonName or M.ADDON_NAME
  mock.ns = ns or mock.ns or {}
  loadLuaFile(mock, path, display or path)
  return mock.ns
end

function M.login(mock)
  mock.FireEvent("VARIABLES_LOADED")
  mock.FireEvent("PLAYER_LOGIN")
  mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  mock.FireEvent("ZONE_CHANGED_NEW_AREA")
end

-- Demarrage complet. opts : ceux de M.new, plus fixtures (true par defaut,
-- false = vraies donnees Data/), fixturesAt, saved, noLogin
function M.boot(opts)
  opts = opts or {}
  local mock = M.new(opts)
  local fixtures = opts.fixtures
  if fixtures == nil or fixtures == true then
    fixtures = { M.fixturesDir() .. "/Zones_enUS_frFR.lua", M.fixturesDir() .. "/Zones_frFR_enUS.lua" }
  elseif fixtures == false then
    fixtures = nil
  end
  M.loadAddon(mock, { fixtures = fixtures, fixturesAt = opts.fixturesAt, saved = opts.saved })
  if not opts.noLogin then M.login(mock) end
  mock.WT = mock.env[M.GLOBAL_NAME]
  return mock
end

return M
