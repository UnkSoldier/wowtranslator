# Revue 09 : T1, cinquième tour (vérification ciblée)

Date : 2026-11-22. Aucune correction appliquée, dossier du jeu non touché, rien de téléchargé, aucun `__pycache__` ni `WoWTranslator/` dans le projet (vérifié).

## Méthode

- Relecture de `build()`, des avertissements de collision, du rapport, de `data_spec.lua:85-200`, `tools/README.md` §4.4, `PLAN.md:106`, `tests/README.md:41`.
- Exécutions : selftest OK (93) ; suite 47 ok / 135 ; mutants « Tout est conforme ».
- Mes reproductions : `S1/W/T/T2` (`fwd = {S1:T, W:T2}`, `bwd = {T:S1, T2:W}`) et `{1:A→B, 2:B→B}` (`fwd = {A:B}`, `bwd = {}`) inchangés ; fuzz de 3000 jeux : invariants et déterminisme propres.
- Assemblage frais (SavedVariables schéma 2, format réel) : `data` **10/10**.
- Trois attaques sur la liste native, sur cet assemblage ; un jeu de données avec 25 % de noms identiques ; le cas `X→N` ×10 / `N→N` ×1 ; `--strict`.

---

## 1. Notes

| | R07 | R08 | **R09** |
|---|---|---|---|
| **Globale** | 9 | 9 | **9/10** |
| Collecteur | 9 | 9 | **9/10** |
| Générateur | 8,5 | 9 | **8,5/10** |
| Docs | 9 | 9 | **9/10** |

Les trois constats de la revue 08 sont corrigés comme demandé. Mais G21 a introduit un défaut : la borne de taille de la liste native (10 %) est calibrée sur une liste qui contient **tous** les noms identiques, pas seulement ceux qui ont besoin d'exemption. Sur des données plausibles, `data_spec` échouera à tort (G23). Le générateur retombe donc à 8,5 jusqu'à correction.

---

## 2. Statut des constats de la revue 08

| Id | Statut | Vérification |
|---|---|---|
| G20 effectifs des deux côtés | **corrigé** | rapport « Collisions avec identité » : identifiants identiques (n), concurrents (m), m/n, sources avec zones et cartes, tri par déséquilibre. Cas `Gate0` ×10 → `Porte` ×1 identique : m/n = 10, avertissement stderr, **`--strict` : rc 1, aucun fichier**. Cas `Arch` ×3 → `Arche` : m/n = 3, listé sans avertissement. Seuil 5 raisonnable |
| G21 durcissement de `data_spec` | **corrigé, avec un défaut** | attaque 1 (liste native avec une valeur `"x"`) : **refusée** ; attaque 3 (liste gonflée à 100 noms) : **refusée** (inverse et taille). Voir G23 pour la borne, G24 pour ce qui reste invérifiable |
| G22 formulation README | **corrigé** | §4.4 : « gagne à égalité d'effectifs, et jamais au-delà » |
| D10 contrat et T7 | **corrigé** (par vous) | `PLAN.md:106` : lire les dictionnaires par nom, jamais `pairs(WT.data)` |

---

## 3. Jugement des seuils

- **`COLLISION_RATIO = 5`** : sensible. À 3 contre 1, un arbitrage humain n'apporte guère ; à 10 contre 1, oui. Avertissement seulement (jamais une règle de traduction) : bon choix.
- **`WT_NATIVE_MAX_RATIO = 0,10`** : **non sensible tel quel**, voir G23.

---

## 4. Nouveaux constats

**G23 — majeur — `build_zone_data.py` `build()` (`"native": identity`), `tests/specs/data_spec.lua:172`**
*Problème* : la liste native contient **tous** les noms identiques dans les deux langues, alors que l'exemption n'est nécessaire que pour ceux qui sont **valeur** d'une entrée directe (les noms de « Collisions avec identité »). La borne de 10 % de `data_spec` est comparée aux entrées directes (hors identités gagnantes). Or les noms propres conservés en français sont fréquents dans les noms de zones. Mesuré sur un jeu valide : 609 entrées traduites + 250 noms identiques (25 %) : liste native 256 contre 609 entrées, **`data_spec` échoue** (« liste native trop grande : 256 nom(s) sur 609 entrées »), alors que les données sont correctes. Fuzz : 685 noms natifs listés sans être valeur d'aucune entrée directe sur 500 jeux. Sur les vraies données la part est inconnue ; si elle dépasse 10 %, le premier `data_spec` de T3 échouera, et la parade (`WT_NATIVE_MAX_RATIO` relevé) vide la borne de son sens (la liste peut alors cacher des dizaines de manques).
*Correction* : ne lister dans `native_*` que les noms **exemptés**, c'est-à-dire les noms natifs qui sont valeur d'au moins une entrée directe (`collisions_identity`). Ajouter à `data_spec` : chaque nom listé **est** valeur d'une entrée directe (sinon la liste est gonflée). La borne de taille peut alors être serrée (2 % par exemple) et garde son sens. Mettre à jour le README §4.4 et les fixtures figées.

**G24 — nit — `data_spec.lua:140-175`, attaque 2**
Une liste native **cohérente** (clé = valeur, identique dans les deux fichiers, petite) qui contient un nom dont l'inverse manque **passe** (attaque 2 : `data` 10/10). C'est inévitable avec les seules données (rien ne distingue « natif voulu » d'« inverse oublié »). Le risque est borné par la taille et par le fait que la liste est produite par le générateur. À consigner dans `tests/README.md` comme limite connue (comme celle déjà notée pour les copies de dictionnaires). Après G23, une vérification supplémentaire devient possible : chaque nom natif listé doit figurer dans le rapport « Collisions avec identité » du générateur, que le selftest compare à la liste.

**G25 — mineur — `build_zone_data.py` (avertissements `--strict`, rapport « Collisions avec identité »)**
*Problème* : le rapport dit « Arbitrer avant `--install` », mais il n'existe **aucun moyen d'arbitrer** : pas d'option pour forcer l'inverse d'un nom natif, ni pour reconnaître une collision examinée. Avec `--strict`, une collision à m/n ≥ 5 bloque définitivement le générateur. Sans `--strict`, l'avertissement reste sans suite possible.
*Correction* : au choix (a) un fichier de décisions versionné (`tools/decisions.txt` : « accepter `Porte` » pour lever l'avertissement, éventuellement « inverse `Porte` -> `Gate0` » pour forcer, ce qui demande de relâcher la règle « un nom natif n'a jamais d'entrée inverse ») ; (b) au minimum, `--accept-collision NOM` répétable qui lève l'avertissement strict pour ce nom. Option (b), la plus simple, suffit.

**G26 — nit — rapport « Collisions avec identité »**
La colonne « Sources : identifiants » énumère **tous** les identifiants (10 dans mon cas). Sur les vraies données, un nom à 200 identifiants fera une ligne illisible. Tronquer à 5 identifiants par source et ajouter « … (+N) ».

---

## 5. Pour atteindre 9/10 (générateur) et au-delà

1. **G23** : ne lister que les noms exemptés, test « chaque nom listé est valeur d'une entrée directe », borne serrée. C'est le seul point qui peut casser T3 sans prévenir.
2. **G25** : `--accept-collision` (ou équivalent).
3. Nits : G24 (limite documentée), G26.

Au-delà, rien ne peut plus être vérifié sans les données réelles : bornes, parts de noms identiques, collisions avec identité, comportement de `GetAreaInfo` sur un identifiant inconnu. Lire le premier rapport dans l'ordre « Avertissements », « Pertes », « Collisions avec identité », « Collisions cibles », « Noms natifs ».
