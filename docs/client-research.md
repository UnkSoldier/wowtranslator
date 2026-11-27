# Recherche client — WoW: Forever (T0)

Date de la recherche : 2026-11-20. Révision 3 : corrections des revues 01 (A1–A9) et 02 (A10–A12), alignement sur PLAN (contrat `WT.SetActive`, fil d'Ariane hors v1, T6 bloqué). Accès au dossier du jeu en **lecture seule** : rien n'a été créé, modifié ni lancé.

Légende :
- **confirmé** : vu sur disque, ou dans le code source officiel de l'UI de ce build précis (source indiquée, avec fichier et ligne quand c'est utile) ;
- **non confirmé** : déduction, à vérifier en jeu avec la commande donnée au §8.

Abréviation : **ws@forever** = dépôt public `Gethe/wow-ui-source`, branche `forever`. Son dernier commit est « 1.60.1 (71037) », soit exactement le build installé. Ce dépôt a été lu en lecture seule via `gh api repos/Gethe/wow-ui-source/contents/<chemin>?ref=forever`, et rien n'a été installé. Les numéros de ligne cités sont ceux de ce dépôt.

## État de T0 : **PARTIEL**

Le critère de PLAN (« T2 à T6 n'ont plus rien à deviner ») n'est atteint que pour T2, T4 et T5. Restent ouverts :
1. **T6** : la présence en jeu de `RaidInfoFrame`, du Group Finder « Vanilla » et l'absence d'`EncounterJournal` ne sont pas vérifiées. T6 ne doit coder que les cibles confirmées par les tests 6 et 7 du §8.
2. **Perte de focus** : aucun événement de perte de focus clavier ou fenêtre n'a été trouvé (voir §6.3). La décision de PLAN (sondage `IsKeyDown` tant que l'addon est actif) est retenue. Le comportement d'`IsKeyDown` avec une touche à modificateur reste à vérifier (test 8).
3. **Vérifications en jeu** : les tests 1 à 11 du §8 n'ont pas encore été faits par l'utilisateur.
4. **Chargement de la carte** : la carte est probablement présente dès le démarrage (§5.3). C'est à confirmer par le test 5, mais T5 peut gérer les deux cas sans attendre le résultat.
5. **`issecretvalue` appelé par du code tainté** : sa documentation (`AllowedWhenUntainted`) laisse un doute (§5.6), que le test 4 tranchera. En attendant, l'appel est protégé par `pcall`.

Rappel du périmètre (PLAN) : le fil d'Ariane de la carte est **hors v1**, et T6 est **bloqué** jusqu'aux tests 6 et 7.

> **Correction importante par rapport au plan initial.** WoW: Forever n'est pas un client privé de l'ère TBC/WotLK. C'est un **produit Blizzard officiel** (code produit `wowf`, type de jeu interne `camelot`), installé par Battle.net à côté du jeu retail. Il tourne sur le **moteur moderne**, celui de retail 12.x (Edit Mode, `C_Map`, `C_AddOns`, valeurs secrètes), avec du contenu de type « vanilla ». `_VERSION == "Lua 5.1"` ne dit rien de l'époque : tous les clients WoW, retail compris, utilisent Lua 5.1. Les noms de frames et d'API sont donc ceux du client **moderne (Mainline)**.

---

## 1. Emplacement de l'installation

| Élément | Valeur | Statut |
|---|---|---|
| Racine Battle.net | `D:\World of Warcraft\` | confirmé (listage de `D:\`) |
| Dossier du client Forever | `D:\World of Warcraft\_forever_\` | confirmé |
| Exécutable | `D:\World of Warcraft\_forever_\Wow.exe` | confirmé |
| Dossier des addons | `D:\World of Warcraft\_forever_\Interface\AddOns\` | confirmé |
| Saveurs présentes dans la même installation | `_forever_` (wowf) et `_retail_` (wow, 12.1.5.70961) | confirmé (`.build.info`) |

`D:\World of Warcraft\_forever_\.flavor.info` contient `wowf`. **Ne pas confondre** avec `_retail_` : l'addon va dans `_forever_\Interface\AddOns\WoWTranslator\`.

Autres emplacements regardés, sans résultat : `C:\Program Files`, `C:\Program Files (x86)` (Battle.net seulement), `D:\Program Files`, `D:\Launcher` (Rockstar). `C:\Games` et `D:\Games` n'existent pas.

## 2. Version / build du client

| Source | Valeur | Statut |
|---|---|---|
| `(Get-Item _forever_\Wow.exe).VersionInfo.FileVersion` | `1.60.1.71037` (ProductVersion « Version 1.60.1.71037 », IsPreRelease = True) | confirmé |
| `D:\World of Warcraft\.build.info`, ligne `Product = wowf` | `Version = 1.60.1.71037`, branche `us`, tags `enUS text` / `enUS speech` | confirmé |
| `_forever_\WTF\Config.wtf` | `engineSurveyPatch "16001"`, `ClientSettings_* "16001,…"` | confirmé |
| `_forever_\Logs\General.log` (connexion au royaume) | royaume en `1.60.1.70399` (build serveur) | confirmé |
| ws@forever | dernier commit « 1.60.1 (71037) » | confirmé (`gh api repos/Gethe/wow-ui-source/commits/forever`) |

Le code de l'UI (FrameXML) **n'est pas extrait sur disque**.

## 3. Numéro `## Interface:`

| Addon installé | Ligne Interface |
|---|---|
| ForeverDungeonJournal | `16001` |
| Spoken / Spoken_Quests (fichier principal) | `16001` |
| EllesmereUIForeverEssentials_Camelot.toc | `16001` + `## AllowLoadGameType: camelot` |
| Angleur_Camelot.toc | `16001` |
| EllesmereUI* (multi-versions) | `120000, …, 120105, 16001` |

**Valeur à utiliser : `## Interface: 16001`.** Statut : confirmé (sources : ces `.toc`, et `Config.wtf` `engineSurveyPatch "16001"`).

Autres directives du `.toc`, confirmées par les `.toc` installés :
- plusieurs numéros séparés par des virgules ;
- `## AllowLoadGameType: camelot` ;
- `## LoadSavedVariablesFirst` ;
- suffixes par fichier `[AllowLoadTextLocale frFR]` ;
- `.toc` suffixés par saveur (`Addon_Camelot.toc`).

