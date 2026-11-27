# Tests hors jeu de WoWTranslator

Suite automatisée et sans dépendance, qui exécute l'addon dans un **mock de l'API WoW** sous Lua 5.1. Les tests sont écrits **avant** le code (test-first) et décrivent le comportement attendu de T2 (Core), T3 (données), T4 (ZoneText), T5 (WorldMap) et T7 (Config).

Client visé : **WoW: Forever 1.60.1 (71037), `## Interface: 16001`, moteur moderne (Mainline), type de jeu `camelot`**. Voir `docs/client-research.md`.

## Lancer

Depuis la racine du projet.

**Sur la machine du projet** (Windows, sans `lua` installé) :

```
python tests/tools/luarun.py tests/run.lua
```

`tests/tools/luarun.py` charge une **DLL Lua 5.1 déjà présente** via `ctypes`. Rien n'est téléchargé ni installé. Ordre de recherche de la DLL :
1. l'option `--dll CHEMIN` (avant le script) ;
2. la variable `WT_LUA_DLL` ;
3. des emplacements connus. Aujourd'hui, c'est le LuaJIT d'OBS : `D:\obs-studio\bin\64bit\lua51.dll`.

**Avec un interpréteur** : `lua5.1 tests/run.lua` ou `luajit tests/run.lua`. Lua 5.2 et plus ne sont pas supportés, faute de `setfenv`.

