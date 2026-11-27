# Revue 10 : T1, sixième tour (vérification ciblée)

Date : 2026-11-22. Aucune correction appliquée, dossier du jeu non touché, rien de téléchargé, aucun `__pycache__` ni `WoWTranslator/` dans le projet (vérifié).

## Méthode

- Exécutions : selftest OK ; suite **49 ok / 135** ; mutants « Tout est conforme ».
- Mon jeu « 609 traduites + 250 noms identiques » (celui qui faisait échouer `data_spec` en revue 09), l'assemblage de base, et quatre attaques sur la liste native, tous sur une copie de l'oracle dans le scratchpad.
- `--accept-collision` avec et sans `--strict`, avec un nom inconnu, avec un nom sous le seuil ; troncature des identifiants.

---

## 1. Notes

| | R08 | R09 | **R10** |
|---|---|---|---|
| **Globale** | 9 | 9 | **9/10** |
| Collecteur | 9 | 9 | **9/10** |
| Générateur | 9 | 8,5 | **9/10** |
| Docs | 9 | 9 | **9/10** |

Les quatre constats de la revue 09 sont corrigés. Il ne reste que des nits et la limite documentée (G24). 9/10 est atteint au sens fixé : on livre comme base pour T3, la suite ne peut venir que des données réelles.

---

## 2. Statut des constats de la revue 09

| Id | Statut | Vérification |
|---|---|---|
| G23 liste native gonflée, borne fausse | **corrigé** | jeu 609 + 250 identiques : `data` **12/12**, liste native vide (aucune collision) ; fixture : natifs = `Orgrimmar` seul ; avec `sv_xn` (collisions `Porte`, `Arche`) la liste contient exactement ces deux noms. Attaque « un nom qui n'est valeur d'aucune entrée directe » : refusée (« liste gonflée : "Nom inconnu" n'est valeur d'aucune entrée directe »). Attaque « 100 noms » : refusée (entrée inverse et taille) |
| G24 limite documentée | **corrigé** | voir §3 : la limite subsiste, elle est consignée |
| G25 arbitrage | **corrigé** | `--accept-collision NOM` répétable. Sans option : avertissement, rc 0. `--strict` seul : rc 1, rien d'écrit. `--strict --accept-collision Porte` : rc 0, fichiers écrits, rapport « Collision acceptée par l'utilisateur » et « (accepte par l'utilisateur) » dans la table. Nom inconnu : avertissement « n'est pas une collision avec identité » |
| G26 troncature | **corrigé** | `Gate0 (10 : zone 3000, … zone 3004 ... (+5))` |

Aucune régression : `data` 12/12 sur l'assemblage frais, les listes natives contiennent désormais seulement les noms exemptés.

---

## 3. Limite connue (G24) : constatée

Attaques sur la liste native de `data_spec` :

| Attaque | Résultat |
|---|---|
| A1 : 100 noms ajoutés, cohérents dans les deux fichiers | **refusée** (noms avec entrée inverse, taille) |
| A3 : nom non valeur d'une entrée directe | **refusée** |
| A2 : un manque d'inverse caché par un nom cohérent dans les deux listes | **passe** |
| A4 : 12 manques cachés (2 % de 609) | **passe** |

A2 et A4 sont la limite inévitable : les données seules ne distinguent pas « natif voulu » d'« inverse oublié ». Elle est bornée par la taille (2 %) et par le fait que le générateur produit la liste. Sur des données réelles de plusieurs milliers d'entrées, 2 % autorise une centaine de noms : plus que le nombre attendu de collisions avec identité. Voir G28.

---

## 4. Nouveaux constats

**G27 — nit — `build_zone_data.py` (`--accept-collision` avec `--strict`)**
Avec `--strict --accept-collision Nope --accept-collision Porte` (`Nope` n'est pas une collision), le programme sort en rc 0 : l'avertissement « n'est pas une collision avec identité » n'arrête pas `--strict`, alors que sa promesse est « tout avertissement est une erreur ». Une faute de frappe dans le nom accepté passe donc en silence en mode strict. Faire de cet avertissement une erreur sous `--strict`.

**G28 — nit — `tests/specs/data_spec.lua` (borne 2 %), `tools/README.md`**
Une fois les listes réduites aux seuls noms exemptés, la borne relative devient trop large pour des données réelles. Option : borne **absolue** en plus (par exemple 30 noms, réglable), à recaler sur le premier rapport (section « Collisions avec identité »). Sans effet sur T3 tant que la liste est petite.

**G29 — nit — rapport**
Un nom accepté sous le seuil (`--accept-collision Arche`, m/n = 3) ne produit ni avertissement ni note : l'acceptation est sans effet et n'est pas signalée. Soit le dire (« déjà sous le seuil »), soit le refuser comme un nom inconnu.

---

## 5. Ce qui reste

1. Nits : G27, G28, G29 (une demi-heure).
2. **Premier jeu de données réel** : bornes, part de noms identiques, collisions avec identité, comportement de `GetAreaInfo` sur un identifiant inconnu. Lecture du rapport dans l'ordre : « Avertissements », « Pertes », « Collisions avec identité », « Collisions cibles », « Noms natifs ». Recaler alors `--min-entries`, `WT_MIN_ENTRIES`, `WT_NATIVE_MAX_RATIO` (et la borne absolue de G28).
3. Hors T1 : les vérifications en jeu de T0 (§8 de `client-research.md`).