Un simple `WoWTranslator.toc` en `16001` suffit. Les fichiers installés sont en UTF-8 (par exemple `Notes-frFR` dans `Spoken_Places.toc`) : écrire nos fichiers en **UTF-8 sans BOM**.

## 4. Locales installées et accès à AreaTable

**Mise à jour du 2026-11-21 : l'utilisateur a installé le pack de langue français.** Relevé fait en lecture seule après l'installation. Le relevé initial (enUS seul) est remplacé par celui-ci.

| Élément | Constat | Statut |
|---|---|---|
| Locales installées (wowf) | **enUS et frFR**, texte et voix. Les tags de la ligne `wowf` de `D:\World of Warcraft\.build.info` (modifié le 2026-11-21 à 11:41) valent `… enUS speech?:… enUS text?:… frFR speech?:… frFR text?` | confirmé |
| Langues de l'installation (Battle.net) | `D:\World of Warcraft\.product.db`, entrée `wowf` / `_forever_` : langues `enUS` et `frFR`. Pour `wow` (`_retail_`), `enUS` seulement | confirmé (chaînes lisibles du fichier binaire ; la structure exacte n'est pas décodée) |
| Langue du texte **active** | toujours **`SET textLocale "enUS"`** | confirmé (`_forever_\WTF\Config.wtf`, dernière écriture le 2026-11-21 à 00:56, **avant** l'installation). L'entrée `wowf` de `.product.db` semble aussi garder `enUS` comme langue choisie (non confirmé, format binaire) |
| Langue audio active | `SET audioLocale "enUS"` | confirmé (idem) |
| `GetLocale()` au prochain lancement | probablement **`enUS`** : le pack est présent, mais la langue du texte n'a pas été basculée | non confirmé (test 2 du §8). Si l'utilisateur choisit « Français » dans Battle.net, `GetLocale()` renverra `frFR` et le sens de l'addon s'inversera (frFR → enUS) |
| Dossiers par locale | aucun `Data\enUS` ni `Data\frFR`. Les seuls dossiers de locale sont des caches d'exécution, `_forever_\Cache\ADB\enUS` et `_forever_\Cache\WDB\enUS`. Aucun cache `frFR`, puisque le jeu n'a pas encore tourné en français | confirmé |
| Stockage | **CASC** partagé : `D:\World of Warcraft\Data\{config,data,ecache,indices,wow,wowf}`. `data\` = 411 fichiers, environ 140 Go (retail compris), mis à jour le 2026-11-21 vers 11:41 (téléchargement du pack) | confirmé |
| AreaTable | DB2 dans le CASC uniquement. Pas de fichier libre, pas de MPQ | confirmé pour CASC ; nom exact (`DBFilesClient\AreaTable.db2`, FileDataID non relevé) : non confirmé |
| Données texte frFR présentes ? | **probablement oui** : le tag `frFR text` est actif dans `.build.info`, et le CASC a reçu des données ce jour-là | non confirmé au niveau fichier (le CASC n'a pas été ouvert) |

Conséquences pour **T1** (**SUPPLANTÉ le 21/11/2026**, voir `PLAN.md` T1 et `tools/README.md`) :
- **Non retenus pour T1** : l'extraction des fichiers du jeu (CASC, DB2) et les outils qui la font (**CascLib**, **CASCExplorer / CASCLib .NET**, **DBCD + WoWDBDefs**, **wow.tools.local**). Motif : l'EULA de Blizzard (§1.C.6, « Data Mining ») l'interdit ; ces outils ne sont donc ni installés, ni téléchargés, ni utilisés.
- **Non retenu pour T1** : Spoken_Places (tables de noms dérivées de AreaTable, licence incertaine, données extraites d'un tiers).
- **Retenu** : la collecte en jeu par l'API officielle (`C_Map.GetAreaInfo`, `C_Map.GetMapInfo`), dans les deux langues, avec l'addon `WoWTranslatorCollector/` (outil de développement, jamais distribué). Le générateur joint les deux langues par identifiant.

Conséquences pour la **checklist (T8)** :
- Les scénarios **[frFR]** (sens frFR → enUS) deviennent exécutables, **à condition** de basculer la langue du texte sur Français dans Battle.net (Paramètres du jeu > Langue du texte) puis de relancer le jeu. Vérifier ensuite `/run print(GetLocale())` → `frFR` (test 2).
- Sans bascule, le client reste en enUS : seuls les scénarios [enUS] s'appliquent.
- Les SavedVariables et l'override `/wt lang` ne dépendent pas de la locale du client.
- Les noms de lieux du client changent avec la langue. Après une bascule, `_forever_\Cache\*\frFR` sera créé par le jeu.

Pistes pour T1 : **non retenues** (voir ci-dessus). Les fichiers `Spoken_Places\Data\...` ne sont ni copiés ni lus pour la génération.

En jeu, l'API ne renvoie que la locale courante. Le dictionnaire embarqué reste nécessaire.

Le pack français est installé (2026-11-21). Pour **jouer** en français : Battle.net > WoW Forever > Paramètres du jeu > Langue du texte = Français, puis relancer. `GetLocale()` renverra alors `frFR`.

## 5. Frames et API pour ce build

Le type de jeu `camelot` charge les fichiers `[Family]` (= Mainline), sauf ceux marqués `[ExcludeLoadGameType camelot]`. Il ajoute ou remplace par des fichiers `[Game]` (= dossier `Camelot\`). Source : en-têtes des `.toc` de ws@forever cités ci-dessous.

### 5.1 Texte d'arrivée dans une zone (T4)
Sources : `Blizzard_FrameXML/Mainline/ZoneText.xml` et `ZoneText.lua` (ws@forever), chargés via `[Family]\ZoneText.xml` et `[Family]\ZoneText.lua` dans `Blizzard_FrameXML.toc`. Statut : **confirmé**.

| Global | Type | Rôle |
|---|---|---|
| `ZoneTextFrame` | Frame (FadingFrame) | événements `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` (`ZoneText_OnLoad`) |
| `ZoneTextString` | FontString de `ZoneTextFrame` | nom de zone |
| `SubZoneTextFrame` | Frame (FadingFrame), sans `OnEvent` | |
| `SubZoneTextString` | FontString de `SubZoneTextFrame` | sous-zone, **ou le nom de zone** (voir point 3) |
| `PVPInfoTextString` | FontString | `SetText`/`SetFormattedText(FACTION_CONTROLLED_TERRITORY, factionName)` |
| `PVPArenaTextString` | FontString | « Combat libre », etc. |
| `ZoneText_Clear()` | fonction globale | vide **trois** chaînes : `ZoneTextString`, `SubZoneTextString`, `PVPInfoTextString` |

Comportement réel, qui conditionne T4 (`ZoneText.lua`, fonction `ZoneText_OnEvent`, sauf mention contraire) :

1. **Liaison par référence.** `ZoneText.xml` déclare `<OnEvent function="ZoneText_OnEvent"/>`. Le XML lie la fonction au frame **au chargement**, en référence directe. Un `hooksecurefunc("ZoneText_OnEvent", …)` remplace la globale, mais **pas** le script déjà lié : il n'a **aucun effet** sur le frame. Il en va de même pour `ZoneText_OnLoad`, `SubZoneText_OnLoad` et `FadingFrame_OnUpdate`.
2. **Mise à jour conditionnelle de `ZoneTextString`.** `ZoneTextString:SetText(zoneText)` n'est appelé que si `zoneText ~= self.zoneText` ou si l'événement est `ZONE_CHANGED_NEW_AREA`. `self.zoneText` mémorise la valeur de `GetZoneText()`, pas le texte affiché : traduire la FontString ne perturbe donc pas cette comparaison.
3. **La sous-zone reçoit le nom de zone.** `SubZoneTextString:SetText("")` est toujours appelé d'abord. Si `GetSubZoneText()` vaut `""` et que la zone n'a pas changé, alors `subzoneText = zoneText`. Si en plus `ZoneTextFrame` n'est pas affiché, alors `SubZoneTextString:SetText(subzoneText)` : **la sous-zone affiche le nom de la zone**. Ce texte doit donc être traduit lui aussi (c'est un nom de zone, présent dans le dictionnaire).
4. **Fondu.** Les deux frames sont des `FadingFrame`, avec `ZoneFadeInDuration = 0.5`, `ZoneHoldDuration = 1.0`, `ZoneFadeOutDuration = 2.0` (haut de `ZoneText.lua`), soit **environ 3,5 s** d'affichage après `FadingFrame_Show`. En dehors de cette fenêtre, les frames sont cachés : une traduction appliquée à `ZoneTextString` est réelle mais **invisible**. T4 ne force pas l'affichage en v1.
5. **PvP.** `SetZoneText(showZone)` lit `C_PvP.GetZonePVPInfo()` et colore les chaînes. Il appelle `PVPArenaTextString:SetText("")` et `PVPInfoTextString:SetText("")`, puis le texte PvP (`SetText` ou `SetFormattedText`).
6. **Texte initial.** `SubZoneText_OnLoad` fait `SubZoneTextString:SetText(GetSubZoneText())` au chargement de FrameXML, donc **avant** notre addon. Au premier `Apply`, la FontString peut déjà contenir un texte qu'aucun hook n'a vu. `Apply` doit donc lire `GetText()` directement.
   **`GetText()` ne renvoie jamais `nil`.** `SimpleFontStringAPIDocumentation.lua:353-364` (ws@forever) déclare son retour `text: cstring, Nilable = false`. Une FontString jamais écrite ou vidée renvoie donc `""` : tester `text == ""`, pas `not text`. Côté écriture, l'argument de `SetText` est déclaré `Nilable = false, Default = ""` (l. 664-670). `SetText(nil)` vaut donc probablement `SetText("")` (non confirmé). Un mock qui renvoie `nil` diverge de la documentation.
7. Les appels sont tous via `SetText` sur les FontStrings nommées. En plus de `ZoneText_OnEvent`, `ZoneText_Clear()` (appelée par d'autres UI) remet à `""`.

**Stratégie de hook pour T4.**
- `hooksecurefunc(ZoneTextString, "SetText", h)` et `hooksecurefunc(SubZoneTextString, "SetText", h)` : hook de **méthode sur l'instance**, qui marche quel que soit l'appelant.
- Facultatif : `ZoneTextFrame:HookScript("OnEvent", h)`. `HookScript` s'ajoute au script lié, contrairement à `hooksecurefunc` sur la globale.
- **Jamais** `hooksecurefunc("ZoneText_OnEvent", …)` ni `ZoneTextFrame:SetScript(…)`.
- Dans le hook : ignorer `""`, mémoriser l'original, puis, si actif, appeler `SetText(traduction)` avec un drapeau anti-récursion.

### 5.2 Texte de zone de la minimap (T4)
Sources (ws@forever) : `Blizzard_Minimap/Blizzard_Minimap.toc`, `Mainline/Minimap.lua`, `Mainline/Minimap.xml`, `Camelot/MinimapZoneTextButton.{xml,lua}`, `Camelot/Minimap.lua`. Statut : **confirmé**.

Fichiers chargés en camelot (d'après `Blizzard_Minimap.toc`) :
- `[Family]\Minimap.lua` (Mainline), **plus** les surcharges `[Game]` : `Camelot\Minimap.lua`, `Camelot\MinimapInstanceDifficulty.lua`, `Camelot\MinimapZoneTextButton.lua`, `Camelot\MinimapTrackingButton.lua`, `Camelot\Diel.lua`, `Camelot\GameTimeFrame.lua`, `Camelot\AddonCompartment.lua`, `Camelot\MinimapConstants.lua` ;
- XML : `Camelot\MinimapZoneTextButton.xml`, `Camelot\MinimapTrackingButton.xml`, `Camelot\MinimapMailFrameTemplate.xml`, `Camelot\MinimapIndicatorFrameTemplate.xml`, `Camelot\GameTimeFrameTemplate.xml`, `Camelot\AddonCompartment.xml` (les versions `[Family]` sont exclues par `[ExcludeLoadGameType camelot]`), et `[Family]\Minimap.xml`.

| Élément | Détail | Source |
|---|---|---|
| `MinimapZoneText` | FontString **globale**, définie dans `MinimapZoneTextButtonTemplate` | `Camelot/MinimapZoneTextButton.xml` |
| `MinimapCluster.ZoneTextButton` | bouton parent (`parentKey="ZoneTextButton"`, clic = carte du monde) | `Mainline/Minimap.xml:24` |
| Écriture du texte | `Minimap_Update()` → `MinimapZoneText:SetText(GetMinimapZoneText())` | `Mainline/Minimap.lua:169-170` |
| Appelants de `Minimap_Update` | `MinimapClusterMixin:OnLoad()` (ligne 372), qui enregistre `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, `SETTINGS_LOADED` (lignes 373-376) ; puis `MinimapClusterMixin:OnEvent()`, qui appelle `Minimap_Update()` pour **tout** événement (ligne 409). `MinimapCluster` est `mixin="MinimapClusterMixin"` (`Mainline/Minimap.xml:3`) | `Mainline/Minimap.lua` |
| Infobulle | `Minimap_SetTooltip()` → `GameTooltip:AddLine(GetZoneText())` et `GetSubZoneText()` (owner `MinimapCluster.ZoneTextButton`) | `Mainline/Minimap.lua:190-194` |
| Surcharge camelot du bouton | `Camelot/MinimapZoneTextButton.lua` ne change que `OnLoad` (atlas) et `OnButtonStateChanged` : rien sur le texte | idem |

`Minimap_Update` est appelé par son nom depuis du Lua (`OnEvent` en `method=`). Hooker la FontString reste quand même la méthode la plus sûre : `hooksecurefunc(MinimapZoneText, "SetText", h)`. Il n'existe pas de `MinimapZoneTextButton` global dans ce build.

⚠ **Conflit utilisateur** (confirmé, `EllesmereUIMinimap\EUI_Minimap_Apply.lua:673-678`) : EllesmereUIMinimap, activé sur plusieurs personnages (`WTF\Account\…\AddOns.txt`), **cache** `MinimapZoneText` et `MinimapCluster.ZoneTextButton`. Il affiche sa propre barre de lieu (`EllesmereUIDataBars\Blocks\Location.lua:70-71`). La traduction de la minimap Blizzard y sera invisible. Une compatibilité est possible, hors v1.

### 5.3 Carte du monde (T5)
Sources (ws@forever) : `Blizzard_WorldMap/Blizzard_WorldMap_Mainline.toc`, `Blizzard_WorldMap.{xml,lua}`, `Blizzard_WorldMapTemplates.lua`, `Camelot/Blizzard_WorldMap.lua`, `Blizzard_SharedMapDataProviders/AreaLabelDataProvider.{xml,lua}`, `Blizzard_SharedXML/ColorUtil.lua`, `Blizzard_SharedXML/SharedColorConstants.lua`.

**Chargement (correction A1).** `Blizzard_WorldMap_Mainline.toc` n'a **pas** de `## LoadOnDemand`. Son en-tête ne contient que `## Title`, `## Author` et `## RequiredDep: Blizzard_MapCanvas, Blizzard_SharedMapDataProviders, Blizzard_HelpPlate` (confirmé). La carte est donc **probablement chargée au démarrage, avant notre addon** (non confirmé en jeu, test 5 du §8). Conséquences pour T5 :
- au chargement du module, **tester `WorldMapFrame` d'abord** et s'accrocher tout de suite s'il existe ;
- sinon, et seulement sinon, attendre `ADDON_LOADED` avec `"Blizzard_WorldMap"` ;
- un module qui n'écoute qu'`ADDON_LOADED` ne s'accrochera probablement jamais.

Les data providers, dont le libellé de zone, sont ajoutés dès l'`OnLoad` de la carte : `WorldMapMixin:OnLoad` (`Blizzard_WorldMap.lua:134`) appelle `self:AddStandardDataProviders()` (ligne 149, définie ligne 192), qui ajoute `AreaLabelDataProviderMixin` (lignes 245-248). Le libellé est donc présent dès que `WorldMapFrame` existe, sans attendre la première ouverture (non confirmé en jeu, même test 5).

| Élément | Accès | Contenu | Statut |
|---|---|---|---|
| Titre de la fenêtre | `WorldMapFrame.BorderFrame:SetTitle(WORLD_MAP / MAP_AND_QUEST_LOG)` (`Blizzard_WorldMap.lua:14,23,28`) | chaîne fixe, **pas un nom de lieu**. **Non traduit** (décision PLAN T5) | confirmé |
| Libellé de zone au survol | data provider `AreaLabelDataProviderMixin`, frame `provider.Label` (`AreaLabelFrameTemplate`), FontStrings `Label.Name` / `Label.Description` | voir le détail ci-dessous | confirmé |
| Fil d'Ariane (**hors v1**, PLAN T5) | `WorldMapFrame.NavBar` (`WorldMapNavBarMixin:Refresh()`, `Blizzard_WorldMapTemplates.lua:527-557`) : boutons `NavBar_AddButton(self, {name = mapInfo.name, …})` ; menus `WorldMapNavBarButtonMixin:GetDropdownList()` (`childInfo.name`, ligne 571) | noms de cartes ; information gardée pour une version ultérieure | confirmé |
| Libellés de zone sur continent | `ZoneLabelDataProvider` (listé dans `Blizzard_SharedMapDataProviders_Mainline.toc`) | non inspecté | non confirmé |
| `EncounterJournalDataProvider` | `[ExcludeLoadGameType camelot]` dans le même `.toc` | absent en Forever | confirmé |

**Libellé au survol : format exact (correction A2)** — `AreaLabelDataProvider.lua`, `AreaLabelFrameMixin:OnUpdate`, lignes 86-106 :
- `name = positionMapInfo.name` (ligne 88). Sinon (ligne 141), `name = MapUtil.FindBestAreaNameAtMouse(...)`, **sans** suffixe.
- Le suffixe n'est ajouté que si `C_Map.GetMapLevels(mapID)` renvoie `playerMinLevel` et `playerMaxLevel` non nuls et `> 0` (ligne 90).
- `color = RGBTableToColorCode(color)` (ligne 101), ce qui produit `"|cffRRGGBB"` (`ColorUtil.lua:90-95` : `format("|cff%02x%02x%02x", …)`, hexadécimal **minuscule**). `FONT_COLOR_CODE_CLOSE = "|r"` (`SharedColorConstants.lua:1`).
- Plage (ligne 103) : `name..color.." ("..min.."-"..max..")"..FONT_COLOR_CODE_CLOSE`, soit **`"Elwynn Forest|cffRRGGBB (1-10)|r"`**. **L'espace est à l'intérieur** du code couleur.
- Niveau unique (ligne 105, quand `min == max`) : **`"Molten Core|cffRRGGBB (60)|r"`**.
- Motif Lua pour séparer nom et suffixe : `^(.-)(|c%x%x%x%x%x%x%x%x %(%d+%-?%d*%)|r)$`. Accepter aussi l'absence de suffixe.

Écritures du FontString (même fichier) :
- `AreaLabelFrameMixin:EvaluateLabels()` fait `self.Name:SetText(areaLabelInfo.name)` (ligne 211), seulement si le libellé est « sale » (`IsDirty`, ligne 204) ;
- sans libellé, il fait `self.Name:SetText("")` et `self.Description:SetText("")` (lignes 236-237) ;
- `OnUpdate` appelle `ClearLabel` puis `EvaluateLabels` à chaque frame (lignes 71-72, 147). Ce n'est que lorsque le contenu change que `SetText` est rappelé.
- D'autres providers peuvent poser un libellé de priorité supérieure (`GetHighestPriorityLabelInfo`, ligne 178). `Name` n'est donc pas toujours un nom de zone : un nom inconnu doit être laissé tel quel.

Accès au libellé (méthode déjà utilisée en Forever par `EllesmereUIForeverEssentials_ZoneLevels.lua:180-185`, confirmé) :
```lua
for provider in pairs(WorldMapFrame.dataProviders) do
  if provider.Label and provider.Label.Name then --[[ hooksecurefunc(provider.Label.Name, "SetText", …) ]] end
end
```

### 5.4 Donjons / instances (T6) — **décisions bloquées, voir l'état de T0**
| Interface | Constat | Statut |
|---|---|---|
| Guide de l'aventurier (`EncounterJournal`) | `Blizzard_EncounterJournal.toc` (ws@forever) : `## AllowLoadGameType: standard, classic`. Les addons Ellesmere utilisent `standard` pour dire « pas Forever » (`EllesmereUIFriends.toc`, `EllesmereUIGroupFinder.toc`), et l'addon tiers ForeverDungeonJournal existe pour combler ce manque. **Probablement absent** | non confirmé (test 7) |
| Recherche de groupe | `Blizzard_GroupFinder_VanillaStyle.toc` : `## AllowLoadGameType: classic, camelot`, `## LoadOnDemand: 1` ; ouverture `LFGVanilla_ToggleFrame(1)` (`Bindings.xml`, binding `TOGGLEGROUPFINDER`) | chargement confirmé (ws@forever) ; frames internes non inspectées |
| Verrous d'instance | `RaidInfoFrame` (`Blizzard_RaidFrame.toc` : `[Family]\RaidFrame.xml [AllowLoadGameType mainline, vanilla, tbc]`) + `GetNumSavedInstances()` / `GetSavedInstanceInfo(i)` (utilisés en Forever par `EllesmereUIDataBars\Blocks\Clock.lua:343`) | non confirmé en jeu (test 6) |
| `GetLFGDungeonInfo(id)` | utilisé par EllesmereUI (`EllesmereUIQoL_Keys.lua:41-42`), mais dans un module qui peut viser retail | non confirmé |
| Texte de zone en entrant dans une instance | même `ZoneTextString` (5.1) | confirmé |

Décision : T6 code **uniquement** les cibles validées par les tests 6 et 7 du §8. Sans validation, T6 se limite au texte de zone (déjà couvert par T4) et ne livre que la structure du module.

### 5.5 API de zone
Source : `Blizzard_APIDocumentationGenerated/ZoneScriptDocumentation.lua` (ws@forever). Statut : **confirmé**.

| Fonction | Retour | Note |
|---|---|---|
| `GetZoneText()` | cstring, non nil | pas de marque secrète |
| `GetSubZoneText()` | cstring, non nil (`""` si aucune) | idem |
| `GetRealZoneText([mapID])` | cstring | `SecretArguments = "AllowedWhenUntainted"` |
| `GetMinimapZoneText()` | cstring | pas de marque secrète |
| `GetAreaText()` | cstring | |

### 5.6 Valeurs secrètes (correction A5)
Ce qui est **confirmé** (ws@forever, `Blizzard_APIDocumentationGenerated`) :
- `FrameScriptDocumentation.lua:287-300` déclare `issecretvalue(value) -> isSecret: bool`, « Returns true if a supplied value is a secret value », `SecretArguments = "AllowedWhenUntainted"`. Le même fichier déclare `canaccessvalue` (l. 65), `canaccesssecrets` (l. 37), `hasanysecretvalues` (l. 253), `issecrettable` (l. 270), `scrubsecretvalues` (l. 374, « secret values replaced by nil »), `scrub` (l. 391) et `secretwrap` (l. 426, « preventing most operations on them from occurring on tainted code paths »).
- `SecretPredicateAPIDocumentation.lua:93-99` : `C_Secrets.HasSecretRestrictions()`, « Returns true if this client build has secret value restrictions enabled ».
- `SimpleFontStringAPIDocumentation.lua` :
  - `GetText` a `SecretReturnsForAspect = { Enum.SecretAspect.Text }` (l. 353-355) ;
  - `SetText` et `SetFormattedText` ont `SecretArguments = "AllowedWhenTainted"` et `SecretArgumentsAddAspect = { Enum.SecretAspect.Text }` (l. 664-667 et 539-542).

  En clair : un code tainté (un addon) **peut** passer une valeur secrète à `SetText`. La FontString prend alors l'aspect secret « Text », et ensuite son `GetText()` **renvoie une valeur secrète**.
- `SecretPredicatesDocumentation.lua:22-25` : `RequiresFontStringTextAccess`, « Guarded APIs reject access for tainted callers if the object has the secret Text aspect assigned ».
- Usage réel en Forever : `Angleur\secrets\secrets.lua:24-35` (chargé par `Angleur_Camelot.toc`) appelle `issecretvalue` et `scrubsecretvalues` sans garde quand `gameVersion == VERSION_FOREVER`. Il écoute aussi `ADDON_RESTRICTION_STATE_CHANGED` (types Combat, Encounter, ChallengeModes, PvPMatch, Map, Chat). Note : `Spoken\Environment.lua:36-38` fait `rawget(_G, "issecretvalue")`, ce qui **ne prouve pas** l'existence de la fonction.

Ce qui reste **non confirmé** : la sémantique exacte d'une valeur secrète pour du code tainté, c'est-à-dire ce que renvoie `type(v)` et quelles opérations lèvent une erreur (`==`, `..`, `#`, `t[v]`, `string.*`). La documentation dit seulement « most operations » (`secretwrap`). Hypothèse de travail, à vérifier par le test 4 : `type(v) == "string"`, et la comparaison, la concaténation ou l'indexation par du code tainté lèvent une erreur.

**Contradiction apparente : `issecretvalue` est `AllowedWhenUntainted`** (`FrameScriptDocumentation.lua:290`).
- La documentation emploie deux valeurs pour cet attribut :
  - `"AllowedWhenTainted"` (`SetText`, `SetFormattedText`) ;
  - `"AllowedWhenUntainted"` (`issecretvalue`, `canaccessvalue`, `scrubsecretvalues`, mais aussi `IsKeyDown`, `InputDocumentation.lua:117`, et `GetRealZoneText`, `ZoneScriptDocumentation.lua:30`).
- Lu à la lettre, `AllowedWhenUntainted` signifierait qu'un code **tainté** (un addon) ne peut pas passer d'argument secret. `issecretvalue(v)` lèverait alors une erreur précisément quand `v` est secret, ce qui rendrait la fonction inutile pour les addons.
- Or Angleur, en Forever, l'appelle depuis du code d'addon, donc tainté (`Angleur\secrets\secrets.lua:26`, et `scrubsecretvalues` l. 32). Spoken fait de même (`Spoken\Environment.lua:38-39`). Leurs auteurs s'attendent donc à ce que l'appel marche. Ce n'est pas une preuve que le cas secret a été exercé.
- Le sens exact de l'attribut est **non confirmé**. Le test 4 du §8 (`issecretvalue(secretwrap("x"))` lancé depuis `/run`, donc tainté) le tranchera.

Règles pour `WT.Translate` et les hooks, qui sont sûres quelle que soit la sémantique exacte :
1. Si `issecretvalue` existe, l'appeler **avant toute autre opération** sur la valeur (pas de `==`, de `type`, de `#` ni d'indexation avant), et **via `pcall`** tant que le test 4 n'a pas tranché : `local ok, sec = pcall(issecretvalue, text); if not ok or sec then return nil end`. Une erreur est traitée comme « secret ».
   **Si `issecretvalue` est absent** (`issecretvalue == nil`, cas d'un client sans valeurs secrètes, comme le prévoit `Spoken\Environment.lua:36`), aucune valeur n'est secrète : sauter ce test et traduire normalement. Ne **jamais** appeler `pcall(nil, …)`, qui échouerait toujours et bloquerait toute traduction. Forme recommandée : `local isv = issecretvalue; if isv then local ok, sec = pcall(isv, text); if not ok or sec then return nil end end`.
2. Dans un hook `SetText`, appliquer la même règle à l'argument reçu. Si la valeur est secrète, ne rien mémoriser ni réécrire.
3. Les textes de zone ne sont pas censés être secrets (§5.5). En donjon ou raid, des restrictions de « carte » existent (`SecretOnRestrictedMaps`, `SecretPredicatesDocumentation.lua:70-72`), mais elles ne visent pas les API de zone.

## 6. Raccourcis clavier (Bindings.xml)

### 6.1 Format
| Point | Constat | Statut |
|---|---|---|
| `runOnUp="true"` supporté | `Blizzard_FrameXML/Bindings_Camelot.xml:4` et suivantes (MOVEANDSTEER, MOVEFORWARD… avec `if ( keystate == "down" )`) ; `Blizzard_PingUI/Bindings.xml` (`TOGGLEPINGLISTENER runOnUp="true"` → `C_Ping.TogglePingListener(keystate == "down")`) | **confirmé (ws@forever)** |
| Variable `keystate` dans le corps | `"down"` / `"up"` | confirmé (mêmes fichiers) |
| Attribut `category` | `category="BINDING_HEADER_XXX"` (Blizzard ; addon Spoken installé) ou chaîne littérale (`category="Dungeon Journal"` chez ForeverDungeonJournal) | confirmé (`_forever_\Interface\AddOns\Spoken\Bindings.xml`, `ForeverDungeonJournal\Bindings.xml`) |
| Attribut `header` | encore accepté (`header="EUI_BAR9"` chez EllesmereUIActionBars) | confirmé (fichier installé) |
| Libellé affiché | globale `BINDING_NAME_<name>` | convention standard ; non confirmé en jeu pour notre addon (test 9) |

### 6.2 Où apparaît le raccourci (correction A9)
Source : `Blizzard_SettingsDefinitions_Frame/Keybindings.lua` (ws@forever), lignes 220-259. Statut : **confirmé**.
- Chaque binding est rangé dans une section dont le titre est `_G[category]` si c'est une chaîne, sinon la valeur brute de `category` (`GetBindingCategoryName`, lignes 220-227).
- Sans `category`, le binding va dans la section `BINDING_HEADER_OTHER` (« Autre ») (ligne 246).
- Avec `category="BINDING_HEADER_WOWTRANSLATOR"`, la section s'intitule « WoWTranslator » si la globale est définie, sinon le texte brut `BINDING_HEADER_WOWTRANSLATOR`. Ce n'est **pas** une catégorie « AddOns ».
- Chemin dans le menu : Options > Gameplay > Raccourcis (catégorie `SETTINGS_KEYBINDINGS_LABEL`, ligne 278), section « WoWTranslator ».
- Si le menu affiche le nom brut, c'est que la globale n'était pas encore définie : la définir au **chargement du fichier**, au niveau supérieur de `Core.lua`.

### 6.3 Perte de focus et filet de sécurité (corrections A4, A7)
- **Aucun événement de perte de focus clavier ou fenêtre trouvé.** Sources :
  - `SystemDocumentation.lua` (ws@forever) ne liste que `GLOBAL_MOUSE_*`, `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD`, `PLAYER_LOGOUT`, etc. ;
  - `KeyBindingsDocumentation.lua` ne liste que `BINDINGS_LOADED`, `MODIFIER_STATE_CHANGED`, `NOTIFY_TURN_STRAFE_CHANGE` et `UPDATE_BINDINGS` ;
  - une recherche de code GitHub `FOCUS` sur les `*Documentation.lua` ne renvoie que la cible « focus » (`PLAYER_FOCUS_CHANGED`) et des API d'EditBox. Cette recherche porte sur la branche par défaut (retail), seule indexée par GitHub.

  Statut : confirmé pour les fichiers lus ; « aucun événement n'existe » reste non démontrable de façon exhaustive.
- **`IsKeyDown` existe — confirmé.**
  - `InputDocumentation.lua:115-128` (ws@forever) : `IsKeyDown(keyOrMouseName: cstring, excludeBindingState: bool = false) -> down: bool?`, `SecretArguments = "AllowedWhenUntainted"`.
  - Usage réel en Forever : `Angleur\AngleurForever.lua:107, 122, 397`, chargé par `Angleur_Camelot.toc`. Par exemple `if IsKeyDown(keybind) == false then` sur la touche liée.
  - Remarque : `Angleur.lua:77, 92, 400`, cité par la revue, contient le même code, mais ce fichier n'est **pas** listé dans `Angleur_Camelot.toc`. C'est donc la version Forever qui fait foi.
- **Touches liées et modificateurs.** Une action peut avoir **deux** touches. `GetBindingKey("WOWTRANSLATOR_HOLD")` renvoie jusqu'à deux valeurs, `key1, key2` (forme utilisée en Forever : `local k1, k2 = GetBindingKey(cmd)`, `EllesmereUIActionBars\EUI_ActionBars_Keybinds.lua:165`). Chacune peut porter des modificateurs (`"SHIFT-T"`). Angleur sonde la touche **de base**, sans modificateurs (`AngleurConfig.angleurKey_Base`, `AngleurForever.lua:115-118`). Pour extraire la base : prendre le dernier segment après `-`, sauf si la chaîne se termine par `--` (touche `-` elle-même, par exemple `"SHIFT--"` → `"-"`). Que `IsKeyDown("SHIFT-T")` marche ou non n'est **pas confirmé** (test 8).
- **Décision (PLAN T2)** : le filet est **armé uniquement par le gestionnaire de touche** (`WoWTranslator_OnHoldKey("down")`), jamais par un `WT.SetActive(true)` venu d'ailleurs (commande, test). Ensuite, tant que l'addon est actif, un sondage léger (`C_Timer.NewTicker` 0,1 s, ou `OnUpdate` d'un frame affiché seulement pendant l'appui) fait :
  1. relire `GetBindingKey("WOWTRANSLATOR_HOLD")` (**toutes** les valeurs, 0 à 2) et réduire chacune à sa touche de base ;
  2. appeler `IsKeyDown(base)` pour **chacune** ;
  3. désactiver (`WT.SetActive(false)`, qui fait `Restore` et remet `IsActive()` à faux) **seulement si toutes** renvoient explicitement `false`. Si au moins une renvoie `true` ou `nil` (touche inconnue, on garde l'état actif), ou s'il n'y a aucune touche liée, ne pas couper ;
  4. arrêter le sondage à la désactivation.

  Raison : l'appui peut venir de la seconde touche. Sonder seulement la première couperait la traduction alors que l'utilisateur tient la touche.

### 6.4 Gabarit pour T2 (correction A8)
```xml
<Bindings>
  <Binding name="WOWTRANSLATOR_HOLD" runOnUp="true" category="BINDING_HEADER_WOWTRANSLATOR">
    WoWTranslator_OnHoldKey(keystate)
  </Binding>
</Bindings>
```
```lua
-- Core.lua, au niveau supérieur (exécuté au chargement du fichier)
local addonName, WT = ...
WoWTranslator = WT                      -- seule globale publique (PLAN)
BINDING_HEADER_WOWTRANSLATOR = "WoWTranslator"
if GetLocale() == "frFR" then
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Afficher l'autre langue (maintenir)"
else
  BINDING_NAME_WOWTRANSLATOR_HOLD = "Show other language (hold)"
end
function WoWTranslator_OnHoldKey(keystate)   -- globale exigée par Bindings.xml
  WT.SetActive(keystate == "down")
end
```

## 7. Décisions pour T2–T6

| Sujet | Valeur à utiliser |
|---|---|
| Dossier d'installation | `D:\World of Warcraft\_forever_\Interface\AddOns\WoWTranslator\` |
| `.toc` | `## Interface: 16001` (on peut ajouter `## AllowLoadGameType: camelot`, facultatif) ; UTF-8 sans BOM |
| Namespace | `local addonName, WT = ...` dans chaque fichier ; globale publique `WoWTranslator` ; **pas** de globale `WT` |
| Locale actuelle | packs **enUS et frFR installés** (2026-11-21), langue du texte active **`enUS`**. Le sens est décidé à l'exécution par `GetLocale()`. frFR → enUS sera testable après bascule de la langue du texte dans Battle.net |
| Bindings | §6.4 : `runOnUp="true"`, `WoWTranslator_OnHoldKey(keystate)`, `category="BINDING_HEADER_WOWTRANSLATOR"`, libellé selon `GetLocale()` |
| Contrat (PLAN) | `WT.IsActive()`, `WT.SetActive(bool)`, `WT.Translate(text)`, `WT.RegisterModule(name, {Apply, Restore})` |
| Reset de sécurité (T2) | `WT.SetActive(false)` sur `PLAYER_LEAVING_WORLD` et `PLAYER_ENTERING_WORLD`. Filet armé **seulement** par `WoWTranslator_OnHoldKey("down")` : sondage `IsKeyDown` sur **toutes** les touches de `GetBindingKey` (touche de base) tant que l'addon est actif ; `WT.SetActive(false)` seulement si **toutes** renvoient explicitement `false` (`nil` = inconnu, on reste actif) (§6.3) |
| T4 – zone | hooks de **méthode** `SetText` sur `ZoneTextString` et `SubZoneTextString` ; ignorer `""` ; traduire aussi le nom de zone posé dans `SubZoneTextString` ; à l'`Apply`, lire le texte déjà présent (posé avant notre chargement). **Jamais** `hooksecurefunc("ZoneText_OnEvent")` ni `SetScript` : utiliser `HookScript` si un hook d'événement est nécessaire. Ne pas forcer l'affichage des frames en fondu (~3,5 s). `PVPInfoTextString`/`PVPArenaTextString` hors v1 |
| T4 – minimap | hook `SetText` sur `MinimapZoneText` ; infobulle facultative ; Ellesmere peut la cacher (sans erreur, juste invisible) |
| T5 – carte | au chargement : `if WorldMapFrame then hook() else attendre ADDON_LOADED "Blizzard_WorldMap" end` ; libellé = `provider.Label.Name`. **Le module** sépare le suffixe `|cffRRGGBB (a-b)|r` / `|cffRRGGBB (n)|r` (§5.3), appelle `WT.Translate(nom)` sur le nom seul, puis recolle le suffixe d'origine ; `""` laissé tel quel ; fil d'Ariane **hors v1** ; titre **non traduit** |
| T6 – instances | **bloqué** : seulement les cibles validées par les tests 6 et 7 |
| `WT.Translate` | `issecretvalue` testé **en premier**, via `pcall`, **s'il existe** (absent = rien n'est secret, on traduit) (§5.6) ; ensuite `type(text) == "string"` ; **recherche exacte** dans le dictionnaire, sans retrait des codes couleur ni du suffixe (décision PLAN). Le découpage du suffixe appartient au module carte (ligne T5) ; `nil` si inconnu |
| Hooks | `hooksecurefunc` sur les méthodes d'instance + drapeau anti-récursion ; jamais de remplacement de fonction ni de script |

## 8. À vérifier par l'utilisateur (en jeu, après `/console scriptErrors 1`)

1. Build et interface : `/run print(GetBuildInfo())` → attendu `1.60.1 71037 … 16001`.
2. Locale : `/run print(GetLocale(), GetCVar("textLocale"))` → attendu `enUS enUS`.
3. Frames de zone : `/run print(ZoneTextString, SubZoneTextString, PVPInfoTextString, PVPArenaTextString, MinimapZoneText, MinimapCluster.ZoneTextButton)` → six tables, aucun `nil`.
4. Valeurs secrètes : `/run print(issecretvalue, C_Secrets and C_Secrets.HasSecretRestrictions(), issecretvalue(GetZoneText()))` → attendu `function: … true/false false`. Pour la sémantique : `/run local v=secretwrap("x"); print(type(v), issecretvalue(v)); print(pcall(function() return v=="x" end)); print(pcall(function() return #v end)); print(pcall(function() local t={}; return t[v] end))`. Pour trancher `AllowedWhenUntainted` (§5.6) : `/run local v=secretwrap("x"); print(pcall(issecretvalue, v))` → `true true` signifie qu'un code tainté peut appeler `issecretvalue` sur une valeur secrète ; `false <erreur>` signifie que non (garder alors le `pcall`). Noter les résultats dans ce document.
5. Carte **juste après la connexion, sans l'ouvrir** : `/run print(WorldMapFrame, C_AddOns.IsAddOnLoaded("Blizzard_WorldMap"), C_AddOns.IsAddOnLoadOnDemand("Blizzard_WorldMap"))` → attendu `table true false`. Puis, toujours sans ouvrir la carte : `/run for p in pairs(WorldMapFrame.dataProviders) do if p.Label and p.Label.Name then print("label ok") end end print(WorldMapFrame.NavBar)`.
6. Instances : `/run print(RaidInfoFrame, LFGVanilla_ToggleFrame, GetNumSavedInstances and GetNumSavedInstances(), GetLFGDungeonInfo)`. Ouvrir aussi la recherche de groupe (binding « Recherche de groupe ») et noter si une liste de donjons nommés apparaît.
   **Résultat du 26/11/2026 (client enUS)** : `RaidInfoFrame` = table, `LFGVanilla_ToggleFrame` = fonction, `GetNumSavedInstances()` = 0 (aucun verrou en cours), `GetLFGDungeonInfo` = fonction. La recherche de groupe s'ouvre (fenêtre « Looking For Group ») : liste déroulante « Filter by activity » avec 34 donjons nommés, et nom de l'activité sous chaque groupe (« Upper Blackrock Spire »). Ces noms sont des **noms d'activité**, pas des noms de zone : « Deadmines » (zone : « The Deadmines »), « Stormwind Stockades », « Dire Maul (North) », « Stratholme (Main Gate) », « Scarlet Library », « Upper Blackrock Spire ». Le dictionnaire de zones en couvre 20 sur 34 (15 traduits, 5 identiques) ; 14 n'y sont pas. Frames internes de la fenêtre : non inspectées.
7. Guide de l'aventurier absent ? `/run print(C_AddOns.LoadAddOn("Blizzard_EncounterJournal"))` → attendu `false` + une raison. **Résultat du 26/11/2026** : `false WRONG_GAME_TYPE`. Le guide de l'aventurier n'existe pas dans Forever : hors T6.
8. `IsKeyDown` :
   - `/run C_Timer.After(2, function() print(IsKeyDown("T"), IsKeyDown("SHIFT-T")) end)` en tenant Shift+T pendant 2 s, puis la même chose sans rien tenir.
   - Après T2, lier **deux** touches à l'action (par exemple F6 et un bouton de souris). Lancer `/run C_Timer.After(2, function() print(GetBindingKey("WOWTRANSLATOR_HOLD")) end)` → les deux touches. Puis tenir **la seconde** touche 5 s : la traduction doit rester active.
9. Après T2 : le raccourci apparaît dans Options > Gameplay > Raccourcis, section « WoWTranslator ». Tester `down`/`up` avec `/run local f=WoWTranslator_OnHoldKey; WoWTranslator_OnHoldKey=function(s) print(s); f(s) end`.
10. Pack français : **installé le 2026-11-21**. Pour tester frFR → enUS, régler Battle.net > Paramètres du jeu > Langue du texte = Français, relancer le jeu, puis le test 2 (attendu `frFR frFR`). Revenir ensuite à English pour les scénarios [enUS].
11. Conflit EllesmereUIMinimap : décider si une compatibilité avec sa barre de lieu est souhaitée (hors v1).
12. Données T1 : **close le 21/11/2026**. Décision : collecte en jeu par l'API officielle (`C_Map`). Extracteurs CASC et Spoken_Places non retenus (voir §4).
