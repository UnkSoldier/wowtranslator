# Revue 08 : T1, quatrième tour

Date : 2026-11-22. Même exigence. Aucune correction appliquée, dossier du jeu non touché, rien de téléchargé. Mes exécutions sont dans le scratchpad (`python -B`) ; aucun `__pycache__` ni `WoWTranslator/` dans le projet (vérifié).

## Méthode

- Relecture de `build()`, `choose()`, `check_invariants()`, `render_lua()`, `run()`, `tools/README.md` §4, `data_spec.lua:85-120`, `tests/README.md` (« noms natifs », « Pont figé »), `PLAN.md` T1, rapport de la fixture.
- Exécutions : selftest OK (90) ; suite 45 ok / 134 ; mutants « Tout est conforme ».
- Reproductions de la revue 07 (S1/W/T/T2, `{1:A→B, 2:B→B}`, Orgrimmar) et 7 autres jeux construits à la main.
- **Fuzz** : 3000 jeux aléatoires (zones et cartes, identités, collisions), invariant de `check_invariants` vérifié, et sortie **identique quand on inverse l'ordre des entrées** (déterminisme) : 0 échec.
- Assemblage frais (SavedVariables schéma 2, format réel, 15 noms de `data_spec` + 600 paires) : `data` **7/7**. Deux mutations sur cet assemblage pour juger la liste native (§3).
- 9 mutants du collecteur rejoués : **tous détectés** comme au tour 3.
- Fixtures figées : régénération identique (`cmp`) pour les deux fichiers.

---

## 1. Notes

| | R06 | R07 | **R08** |
|---|---|---|---|
| **Globale** | 8,5 | 9 | **9/10** |
| Collecteur | 8,5 | 9 | **9/10** |
| Générateur | 8,5 | 8,5 | **9/10** |
| Docs | 8,5 | 9 | **9/10** |

Atteint au sens fixé : on livre comme base pour T3, il reste un défaut de conception mineur (G20) et des nits. Le point de repère est la lecture du premier rapport réel (sections « Pertes », « Collisions avec identité », « Collisions cibles »).

---

## 2. Statut des constats de la revue 07

| Id | Statut | Vérification |
|---|---|---|
| G17 gagnant inverse hors cible gagnante | **corrigé** | `S1→T` (1 id) / `W→T` (1 id, id 1) / `W→T2` (5 ids) : `fwd = {S1:T, W:T2}`, `bwd = {T:S1, T2:W}`. Pas de garde mutuelle (`cand` = sources dont la cible gagnante est `t`) |
| G18 identité perd les égalités | **corrigé** | `{1:A→B, 2:B→B}` : `fwd = {A:B}`, `bwd = {}`, native `[B]`. Plus de « B → A ». `choose(..., prefer=s)` fait gagner l'identité à égalité. Section « Collisions avec identité » présente |
| G19 README ne dit pas ce que la garde perd | **corrigé** | README §4.4 à §4.6 : plus de garde mutuelle, les deux seules pertes (source qui perd en direct, identité qui perd) sont énumérées |
| C12 | **corrigé** | `schedule(state.run)` pour le premier minuteur (`Collector.lua:274`) |
| D9 fixtures figées | **corrigé** | `tests/README.md`, « Pont figé » |

Aucune régression : le fuzz (3000 jeux, invariants, déterminisme sous permutation) est propre, les mutants du collecteur sont tous tués, le pont est identique à une régénération.

---

## 3. Jugement : la liste native (demandé)

**Verdict : conception acceptable et cohérente avec le contrat. Un trou de durcissement dans `data_spec` (G21).**

