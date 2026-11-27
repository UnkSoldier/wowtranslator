# Revue 02 — T0 rév. 2, tests et PLAN

Date : 2026-11-21. Même niveau d'exigence que la revue 01 ; aucune correction appliquée, dossier du jeu en lecture seule, rien de téléchargé.

## Méthode

1. Relecture complète de `PLAN.md`, `docs/client-research.md` (rév. 2), `tests/**` (dont `tests/tools/luarun.py`) et `docs/test-checklist.md`.
2. **Vérification des nouvelles citations de A**, sans faire confiance au texte :
   - dans `wow-ui-source@forever` via `gh api` : `Keybindings.lua:220-259,278`, `Minimap.lua:368-412`, `FrameScriptDocumentation.lua:287-300`, `InputDocumentation.lua:115-128`, `SimpleFontStringAPIDocumentation.lua`, `SecretPredicatesDocumentation.lua`, `Blizzard_WorldMap.lua:134,149,192,245-248`, `AreaLabelDataProvider.lua:71-106`, `ColorUtil.lua:90-95` ;
   - sur disque : `Angleur_Camelot.toc`, `AngleurForever.lua:105-123,397`, `Angleur/secrets/secrets.lua:24-35`, `EllesmereUIForeverEssentials_ZoneLevels.lua:180-185`, `Location.lua:70-71`, `EUI_ActionBars_Keybinds.lua:165`, `Clock.lua:343`, `EllesmereUIQoL_Keys.lua:41-42`, les `.toc` Ellesmere.
   - **Tout est exact.** Au passage, A corrige une erreur de la revue 01 : `Angleur.lua` n'est pas chargé en camelot, c'est `AngleurForever.lua` qui fait foi. C'est juste.
3. Suite exécutée avec le lanceur versionné, `python tests/tools/luarun.py tests/run.lua` : **24 ok, 109 échecs « toc introuvable »**, comme annoncé. Avertissement LuaJIT affiché.
4. L'implémentation de référence de l'auteur (`scratchpad/proj/WoWTranslator`), recopiée contre les tests **actuels**, passe **133/133**.
5. **Les mutants annoncés ne sont pas dans le scratchpad.** Je les ai donc refaits moi-même sur la base de l'implémentation de référence :

| Mutant (cassé en jeu, sauf M6) | Revue 01 | Revue 02 |
|---|---|---|
| M1 : module de zone hooké sur la globale `ZoneText_OnEvent` | passait | **échoue** (4 tests `module_zonetext` + `hooks`) ✔ |
| M2 : carte accrochée seulement sur `ADDON_LOADED` | passait | **échoue** (4 tests en mode préchargé) ✔ |
| M3 : suffixe reconnu au mauvais format `" |c…(…)|r"` | passait | **échoue** (4 tests) ✔ |
| M5 : `ZoneTextFrame:SetScript("OnEvent", …)` | passait | **échoue** ✔ |
| M6 : SavedVariables écrites à `PLAYER_LOGOUT` (conception valide) | échouait à tort | **passe** (c'est l'impl. de référence) ✔ |
| M7 : `goto` dans `Core.lua` | passait | **échoue** (lint) ✔ |
| **N1** : `Translate` fait `text == ""` puis `dict[text]`, et **ensuite seulement** `issecretvalue` | — | **passe 133/133** ✘ (B3) |
| **N2** : filet de sécurité via `C_Timer.NewTicker(0.1, …)`, comme le recommande `client-research.md:258` | — | **échoue à tort** : `attempt to call field 'NewTicker' (a nil value)` ✘ (B20) |

---

## 1. Notes

| | Revue 01 | Revue 02 |
|---|---|---|
| **Globale** | 6/10 | **8/10** |
| A — Recherche client (T0) | 6,5/10 | **8,5/10** |
| B — Tests et checklist | 6/10 | **8/10** |
| PLAN (coordinateur) | — | **7,5/10** |

**A.** La révision est solide. Chaque affirmation est sourcée au fichier et à la ligne, et les sources vérifiées sont exactes. Les statuts « confirmé / non confirmé » sont honnêtes, T0 est déclaré « PARTIEL » avec la liste de ce qui bloque, et le §5.6 sur les valeurs secrètes est un vrai travail. Restent un défaut de conception partagé avec PLAN (une seule touche sondée, A10) et deux points de documentation non exploités (A11, A12).

