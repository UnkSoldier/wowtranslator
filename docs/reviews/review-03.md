# Revue 03 — PLAN, T0 rév. 3, tests et mutants

Date : 2026-11-21. Même exigence qu'aux revues 01 et 02. Aucune correction appliquée, dossier du jeu en lecture seule, rien de téléchargé.

## Méthode

1. Relecture de `PLAN.md`, `docs/client-research.md` (rév. 3), `tests/README.md`, `tests/wow_mock.lua`, des specs (dont la nouvelle `core_setactive_spec.lua`), de `tests/mutants/` (référence, 17 patches, `run_mutants.py`) et de `docs/test-checklist.md`.
2. **Citations nouvelles de A vérifiées** dans `wow-ui-source@forever` :
   - `SimpleFontStringAPIDocumentation.lua` : `GetText` → `cstring, Nilable = false` ; `SetText(text: cstring, Nilable = false, Default = "")` aux lignes 664-670 ;
   - `FrameScriptDocumentation.lua:290` (`AllowedWhenUntainted`).

   Tout est exact.
3. Exécutions :
   - `python tests/tools/luarun.py tests/run.lua` : **28 ok, 120 échecs « toc introuvable »**, conforme.
   - `python tests/mutants/run_mutants.py -v` : **référence 148/148, 17 mutants conformes** à leur statut attendu (« Tout est conforme »).
4. **Mutants à moi**, appliqués à une copie de la référence (scratchpad), et lancés par `run.lua --addon=…` :

