# Revue 07 : T1, troisième tour

Date : 2026-11-21. Même exigence que les revues précédentes. Aucune correction appliquée, dossier du jeu non touché, rien de téléchargé. Mes exécutions sont dans le scratchpad (`python -B` partout) ; aucun `__pycache__` ni `WoWTranslator/` dans le projet (vérifié).

## Méthode

- Relecture de `Collector.lua`, de `build()` / `choose()` / `run()` dans `build_zone_data.py`, de `tools/README.md` §3-§4, de `collector_spec.lua`, du rapport produit par la fixture.
- Exécutions : selftest **78 ok** ; suite **45 ok / 134** ; collecteur **17 ok** ; mutants « Tout est conforme ».
- **Mutants du collecteur** sur une copie (9) : M1 écriture au démarrage, M2/M2b/M2c bornes (zones, cartes, toujours), M6/M6b/M6c opération sur une valeur avant le test de secret (zone, nom de carte, table `info`), M13 jeton retiré, M14 avertissement `toc` retiré. **Tous détectés** (un seul échec chacun, ou 5 pour M1). M2 et M6, qui survivaient au tour 2, sont désormais tués.
- Banc de simulation : `stop` puis `start` laisse encore 2 minuteurs en attente, mais l'ancien ne fait plus rien (jeton) ; 1250 appels API au total, un seul « termine ».
- Assemblage frais (SavedVariables schéma 2 au format réel, 15 noms de `data_spec` + 600 paires) : `data` **7/7** ; suite complète : seul le garde-fou anti-oracle échoue (voulu).
- `--install`, `--report` et garde d'écrasement testés sur une copie de `tools/` (voir G14, G15).
- **Expériences sur `build()`** : 7 jeux de paires construits à la main (G13, G17, G18).

---

## 1. Notes

| | R05 | R06 | **R07** |
|---|---|---|---|
| **Globale** | 7 | 8,5 | **9/10** |
| Collecteur | 7,5 | 8,5 | **9/10** |
| Générateur | 7 | 8,5 | **8,5/10** |
| Docs | 6,5 | 8,5 | **9/10** |

Au sens fixé (« on livre comme base, il ne reste que des nits ») : **atteint pour le collecteur et les docs**. Le générateur est à 8,5 : la garde de paire mutuelle, que je juge sûre mais trop stricte (G17), perd des entrées légitimes dans un cas simple, et la règle d'identité par fréquence peut produire une traduction fausse d'un nom natif (G18). Aucun des deux n'est bloquant, tous deux sont mesurés par la section « Pertes » du rapport. Note globale arrondie à 9 parce que l'ensemble est livrable pour T3 à condition de lire ce rapport.

---

## 2. Statut des constats de la revue 06