**B.** Gros progrès : FrameXML porté **à l'identique** (j'ai comparé avec la source), liaison XML par référence, double mode de carte, `Logout` fidèle, lint, lanceur reproductible. Toutes les mutations de la revue 01 sont désormais attrapées. Mais la règle phare « `issecretvalue` en premier » est annoncée comme **vérifiée** alors qu'elle ne l'est pas (N1), et le mock rejette la conception recommandée par T0 (N2).

**PLAN.** Mis à jour et cohérent sur l'essentiel (globale `WoWTranslator`, moteur moderne, titre de carte, filet `IsKeyDown`). Mais la spécification du filet est incomplète (touche de base, deux touches liées), et le fil d'Ariane est dans le périmètre de PLAN sans aucun test.

---

## 2. Statut des constats de la revue 01

### A — `docs/client-research.md`

| Id | Statut | Vérification |
|---|---|---|
| A1 carte non LoadOnDemand | **corrigé** | `:150-155` cite le `.toc` ; test 5 du §8 ; décision T5 « tester `WorldMapFrame` d'abord » (`:295`) |
| A2 format du suffixe | **corrigé** | `:165-171`, lignes 86-106 et `ColorUtil.lua:90-95` vérifiées ; deux variantes, motif fourni |
| A3 `ZoneText_OnEvent` | **corrigé** | `:111-125`, points 1 à 7 conformes au code source |
| A4 `IsKeyDown` | **corrigé** | `:253-257` ; `InputDocumentation.lua:115-128` vérifié ; corrige à juste titre la citation de la revue 01 |
| A5 `issecretvalue` | **corrigé** | `:208-225`, documentation vérifiée ; sémantique marquée non confirmée, avec test 4 |
| A6 minimap camelot | **corrigé** | `:130-143` ; `Minimap.lua:372-376,409` vérifié |
| A7 T0 partiel | **corrigé** | `:11-17` |
| A8 libellé localisé | **corrigé** | `:273-277` |
| A9 section des raccourcis | **corrigé** | `:238-244` ; `Keybindings.lua:220-227` (`GetBindingCategoryName`), `:246` (`BINDING_HEADER_OTHER`), `:278` vérifiés. Il s'agit bien d'une section « WoWTranslator » propre, pas de catégorie « AddOns » : ma remarque A9 de la revue 01 était fausse |

### B — tests et checklist

