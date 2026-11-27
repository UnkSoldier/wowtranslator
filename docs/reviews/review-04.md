# Revue 04 — PLAN, T0, tests, mutants

Date : 2026-11-21. Même exigence qu'aux revues 01 à 03. Aucune correction appliquée, dossier du jeu en lecture seule, rien de téléchargé.

## Méthode

1. Relecture des parties modifiées :
   - `PLAN.md` : arborescence, « Règle sur l'oracle », contrat, T2 ;
   - `docs/client-research.md` : A13 et alignements (§5.6 l. 236, §6.3 l. 271, §7 l. 312 et 317) ;
   - `tests/README.md` ;
   - les nouvelles specs : `core_keybinding` 161-180, `module_worldmap` 86-115, `hooks` 124, garde-fous `structure` 43-55 et `data` 60-81 ;
   - `wow_mock.lua` (`rawget` gardé, `noIssecretvalue`) ;
   - l'oracle `tests/mutants/reference` et `run_mutants.py` ;
   - `docs/test-checklist.md` (7.7).
2. Exécutions :
   - `python tests/tools/luarun.py tests/run.lua` : **28 ok, 133 échecs « toc introuvable »**, conforme.
   - `python tests/mutants/run_mutants.py` : oracle à **159 ok et 2 échecs voulus** (les garde-fous), **25 mutants conformes**, dont mes X10, X23, X23b, X26, Y4, Y6 et Y7, ainsi que R31.
3. **Nouveaux mutants** à moi, sur une copie de l'oracle (le verdict compte les échecs **en plus** des 2 garde-fous) :

| Id | Mutation | Résultat | Verdict |
|---|---|---|---|
| Z1 | filet non désarmé par `SetActive(false)` (sondage qui continue après un reset) | 2 échecs en plus | détecté ✔ |
| Z2 | `nil` de `IsKeyDown` traité comme « relâché » (`if d then`) | 2 échecs en plus | détecté ✔ |
| **Z14** | `down` n'arme le filet **que** lors du passage inactif → actif (`if not active then SetActive(true); armNet() end`) | **0 échec en plus** | non détecté → B34 |
| Z10 | dictionnaires copiés au chargement, copie indexée avant `issecretvalue` | 0 échec en plus | limite **documentée** (`tests/README.md:153`) : accepté |

---

## 1. Notes

| | R01 | R02 | R03 | **R04** |
|---|---|---|---|---|
| **Globale** | 6 | 8 | 8,5 | **9/10** |
| A — T0 | 6,5 | 8,5 | 9 | **9/10** |
| B — tests, checklist, mutants | 6 | 8 | 8,5 | **9/10** |
| PLAN | — | 7,5 | 8,5 | **9/10** |

Au sens fixé en revue 01 (« 9/10 = on livre comme base de développement, il ne reste que des nits »), **c'est atteint**. Le seul constat au-dessus du nit (B34) est mineur, localisé et se corrige en quelques lignes. Il ne bloque pas le démarrage de T2-T7. La base reste « partielle » sur un seul point, attendu : les vérifications en jeu de T0 (§8).

---

## 2. Statut des constats de la revue 03

