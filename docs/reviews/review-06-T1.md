# Revue 06 : T1, deuxième tour

Date : 2026-11-21. Même exigence que la revue 05. Aucune correction appliquée, dossier du jeu lu en lecture seule, rien de téléchargé. Tout ce que j'ai produit est dans le scratchpad ; aucun `__pycache__` ne reste dans le projet (`python -B` partout, vérifié par `find`).

## Méthode

1. Relecture complète de `Collector.lua` (354 l.), `build_zone_data.py` (1061 l.), `tools/README.md`, `tests/specs/collector_spec.lua`, `tests/fixtures/collector/`, `client-research.md` §4 et question 12, `PLAN.md` (T1, T3, T5), `tests/README.md`.
2. Exécutions :
   - `--selftest` : **70 ok, 0 KO** ; suite du projet : **42 ok, 134 « addon absent »** ; `run_mutants.py` : « Tout est conforme » (Z14 y est bien détecté).
   - **Assemblage frais** : SavedVariables **schéma 2** au format réel (CRLF, compact, 15 noms de `data_spec` + 600 paires + 2 cartes), généré par la copie de `tools/` dans le scratchpad, copié dans une copie de l'oracle sans ses `Data/` : `data` = **7 ok sur 7** (6 de `data_spec` + le pont). Suite complète sur cet assemblage : 175 ok, 1 échec (le garde-fou anti-oracle, voulu).
   - **Débit** : 12000 zones + 1499 cartes par langue (0,7 Mo), génération complète en 0,5 s.
   - **Entrées hostiles** sur l'analyseur : voir G7.
   - **`--install`** testé dans une **copie** de `tools/` (le dépôt n'a jamais reçu de `WoWTranslator/`) : voir G1.
   - **Mutants du collecteur** (12, sur une copie) : voir C7.
   - **Banc de simulation** du collecteur (`C_Map`, `C_Timer` simulés) : voir C8.

---

## 1. Notes

| | R05 | **R06** |
|---|---|---|
| **Globale** | 7 | **8,5/10** |
| Collecteur | 7,5 | **8,5/10** |
| Générateur | 7 | **8,5/10** |
| Docs | 6,5 | **8,5/10** |

Tous les constats de la revue 05 sont corrigés, vérifiés par exécution, et sans régression. Les trois défauts de fond (écrasement du bloc complet, écriture avant validation, sens inverse faux) sont réglés proprement. Il reste un défaut de conception moyen, **G13** (la règle d'identité exclut trop), et une série de trous de test et de nits. Rien ne bloque T3, sauf G13 à trancher avant de lire le premier rapport réel.

---

## 2. Statut des constats de la revue 05

| Id | Statut | Vérification |
|---|---|---|
| C1 bloc écrit au démarrage | **corrigé** | `Collector.lua:165` (`ensureDB()[state.locale] = work` seulement dans `finish`). Mutant M1 « écrit au démarrage » : 5 échecs. Banc : l'ancien bloc survit à `/reload` et à `stop` |
| C2 bornes et compteurs absents | **corrigé** | champs `maxAreaId`, `maxMapId`, `maxFound*`, `unknownIds`, `secretIgnored`, `emptyIgnored`, `complete`, `schema` (`:171-181`, `:262-271`) ; avertissements `NEAR_BOUND` et `MIN_AREAS` ; le générateur les re-vérifie (`validate_block`, `check_pair`) |
| C3 « erreurs API » alarmant | **corrigé** | compteur « sans nom », texte neutre (`:164-166`) |
| C4 `step` non protégé, pas de `stop` | **corrigé** | `pcall(tickBody)` `:222`, `/wtcollect stop` ; test « erreur Lua inattendue » |
| C5 | sans objet | |
| C6 `status` ne compare pas le build | **corrigé** | `:286-290`, test « status » |
| C7 pas de spec du collecteur | **corrigé, avec réserves** | 14 tests, dans `SPECS` (`run.lua:29`). Réserves : C9, C10 |
| G1 écriture avant seuil, défaut dangereux | **corrigé** | validations avant écriture (`run`), seuil : rapport seul, `tools/out/` par défaut, `--install` explicite et incompatible avec `--out-dir`, `write_atomic`. Refus d'écraser un fichier non généré **vérifié** (copie de l'oracle refusée, rc 1, rien écrit). Résidus : G14, G15 |
| G2 blocs partiels acceptés | **corrigé** | `complete`, `schema`, `locale`, compteurs, bornes, `maxFound*` : tout refusé en code 1 ; `version`/`build`/`toc` différents : refus sauf `--allow-mismatch` ; couverture, bornes, proximité : avertissements, `--strict` |
| G3 sens inverse sans effectifs | **corrigé** | `{Rare:1, Common:5}` → `bwd[X] = Common` (le cas d'avant donnait `Rare`) |
| G4 identités ignorées dans le sens inverse | **corrigé, mais sur-corrigé** | le cas `{A,B}` ne produit plus de traduction fausse. Voir **G13** (exclusion trop large) |
| G5 normalisation des clés | **corrigé** | clés brutes (`'  Thousand    Needles '` conservé), formes brutes et variantes typographiques au rapport |
| G6 zone/carte | **corrigé** | `choose()` : zone prime, origine au rapport, section « Conflits zone contre carte » ; reporté dans `PLAN.md` T5 |
| G7 analyseur | **corrigé** | profondeur 50, `RecursionError` rattrapé, entier géant : « nombre hors limite », BOM accepté, `--[==[ ]==]`, `\` + CRLF → `\n`. Vérifié : 5000 et 100000 niveaux → `DataError` |
| G8 sentinelle `"absent"` | **corrigé** | `_MISSING = object()` ; `{1:"absent"}` joint normalement |
| G9 libellé de build | **corrigé** | `1.60.1.71037 (toc 16001)` |
| G10 `\|` dans le rapport | **corrigé** | `md_cell` |
| G11 selftest | **corrigé, avec réserve** | fixture au format réel, bloc incomplet, seuil sans fichier, pont figé. Réserve : G15 |
| G12 mode CSV mort | **corrigé** | supprimé, fixtures CSV aussi |
| D1 commande vers `WoWTranslator/Data` | **corrigé** | §2.6 écrit dans `tools/out/`, `--install` réservé à T3 |
| D2 `client-research.md` §4 | **corrigé** | marqué SUPPLANTÉ, question 12 close |
| D3 étapes utilisateur | **corrigé** | activation, même compte, plausibilité, pas de `/reload`, désactivation (§2.4), recherche PowerShell du fichier, noms de constantes |
| D4 PLAN | **corrigé** (par vous) | `PLAN.md:31-33`, `:74` |

---

## 3. Réponses aux questions du tour 2

- **L'exclusion d'identité supprime-t-elle des entrées légitimes ?** Oui : G13.
- **`--install` respecte-t-il « jamais écraser un fichier non généré » ?** Oui pour les deux fichiers de données (testé : fichier de l'oracle refusé, code 1, aucune écriture ; fichiers générés remplacés). Mais le rapport n'est pas gardé (G14), et la garde repose sur une chaîne dans les 400 premiers octets.
- **La spec du collecteur teste-t-elle le vrai comportement ?** Pour l'essentiel oui : elle charge le vrai `Collector.lua`, fait tourner les vrais ticks du mock, simule `/reload` en rechargeant le fichier. Mais j'ai passé 12 mutants : 9 sont détectés, 3 survivent (voir C7). L'un d'eux est une vraie lacune due à une particularité du mock (C9).

---

## 4. Nouveaux constats

### C — Collecteur

**C7 (suite) — résultat des mutants sur `collector_spec.lua`**

| Mutant | Résultat |
|---|---|
| M1 bloc écrit au démarrage | détecté (5 échecs) |
| M4 pas de `pcall` dans `step` | détecté |
| M5 `complete` jamais posé | détecté (2) |
| M7 `BATCH = 100000` | détecté |
| M8 avertissement `MIN_AREAS` retiré | détecté |
| M9 `status` ignore `complete` | détecté |
| M10 `reset` autorisé pendant la collecte | détecté |
| M11 `lastArea` non suivi | détecté |
| M12 `info` secret non testé (cartes) | détecté |
| **M2 avertissement `NEAR_BOUND` retiré** | **survit** : voir C10 |
| **M3 `stop` ne remet pas `running` à faux** | survit, mais **équivalent** : `work = nil` fait lever `tickBody`, le `pcall` arrête la collecte. Comportement observable identique |
| **M6 test du secret après `name:find(...)`** | **survit** : voir C9 |

**C9 — mineur — `collector_spec.lua:117-128`, `:120`, `tests/wow_mock.lua:734`**
*Problème* : le test « valeur secrète » utilise `m.MakeSecret("Zone secrete")`, qui **marque une chaîne par valeur** : la chaîne reste une chaîne ordinaire, sur laquelle `:find`, `==`, `type` ne lèvent rien. La règle du projet (`PLAN.md:53`, `client-research.md` §5.6) est de tester `issecretvalue` **avant toute opération**. Un collecteur qui fait `name:find("%S")` avant le test passe donc la spec (mutant M6). Le mock offre `mock.NewSecretProxy()` (`tests/README.md:145`) dont toute opération lève, justement pour cela.
*Correction* : dans le test, renvoyer `m.NewSecretProxy()` pour une zone, et pour **le nom** d'une carte, et pour la **table** `info` d'une autre carte. Attendu : aucun échec Lua, compteurs `secretIgnored` = 3, rien de stocké.

**C10 — mineur — `collector_spec.lua` (absence), `Collector.lua:182-192`**
*Problème* : l'avertissement « borne trop basse » (`NEAR_BOUND`) n'est testé nulle part (mutant M2). C'est pourtant le garde-fou de la question ouverte n° 1 (bornes non confirmées). Même remarque pour l'avertissement carte (`:188-191`).
*Correction* : `world(950, 10)` avec `start 1000 20` : le message « pres de la borne 1000 » doit apparaître ; `start 5000 20` : il ne doit pas apparaître. Idem pour les cartes.

**C8 — nit — `Collector.lua:197-199`, `:230-236`, `:299-306`**
*Problème* : `stop` puis `start` rapides laissent un **second** minuteur en attente de l'ancienne chaîne : mesuré, 2 minuteurs en attente après `stop` + `start`, la collecte tourne deux fois plus vite avec deux chaînes qui partagent l'état. Le résultat est correct ici (état partagé, un seul `termine`), mais par chance : le mécanisme n'est pas sûr si l'on modifie un jour `tickBody`.
*Correction* : un compteur `state.run` incrémenté à chaque `start`, capturé par la fermeture planifiée (`local id = state.run; C_Timer.After(DELAY, function() if id == state.run then step() end end)`), ou un test explicite « stop puis start : un seul minuteur ».

**C11 — nit — `Collector.lua:98-110`, `:170`**
Si `GetBuildInfo` est absent ou renvoie un `toc` non entier, le bloc est écrit sans `toc` et le générateur le refusera plus tard (« champ 'toc' absent »), sans que le collecteur l'ait dit. Ajouter un `ATTENTION` à `finish` quand `toc` n'est pas un entier.

### G — Générateur

**G13 — mineur — `build_zone_data.py:471-475` (`identity`, `usable`), `tools/README.md` §4.4**
*Problème* : la règle d'identité exclut un nom des **deux sens**, avec **toutes** les paires qui le touchent, dès **un seul** identifiant où les deux langues coïncident. Vérifié :
- `{1..6: "Spire"}` contre `{1..5: "Flèche", 6: "Spire"}` : **aucune entrée** (6 paires exclues), alors que 5 identifiants sur 6 disent « Flèche ». Un seul nom resté non traduit dans le client (cas connu chez Blizzard pour certaines sous-zones) supprime la traduction de tout le nom ;
- un seul **identifiant de carte** identique tue trois zones traduites (`identity via map only`) ;
- `{1: "Orgrimmar Gate" -> "Orgrimmar", 2: "Orgrimmar" -> "Orgrimmar"}` : la paire « Orgrimmar Gate » → « Orgrimmar » est exclue **dans le sens direct** aussi, où elle est pourtant correcte (un client enUS qui affiche « Orgrimmar Gate » doit recevoir « Orgrimmar »). Le danger décrit en 4.4 ne concerne que le sens **inverse** (« Orgrimmar » traduit en « Orgrimmar Gate »).
*Correction* : appliquer l'identité comme un candidat ordinaire, par la fréquence : (a) sens direct : le nom source garde l'identité parmi les cibles ; si l'identité gagne (effectifs, zone avant carte), pas d'entrée ; sinon la cible gagnante reste, et l'identité est listée au rapport comme « identité minoritaire écartée » ; (b) sens inverse : pour une cible `t` qui est aussi nom source à identité majoritaire, ne pas créer `frFR_enUS[t]` ; sinon le créer. Ne **pas** exclure le sens direct à cause du sens inverse. Rapport : nombre d'identifiants perdus par nom identique (aujourd'hui : « paires exclues » global seulement).
*Remarque* : sur les données réelles, la gravité dépend du nombre de noms partiellement localisés, inconnu avant la première collecte ; le rapport actuel ne permet pas de le mesurer par nom (voir la correction).

**G14 — nit — `build_zone_data.py:795-805`, `:854-856`**
`--report` écrase **n'importe quel fichier** sans garde (vérifié : `--report precious.txt` remplace un fichier de la copie). Appliquer la même garde « généré par » (première ligne `# Rapport de couverture`) ou refuser un chemin existant non généré. Autre résidu : `os.replace` successifs ne sont pas atomiques **entre** les trois fichiers (une erreur entre deux remplacements laisse un mélange) ; très improbable, à documenter.

**G15 — mineur — selftest (`build_zone_data.py` section « Autotest »)**
*Problème* : le selftest passe toujours `--out-dir` et `--report` : ni le **chemin par défaut** (`tools/out/`), ni `--install`, ni leur incompatibilité, ni la garde d'écrasement **en mode installation** ne sont couverts. C'est la partie de G1 que l'utilisateur rencontrera. Je l'ai testée à la main sur une copie : elle fonctionne, mais rien ne la protège d'une régression.
*Correction* : un test qui copie `tools/` (ou le script) dans un dossier temporaire, lance sans `--out-dir`, et vérifie que seuls `tools/out/*` apparaissent et qu'aucun `WoWTranslator/` n'est créé ; un second avec `--install` vers ce dossier temporaire (fichier non généré préexistant : refus).

**G16 — nit — `build_zone_data.py:571-573`, `:633-635`**
Les comptes « Identifiants seulement enUS / frFR » ne distinguent pas zones et cartes dans le rapport (seul l'avertissement de couverture le fait). À séparer si les avertissements apparaissent sur les données réelles.

### D — Docs

**D5 — nit — `tools/README.md:3`, `:203`, `tools/.gitignore`**
« ignoré par git » : le projet n'est pas un dépôt git (`tools/.gitignore` est donc inerte). Dire « dossier de travail, jetable ; supprimer avant toute copie ». Sans effet fonctionnel.

**D6 — nit — `tools/README.md:233`**
Question ouverte 6 (« T5 hérite de la traduction de zone… à reporter dans `PLAN.md` ») est périmée : c'est reporté (`PLAN.md:130`). La clore.

**D7 — nit — `PLAN.md:123-124`**
T3 dit « Lancer T1, … commiter `Data/*` » sans mentionner `--install` ni la relecture de `tools/out/rapport_couverture.md`. Ajouter : « générer dans `tools/out/`, relire le rapport (G13), puis `--install` ».

**D8 — nit — `docs/test-checklist.md:11`**
« Aujourd'hui, seul **enUS** est installé » contredit `client-research.md` §4 (pack français installé le 21/11/2026) et la procédure de collecte frFR. Hors T1, mais la collecte frFR n'a de sens que si le pack est là.

---

## 5. Pour atteindre 9/10

1. **G13** : règle d'identité par fréquence (candidat ordinaire), avec comptage des identifiants perdus par nom identique au rapport. C'est le seul point de conception ; sans lui, un seul identifiant non localisé efface un nom entier.
2. **C9 + C10** : proxy secret dans la spec (rend la règle « secret avant toute opération » réellement testée) et tests de l'avertissement de borne. 20 minutes.
3. **G15** : test du chemin par défaut et de `--install` (aucun `WoWTranslator/` ne doit apparaître hors installation).
4. Nits : C8 (jeton de génération du minuteur), C11, G14, G16, D5 à D8.

Après ces points, la base est à 9/10. Le seul inconnu qui restera est hors de portée des auteurs : les chiffres réels (bornes, nombre de noms non localisés, comportement de `GetAreaInfo` sur un identifiant inconnu), qui viendront avec la première collecte. Premier réflexe à ce moment-là : lire dans le rapport la liste des noms identiques exclus et les avertissements de couverture.