| Id | Statut | Vérification |
|---|---|---|
| B1 liaison par référence | **corrigé** | `wow_mock.lua:1007-1031` (`bindXmlScript`) ; selftest `mock_selftest_spec.lua:47-56` ; M1 détecté |
| B2 `ZoneText_OnEvent` fidèle | **corrigé** | `wow_mock.lua:317-519`, comparé ligne à ligne avec `ZoneText.lua@forever` ; tests `module_zonetext_spec.lua:220-259` |
| B3 valeurs secrètes | **partiel** | `type()` renvoie `"string"` et les proxies passent par les hooks (`wow_mock.lua:585-589`, `hooks_spec.lua:102-122`). Mais l'ordre « `issecretvalue` en premier » n'est **pas** vérifié, alors que `tests/README.md:83` et `:136` affirment le contraire : N1 passe. Voir B3-bis ci-dessous |
| B4 LuaJIT / lint | **corrigé** | `run.lua:55-58`, `wow_mock.lua:130-221`, `structure_spec.lua:31-41` ; M7 détecté. Petites lacunes en B24 |
| B5 carte préchargée | **corrigé** | `module_worldmap_spec.lua:10-27`, deux modes ; M2 détecté |
| B6 format réel du suffixe | **corrigé** | `wow_mock.lua:1088-1103` ; M3 détecté |
| B7 `Logout` | **corrigé** | `wow_mock.lua:1174-1181` ; M6 passe |
| B8 scripts Blizzard comparés par référence | **corrigé** | `hooks_spec.lua:26-36`, `derivesFrom` ; M5 détecté |
| B9 filet `IsKeyDown` | **corrigé, avec lacunes** | `core_keybinding_spec.lua:253-310`, `LoseKeyUp`. Lacunes en B20 et B21 |
| B10 lanceur reproductible | **corrigé** | `tests/tools/luarun.py`, `README.md:11-24` |
| B11 `skip` | **corrigé** | `README.md:105` |
| B12 `isNil` tautologique | **corrigé** | `hooks_spec.lua:49` utilise `T.isEmpty`. Voir quand même B22 (la doc tranche nil / "") |
| B13 cas manquants | **corrigé** | `module_zonetext_spec.lua:183-195` ; `config_spec.lua:159-171` ; `hooks_spec.lua:124-136` ; `core_translate_spec.lua:115-120` |
| B14 données | **corrigé** | `data_spec.lua:196-276` (raid, zones de départ, test d'inversion) ; seuil provisoire documenté |
| B15 checklist 1.1 | **corrigé** | `test-checklist.md:13`, `:37-39` |
| B16 checklist [frFR] carte / T6 / modificateur | **corrigé** | `:128-130`, `:153-163`, `:82-84` |
| B17 section des raccourcis | **corrigé** | `:29`, conforme à A9 vérifié |
| B18 mock (Clear, C_PvP, string) | **corrigé** | `wow_mock.lua:491-495`, `:733`, `:590-594` |
| B19 `where()` | **corrigé** | `run.lua:82-92` |

---

## 3. Nouveaux constats

### A — `docs/client-research.md`

**A10 — majeur — `client-research.md:257-258`, `:292` (et PLAN, voir P1)**
*Problème* : le filet sonde **une seule** touche, celle renvoyée par `GetBindingKey("WOWTRANSLATOR_HOLD")`. Or `GetBindingKey` renvoie **jusqu'à deux** touches (deux emplacements par action dans le menu des raccourcis ; `EUI_ActionBars_Keybinds.lua:165`, cité par A, fait d'ailleurs `local k1, k2 = GetBindingKey(cmd)`). Si l'utilisateur tient la **seconde** touche, `IsKeyDown(<première>)` renvoie `false` : le filet coupe la traduction en moins d'une seconde, **pendant l'appui**. C'est un bug fonctionnel de la conception recommandée.
*Correction attendue* : « sonder **toutes** les touches renvoyées par `GetBindingKey` (modificateurs retirés) et ne désactiver que si **aucune** n'est enfoncée (`== false` pour toutes ; `nil` = inconnu, ne pas couper) ». Mettre à jour `:257-258`, `:292` et le test 8 du §8 (tenir la seconde touche).

**A11 — mineur — `client-research.md:297` contre `tests/README.md:113` (hypothèse 3)**
*Problème* : le §7 dit que `WT.Translate` doit « retirer les codes couleur et le suffixe avant le lookup ». L'hypothèse 3 des tests dit « recherche exacte », et le suffixe est géré par le module carte (`:295`). Les deux documents se contredisent, et aucun test ne tranche (`core_translate_spec.lua:179-183` vérifie seulement l'absence d'erreur). Si `Translate` retire le suffixe, il renvoie la traduction **sans** le suffixe : le module carte ne peut plus le recoller proprement.
*Correction attendue* : une seule règle. Recommandation : `Translate` fait une recherche exacte, et le découpage du suffixe appartient au module carte (`:295`). Supprimer la mention de `:297`, ou l'inverse, mais alors l'aligner dans `tests/README.md` et ajouter un test.

**A12 — mineur — `client-research.md:213-216`, `:220`**
Deux points de la documentation, lue mais pas exploitée :
1. `SimpleFontStringAPIDocumentation.lua` (`GetText`, l. 353-365) déclare le retour `text: cstring, Nilable = false`. `GetText()` ne renvoie donc **jamais** `nil` (il renvoie `""`), ce qui tranche la question « nil ou "" » laissée ouverte par B (`tests/README.md:67`).
2. `issecretvalue` est déclaré avec `SecretArguments = "AllowedWhenUntainted"` (`FrameScriptDocumentation.lua:291`, cité `:210`). Pris à la lettre, un appel par du code tainté **avec** un argument secret serait refusé, ce qui contredirait l'usage d'Angleur. Le document cite l'attribut sans discuter cette contradiction.

*Correction attendue* : ajouter le point 1 au §5.1 ou au §5.6. Pour le point 2, une phrase qui le signale et renvoie au test 4 du §8 : le `issecretvalue(v)` sur `secretwrap` lancé depuis `/run` le tranchera.

### B — tests et checklist