| Id | Statut | Vérification |
|---|---|---|
| A13 `issecretvalue` absent | **corrigé** | `client-research.md:236` (jamais `pcall(nil, …)`, forme recommandée), `:317` ; `PLAN.md:111` ; mutant Y6 détecté |
| B27 secrets sur la carte | **corrigé** | `module_worldmap_spec.lua:86-115` (proxy pendant l'appui, à l'`Apply`, chaîne marquée avec suffixe, deux modes) ; Y4 détecté (6 échecs) |
| B28 données synthétiques | **corrigé** | `data_spec.lua:60-81` |
| B29 `rawget` / garantie du README | **corrigé** | `wow_mock.lua:725-732` ; `README.md:145-153` reformulé, limite des copies documentée ; X26 détecté |
| B30 mode sans `issecretvalue` | **corrigé** | `wow_mock.lua:722-724` ; Y6 |
| B31 oracle conforme à la règle 2 | **corrigé** | `reference/…/Core.lua:123-143` ; test `hooks_spec.lua:124` ; R31 détecté |
| B32 garde-fous autour de l'oracle | **corrigé, avec un nit** | règle dans `PLAN.md:43` et `README.md:50-53` ; test `structure_spec.lua:43-55` ; API sous `WT._ref`. Nit en B35 |
| B33 mode « toujours en erreur » | **reporté, accepté** | `README.md:216`, section « Décisions reportées » ; formulation à corriger (B36) |
| P5 `nil` = ne pas couper | **corrigé** | `PLAN.md:109` ; tests `core_keybinding` « une touche false + une touche nil » ; Z2 détecté |
| P6 qui arme le filet | **corrigé, avec une réserve** | `PLAN.md:107`, `client-research.md:271`, `README.md:194`, checklist 7.7 ; X23b détecté. Réserve : un `down` reçu alors qu'on est **déjà** actif doit-il armer ? Non spécifié, et non testé (Z14), voir B34/P8 |
| P7 cohérence PLAN | **corrigé** | `PLAN.md:106` (reset via `SetActive(false)`), `:111` (absence d'`issecretvalue`), arborescence `:31-41` |

---

## 3. Choix à juger : 2 tests anti-oracle en échec voulu sur l'oracle

**Verdict : acceptable.** Les garde-fous doivent échouer sur l'oracle, sinon ils ne protègent de rien. `run_mutants.py` exige exactement ces 2 échecs et rien d'autre (`REFERENCE_EXPECTED_FAILS`), puis juge chaque mutant sur ses échecs **en plus**. J'ai vérifié que le verdict des mutants reste exact (Z1 et Z2 : 2 échecs en plus, détectés ; Z14 : aucun).

Deux défauts, de niveau nit (B37) :
- le couplage se fait par le **nom exact** des deux tests : renommer un test casse la ligne de base ;
- `run.lua --addon=tests/mutants/reference` lancé seul sort en code 1, ce qui peut tromper.

Alternative plus propre : une option `--oracle` de `run.lua` qui marque ces deux tests « échec attendu » (xfail). L'oracle sortirait alors à 0 tout seul, sans liste de noms dans le script Python.

---

## 4. Nouveaux constats

### A — `docs/client-research.md`
Aucun nouveau constat. Le document est cohérent avec PLAN, le README des tests et la checklist sur tous les points revus (contrat, filet, secrets, carte, T6).

### B — tests, checklist, mutants

**B34 — mineur — `specs/core_keybinding_spec.lua:161-180` (absence)**
*Problème* : aucun test ne vérifie qu'un `down` reçu alors que l'addon est **déjà** actif (activé par `SetActive(true)` programmatique, par exemple la checklist 7.7) **arme quand même** le filet. Mutant Z14 : 0 échec en plus. En jeu : `/run WoWTranslator.SetActive(true)`, puis l'utilisateur tient la touche, puis Alt+Tab → le `up` est perdu, le filet n'est pas armé, et la traduction **reste active indéfiniment**. C'est exactement ce que PLAN interdit (« un relâchement manqué ne doit jamais laisser la traduction active »).
*Correction attendue* : un test `SetActive(true)` → `KeyDown()` → `LoseKeyUp()` → `Wait(1)` → `IsActive() == false`. Versionner Z14 avec `Expect: fail`.

**B35 — nit — `specs/structure_spec.lua:43-55`**
Le garde-fou se contourne en supprimant trois commentaires. Ajouter un contrôle structurel : `T.isNil(m.WT._ref)` après le boot. C'est l'API hors contrat de l'oracle, la trace la plus probable d'une copie.

**B36 — nit — `tests/README.md:216`**
« (testé : rien n'est traduit, aucune erreur) … non testé pour l'instant » : la même puce dit « testé » puis « non testé ». Préciser : le mutisme est testé (`core_translate_spec.lua:87`), le message dans le chat ne l'est pas.

**B37 — nit — `tests/mutants/run_mutants.py` (`REFERENCE_EXPECTED_FAILS`)**
Voir §3 : couplage par nom exact, et code de sortie 1 de `run.lua` sur l'oracle. Option `--oracle` (xfail) recommandée.

### P — `PLAN.md`

**P8 — nit — `PLAN.md:107`**
Écrire : « **chaque** `down` arme le filet, même si l'addon est déjà actif ». C'est ce qui fixe B34. Sans cette phrase, « armé uniquement par la touche » se lit aussi comme « armé au passage à actif par la touche », c'est-à-dire Z14.

**P9 — nit — `PLAN.md:44`**
`WT.IsActive() -- true tant que la touche est maintenue` : depuis l'activation programmatique (checklist 7.7), `IsActive()` peut être vrai sans touche. Écrire « true tant que le mode traduit est actif ».

---

## 5. Avant de lancer T2-T7

Rien n'est bloquant. À faire de préférence avant T2, en moins d'une heure : B34 + P8 (test et phrase), puis B35 et B36. B37 est un confort de maintenance. Le seul « partiel » qui reste est attendu et hors de portée des auteurs : les vérifications en jeu de T0 (§8, tests 4, 5, 8 en priorité), qui pourront remettre en cause les hypothèses sur les valeurs secrètes et `IsKeyDown` avec modificateur.
