# Revue 01 — T0 (recherche client) et suite de tests

Date : 2026-11-20. Relecteur : revue stricte, aucune correction appliquée.

Périmètre :
- **A** (auteur T0) : `docs/client-research.md`.
- **B** (auteur des tests) : `tests/` (`run.lua`, `wow_mock.lua`, `specs/`, `fixtures/`, `README.md`) et `docs/test-checklist.md`.

## Méthode

1. Lecture complète de `PLAN.md`, `docs/client-research.md`, `tests/**` et `docs/test-checklist.md`.
2. Vérification des faits de A **en lecture seule** : `D:\World of Warcraft\.build.info`, `_forever_\.flavor.info`, `_forever_\WTF\Config.wtf`, les `.toc` installés, `EllesmereUIMinimap\EUI_Minimap_Apply.lua`, `Spoken\Environment.lua`, `Angleur\Angleur.lua`. Lecture des sources Blizzard du build via `gh api repos/Gethe/wow-ui-source/contents/...?ref=forever` : `Blizzard_FrameXML/Mainline/ZoneText.{xml,lua}`, `Blizzard_FrameXML/Bindings_Camelot.xml`, `Blizzard_FrameXML.toc`, `Blizzard_Minimap/Blizzard_Minimap.toc`, `Blizzard_Minimap/{Mainline,Camelot}/*`, `Blizzard_WorldMap/Blizzard_WorldMap_Mainline.toc`, `Blizzard_SharedMapDataProviders/AreaLabelDataProvider.lua`.
3. Exécution de la suite (LuaJIT 2.1 d'OBS via `luarun.py`) : **15 ok, 84 échecs « addon absent »**, conforme à ce qui est annoncé.
4. **Validation empirique** (hors projet, dans le scratchpad) : j'ai écrit un addon de référence minimal (Core, ZoneText, WorldMap, Config, Data). Il passe **99/99** : la suite est implémentable et ne force pas de conception absurde. J'ai ensuite fait des **mutations** (addons cassés en jeu) pour voir si la suite les attrape :

| Mutation (cassée en jeu) | Résultat suite | Constat |
|---|---|---|
| M1 : module de zone qui fait `hooksecurefunc("ZoneText_OnEvent", …)` au lieu de hooker les FontStrings | tous les tests `module_zonetext` **passent** | B1 |
| M2 : module carte qui n'attend que `ADDON_LOADED "Blizzard_WorldMap"` | **99/99** | B5 |
| M3 : suffixe de niveau reconnu seulement au format du test (`" |c…(1-10)|r"`) | **99/99** | B6 |
| M5 : `ZoneTextFrame:SetScript("OnEvent", …)` (script Blizzard remplacé) | **99/99** | B8 |
| M6 : override écrit dans les SavedVariables à `PLAYER_LOGOUT` (conception valide) | **échoue** (faux négatif) | B7 |
| M7 : `goto` dans `Core.lua` (refusé par Lua 5.1 du jeu) | **99/99** | B4 |

---

## 1. Notes

| | Note |
|---|---|
| **Globale** | **6/10** |
| A — Recherche client (T0) | **6,5/10** |
| B — Tests et checklist | **6/10** |

**A.** Le travail est sérieux et l'essentiel est juste : installation, build `1.60.1.71037`, `Interface 16001`, locale `enUS` seule, `runOnUp`/`keystate`, noms de FontStrings, conflit Ellesmere (tout vérifié). La correction « moteur moderne et pas 3.3.5 » est capitale et bien démontrée. Mais plusieurs points marqués **confirmé** sont faux ou incomplets précisément là où T4/T5 vont coder : chargement de la carte, format du suffixe de niveau, comportement réel de `ZoneText_OnEvent` (liaison par référence, fondu, sous-zone = nom de zone). Une preuve qui était sur le disque (`IsKeyDown` chez Angleur) a été manquée.

**B.** L'infrastructure est remarquable : chargeur `.toc` avec annotations, `hooksecurefunc` post-hook fidèle, isolation des erreurs, état par test, messages « addon absent » propres, hypothèses de contrat explicites. Mais le mock contient une **infidélité bloquante** (B1) qui valide un addon inerte en jeu. D'autres trous laissent passer des addons cassés (B4, B5, B6, B8), et un défaut du mock rejette une conception valide (B7). La checklist donne un résultat attendu faux dès le scénario 1.1.

---

## 2. Constats

Sévérités : **bloquant** (à corriger avant de bâtir dessus), **majeur**, **mineur**, **nit**.

### A — `docs/client-research.md`

**A1 — majeur — `client-research.md:246`, `:330` (repris dans `tests/README.md:53`, `wow_mock.lua:679-707`)**
*Problème* : « La carte est le `WorldMapFrame` moderne, chargé à la demande (addon `Blizzard_WorldMap`) », avec le statut **confirmé**. Or `Blizzard_WorldMap/Blizzard_WorldMap_Mainline.toc@forever` n'a **pas** de `## LoadOnDemand` (en-tête : `Title`, `Author`, `RequiredDep` seulement). La carte est donc très probablement chargée au démarrage, **avant** notre addon. Un module qui n'attend que `ADDON_LOADED "Blizzard_WorldMap"` ne s'accrochera jamais (voir B5).
*Correction attendue* : passer le statut à « non confirmé, probablement chargé au démarrage », citer le `.toc`. Ajouter au §8 : `/run print(WorldMapFrame, C_AddOns.IsAddOnLoaded("Blizzard_WorldMap"), C_AddOns.IsAddOnLoadOnDemand("Blizzard_WorldMap"))` juste après connexion, sans ouvrir la carte. Au §7 T5, écrire « tester `WorldMapFrame` **d'abord** au chargement, sinon `ADDON_LOADED` ».

**A2 — majeur — `client-research.md:251`, `:261`**
*Problème* : format du suffixe de niveau imprécis et incohérent (`" (10-20)"` à la ligne 251, `|c…(min-max)|r` à la ligne 261). Le code réel (`AreaLabelDataProvider.lua@forever`, `AreaLabelFrameMixin:OnUpdate`, lignes 89-105) fait `name..color.." ("..min.."-"..max..")"..FONT_COLOR_CODE_CLOSE`. On obtient `"Elwynn Forest|cffRRGGBB (1-10)|r"` : **l'espace est à l'intérieur** du code couleur. Il existe aussi une variante à un seul niveau, `" (60)"`, et le suffixe n'apparaît que si `C_Map.GetMapLevels` renvoie des niveaux. La source (fichier et lignes) n'est pas citée.
*Correction attendue* : citer `AreaLabelDataProvider.lua` lignes 89-105 et donner les deux formats exacts. Préciser que `EvaluateLabels` (ligne 211) fait `Name:SetText(name)` et que `ClearAllLabels` fait `Name:SetText("")` (ligne 236).

**A3 — majeur — `client-research.md:214-229`, `:218`**
*Problème* : la description de `ZoneText_OnEvent` est incomplète sur des points qui conditionnent T4 :
1. `ZoneText.xml@forever` déclare `<OnEvent function="ZoneText_OnEvent"/>`. La fonction est **liée par référence au chargement** : un `hooksecurefunc("ZoneText_OnEvent", …)` n'a **aucun effet** sur le frame. Cet avertissement manque, alors que c'est le piège n° 1.
2. `ZoneTextString:SetText` n'est appelé que si la zone a changé ou sur `ZONE_CHANGED_NEW_AREA` (`ZoneText.lua`, `ZoneText_OnEvent`).
3. Quand la sous-zone est vide et que la zone n'a pas changé, `subzoneText = zoneText` : **`SubZoneTextString` reçoit le nom de la zone** si `ZoneTextFrame` n'est pas affiché.
4. Les deux frames sont des `FadingFrame` (0,5 + 1 + 2 s) : hors de cette fenêtre, la traduction de `ZoneTextString` est invisible.
5. `SetZoneText` utilise `C_PvP.GetZonePVPInfo`.

*Correction attendue* : ajouter ces cinq points au §5.1 avec la source (fichier et fonction), et au §7 : « ne jamais hooker `ZoneText_OnEvent` ; hooker les FontStrings ou utiliser `HookScript` ».

**A4 — mineur — `client-research.md:317`, `:327`, `:344`**
*Problème* : « L'existence d'`IsKeyDown` […] n'est pas confirmée ». Pourtant, `_forever_\Interface\AddOns\Angleur\Angleur.lua:92` (addon chargé en camelot via `Angleur_Camelot.toc`) fait `if IsKeyDown(keybind) == false then`, sur une touche liée. C'est une preuve sur disque, manquée.
*Correction attendue* : citer Angleur (lignes 77, 92, 400) et passer à « existe (usage tiers en Forever) ; comportement avec modificateurs non confirmé ».

**A5 — mineur — `client-research.md:287`**
*Problème* : l'existence d'`issecretvalue` est justifiée par Spoken. Mais `Spoken\Environment.lua:36-38` dit explicitement « Clients without secrets have no issecretvalue » et fait `rawget(_G, "issecretvalue")` : ce n'est donc pas une preuve. Rien non plus sur la **sémantique** des valeurs secrètes (ce que renvoie `type()`, quelles opérations lèvent une erreur : comparaison, indexation, `#`), dont dépendent `WT.Translate` et le mock (B3).
*Correction attendue* : citer un fichier `Blizzard_APIDocumentationGenerated` du build qui déclare `issecretvalue`, ou passer en « non confirmé » (test n° 4 du §8). Ajouter un paragraphe sur les opérations interdites, sourcé ou marqué non confirmé.

**A6 — mineur — `client-research.md:232`, `:238`**
*Problème* : la source de la minimap ne mentionne pas les surcharges camelot effectivement chargées (`[Game]\Minimap.lua`, `[Game]\MinimapZoneTextButton.lua`, d'après `Blizzard_Minimap.toc@forever`). L'appelant de `Minimap_Update()` (« sur `ZONE_CHANGED*` reçus par `MinimapCluster` ») n'est pas cité (fichier, fonction), alors que `Mainline/Minimap.lua` ne l'appelle qu'à sa définition (ligne 169).
*Correction attendue* : citer précisément l'appelant (fichier et ligne) et lister les surcharges `[Game]` camelot.

**A7 — mineur — `client-research.md:78` (critère de PLAN) / §5.4 / §8**
*Problème* : PLAN définit T0 comme fait « quand T2 à T6 n'ont plus rien à deviner ». T6 reste entièrement à deviner (`EncounterJournal`, Group Finder et `RaidInfoFrame` non confirmés), la perte de focus (PLAN:93) n'a reçu aucune réponse (« aucun événement connu », sans source), et les 12 vérifications en jeu ne sont pas faites.
*Correction attendue* : marquer explicitement T0 « partiel », avec la liste des décisions bloquées pour T6 et la perte de focus. Ajouter une ligne : « il n'existe pas d'événement de perte de focus clavier dans l'API (vérifié dans `APIDocumentationGenerated`) », ou bien le nom de l'événement s'il existe.

**A8 — nit — `client-research.md:310`**
Le gabarit fixe `BINDING_NAME_WOWTRANSLATOR_HOLD` en français alors que le client est enUS. Écrire directement la version localisée selon `GetLocale()`.

**A9 — nit — `client-research.md:297`**
« Le raccourci apparaît dans Options > Raccourcis > section de l'addon » : sur le client moderne, il peut apparaître sous une catégorie « AddOns ». Le dire, puisque la checklist (0.4) en dépend.

### B — `tests/` et `docs/test-checklist.md`

**B1 — bloquant — `tests/wow_mock.lua:646`**
*Problème* : `ztf:SetScript("OnEvent", function(...) return env.ZoneText_OnEvent(...) end)` résout la globale **au moment de l'appel**. En jeu, `<OnEvent function="ZoneText_OnEvent"/>` lie la référence au chargement. Prouvé par la mutation M1 : un module qui fait `hooksecurefunc("ZoneText_OnEvent", …)` passe tous les tests `module_zonetext`, alors qu'il serait inerte en jeu. Le mock donne ici un feu vert à un addon cassé.
*Correction attendue* : `ztf:SetScript("OnEvent", env.ZoneText_OnEvent)` (référence capturée à la création), comme le XML. Ajouter un test dans `mock_selftest` : après `hooksecurefunc("ZoneText_OnEvent", h)`, un `SetZone` **n'appelle pas** `h`. Faire de même pour tout futur handler XML `function=`. `Minimap_Update`, appelé par nom depuis du Lua, peut rester dynamique.

**B2 — majeur — `tests/wow_mock.lua:629-642`, `specs/module_zonetext_spec.lua:59-62`**
*Problème* : le `ZoneText_OnEvent` du mock diverge du vrai (A3) :
- `ZoneTextString:SetText` à chaque événement ;
- `SubZoneTextString` ne reçoit jamais le nom de zone ;
- pas de `zoneText` mémorisé, pas d'`IsShown`, pas de fondu ;
- `ZoneText_Clear` vide aussi `PVPArenaTextString` (ligne 633), contrairement au vrai.

Conséquence : `module_zonetext_spec.lua:61` attend `SubZoneTextString == ""` après la sortie d'une sous-zone. En jeu, il contiendrait `"Elwynn Forest"`, à traduire en `"Forêt d'Elwynn"`. Ce test fige donc un comportement qui n'existe pas.
*Correction attendue* : porter l'algorithme réel de `ZoneText.lua@forever` (`self.zoneText`, `showZoneText`, `IsShown`, `FadingFrame_Show` simulé par `Show` puis `Hide` après `Tick`) et corriger `ZoneText_Clear` (trois chaînes). Réécrire le test 53-67 : sous-zone quittée avec `ZoneTextFrame` caché, `SubZoneTextString` affiche la zone traduite pendant l'appui puis la zone d'origine au relâchement.

**B3 — majeur — `tests/wow_mock.lua:326-342`, `specs/core_translate_spec.lua:51-61`, `specs/hooks_spec.lua:92-100`**
*Problème* : le modèle des valeurs secrètes ne piège pas les erreurs réelles :
- le proxy est un `userdata` : un simple `if type(text) ~= "string"` passe le test sans jamais appeler `issecretvalue` ;
- les chaînes marquées par `MakeSecret` acceptent `==`, `#`, `..` et l'indexation sans erreur.

À ma connaissance, en 12.x une valeur secrète garde son type (`"string"`) et c'est la comparaison ou l'indexation par du code non sécurisé qui lève une erreur (à confirmer, voir A5). Un `Translate` qui fait `if text == "" then` ou `dict[text]` **avant** `issecretvalue` passe la suite mais peut lever une erreur en jeu.
*Correction attendue* :
1. Dans l'env, envelopper `type` pour qu'un proxy secret renvoie `"string"`.
2. Faire passer les proxies par `SetText`/`GetText` dans les hooks (test : Blizzard pose un proxy pendant l'appui, et au moment d'`Apply`).
3. Documenter dans `README.md` la limite résiduelle (`==` et l'indexation ne sont pas interceptables en Lua 5.1) et la règle imposée : `issecretvalue` est testé **en premier**. Ajouter un test statique qui le vérifie sur `WT.Translate` (instrumentation de `issecretvalue` : il doit être appelé pour chaque entrée).

**B4 — majeur — `tests/run.lua:49-57`, `tests/README.md:15`**
*Problème* : « `luajit tests/run.lua` marche aussi (même dialecte) » est faux. LuaJIT 2.1 (celui utilisé ici) accepte `goto`/`::label::`, `\u{…}`, `\x41`, `1LL` et expose `bit`, alors que le Lua 5.1 du jeu les refuse. J'ai vérifié chacun de ces cas avec le DLL d'OBS. Le garde-fou `_VERSION ~= "Lua 5.1"` est inopérant, car LuaJIT renvoie `"Lua 5.1"`. Mutation M7 : un `goto` dans `Core.lua` passe 99/99.
*Correction attendue* : ajouter un test `structure` qui scanne tous les `.lua` de l'addon et les corps de `Bindings.xml` (commentaires et chaînes retirés) à la recherche de `goto`, `::%w+::`, `\u{`, `\x`, `%d+U?LL`, `//`, `bit32`, `utf8%.`, `table%.unpack`, `table%.pack`, `_ENV`, `%f[%w]load%(`. Dans `run.lua`, afficher un avertissement si `jit` est défini. Corriger `README.md:15`.

**B5 — majeur — `tests/wow_mock.lua:679-707`, `specs/module_worldmap_spec.lua` (toute la spec)**
*Problème* : la suite ne teste que le cas « carte chargée **après** l'addon ». Or `Blizzard_WorldMap` n'est pas en LoadOnDemand (A1), donc le cas réel est probablement l'inverse. Mutation M2 : un module qui n'écoute qu'`ADDON_LOADED` passe 99/99.
*Correction attendue* : ajouter une option de boot `worldMapPreloaded = true` qui crée `WorldMapFrame` dans `M.new`, **avant** le chargement de l'addon et sans `ADDON_LOADED` ultérieur. Exécuter chaque test de `module_worldmap` dans les deux modes. Mettre à jour `README.md:53`.

**B6 — majeur — `specs/module_worldmap_spec.lua:44-56`**
*Problème* : le format testé `"Elwynn Forest |cff00ff00(1-10)|r"` n'est pas celui du client, qui produit `"Elwynn Forest|cff00ff00 (1-10)|r"` (A2). Mutation M3 : un module qui ne reconnaît que le format du test passe 99/99 mais échouerait en jeu. Manquent aussi le format à un niveau `" (60)"` et l'effacement `Name:SetText("")` par `ClearAllLabels` pendant l'appui.
*Correction attendue* : tester le format réel exact, la variante à un niveau et le libellé vidé (`""` conservé, pas de texte périmé au relâchement). Garder éventuellement l'ancien format comme cas supplémentaire.

**B7 — majeur — `tests/wow_mock.lua:767-771`, `specs/config_spec.lua:61-67`**
*Problème* : `mock.SaveVariables()` copie l'état sans déclencher `PLAYER_LEAVING_WORLD` ni `PLAYER_LOGOUT`. En jeu, `/reload` et la déconnexion déclenchent ces événements **avant** l'écriture des SavedVariables. Mutation M6 : un addon valide qui écrit sa config à `PLAYER_LOGOUT` échoue au test de persistance. C'est une sur-spécification imposée par un défaut du mock. De plus, la copie profonde garde fonctions et userdata, alors que le client ne sérialise que des chaînes, nombres, booléens et tables.
*Correction attendue* : remplacer par `mock.Logout()` (ou `mock.Reload()`), qui déclenche `PLAYER_LEAVING_WORLD` puis `PLAYER_LOGOUT`, puis sérialise avec le filtrage réel. Ajouter un `mock_selftest` correspondant.

**B8 — majeur — `specs/hooks_spec.lua:25-36`**
*Problème* : « scripts des frames Blizzard non remplacés » vérifie seulement que `OnEvent ~= nil`. Mutation M5 : `ZoneTextFrame:SetScript("OnEvent", …)` passe. Or PLAN interdit tout remplacement (« jamais de remplacement de fonction »), et c'est une source classique de taint.
*Correction attendue* : mémoriser dans `mock.originals` la référence de chaque script Blizzard (`OnEvent`, `OnUpdate`) et exiger soit l'égalité, soit un wrapper `HookScript` dont la chaîne `orig` remonte à l'original. Le `HookScript` du mock enregistre déjà `hookWrappers` (`wow_mock.lua:510`) : il suffit de remonter la chaîne.

**B9 — mineur — `specs/core_keybinding_spec.lua:77-84`, `wow_mock.lua:351-358`**
*Problème* : le test « avec `IsKeyDown` » vérifie seulement que le filet **ne coupe pas** pendant l'appui. Rien ne vérifie qu'il **sert** : touche relâchée sans `up`, puis `Tick`, puis désactivation. Le mock ne simule pas non plus un `up` perdu (`keysDown.BOUND = false` sans exécuter le binding). Par ailleurs `GetBindingKey` renvoie `nil` sans l'option, alors qu'une touche est liée en jeu. Enfin, A4 montre qu'`IsKeyDown` existe, donc l'hypothèse « absent par défaut » est caduque.
*Correction attendue* : ajouter `mock.LoseKeyUp()` (relâchement physique sans binding) et un test conditionnel : si l'addon installe un filet (`OnUpdate` actif pendant l'appui), il désactive au plus tard en N ticks. Exposer `IsKeyDown` par défaut, conformément à A4, et garder un mode « sans IsKeyDown ».

**B10 — mineur — `tests/README.md:12`, `:30`, `docs/test-checklist.md:6`**
*Problème* : la commande documentée `lua5.1 tests/run.lua` ne fonctionne pas sur la machine du projet. Le seul moyen réel (`luarun.py` sur le `lua51.dll` d'OBS) vit dans un scratchpad éphémère, hors dépôt. La suite n'est donc pas reproductible.
*Correction attendue* : versionner le lanceur (par exemple `tools/luarun.py`, avec le chemin du DLL en argument ou en variable d'environnement), le documenter dans `README.md` et la checklist, et signaler la réserve LuaJIT (B4).

**B11 — mineur — `tests/README.md:77`**
*Problème* : « Les specs `module_*` et `config` sont **ignorées** (`skip`) » est faux aujourd'hui : elles échouent avec « addon absent » (voir l'exécution : 0 ignoré). Le `skip` ne s'applique qu'une fois le `.toc` présent.
*Correction attendue* : reformuler (« ignorées dès que le `.toc` existe mais ne liste pas le fichier ; en échec tant que l'addon est absent »).

**B12 — mineur — `specs/hooks_spec.lua:49`, `specs/mock_selftest_spec.lua:50-51`**
*Problème* : `T.isNil(fs:GetText())` après `SetText(nil)` vérifie une convention **du mock**, pas l'addon (touche relâchée). C'est un test tautologique, et le comportement réel (`nil` ou `""`) n'est pas confirmé, alors que `T.isEmpty` existe justement pour ça (`run.lua:120-123`).
*Correction attendue* : utiliser `T.isEmpty` dans `hooks_spec`. Dans le selftest, documenter que la valeur réelle est non confirmée.

**B13 — mineur — cas manquants dans les specs**
- Apply alors que `ZoneTextString` n'a jamais reçu de texte (`nil`) : la mise en place du mock (`wow_mock.lua:623-628`) ne pose aucun texte initial, alors qu'en jeu `SubZoneText_OnLoad` fait `SubZoneTextString:SetText(GetSubZoneText())` **avant** le chargement des addons. Le mock doit l'imiter, et un test doit couvrir le texte posé avant le hook.
- `/wt lang` changé **pendant** l'appui : cohérence d'affichage et de restauration.
- Un autre addon qui appelle `SetText` sur la même FontString pendant l'appui (Ellesmere, par exemple) : le relâchement doit restaurer son texte, pas l'ancien.
- Assumption 2 (`README.md:84`), « l'ordre Core/Data n'importe pas » : aucun test ne charge les fixtures **avant puis après** Core.

*Correction attendue* : un test par point.

**B14 — mineur — `specs/data_spec.lua:6-16`, `:39`**
*Problème* : PLAN T3 exige « capitales, donjons et raids, zones de départ ». L'échantillon ne contient ni raid (Molten Core / Cœur du Magma, par exemple) ni la plupart des zones de départ (Dun Morogh, Teldrassil, Mulgore, Tirisfal Glades / Clairières de Tirisfal). Le seuil `>= 50` est arbitraire, sans lien avec le rapport de couverture de T1. Les collisions (PLAN T1) ne sont pas testées : un nom frFR qui viendrait de deux noms enUS différents.
*Correction attendue* : compléter l'échantillon avec au moins un raid et les zones de départ. Remplacer le seuil par une borne tirée du rapport de T1, ou la justifier. Ajouter un test qui vérifie que les deux tables sont des inverses l'une de l'autre, sauf pour les collisions listées.

**B15 — mineur — `docs/test-checklist.md:34-36`**
*Problème* : 1.1 attend que « le texte de zone **et** la minimap affichent Hurlevent » pendant l'appui. En jeu, le grand texte central a disparu en fondu environ 3,5 s après l'arrivée (A3) : le testeur notera un faux KO.
*Correction attendue* : 1.1 doit porter sur la **minimap** seulement, et renvoyer au 1.3 pour le grand texte (à faire dans les 3 s qui suivent le franchissement).

**B16 — mineur — `docs/test-checklist.md:94-97`, `:105-121`**
*Problème* : aucun scénario **[frFR]** pour la carte du monde (survol, suffixe de niveau en sens inverse). Aucune section T6 (Instances), alors que PLAN T8 couvre T3-T7. Pas de cas « raccourci avec modificateur » (Shift+touche, modificateur relâché en premier), alors que c'est un cas classique de `up` perdu.
*Correction attendue* : ajouter 6.x [frFR], une section T6 « à activer si T6 est livré », et un scénario « modificateur relâché avant la touche ».

**B17 — nit — `docs/test-checklist.md:25-27`**
« section **WoWTranslator** » : ajouter « ou sous la catégorie AddOns » (A9).

**B18 — nit — `tests/wow_mock.lua:633`, `:385`, `:248`**
- `ZoneText_Clear` vide quatre chaînes au lieu de trois (couvert par B2).
- `GetZonePVPInfo` est une globale au lieu de `C_PvP.GetZonePVPInfo`.
- `env.string = string` partage la vraie table : un addon qui la modifierait polluerait le lanceur et les tests suivants. Utiliser une copie superficielle, comme pour `table` et `math`.

**B19 — nit — `tests/run.lua:76-80`**
`where()` suppose une profondeur fixe de 4. Pour les échecs issus de `T.noLuaErrors` appelé depuis `T.boot`, l'emplacement affiché est dans `run.lua`, pas dans la spec. Remonter la pile jusqu'au premier cadre hors de `run.lua`.

### Hors A/B — incohérences de `PLAN.md` à arbitrer par le coordinateur

- `PLAN.md:4` : « client Lua 5.1, numéro d'interface à confirmer » est périmé (16001 et moteur moderne, d'après T0).
- `PLAN.md:104` (T5 : « titre de la carte ») contredit `client-research.md:250` et l'hypothèse 13 de `tests/README.md` (ne pas traduire le titre). Le titre n'est pas un nom de lieu : il faut corriger PLAN.
- `PLAN.md:93` (reset sur « perte de focus ») n'a ni événement identifié (A7) ni test (`tests/README.md:92`). Il faut décider explicitement : filet `IsKeyDown` ou exigence abandonnée.
- `PLAN.md:41` : une globale nommée `WT` (deux lettres) risque une collision avec un autre addon. Envisager `WoWTranslator` en globale et `WT` comme alias local. Cela changerait `run.lua:270`, l'hypothèse 1 de `tests/README.md` et la checklist 0.3.

---

## 3. Ce qu'il faut changer pour atteindre 9/10

**A (T0)**
1. Corriger A1 (carte non LoadOnDemand), A2 (format exact du suffixe, deux variantes) et A3 (liaison par référence de `ZoneText_OnEvent`, fondu, sous-zone = nom de zone), avec fichier et ligne cités.
2. Mettre à jour les statuts « confirmé » selon des preuves réelles (A4 `IsKeyDown` via Angleur, A5 `issecretvalue` et sa sémantique).
3. Déclarer T0 « partiel » tant que les points T6 et perte de focus ne sont pas tranchés (A7).

**B (tests)**
1. **B1** corrigé, avec un selftest qui prouve que `hooksecurefunc("ZoneText_OnEvent")` est inopérant.
2. `ZoneText_OnEvent` du mock porté depuis la source réelle, et le test de sous-zone réécrit (B2).
3. Lint de syntaxe Lua 5.1 stricte dans `structure`, et README corrigé sur LuaJIT (B4).
4. Carte préchargée testée (B5), format réel du suffixe (B6), `Logout`/`Reload` fidèle (B7), scripts Blizzard comparés par référence (B8).
5. Modèle de valeurs secrètes renforcé et limites documentées (B3).
6. Lanceur versionné et reproductible (B10), README juste sur `skip` (B11).
7. Checklist corrigée : 1.1 minimap, scénarios [frFR] pour la carte, section T6, modificateurs (B15, B16).
8. Relancer les mutations M1 à M7 du tableau ci-dessus : M1, M2, M3, M5 et M7 doivent **échouer**, M6 doit **passer**.

Les autres points (B9, B12-B14, B17-B19, A6, A8, A9) relèvent du 9/10 « avec des nits » s'ils restent, mais B9 et B13 devraient être faits avant T4.