**B3-bis (suite de B3) — majeur — `tests/README.md:83`, `:136` ; `core_translate_spec.lua:161-168` ; `wow_mock.lua:671-675`**
*Problème* : le README affirme que la règle « `issecretvalue` en premier » est « vérifiée par instrumentation sur `Translate` ». Le test vérifie seulement que `issecretvalue` est **appelé**, pas **avant** le reste. Mutant N1 (`text == ""` puis `dict[text]`, et `issecretvalue` ensuite) : **133/133**. La règle centrale du §5.6 de T0 n'est donc pas protégée, et la documentation des tests est fausse sur ce point.
*Correction attendue* : (a) envelopper les dictionnaires chargés (`WT.data.*`) dans un proxy `__index` (table vide + métatable) qui signale une erreur si on y cherche une valeur marquée secrète (`MakeSecret`) **avant** que `issecretvalue` ait été appelé sur cette même valeur. On attrape ainsi l'indexation. (b) Reformuler `README.md:83` et `:136` : « appel vérifié ; ordre vérifié pour l'indexation ; `==` non vérifiable en Lua 5.1 ». (c) Garder N1 comme mutant de non-régression.

**B20 — majeur — `wow_mock.lua:719-724`**
*Problème* : `C_Timer` n'expose que `After`. `C_Timer.NewTicker` et `C_Timer.NewTimer` (avec `:Cancel()`) existent dans le client moderne, et T0 recommande explicitement `C_Timer.NewTicker` pour le filet (`client-research.md:258`). Mutant N2 : une implémentation correcte qui suit T0 échoue à **toutes** les specs touchant à l'appui (`attempt to call field 'NewTicker'`). C'est un faux négatif qui impose une conception (OnUpdate).
*Correction attendue* : ajouter `NewTicker(interval, cb, iterations)` et `NewTimer(delay, cb)`, avec des objets `:Cancel()` / `:IsCancelled()`, pilotés par `mock.Tick`. Ajouter un selftest, puis un test « filet par ticker » (le mutant N2 doit passer).

**B21 — majeur — `wow_mock.lua:700-705`, `core_keybinding_spec.lua:253-310`**
*Problème* : `GetBindingKey` ne renvoie qu'**une** touche, donc le défaut A10 est inobservable. Aucun test « seconde touche tenue ». L'impl. de référence (`Core.lua:31-34`) a exactement ce bug et passe.
*Correction attendue* : option `boundKeys = { "F6", "BUTTON4" }` (deux valeurs renvoyées). `mock.KeyDown(i)` enfonce la i-ème touche. Test : appui sur la seconde touche, `Wait(2)`, toujours actif ; `LoseKeyUp` puis `Wait(1)`, désactivé.

**B22 — mineur — `wow_mock.lua:818`, `mock_selftest_spec.lua` (« textes posés au chargement », `T.isNil(ZoneTextString:GetText())` ; « FontString », `T.isNil` après `SetText(nil)`), `tests/README.md:67`**
*Problème* : la documentation du build (A12, point 1) dit `GetText` → `cstring, Nilable = false`. Le mock renvoie `nil` pour une FontString jamais écrite ou après `SetText(nil)`, et le selftest fige ce comportement. Un addon qui fait `if not text then … end` à la place de `text == ""` est mal exercé.
*Correction attendue* : `FS:GetText()` renvoie `st.text or ""`. Corriger les deux selftests et `README.md:67` (citer la doc).

**B23 — mineur — `specs/module_worldmap_spec.lua` (absence), `wow_mock.lua:1070-1079`, `test-checklist.md:125`**
*Problème* : PLAN T5 (`PLAN.md:107`) met le **fil d'Ariane** dans le périmètre v1. Aucun test ne le couvre, le mock `NavBar` n'est pas porté depuis la source (`WorldMapNavBarMixin:Refresh`, `Blizzard_WorldMapTemplates.lua:527-557`, cité par A), et la checklist dit « si implémenté ». Test-first incohérent avec le contrat.
*Correction attendue* : soit le coordinateur retire le fil d'Ariane de la v1 (P2), soit B porte `NavBar_AddButton` / `Refresh` et ajoute au moins : boutons traduits pendant l'appui, restaurés au relâchement, `Refresh` pendant l'appui. Aligner ensuite `test-checklist.md:125`.