| Id | Mutation | Résultat | Verdict |
|---|---|---|---|
| X10 | `pcall(issecretvalue)` en erreur traité comme **non** secret | 1 échec | détecté ✔ |
| X23 | filet jamais armé | 5 échecs | détecté ✔ |
| **X23b** | filet armé **seulement** par `WoWTranslator_OnHoldKey("down")`, pas par `WT.SetActive(true)` | **148/148** | contrat ambigu → P6 |
| **X26** | `Translate` fait `rawget(dict, text)` **avant** `issecretvalue` | **148/148** | garde contournable → B29 |
| **Y4** | module carte sans garde secret : `text:match(...)` sur la valeur brute | **148/148** | trou de couverture → B27 |
| Y5 | suffixe recollé aussi quand le nom est inconnu | 148/148 | mutant équivalent (même texte), sans conséquence |
| **Y6** | `issecretvalue` absent traité comme « secret » (l'addon ne traduit plus rien) | **148/148** | nit → B30 |
| Y7 | erreur de module avalée (pas de `geterrorhandler`) | 2 échecs | détecté ✔ |

---

## 1. Notes

| | Revue 01 | Revue 02 | Revue 03 |
|---|---|---|---|
| **Globale** | 6/10 | 8/10 | **8,5/10** |
| A — Recherche client (T0) | 6,5 | 8,5 | **9/10** |
| B — Tests, checklist, mutants | 6 | 8 | **8,5/10** |
| PLAN | — | 7,5 | **8,5/10** |

**A.** Toutes les corrections A10 à A12 sont faites, sourcées et justes. Il ne reste aucun point bloquant. T0 est publiable comme base, avec son statut « partiel » honnête (les vérifications en jeu restent à faire).

**B.** Très bon niveau : mutants versionnés et exécutables d'une seule commande, filet multi-touches, garde des dictionnaires, `C_Timer` complet, `GetText` jamais `nil`, lint étendu. Restent des trous de couverture que mes mutants ont trouvés, et une référence dont deux propriétés posent problème (B28, B31).

**PLAN.** Le contrat est maintenant explicite (`SetActive`, recherche exacte, `pcall`). Deux formulations restent ambiguës ou en léger décalage avec T0 et les tests (P5, P6).

---

## 2. Statut des constats de la revue 02

| Id | Statut | Vérification |
|---|---|---|
| A10 filet multi-touches | **corrigé** | `client-research.md:269-276`, `:311` ; test 8 du §8 avec la seconde touche (`:330`) |
| A11 recherche exacte | **corrigé** | `client-research.md:316`, `PLAN.md:46-49`, `tests/README.md` hypothèse 3, `core_translate_spec.lua:95` |
| A12 `GetText` / `AllowedWhenUntainted` | **corrigé** | `client-research.md:122`, `:226-235`, test 4 du §8 (`:324`) |
| B3-bis ordre `issecretvalue` | **corrigé, avec une réserve** | garde `wow_mock.lua:1337-1354` ; N1 et S1 détectés. Réserve : le contournement par `rawget` passe (X26), voir B29 |
| B20 `C_Timer.NewTicker` / `NewTimer` | **corrigé** | `wow_mock.lua:771-797` ; N2 passe |
| B21 deux touches | **corrigé** | `wow_mock.lua:745-755`, `core_keybinding_spec.lua:111-128` ; K1 détecté |
| B22 `GetText` jamais `nil` | **corrigé** | `wow_mock.lua:891-895`, `README` |
| B23 fil d'Ariane | **corrigé** | hors v1 (`PLAN.md:112`), checklist 6.5 alignée |
| B24 lint et `bit` | **corrigé** | `wow_mock.lua:144-160`, `:612-624` |
| B25 `MinimapCluster_OnEvent` | **corrigé** | `wow_mock.lua:534-539` |
| B26 checklist : seconde touche et touche `-` | **corrigé** | `test-checklist.md:88-93` (3.6, 3.7) |
| P1 spécification du filet | **corrigé, avec une réserve** | `PLAN.md:101`. Réserve : la valeur `nil` n'y est pas traitée, voir P5 |
| P2 fil d'Ariane | **corrigé** | `PLAN.md:112` |
| P3 T0 partiel, T6 bloqué, question 1 | **corrigé** | `PLAN.md:86`, `:115`, `:131` |
| P4 `SetActive` au contrat | **corrigé** | `PLAN.md:45` |

---

## 3. Nouveaux constats

### A — `docs/client-research.md`

**A13 — nit — `client-research.md:235`, et `PLAN.md:47`**
La règle « `pcall(issecretvalue, text)` ; erreur = secret » ne précise pas le cas où `issecretvalue` est absent. Lue sans le « si `issecretvalue` existe » qui la précède, elle conduit à `pcall(nil, …)` → erreur → « secret » → plus aucune traduction (mutant Y6). Le §5.6 dit bien « si `issecretvalue` existe », mais pas PLAN. Aligner les deux formulations (voir P7).

### B — tests, checklist, mutants

**B27 — mineur — `specs/module_worldmap_spec.lua` (absence), `specs/hooks_spec.lua:3-4`**
*Problème* : les tests de secrets (`hooks_spec.lua:92-122`) ne couvrent que `ZoneTextString`, `SubZoneTextString` et `MinimapZoneText`. Le libellé de la carte n'est jamais exercé avec un secret. Mutant Y4 (le module carte fait `text:match(...)` avant toute garde) : 148/148. En jeu, sur une carte « restreinte » (`SecretOnRestrictedMaps`, `client-research.md:237`), ce serait une erreur Lua dans un hook à chaque survol.
*Correction attendue* : ajouter `m.worldMapAreaLabel` à la liste des FontStrings des tests de secrets (proxy posé pendant l'appui, proxy déjà affiché à l'`Apply`, chaîne marquée avec suffixe), dans les deux modes de carte. Ajouter Y4 aux mutants, avec `Expect: fail`.

**B28 — mineur — `specs/data_spec.lua:224-276`, `tests/mutants/reference/WoWTranslator/Data/*.lua`**
*Problème* : les données **synthétiques** de la référence (échantillon réel + 252 entrées `"Zone N" = "Zone FR N"`) passent **toute** la spec `data` : taille ≥ 200, inversion, échantillon. Si quelqu'un copie `reference/…/Data` dans l'addon, T3 sera « vert » avec de fausses données.
*Correction attendue* : dans `data_spec`, échouer si une clé ou une valeur correspond à `^Zone %d+$` ou `^Zone FR %d+$`, ou si le fichier contient le marqueur `REFERENCE (oracle de test)`. Ajouter un mutant « données de la référence copiées », avec `Expect: fail` sur `data`.

**B29 — mineur — `wow_mock.lua:1337-1354`, `tests/README.md` (« l'indexation … n'a **jamais** lieu (garde) »)**
*Problème* : la garde ne voit que l'indexation passant par `__index` de la table d'origine. `rawget(dict, secret)` (mutant X26 : 148/148), une copie ou fusion des dictionnaires au chargement, ou un dictionnaire rempli après `ADDON_LOADED` la contournent. Le README affirme une garantie (« jamais ») que le mock ne donne pas.
*Correction attendue* :
1. Envelopper `env.rawget` pour qu'il lève une erreur si la clé est secrète (même règle que la garde).
2. Reformuler le README : « vérifié pour l'indexation directe et `rawget` des tables `WT.data.*` d'origine ; une copie des dictionnaires n'est pas surveillée ».
3. Ajouter X26 aux mutants, avec `Expect: fail`.

**B30 — nit — `wow_mock.lua:705-720`**
Pas de mode « `issecretvalue` absent ». Un addon qui traite l'absence comme « secret » ne traduit plus rien, et passe quand même (Y6). Forever a la fonction (documentée), donc l'impact est faible. Ajouter `opts.noIssecretvalue` et un test « traduit normalement ».

**B31 — mineur — `tests/mutants/reference/WoWTranslator/Core.lua:108-112`**
*Problème* : l'oracle viole la règle 2 du §5.6 de T0 (« si la valeur est secrète, ne rien mémoriser ni réécrire ») : le hook fait `st.original, st.applied = text, nil` **sans** test de secret, puis `Restore` peut réécrire ce secret. La suite ne vérifie pas la règle 2, sinon l'oracle échouerait. Un oracle qui contredit la spécification l'affaiblit, surtout s'il est copié.
*Correction attendue* : corriger la référence (garde `isSecret` au début du hook), puis ajouter un test qui détecte la mémorisation. Par exemple : un secret posé pendant l'appui, puis Blizzard repose un texte normal, puis relâchement → le texte affiché est le texte normal et `SetText` n'a jamais été rappelé avec le secret (compteur par valeur dans le mock).

**B32 — mineur — décision sur `tests/mutants/reference/` (question du coordinateur)**
*Avis* : **acceptable**, à condition d'ajouter des garde-fous. Un oracle est la seule façon de prouver que la suite est satisfaisable et de faire tourner les mutants : il a fait ses preuves dans cette revue. Les risques réels sont les suivants :
- **Copie en bloc par T2-T7.** La référence est complète (133 lignes de Core, `.toc` chargeable en `16001`). Une copie importerait ses raccourcis (B31), ses données synthétiques (B28) et une **API publique hors contrat** : `WT.HookFontString`, `WT.Group`, `WT.IsSecret`, `WT.GetTargetLocale` et `WT.db`, qui deviendraient de fait l'API de l'addon.
- **Sur-ajustement.** Les tests ont été validés contre une seule implémentation, écrite par l'auteur des tests. Les mutants limitent ce risque mais ne l'éliminent pas.

*Correction attendue* :
1. Un test `structure` qui échoue si l'addon réel contient le marqueur `IMPLEMENTATION DE REFERENCE`, `oracle de test` ou le titre `(reference de test)`.
2. B28 (données).
3. Une règle écrite dans `PLAN.md` et `tests/README.md` : « T2-T7 n'ouvrent pas `tests/mutants/reference` comme base de code ; ils codent depuis le contrat et les specs ».
4. Préfixer les aides de la référence (`WT._ref*`) ou les rendre locales, pour qu'aucune API hors contrat ne puisse être recopiée telle quelle.

**B33 — nit — `specs/core_translate_spec.lua:80-94` (`issecretErrors = "always"`)**
Le test impose que, si `issecretvalue` lève une erreur **à chaque** appel, l'addon ne traduise plus rien. C'est cohérent avec la règle de PLAN (« erreur = secret »), mais ce scénario rend l'addon inutile sans le signaler. Recommandation : si le test 4 du §8 montre ce cas, prévoir un message unique dans le chat. À noter comme décision, pas à corriger maintenant.

### P — `PLAN.md`

**P5 — mineur — `PLAN.md:101`**
« Si **aucune** n'est enfoncée : `WT.SetActive(false)` ». Le cas `IsKeyDown` → `nil` (état inconnu, par exemple avec une touche à modificateur) n'est pas traité. Lu à la lettre (`nil` = « pas enfoncée »), il coupe la traduction, alors que T0 (`client-research.md:274`), le README (hypothèse 10) et les tests (`core_keybinding_spec.lua:140`) exigent de **ne jamais couper** sur `nil`. Écrire : « seulement si toutes renvoient exactement `false` ; `nil` = ne pas couper ».

**P6 — mineur — `PLAN.md:45`, `:101`**
Le contrat ne dit pas si le filet est armé par **toute** activation (`SetActive(true)`, y compris par un `/run` ou une future option « bascule ») ou seulement par la touche. Les deux implémentations passent (mutant X23b). Conséquence pratique : avec la référence, `WoWTranslator.SetActive(true)` sans touche tenue est annulé en 0,2 s par le filet. Trancher dans PLAN (recommandation : le filet est armé par `SetActive(true)`, donc l'activation programmatique est réservée au mode « maintenir »), puis ajouter un test.

**P7 — nit — `PLAN.md:100`, `:47`, `:17-37`**
- `:100` dit « `Restore` sur `PLAYER_LEAVING_WORLD`… » alors que le contrat fait de `SetActive(false)` le seul point de bascule (`:45`).
- `:47` ne précise pas « si `issecretvalue` existe » (A13).
- L'arborescence ne mentionne ni `tests/` ni `tests/mutants/reference`, ni la règle « ne pas copier l'oracle » (B32).

---

## 4. Ce qu'il reste pour atteindre 9/10

1. **PLAN** : P5 (`nil` = ne pas couper) et P6 (qui arme le filet), puis le test correspondant. P7 au passage.
2. **Référence encadrée** (B32) : test « pas de marqueur de référence dans l'addon », données synthétiques refusées (B28), oracle conforme à la règle 2 (B31), aides hors contrat rendues locales.
3. **Couverture** : secrets sur le libellé de carte (B27), garde étendue à `rawget` et README exact (B29). Les mutants X26 et Y4 sont à versionner avec `Expect: fail`, et X23b à classer selon la décision P6.

Les autres points (A13, B30, B33) sont des nits. Une fois les points 1 à 3 faits, je mettrais **9/10** : base prête pour T2-T7, en attente des vérifications en jeu de T0.