> **Réserve LuaJIT.** LuaJIT (dont la DLL d'OBS) accepte des constructions que le Lua 5.1 du jeu refuse. Le lanceur l'annonce, et la spec `structure` passe tout le code de l'addon (fichiers `.lua` du `.toc` et corps de `Bindings.xml`) au **lint Lua 5.1 strict** (`M.lint51`). Il signale `goto`, `::label::`, `//`, `\x`, `\u{}`, `\z`, `1LL`, `0x10LL`, `1i`, `0x1p4`, `& | ~ << >>`, `bit32`, `bit.tohex/rol/ror/bswap/tobit`, `utf8`, `table.unpack/pack/move`, `math.type`, `string.pack`, `coroutine.isyieldable`, `_ENV`, `load(`, `require`, `jit.` et `ffi`.

Options de `run.lua` :

| Option | Effet |
|---|---|
| `core_keybinding` (texte libre) | ne lance que les tests dont « spec + nom » contient ce texte |
| `--list` | liste les tests sans les exécuter |
| `--root=CHEMIN` | racine du projet |
| `--addon=DOSSIER` | dossier de l'addon à tester (défaut : `RACINE/WoWTranslator`) ; utilisé par les mutants |
| `--oracle` | l'addon testé est l'oracle `tests/mutants/reference` : les garde-fous anti-oracle doivent échouer et s'affichent `xfail` (voir plus bas) |
| `WT_INTERFACE=16001` | numéro `## Interface` attendu |
| `WT_MIN_ENTRIES=200` | nombre minimal d'entrées par dictionnaire (provisoire, à aligner sur le rapport de couverture de T1) |

Code de sortie : `0` si tout passe, `1` en cas d'échec, `2` si le lanceur ne peut pas démarrer. `luarun.py` renvoie aussi `3` pour une erreur Lua non rattrapée et `4` s'il ne trouve pas de DLL.

État au 2026-11-21 : **162 tests**.
- Dans le projet : **50 ok** (28 `mock_selftest` + 17 `collector` + 5 `data` sur tables synthétiques) et **135 en échec**, tous avec « `WoWTranslator/WoWTranslator.toc` introuvable ». C'est attendu tant que l'addon n'est pas écrit.
- Contre l'implémentation de référence, avec `--oracle --addon=tests/mutants/reference/WoWTranslator` : **160 ok, 0 échec, 2 `xfail`** (les garde-fous anti-oracle, voir ci-dessous), code de sortie 0.

## Non-régression de la suite : référence et mutants

```
python tests/mutants/run_mutants.py        # référence + tous les mutants
python tests/mutants/run_mutants.py -v M1  # détail d'un mutant
```

- `tests/mutants/reference/WoWTranslator/` est une **implémentation de référence**, qui sert **uniquement d'oracle de test**. Elle prouve que la suite est satisfaisable et sert de base aux mutants. Ce n'est **pas** le code de l'addon. Ses aides internes sont rangées sous `WT._ref` (hors contrat) et ses données `Data/` sont synthétiques.
- **Règle (PLAN.md) : T2 à T7 ne partent pas de l'oracle.** Ils n'ouvrent pas `tests/mutants/reference` comme base de code : ni copie, ni données, ni API `_ref`. Ils codent depuis le contrat de PLAN.md et les specs.
- **Garde-fous** : la suite **refuse l'oracle lui-même comme addon**. Ces tests sont déclarés avec `T.oracleGuard` au lieu de `T.test` :
  - `structure` : « l'addon ne reprend pas l'oracle de test » échoue si un fichier de l'addon (`.lua` ou `.toc`) contient `IMPLEMENTATION DE REFERENCE`, `oracle de test` ou `(reference de test)`, **ou** si `WoWTranslator._ref` existe après le chargement. Ce dernier point attrape l'oracle même quand ses commentaires ont été retirés ;
  - `data` : « données réelles » échoue sur le marqueur ou sur des entrées synthétiques `Zone N` / `Zone FR N`.
- **Option `run.lua --oracle`** : elle déclare que l'addon testé **est** l'oracle. Chaque `T.oracleGuard` en échec s'affiche alors `xfail` (échec attendu) et n'est pas compté comme échec. Un garde-fou qui **passe** sous `--oracle` devient un échec (« garde-fou non déclenché »). Le code de sortie vaut 0 quand seuls les garde-fous échouent. Sans `--oracle` (cas normal), les garde-fous sont des tests ordinaires.
- `run_mutants.py` lance toujours `run.lua --oracle`. Il ne dépend donc d'aucun nom de test. La référence est conforme si elle obtient 0 échec réel et au moins un `xfail`, et chaque mutant est jugé sur ses échecs réels.
- `tests/mutants/patches/<ID>.patch` contient un mutant par fichier : en-tête `# Description:` et `# Expect: pass|fail`, puis des opérations `@@ edit` (remplacement exact), `@@ replace-file` ou `@@ append`.
- Le script copie la référence dans un dossier temporaire, applique le patch, lance `run.lua --oracle --addon=…`, puis compare le statut attendu au statut obtenu. Code de sortie `0` si tout est conforme.

| Id | Mutant | Attendu |
|---|---|---|
| M1 | module de zone hooké sur la globale `ZoneText_OnEvent` | fail |
| M2 | carte accrochée seulement sur `ADDON_LOADED` | fail |
| M3 | suffixe de niveau au mauvais format | fail |
| M5 | `SetScript` sur `ZoneTextFrame` | fail |
| M6 | config écrite seulement à `PLAYER_LOGOUT` (conception valide) | **pass** |
| M7 | `goto` dans `Core.lua` | fail |
| N1 | `Translate` compare ou indexe **avant** `issecretvalue` | fail |
| N2 | filet de sécurité via `C_Timer.NewTicker` (conception valide) | **pass** |
| K1 | filet qui ne sonde que la **première** touche liée | fail |
| S1 | `issecretvalue` appelé sans `pcall` | fail |
| E1 | pas de filet de sécurité | fail |
| E2 | sondage `IsKeyDown` permanent | fail |
| E3 | modificateurs non retirés | fail |
| E4 | `Translate` sans `issecretvalue` | fail |
| E5 | pas de garde anti-récursion | fail |
| E6 | `Apply`/`Restore` sans `pcall` | fail |
| E7 | restauration d'un original périmé | fail |
| Z14 | `down` n'arme le filet que sur la transition inactif → actif | fail |
| R31 | le hook mémorise un secret et `Restore` le réécrit | fail |
| X10 | erreur de `pcall(issecretvalue)` traitée comme non secrète | fail |
| X23 | filet jamais armé | fail |
| X23b | filet armé par tout `SetActive(true)` (pas seulement par la touche) | fail |
| X26 | `rawget(dict, text)` avant `issecretvalue` | fail |
| Y4 | module carte sans garde secret (`text:match` sur la valeur brute) | fail |
| Y6 | `issecretvalue` absent traité comme « secret » | fail |
| Y7 | erreur de module avalée (pas de `geterrorhandler`) | fail |

Tout changement de la suite doit garder ce tableau conforme.

## Fichiers

| Fichier | Rôle |
|---|---|
| `run.lua` | lanceur, assertions (`T.eq`, `T.ok`, `T.isNil`, `T.isEmpty`, `T.noError`, `T.raises`, `T.skip`…) et aides (`T.boot`, `T.spyModule`, `T.takeErrors`, `T.requireTocFile`) |
| `wow_mock.lua` | mock de l'API, code FrameXML porté, chargeur d'addon, garde des dictionnaires, lint Lua 5.1 |
| `tools/luarun.py` | hôte Python : `run.lua` sur une DLL Lua 5.1 existante |
| `mutants/` | référence (oracle), patches des mutants, `run_mutants.py` |
| `fixtures/Zones_*.lua` | petits dictionnaires au format de `Data/` (remplacent les vraies données pour le Core et les modules) |
| `fixtures/FakeAddon/` | mini-addon de test du chargeur |
| `specs/*_spec.lua` | spécifications |

Fixtures : `Stormwind City`↔`Hurlevent`, `Orgrimmar`↔`Orgrimmar` (nom identique), `Ironforge`↔`Forgefer`, `The Deadmines`↔`Les Mortemines`, `Elwynn Forest`↔`Forêt d'Elwynn`, `Goldshire`↔`Comté-de-l'Or`, `Trade District`↔`Quartier commerçant`.

## Le mock (`wow_mock.lua`)

- **Environnement isolé** par test (`setfenv`), avec la bibliothèque du client seulement : pas d'`io`, d'`os`, de `debug` ni de `require`.
  - `string`, `table` et `math` sont des copies ;
  - `coroutine` est limité à l'API 5.1 ;
  - `bit` est limité à `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift` et `mod` (pas les extras LuaJIT).
- **Chargement comme le client** :
  - `.toc` avec ses annotations `[AllowLoadTextLocale]`, `[AllowLoadGameType]` et `[ExcludeLoadGameType]` (type de jeu `camelot`) ;
  - `local addonName, ns = ...` avec le même `ns` pour tous les fichiers ;
  - fichiers XML `<Script>` / `<Include>` ;
  - SavedVariables, puis `ADDON_LOADED` ;
  - `Bindings.xml` lu à part.
- **Connexion** : `VARIABLES_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`. **Déconnexion / `/reload`** : `mock.Logout()` déclenche `PLAYER_LEAVING_WORLD` puis `PLAYER_LOGOUT`, puis écrit les SavedVariables avec le filtrage du client.
- **Erreurs** : une erreur de script part au gestionnaire `geterrorhandler()` sans arrêter les autres frames. Un test qui laisse des erreurs non vérifiées échoue (`T.takeErrors` sert aux erreurs attendues).
- **Frames** : `CreateFrame`, `RegisterEvent` (événement inconnu refusé, liste `M.KNOWN_EVENTS`), `SetScript`/`GetScript`/`HookScript`, handlers `(self, event, ...)`, `Show`/`Hide`/`IsShown`/`IsVisible`.
- **Temps** : `mock.Tick(dt)` / `mock.Wait(s)` déclenchent les OnUpdate des frames visibles et `C_Timer`. `C_Timer` fournit `After`, `NewTimer` et `NewTicker(interval, cb, iterations)`, avec des objets `:Cancel()` / `:IsCancelled()`, et le callback reçoit l'objet. Au plus un déclenchement par timer et par Tick.
- **FontString** : `SetText` (un nombre est converti, une table lève une erreur, un secret est accepté). `GetText` ne renvoie **jamais `nil`**, mais `""` pour un texte vide (`SimpleFontStringAPIDocumentation` : `cstring, Nilable = false`). `SetText(nil)` donne donc `""`, ce qui est probable mais non confirmé en jeu. `SetFormattedText` ne passe pas par `SetText`.
- **`hooksecurefunc`** : vrai post-hook. Une récursion non gardée provoque un vrai `stack overflow`. `mock.derivesFrom(f, orig)` remonte une chaîne de hooks.
- **FrameXML porté depuis `wow-ui-source@forever` (71037)** :
  - `ZoneText.lua` (`SetZoneText`, `ZoneText_OnLoad/OnEvent`, `SubZoneText_OnLoad`, `ZoneText_Clear`), `FadingFrame.lua`, `Minimap_Update`, et `MinimapClusterMixin:OnEvent` (appelle `Minimap_Update` pour **tous** les événements, `SETTINGS_LOADED` compris) ;
  - scripts XML `function=` liés **par référence** : `hooksecurefunc("ZoneText_OnEvent")` n'a aucun effet ;
  - sous-zone quittée avec le cadre caché : `SubZoneTextString` reçoit le nom de la zone ;
  - fondu de 3,5 s ;
  - textes posés à l'OnLoad, avant les addons.
- **Minimap** : `MinimapZoneText` global, `MinimapCluster.ZoneTextButton`, pas de `MinimapZoneTextButton` global.
- **Carte** :
  - par défaut, `WorldMapFrame` existe **avant** l'addon (`worldMapPreloaded = false` pour le mode « à la demande ») ;
  - `mock.WorldMapHover(nom, min, max, couleur)` produit les formats réels `"Nom|cffRRGGBB (a-b)|r"` et `"Nom|cffRRGGBB (n)|r"` ;
  - `WorldMapHover(nil)` imite `ClearAllLabels` ;
  - le fil d'Ariane (`NavBar`) existe dans le mock mais est **hors v1** (PLAN.md T5) : aucun test.
- **Touches liées et filet** :
  - `GetBindingKey("WOWTRANSLATOR_HOLD")` renvoie **jusqu'à deux** touches : `opts.boundKeys = { "F6", "BUTTON4" }`, ou `opts.boundKey`, défaut `"F6"`. `noBoundKey` = aucune ;
  - touche de base selon `M.baseKey` : `"SHIFT-F6"` → `"F6"`, `"CTRL-SHIFT-F6"` → `"F6"`, `"SHIFT--"` → `"-"` ;
  - `IsKeyDown(base)` renvoie `true`/`false`. `IsKeyDown("SHIFT-F6")` renvoie `nil` (non confirmé) ;
  - `isKeyDownUnknown` = toujours `nil`, `unknownKeys = { BUTTON4 = true }` = `nil` pour ces touches seulement, et `noIsKeyDown` retire la fonction ;
  - `mock.KeyDown(i)` / `KeyUp(i)` agissent sur la i-ème touche et exécutent le binding (le `up` n'est transmis que si `runOnUp="true"`) ;
  - `mock.LoseKeyUp([i])` relâche sans binding (perte de focus) ;
  - `mock.isKeyDownCalls` compte les sondages.
- **Valeurs secrètes** (sémantique 12.x non confirmée) :
  - `mock.NewSecretProxy()` crée une valeur opaque. Pour l'addon, `type()` vaut `"string"`. `..`, `#`, méthode/index, `<`, et `==` entre deux secrets lèvent une erreur ;
  - `mock.MakeSecret("x")` marque une chaîne par valeur ;
  - `issecretvalue` compte ses appels. `opts.issecretErrors = "secret" | "always"` le fait lever une erreur, comme le permettrait `SecretArguments = "AllowedWhenUntainted"`. `opts.noIssecretvalue` le retire (client sans secrets) ;
  - **garde des dictionnaires** : après le chargement de l'addon (juste avant `ADDON_LOADED`), chaque table `WT.data.*` **présente à ce moment** reçoit un `__index`, et le `rawget` de l'environnement est enveloppé. Les deux lèvent une erreur si on cherche une valeur secrète : chaîne marquée **absente** du dictionnaire, ou proxy. `pairs` et les clés présentes ne sont pas affectés ;
  - chaque FontString compte les `SetText` reçus avec une valeur secrète (`m.st(fs).secretSetCount`).
  - **Ce qui est vérifié** :
    - que `issecretvalue` est **appelé** à chaque `Translate` ;
    - que les tables `WT.data.*` d'origine ne sont **jamais** lues avec un secret, ni par indexation directe ni par `rawget` ;
    - qu'une erreur de `issecretvalue` est rattrapée, et que son absence n'empêche pas de traduire ;
    - qu'un module ne **réécrit** jamais un secret.
  - **Ce qui ne l'est pas** :
    - une **copie** ou fusion des dictionnaires (ou un dictionnaire créé après `ADDON_LOADED`) n'est pas surveillée ;
    - l'ordre par rapport à une comparaison `secret == "x"` n'est pas interceptable en Lua 5.1 ;
    - la **mémorisation** d'un secret n'est observable que si elle aboutit à une réécriture.
- **Autres** : `GameTooltip`, `DEFAULT_CHAT_FRAME`, `C_AddOns`, `C_PvP.GetZonePVPInfo`, et `GetBuildInfo` → `1.60.1, 71037, …, 16001`.

Si un test échoue parce qu'il manque au mock une API **qui existe réellement** dans le client 1.60.1, il faut compléter le mock, et non contourner le code.

## Hypothèse de `data_spec` : noms natifs

Un **nom natif** est un nom identique dans les deux langues pour au moins un identifiant (par exemple « Orgrimmar », « Dun Morogh »). Un client frFR qui affiche ce nom n'a rien à traduire.

- Le générateur écrit la liste de ces noms dans `WT.data.native_enUS_frFR` (fichier `Zones_enUS_frFR.lua`) et `WT.data.native_frFR_enUS` (fichier `Zones_frFR_enUS.lua`). Ce ne sont **pas** des entrées de traduction.
- `data_spec` relâche **une seule** règle : une valeur du sens direct qui est un nom natif peut ne pas avoir d'entrée inverse. Partout ailleurs, l'inverse est exigé (`enUS_frFR[k] = v` exige `frFR_enUS[v]`, et `frFR_enUS[v] = k` exige `enUS_frFR[k] = v`, sauf collisions cohérentes).
- Un nom natif ne doit **jamais** avoir d'entrée inverse : `data_spec` échoue si c'est le cas.
- Sans liste native (table absente), aucune exemption : la règle stricte s'applique.
- La liste ne contient que les **noms exemptés** : les noms natifs qui sont valeur d'une entrée directe (cas « collision avec identité »). Les autres noms identiques ne sont pas listés. `data_spec` contrôle : chaque nom listé est valeur d'une entrée directe ; `clé = valeur` ; les deux listes ont les mêmes noms ; aucun nom natif n'a d'entrée inverse ; la liste ne dépasse ni **2 % des entrées directes** (`WT_NATIVE_MAX_RATIO`) ni **30 noms** en valeur absolue (`WT_NATIVE_MAX_COUNT`). Les deux bornes sont provisoires, à recaler sur le premier rapport réel. Des tests négatifs sur tables synthétiques prouvent que chacun de ces contrôles mord ; un test de forme réelle (609 noms traduits, 250 noms identiques, 2 exemptés) doit passer.
- **Limite connue (G24)** : une liste native petite et cohérente qui cache un manque d'entrée inverse (un nom ajouté à tort, valeur d'une entrée directe, sans entrée inverse) passe tous les contrôles. Les seules données ne distinguent pas « natif voulu » d'« inverse oublié ». Le risque est borné par le plafond de taille et par le fait que la liste est produite par le générateur à partir des identifiants identiques (et contrôlée par le selftest contre le rapport « Collisions avec identité »). Ce n'est pas détectable sans les identifiants d'origine.

## Pont figé (`collector`)

`tests/fixtures/collector/Zones_enUS_frFR.lua` et `Zones_frFR_enUS.lua` sont les sorties **figées** de `tools/build_zone_data.py` à partir de `tools/fixtures/WoWTranslatorCollector.lua`. La spec `collector` les relit avec les mêmes invariants que `data_spec`. Le selftest du générateur vérifie qu'elles sont **identiques** à une régénération.

Si une règle du générateur change (ou la fixture), régénérer les deux fichiers :

```
python tools/build_zone_data.py --from-savedvariables tools/fixtures/WoWTranslatorCollector.lua --out-dir tests/fixtures/collector --min-entries 1 --no-overrides
```

puis relancer `python tools/build_zone_data.py --selftest` et la suite.

## Ce que couvre chaque spec

| Spec | Couverture |
|---|---|
| `collector` | l'addon de collecte `WoWTranslatorCollector` (T1) : lots, bloc écrit seulement à la fin, relance et `/reload` en cours, secrets, identifiants inconnus, bornes ; pont vers les invariants de `data_spec` sur `tests/fixtures/collector/` (voir « Pont figé » ci-dessous) |
| `mock_selftest` | le mock : `hooksecurefunc`, liaison par référence, FrameXML porté, FontString (`GetText` jamais nil), événements, minimap, carte, suffixe, secrets (modes d'erreur, garde des dictionnaires), touches (deux touches, `baseKey`), `C_Timer` (ticker, timer, `Cancel`, itérations), `bit`/`coroutine` restreints, `.toc`, lint, chargeur, `Logout`, bindings, slash, isolation |
| `structure` | `.toc`, ordre Core/Modules/Config, **lint Lua 5.1**, `Bindings.xml` (`WOWTRANSLATOR_HOLD`, `runOnUp`, `category`, hors `.toc`), libellés `BINDING_*`, **pas de code de l'oracle dans l'addon**, chargement sans erreur (locales, données, carte), `WoWTranslator` = namespace et pas de globale `WT`, aucune fuite de globales |
| `core_translate` | API, traduction, ordre Core/Data indifférent, nom identique, inconnu, entrées non string, secrets (chaîne marquée, proxy, **pas d'indexation avec un secret**, `issecretvalue` en erreur → `pcall`, traité comme secret ; `issecretvalue` absent → traduction normale), **recherche exacte** (codes couleur et suffixes non retirés), `issecretvalue` appelé, indépendance vis-à-vis de la touche |
| `core_locale` | enUS → frFR, frFR → enUS, mauvais sens, enGB, locale non gérée |
| `core_keybinding` | handler global, `down`/`up`, auto-repeat, `up` orphelin, cycles, keystate inattendu, combat ; **filet** : pas de coupure pendant l'appui, `up` perdu → désactivation en moins d'1 s, aucun sondage hors appui, modificateur, **deux touches** (seconde tenue : pas de coupure), touche `SHIFT--`, `IsKeyDown` → `nil` (jamais de coupure), une touche `false` + une touche `nil` (pas de coupure), **filet armé uniquement par la touche** (`SetActive(true)` seul n'est pas coupé), **chaque `down` arme le filet même si l'état est déjà actif**, désarmé puis réarmé, sans `IsKeyDown`, sans touche liée (jamais de coupure) |
| `core_setactive` | `WT.SetActive` exposé, idempotent, état partagé avec la touche, valeurs non booléennes |
| `core_modules` | `Apply`/`Restore`, plusieurs modules, `IsActive()` pendant `Apply`/`Restore`, isolation des erreurs |
| `core_safety` | `PLAYER_LEAVING_WORLD` / `PLAYER_ENTERING_WORLD`, `up` tardif, nouvel appui |
| `hooks` | aucune globale ni méthode remplacée, scripts Blizzard comparés par référence, `SetText` identique touche relâchée, valeurs étranges, `SetText("")`, anti-récursion, secrets (chaîne marquée, proxy pendant l'appui et à l'`Apply`, **jamais réécrit**), autre addon qui écrit dans la FontString, PVP*TextString intouchés |
| `module_zonetext` | (si dans le `.toc`) zone, sous-zone, minimap, texte posé avant l'addon, changement de zone, sous-zone quittée (cadre caché ou visible), fondu, inconnu, identique, frFR, mauvais sens, auto-repeat, écran de chargement, perte de focus, `ZoneText_Clear`, `Minimap_Update`, minimap cachée |
| `module_worldmap` | (si dans le `.toc`) chaque test en mode **préchargé** et **à la demande** : survol traduit et restauré, libellé déjà affiché, inconnu, suffixe réel (plage et niveau unique) **recollé à l'identique**, `ClearAllLabels`, **secrets** (proxy pendant l'appui, proxy à l'`Apply`, chaîne secrète avec suffixe), touche relâchée, titre jamais traduit |
| `config` | (si dans le `.toc`) `/wt`, `/wt status`, entrées invalides, SavedVariables, override dans les deux sens, langue invalide, `/wt lang` pendant l'appui, persistance via `Logout`, SavedVariables corrompues |
| `data` | vraies données : **ni données synthétiques ni marqueur de l'oracle**, tables non vides, taille minimale, tables inverses l'une de l'autre (hors collisions cohérentes **et hors noms natifs**, voir l'hypothèse ci-dessous), échantillon de PLAN T3 dans les deux sens, chaque fichier chargeable seul |

Statut `skip` : `module_zonetext`, `module_worldmap` et `config` sont ignorées **dès que le `.toc` existe mais ne liste pas le fichier** concerné. Tant que l'addon est absent, elles **échouent** comme les autres. `data` échoue sans `Data/`. Rien pour T6 (cibles non confirmées en jeu) ni pour le fil d'Ariane (hors v1).

## Hypothèses sur le contrat

Ces hypothèses tranchent les ambiguïtés du contrat de PLAN.md. Les tests les imposent.

1. **Globale publique `WoWTranslator` = namespace**, pas de globale `WT`. Globales autorisées : `WoWTranslator*`, `WOWTRANSLATOR*`, `SLASH_*`, `BINDING_*` et les SavedVariables.
2. **Le Core n'écrase jamais `WT.data`**, et la recherche se fait à l'appel : l'ordre Core/Data est indifférent.
3. **`Translate` est une recherche EXACTE** dans `WT.data[source.."_"..cible]` : elle ne retire ni codes couleur, ni suffixes, ni espaces. C'est au module de découper son texte : le module carte découpe le suffixe de niveau, traduit le nom seul et **recolle le suffixe d'origine**.
4. **Nom identique** (`Orgrimmar`) : `"Orgrimmar"` ou `nil`.
5. **`enGB` = `enUS`** ; une autre locale ne provoque aucune erreur.
6. **Raccourci** : `<Binding name="WOWTRANSLATOR_HOLD" runOnUp="true" category="BINDING_HEADER_WOWTRANSLATOR">` appelle la globale `WoWTranslator_OnHoldKey(keystate)`. Toute valeur autre que `"down"` vaut relâchement.
7. **`WT.SetActive(bool)` est le seul point de bascule, et il est idempotent.** `Restore` n'est appelé qu'au passage actif → inactif.
8. **`IsActive()` vaut `true` pendant `Apply` et `false` pendant `Restore`.**
9. **Isolation des modules** : `pcall`/`xpcall`/`securecall` et `geterrorhandler()`. Les autres modules continuent, et l'état bascule quand même.
10. **Reset** sur `PLAYER_LEAVING_WORLD` / `PLAYER_ENTERING_WORLD`. **Filet (PLAN.md T2)** :
    - armé **uniquement par la touche** : **chaque** `WoWTranslator_OnHoldKey("down")` l'arme, y compris quand l'état est déjà actif (par exemple après un `SetActive(true)`). Un `SetActive(true)` venant d'ailleurs ne l'arme pas. Il est désarmé à la désactivation. N'importe quel mécanisme de minuterie convient ;
    - sonde **toutes** les touches de `GetBindingKey` (jusqu'à deux), réduites à leur touche de base (`"SHIFT--"` → `"-"`) ;
    - désactive (`SetActive(false)`) en moins d'1 s seulement si **toutes** renvoient **exactement** `false`. Une seule touche `true` ou `nil` suffit à garder l'état actif ;
    - `nil` (inconnu), pas de touche liée ou pas d'`IsKeyDown` → jamais de coupure.
11. **Hooks** :
    - FontStrings seulement, jamais `ZoneText_OnEvent`, jamais `SetScript` sur un frame Blizzard ;
    - `SetText("")` reste `""` ;
    - un secret est intouché ;
    - au plus un `SetText` supplémentaire par appel ;
    - on restaure le **dernier** texte posé.
12. **`PVPInfoTextString` / `PVPArenaTextString`** sont hors v1.
13. **Carte** : on gère « `WorldMapFrame` existe déjà » **et** `ADDON_LOADED`. Le titre et le fil d'Ariane ne sont pas traduits (hors v1).
14. **Config** : `/wt lang enUS|frFR` persiste dans la première SavedVariable (écriture immédiate ou à `PLAYER_LOGOUT`). Une valeur invalide est refusée, des SavedVariables corrompues donnent les valeurs par défaut, les deux dictionnaires sont toujours chargés, et `/wt status` affiche au moins une ligne.
15. **Valeurs secrètes** :
    - `issecretvalue` peut être **absent** : aucune valeur n'est alors secrète et la traduction fonctionne ;
    - un module ne **mémorise ni ne réécrit** jamais un texte secret (règle 2 de client-research §5.6). La suite vérifie l'absence de réécriture ;
    - `issecretvalue` est appelé **via `pcall`**, et une erreur vaut « secret » (règle de PLAN.md, `AllowedWhenUntainted`) ;
    - il est testé **avant** toute comparaison ou indexation de la valeur ;
    - la suite vérifie l'appel, l'absence d'indexation avec un secret et le `pcall`, mais pas l'ordre vis-à-vis d'un `==` (voir le mock).

## Décisions reportées

- **B33** : si `issecretvalue` lève une erreur à **chaque** appel, la règle « erreur = secret » rend l'addon muet. Le mutisme est **testé** (`core_translate`, `issecretErrors = "always"` : rien n'est traduit, aucune erreur). Le **message d'avertissement** dans le chat qui pourrait signaler ce cas n'est ni décidé ni testé. À trancher si le test 4 du §8 de client-research montre ce cas en jeu.