**B24 — nit — `wow_mock.lua:130-152`, `:594`**
Le lint ne voit pas `0x10LL` (le motif exige un caractère non-mot avant les chiffres), le littéral imaginaire LuaJIT `1i`, ni `0x1p4`. L'environnement expose la bibliothèque `bit` **de LuaJIT** (`tohex`, `rol`, `ror`, `bswap`, `tobit`, absents du `bit` du client), ainsi que `coroutine.isyieldable`. Restreindre `env.bit` à `band, bor, bxor, bnot, lshift, rshift, arshift, mod` et ajouter ces motifs au lint.

**B25 — nit — `wow_mock.lua:515-519`**
`MinimapCluster_OnEvent` ignore `SETTINGS_LOADED`, alors que le vrai `MinimapClusterMixin:OnEvent` (`Minimap.lua:405-410`) appelle `Minimap_Update()` pour **tous** les événements. Divergence sans effet aujourd'hui, mais le commentaire « porté » ne doit pas mentir : copier la vraie fonction.

**B26 — mineur — `docs/test-checklist.md:28-30`, `:76-84`**
Pas de scénario « raccourci sur la **seconde** touche » (A10/B21). Par exemple : F6 en touche 1 et un bouton de souris en touche 2 ; tenir le bouton 5 s ; attendu : la traduction reste. Pas non plus de scénario de touche liée à `-` (`"SHIFT--"`, cité par A `:257`).

### P — `PLAN.md` (coordinateur)

**P1 — majeur — `PLAN.md:96`**
*Problème* : « vérifie la touche liée via `IsKeyDown` ». Ce n'est ni « la touche **de base** » (modificateurs retirés), contrairement à ton message, à `client-research.md:257-258` et à `tests/README.md:120`, ni « **toutes** les touches liées » (A10). « on fait un `Restore` » est aussi ambigu : il faut une désactivation (`SetActive(false)`), qui appelle `Restore` **et** met `IsActive()` à faux.
*Correction attendue* : « tant que l'addon est actif, sonder `IsKeyDown` sur chacune des touches de `GetBindingKey("WOWTRANSLATOR_HOLD")`, modificateurs retirés ; désactiver si aucune n'est enfoncée (`false`) ; `nil` = ne pas couper ».

**P2 — mineur — `PLAN.md:107`**
Le fil d'Ariane est en v1, mais les tests ne le couvrent pas et la checklist le dit facultatif (B23). Trancher : v1 ou plus tard.

**P3 — nit — `PLAN.md:125-128`, `:109-110`, `:80`**
- Question ouverte 1 (« numéro d'interface exact et locales installées ») : elle est résolue.
- T6 n'est pas marqué « bloqué en attente des tests en jeu 6 et 7 », alors que T0 le dit (`client-research.md:14`, `:195`).
- T0 n'est pas indiqué comme « partiel ».

**P4 — nit — `PLAN.md:39-50`**
Le contrat ne mentionne pas `WT.SetActive`, pourtant utilisé par le gabarit de T0 (`client-research.md:279`) et par le filet. Le déclarer public ou explicitement interne.

---

## 4. Ce qu'il reste pour atteindre 9/10

1. **Filet de sécurité correct et testé** : P1 + A10 + B21 (toutes les touches liées, touche de base, `nil` = ne pas couper), B20 (`C_Timer.NewTicker`/`NewTimer` dans le mock), et checklist B26. Le mutant N2 doit passer, et un mutant « seule la première touche » doit échouer.
2. **Règle « `issecretvalue` en premier »** réellement protégée pour l'indexation, et README honnête (B3-bis). Le mutant N1 doit échouer.
3. **Une seule règle pour le suffixe et les codes couleur** dans `Translate` (A11), alignée dans T0, `tests/README.md` et un test.
4. **Fil d'Ariane** : tranché dans PLAN (P2), puis testé ou retiré (B23).
5. Ensuite, seuls des nits resteraient : B22, B24, B25, A12, P3, P4.

Les mutants M1-M7 et N1-N2 devraient être versionnés (par exemple `tests/mutants/`, avec un script qui vérifie leur statut attendu). Ils ne sont pas dans le scratchpad, contrairement à ce qui était annoncé : sans eux, la non-régression de la suite elle-même n'est pas reproductible.