| Id | Statut | Vérification |
|---|---|---|
| G13 règle d'identité trop large | **corrigé** | `build()` : l'identité est un candidat de `choose()`. Cas `Spire` (1 identité, 5 « Flèche ») : `Spire -> Flèche` gardé ; cas identité d'une seule carte : plus de perte globale ; fixture « Orgrimmar Gate » (id 23) donne une entrée directe. Sections « Pertes » et « Noms identiques » présentes et justes. Deux défauts nouveaux : G17, G18 |
| C8 deux chaînes de minuteurs | **corrigé** | jeton `state.run`, `schedule(token)`, `step(token)` (`Collector.lua:34`, `:152`, `:223-224`) ; test « stop puis start » ; mutant M13 tué |
| C9 `MakeSecret` au lieu du proxy | **corrigé** | test « valeur secrète (proxy : toute opération lève) » ; M6, M6b, M6c tués |
| C10 avertissement de borne non testé | **corrigé** | test « borne trop basse » (zones et cartes, présent et absent) ; M2, M2b, M2c tués |
| C11 `toc` absent | **corrigé** | `Collector.lua:186-187`, test « toc absent » ; M14 tué |
| G14 `--report` sans garde | **corrigé** | `is_generated(report_path, REPORT_MARK)` avant toute écriture, y compris au chemin « seuil » ; `--report precious.txt` : rc 1, fichier intact, aucun fichier de données. Non-atomicité des trois remplacements documentée (README §3) |
| G15 selftest chemin par défaut et `--install` | **corrigé** | tests du chemin par défaut, de `--install`, de la garde, de `--install` + `--out-dir`. Vérifié à la main sur copie : défaut = `tools/out/` seul, aucun `WoWTranslator/` créé ; `--install` refuse un fichier de l'oracle |
| G16 zones/cartes non séparées | **corrigé** | « seulement enUS, zones / cartes » au rapport |
| D5 « ignoré par git » | **corrigé** | README §7 : `.gitignore` conditionnel, « pas un dépôt git aujourd'hui » |
| D6 question 6 périmée | **corrigé** | remplacée (nombre de noms identiques et pertes, à lire au premier rapport) |
| D7 PLAN T3 | **corrigé** (par vous) | `PLAN.md` T3 : collectes, `tools/out/`, rapport, échantillon, puis `--install` |
| D8 checklist « seul enUS » | **corrigé** | `test-checklist.md:11` |

---

## 3. Jugement : la garde de paire mutuelle (demandé)

**Règle** (`build()`, `partner`, README §4.6) : `fwd[s] = t` est gardée seulement si `bwd_win[t]` existe, vaut `w != t`, et `fwd_win[w] == t`.

**Pourquoi l'auteur a raison de ne pas « simplement omettre `frFR_enUS[t]` »** : `data_spec.lua` exige que chaque **valeur** du sens direct soit une **clé** du sens inverse (`r == nil` est une incohérence). Un `fwd[s] = t` sans `bwd[t]` ferait échouer le test.

**Mais l'invariant de `data_spec` n'est pas sain pour des données réelles dans un cas : l'identité.** Dire qu'une chaîne `t` doit toujours avoir une entrée inverse n'a de sens que si `t` change de langue. Une cible qui est aussi un nom natif (« Orgrimmar ») n'a, correctement, **pas** d'entrée inverse : un client frFR qui voit « Orgrimmar » n'a rien à traduire. Le test oblige donc le générateur à **jeter** une entrée directe correcte (`Orgrimmar Gate -> Orgrimmar`) pour satisfaire une règle qui n'est pas un besoin du produit. Deux issues propres : (a) faire accepter à `data_spec` une valeur absente des clés inverses **si** cette valeur est un nom identique connu ; (b) écrire les entrées d'identité (`["Orgrimmar"] = "Orgrimmar"`) dans les deux tables : l'invariant tient (`sources[v] > 1` et `fwd[bwd[v]] == v`), `Translate` renvoie le même texte, et le coût est de quelques dizaines de lignes. Ce n'est pas à l'auteur de T1 de changer `data_spec` seul ; c'est une décision à prendre avec le propriétaire des tests.

**Cas où la garde perd à tort : G17.**

---

## 4. Nouveaux constats

### G — Générateur

**G17 — mineur — `build_zone_data.py` `build()`, `partner()` (garde de paire), `tools/README.md` §4.6**
*Problème* : le gagnant du sens inverse `bwd_win[t]` est choisi parmi **toutes** les sources de `t`, y compris celles dont la cible gagnante est **ailleurs**. Si ce gagnant `w` a sa cible gagnante `t' != t`, la garde fait échouer **toutes** les paires vers `t`, alors qu'une source `s1` dont `t` est la seule traduction est légitime. Reproduit :
- `S1 -> T` (1 identifiant, id 10) ; `W -> T` (1 identifiant, id 1, le plus petit) et `W -> T2` (5 identifiants).
- Résultat : `fwd = {W: T2}`, `bwd = {T2: W}`. `S1 -> T` est **perdue** (listée au rapport), alors que `T -> S1` est un résultat cohérent (aucune ambiguïté réelle : `W` va vers `T2`).
*Correction* : choisir le gagnant du sens inverse parmi les **sources dont la cible gagnante est `t`** (comme faisait la revue 06 avec `kept`), puis appliquer l'invariant. Attendu : `fwd = {W: T2, S1: T}`, `bwd = {T2: W, T: S1}`. L'identité reste un candidat : si l'identité est gagnante pour `t`, pas d'entrée inverse (et voir §3).