- **Cohérence avec `Translate` et le contrat.** `Translate` lit `WT.data[source.."_"..cible]`, c'est-à-dire `enUS_frFR` ou `frFR_enUS`. Les clés `native_enUS_frFR` et `native_frFR_enUS` ne correspondent à aucune paire de locales : elles ne peuvent être lues que par accident. Le fichier reste chargeable seul, sans globale (testé : `data` 7/7). Aucun test existant ne parcourt `WT.data` en s'attendant à deux tables (`data_spec.lua:68` n'y cherche que des entrées synthétiques « Zone N »). Risque restant : tout code **futur** qui itère `WT.data` avec `pairs` (par exemple `/wt status`, « couverture des dictionnaires », `PLAN.md:138`) comptera les listes natives comme des dictionnaires. Voir D10.
- **Oracle et mutants.** L'oracle n'a pas de listes natives : la règle stricte s'applique (« sans liste, aucune exemption », `tests/README.md`), son jeu de données passe. « Tout est conforme » confirmé.
- **Justesse du modèle.** Un nom natif est un nom que le client affiche tel quel dans les deux langues : lui refuser une entrée inverse est correct, et l'exiger (ou lui en inventer une) le traduirait à tort. La liste est le moyen minimal de dire à `data_spec` « cette absence est voulue » sans écrire d'entrées d'identité.
- **La liste peut-elle cacher un vrai manque d'inverse ?** **Oui, si elle est fausse.** Test fait sur l'assemblage : retirer l'entrée inverse d'un nom non natif fait échouer `data` ; ajouter ce même nom à `native_enUS_frFR` (avec une valeur quelconque) fait passer `data` (7/7). La liste est une donnée non vérifiée. Dans le flux normal elle est produite par le générateur à partir de vrais identifiants identiques, donc fiable ; mais rien dans le test ne s'oppose à une liste gonflée, par erreur ou par paresse. Voir G21.

---

## 4. Nouveaux constats

**G20 — mineur — `build_zone_data.py` `build()` (`if t in ident_set: ... continue`), `tools/README.md` §4.4**
*Problème* : « un nom natif n'a **jamais** d'entrée inverse », quelle que soit la fréquence. Reproduit : `X → N` pour 10 identifiants, et `N → N` (identité) pour 1 seul. Résultat : `bwd = {}`, `N` natif, `X` en collision. Un client frFR qui affiche « N » dans ces 10 lieux ne le voit pas traduit en « X », au nom d'**un** identifiant natif. C'est le même défaut de proportion que G13, côté inverse. À l'inverse, G18 avait raison de protéger les égalités : le dommage d'une fausse traduction est plus grave que celui d'un nom laissé tel quel, mais pas à 10 contre 1.
*Correction (choix à faire, pas une obligation)* : soit garder la règle (simple, sûre, documentée) et ajouter au rapport, dans « Collisions avec identité », le **nombre d'identifiants** de chaque côté (ex. « Orgrimmar : 1 identique, 10 vers Orgrimmar Gate ») pour que l'humain arbitre avant `--install` ; soit autoriser l'inverse quand les effectifs non natifs dépassent largement l'identité (seuil à fixer), ce qui demande de relâcher aussi la règle de `data_spec` « un nom natif n'a jamais d'entrée inverse ». Je recommande la première option, la moins risquée.

**G21 — mineur — `tests/specs/data_spec.lua:103`, `:118`**
*Problème* : voir §3. L'exemption teste `native[v] ~= nil` : une valeur quelconque suffit, la liste n'est contrôlée ni en cohérence (clé = valeur), ni entre fichiers, ni en taille.
*Correction* : dans `data_spec`, exiger (a) `native[n] == n` pour chaque entrée ; (b) que `native_enUS_frFR` et `native_frFR_enUS` soient **identiques** ; (c) qu'aucun nom natif ne soit une clé de `frFR_enUS` (déjà fait) ; (d) une taille raisonnable (par exemple moins de 5 % des entrées). Ajouter un test négatif : une liste native qui cache un manque est refusée par (d) ou (a)/(b).

**D10 — nit — `PLAN.md:30-42` (contrat), `:138` (T7)**
Le contrat d'interface ne mentionne pas les listes natives, et T7 (`/wt status`, couverture) ne dit pas qu'il faut lire `WT.data.enUS_frFR` / `WT.data.frFR_enUS` **par nom**, pas en itérant `WT.data`. Une phrase dans le contrat (« `WT.data.native_*` : listes de noms, pas des dictionnaires ; ne pas itérer `WT.data` ») suffit.

**G22 — nit — `tools/README.md:173`**
« Elle gagne les égalités… Elle ne gagne que par son nombre d'identifiants » : la phrase se lit comme une contradiction. Écrire : « elle gagne les égalités d'effectifs, jamais au-delà ».

---

## 5. Pour atteindre 9,5

1. **G21** : durcir `data_spec` (clé = valeur, listes identiques, taille bornée, test négatif). Moins d'une heure.
2. **G20** : afficher les effectifs des deux côtés dans « Collisions avec identité » (option recommandée). 
3. Nits : D10, G22.

Au-delà, rien de plus ne se joue sur le papier : les bornes réelles, le nombre de noms natifs, de pertes et de collisions avec identité, et le comportement de `GetAreaInfo` sur un identifiant inconnu ne seront connus qu'après la première collecte en jeu. Ordre de lecture du premier rapport : « Avertissements », « Pertes », « Collisions avec identité », « Collisions cibles », « Noms natifs ».