**G18 — mineur — `build_zone_data.py` `choose()`, `tools/README.md` §4.4**
*Problème* : à égalité d'effectifs, `choose` départage par plus petit identifiant, **y compris contre une paire identique**. Reproduit : `{1: A -> B, 2: B -> B}` donne `bwd[B] = A` : un client frFR dans la zone 2 (vrai nom « B ») la verra traduite en « A ». Même effet à effectifs inégaux dans la fixture : `Orgrimmar` (identité, 1 identifiant) perd contre `Orgrimmar Gate` (2) : la ville « Orgrimmar » s'affiche « Orgrimmar Gate » dans un client frFR (le README §4.4 le documente comme voulu). Le dommage n'est pas symétrique : traduire à tort un nom natif (visible, faux) est pire que laisser en l'état (neutre).
*Correction* : à égalité d'effectifs, l'identité l'emporte (plus petit identifiant ne doit pas jouer contre elle) ; et marquer au rapport « collision cible avec identité » (colonne ou drapeau dans « Collisions cibles »), avec les identifiants, pour relecture humaine avant `--install`. Le libellé « traduction ailleurs (voir Pertes) » de « Noms identiques » ne dit pas que le nom natif sera mal traduit côté frFR : le dire.

**G19 — nit — `tools/README.md` §4.6, `build()`**
Le README présente la garde comme « chaque entrée d'un sens a son inverse » sans dire qu'elle perd une paire quand le gagnant inverse a sa cible ailleurs (G17) ni quand l'identité gagne (§3). Une fois G17 corrigé, ne reste que le second cas : l'écrire, avec la remarque sur `data_spec`.

### C — Collecteur

**C12 — nit — `Collector.lua:272-275`**
`start` planifie `C_Timer.After(0, ...)` sans passer par `schedule`, par cohérence ; aucun effet. Les anciens minuteurs en attente restent dans la file jusqu'à leur échéance (inoffensifs grâce au jeton). Rien à faire.

### D — Docs

**D9 — nit — `tests/README.md`, `PLAN.md`**
Le README de tests et le PLAN annoncent bien 45 ok / 134, mais rien n'y dit que le pont lit des **fixtures figées** (`tests/fixtures/collector/`) comparées par le selftest : un changement de règle du générateur exige de les régénérer (commande donnée dans `tools/README.md` §3). Une ligne dans `tests/README.md` suffit.

---

## 5. Pour atteindre 9/10 (générateur) et 9,5

1. **G17** : gagnant du sens inverse restreint aux sources dont la cible gagnante est `t`. Test d'unité : le cas `S1/W/T/T2` ci-dessus (fixture : un nom `W` à 6 identifiants, une seule source concurrente).
2. **G18** : l'identité gagne les égalités ; drapeau « collision avec identité » au rapport.
3. **§3** : décider avec le propriétaire de `data_spec` entre (a) relâcher l'invariant pour les noms identiques et (b) écrire les identités. Tant que ce n'est pas fait, des entrées directes correctes sont perdues quand la cible est un nom natif, et elles sont listées dans « Pertes ».
4. Nits : G19, C12, D9.

Reste hors de portée des auteurs : les chiffres réels (bornes, nombre de noms identiques, de pertes et de collisions avec identité), connus seulement après la première collecte. Premier réflexe à ce moment : lire dans le rapport « Pertes », « Collisions cibles » et « Noms identiques », dans cet ordre.
