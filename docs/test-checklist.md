# Checklist de test en jeu — WoWTranslator

Client : **WoW: Forever 1.60.1 (71037)**, `## Interface: 16001` (voir `docs/client-research.md`).
L'addon s'installe dans `D:\World of Warcraft\_forever_\Interface\AddOns\WoWTranslator\` (pas dans `_retail_`).

Avant la session en jeu, lancer les tests hors jeu depuis la racine du projet :
`python tests/tools/luarun.py tests/run.lua` (ou `lua5.1 tests/run.lua` si un interpréteur est installé). Le résultat doit être `0 echec(s)`. Voir `tests/README.md`.

Chaque scénario donne des **Étapes** et un **Attendu**. Cocher chaque case et noter le résultat : OK, ou KO avec une capture et le message d'erreur.

> **Pack de langue.** Les deux packs sont installés (enUS et frFR, 2026-11-21). Les scénarios marqués **[frFR]** demandent que la langue du texte soit réglée sur Français dans Battle.net (Paramètres du jeu > Langue du texte), jeu relancé ; vérifier `/run print(GetLocale())` → `frFR`. Sans ce réglage, le client reste en enUS et seuls les scénarios [enUS] s'appliquent. Le sens frFR → enUS se vérifie aussi, de façon indirecte, via l'override `/wt lang` (scénario 7.2).

> **Texte d'arrivée central.** `ZoneTextString` et `SubZoneTextString` s'effacent en fondu environ **3,5 s** après leur affichage (0,5 + 1 + 2 s). Les vérifier dans cette fenêtre, sinon le texte est simplement invisible : ce n'est pas un KO. La **minimap**, elle, est toujours visible.

---

## 0. Préparation (à chaque session)

- [ ] **0.1 Activer les erreurs Lua**
  - Étapes : `/console scriptErrors 1`, puis `/reload`.
  - Attendu : toute erreur Lua s'affiche dans une fenêtre. Garder ce réglage actif pendant toute la checklist. Une fenêtre d'erreur qui mentionne `WoWTranslator` est un KO (noter le texte complet).
- [ ] **0.2 Version et locale**
  - Étapes : `/run print(GetBuildInfo())`, puis `/run print(GetLocale())`.
  - Attendu : `1.60.1  71037  …  16001`, puis `enUS` (ou `frFR` pour les scénarios [frFR]).
- [ ] **0.3 Addon chargé**
  - Étapes : écran des personnages > AddOns. En jeu : `/run print(WoWTranslator and WoWTranslator.Translate and "ok", WT)`.
  - Attendu : l'addon apparaît sans mention « Périmé » ni « Incompatible ». La commande affiche `ok nil` : la globale `WT` ne doit **pas** exister.
- [ ] **0.4 Raccourci**
  - Étapes : Options > Gameplay > Raccourcis. Trouver la section **WoWTranslator** (une section à part, grâce à `category="BINDING_HEADER_WOWTRANSLATOR"`). Assigner une touche **sans modificateur** (par exemple `F6`) à « Afficher l'autre langue ».
  - Attendu : la section et l'action existent, avec un libellé lisible (pas `BINDING_NAME_…`).
- [ ] **0.5 Addons en conflit**
  - Étapes : noter si EllesmereUIMinimap est actif sur ce personnage.
  - Attendu : s'il est actif, la minimap Blizzard est cachée. Les étapes « minimap » sont alors **non applicables** (pas KO).

## 1. Comportement de base (enUS → frFR)

- [ ] **1.1 Appui / relâchement (minimap)**
  - Étapes : à Hurlevent (Stormwind City), hors sous-zone si possible, maintenir la touche puis relâcher.
  - Attendu : pendant l'appui, le nom de la **minimap** affiche **Hurlevent**. Au relâchement, **Stormwind City** revient immédiatement. (Pour le grand texte central, voir 1.3.)
- [ ] **1.2 Sous-zone**
  - Étapes : dans Stormwind, entrer dans Trade District, puis maintenir la touche.
  - Attendu : la minimap affiche **Quartier commerçant**. Si le texte central est encore visible, il est traduit aussi. Au relâchement, retour à l'anglais.
- [ ] **1.3 Texte d'arrivée central**
  - Étapes : franchir une frontière de zone et maintenir la touche **dans les 3 secondes** pendant que le grand texte est affiché.
  - Attendu : le grand texte (zone et sous-zone) passe en français tant que la touche est tenue, puis revient à l'anglais (ou disparaît normalement en fondu).
- [ ] **1.4 Auto-répétition**
  - Étapes : maintenir la touche 5 secondes ou plus.
  - Attendu : affichage stable en français, sans clignotement. Retour à l'anglais au relâchement.
- [ ] **1.5 Appuis rapides**
  - Étapes : taper la touche 10 fois rapidement.
  - Attendu : on finit toujours sur l'anglais, sans erreur Lua.
- [ ] **1.6 Nom identique**
  - Étapes : à Orgrimmar (ou Darnassus, Durotar), maintenir la touche.
  - Attendu : le nom ne change pas, sans erreur.

## 2. Changement de zone en tenant la touche (PLAN T8)

- [ ] **2.1 Zone → zone**
  - Étapes : à la frontière Elwynn Forest → Westfall, maintenir la touche **avant** de la franchir, la franchir, puis relâcher.
  - Attendu : après le passage, la minimap (et le texte central s'il est visible) affiche **Marche de l'Ouest**. Au relâchement, on voit le **nouveau** nom anglais (Westfall), **pas** Elwynn Forest.
- [ ] **2.2 Sous-zone → sous-zone**
  - Étapes : dans Goldshire (Elwynn), touche tenue, sortir de la sous-zone puis y revenir.
  - Attendu : chaque nouveau texte est traduit pendant l'appui (**Comté-de-l'Or**, **Forêt d'Elwynn**). Au relâchement, le texte correspond au lieu **actuel**.
- [ ] **2.3 Quitter une sous-zone longtemps après l'arrivée**
  - Étapes : rester plus de 4 s dans Goldshire (le texte central a disparu), maintenir la touche, puis sortir vers la forêt.
  - Attendu : le texte de sous-zone central réapparaît avec le **nom de la zone** (comportement Blizzard), traduit : **Forêt d'Elwynn**. Au relâchement : Elwynn Forest. Aucun vieux texte ne réapparaît.

## 3. Relâchement manqué : écran de chargement, perte de focus (PLAN T8)

- [ ] **3.1 Relâcher pendant un écran de chargement**
  - Étapes : maintenir la touche, prendre un portail ou la pierre de foyer, ou entrer dans un donjon (Les Mortemines). **Relâcher pendant** l'écran de chargement.
  - Attendu : à l'arrivée, tout est en anglais avec le nom du **nouveau** lieu (**The Deadmines**). Aucun texte français ne reste.
- [ ] **3.2 Garder la touche pendant tout le chargement**
  - Étapes : même chose, mais ne relâcher qu'après l'arrivée.
  - Attendu : à l'arrivée, l'affichage est en anglais (reset de sécurité). Le relâchement tardif ne change rien et ne réaffiche pas l'ancien lieu. Un nouvel appui traduit normalement.
- [ ] **3.3 Perte de focus (Alt+Tab)**
  - Étapes : maintenir la touche, faire Alt+Tab vers une autre fenêtre, relâcher hors du jeu, puis revenir.
  - Attendu : en **moins d'une seconde** environ, le texte est revenu en anglais (filet `IsKeyDown`). Si le texte reste en français, c'est un KO : noter la durée observée.
- [ ] **3.4 Champ de saisie**
  - Étapes : maintenir la touche, appuyer sur Entrée (le chat s'ouvre), relâcher la touche, puis Échap.
  - Attendu : même règle qu'en 3.3, retour à l'anglais en moins d'une seconde.
- [ ] **3.5 Raccourci avec modificateur : modificateur relâché en premier**
  - Étapes : assigner temporairement **Maj+F6** au raccourci. Maintenir Maj+F6, relâcher **Maj d'abord**, puis F6. Recommencer en relâchant F6 d'abord.
  - Attendu : dans les deux ordres, retour à l'anglais au plus tard 1 s après le relâchement de F6, sans erreur. Noter si le `up` du binding est reçu ou si c'est le filet qui agit. Remettre ensuite F6 seul.
- [ ] **3.6 Seconde touche liée**
  - Étapes : Options > Gameplay > Raccourcis > WoWTranslator : garder F6 en **touche 1** et mettre un bouton de souris (par exemple Bouton 4) en **touche 2**. Tenir le **bouton de souris** pendant 5 s, puis le relâcher. Recommencer avec F6.
  - Attendu : la traduction reste active pendant les 5 s (le filet sonde les deux touches et ne coupe pas). Au relâchement, retour à l'anglais. Même résultat avec F6.
- [ ] **3.7 Touche liée à `-` (avec modificateur)**
  - Étapes : lier temporairement **Maj + -** (`SHIFT--`). La tenir 5 s, puis relâcher. Ensuite, tenir Maj + -, faire Alt+Tab, relâcher hors du jeu, et revenir.
  - Attendu : pas de coupure pendant les 5 s, et retour à l'anglais au relâchement. Dans le cas Alt+Tab, retour à l'anglais en moins d'1 s. Remettre ensuite F6.
- [ ] **3.8 `/reload` touche tenue**
  - Étapes : maintenir la touche et taper `/reload` (macro ou autre main).
  - Attendu : après le rechargement, tout est en anglais, sans erreur.

## 4. Nom inconnu (PLAN T8)

- [ ] **4.1 Lieu absent du dictionnaire**
  - Étapes : trouver un lieu non couvert (`/wt status` donne la couverture ; sinon une petite sous-zone obscure). Maintenir la touche.
  - Attendu : texte **inchangé**, sans erreur ni texte vide.
- [ ] **4.2 Mélange connu / inconnu**
  - Étapes : zone connue et sous-zone inconnue ; maintenir la touche.
  - Attendu : la zone est traduite là où elle s'affiche, la sous-zone reste en anglais.

## 5. Les deux sens (PLAN T8)

- [ ] **5.1 enUS → frFR** : scénarios 1 à 4 sur le client enUS.
- [ ] **5.2 [frFR] frFR → enUS**
  - Étapes : installer le pack, relancer, vérifier que `GetLocale()` renvoie `frFR`, puis refaire 1.1, 1.2, 2.1, 3.1 et 4.1.
  - Attendu : résultats symétriques, par exemple **Hurlevent** → **Stormwind City** pendant l'appui, puis retour à **Hurlevent**.
- [ ] **5.3 [frFR] Accents**
  - Étapes : Forêt d'Elwynn, Comté-de-l'Or.
  - Attendu : traduction correcte (Elwynn Forest, Goldshire), sans caractères cassés (`Ã©`).
- [ ] **5.4 Accents dans l'autre sens (client enUS)**
  - Étapes : à Elwynn Forest, maintenir la touche.
  - Attendu : **Forêt d'Elwynn** s'affiche avec les bons accents.

## 6. Carte du monde (T5)

- [ ] **6.1 Libellé de survol**
  - Étapes : ouvrir la carte (M), survoler une zone, maintenir la touche.
  - Attendu : le libellé passe en français. Le suffixe de niveau coloré (` (1-10)` ou ` (60)`) reste identique (même couleur, même texte). Au relâchement, retour à l'anglais.
- [ ] **6.2 Survol touche tenue**
  - Étapes : touche tenue, passer d'une zone à l'autre puis sortir de toute zone.
  - Attendu : chaque libellé est traduit. Hors zone, le libellé est vide et le reste au relâchement (pas d'ancien nom).
- [ ] **6.3 Titre de la fenêtre**
  - Étapes : touche tenue, carte ouverte.
  - Attendu : le titre (« World Map ») n'est **pas** modifié.
- [ ] **6.4 Première ouverture après `/reload`**
  - Étapes : `/reload`, maintenir puis relâcher la touche sans ouvrir la carte, puis ouvrir la carte et refaire 6.1.
  - Attendu : aucune erreur, et 6.1 fonctionne. Vérifier aussi que `/run print(C_AddOns.IsAddOnLoaded("Blizzard_WorldMap"))` affiche `true` avant même d'ouvrir la carte (carte chargée au démarrage).
- [ ] **6.5 Fil d'Ariane : hors v1**
  - Étapes : touche tenue, regarder les boutons continent > zone en haut de la carte.
  - Attendu : noms **inchangés** (le fil d'Ariane est hors périmètre v1, PLAN.md T5) et aucune erreur.
- [ ] **6.6 [frFR] Carte en sens inverse**
  - Étapes : sur le client frFR, refaire 6.1 et 6.2 (par exemple survoler la Forêt d'Elwynn).
  - Attendu : **Elwynn Forest** avec le suffixe de niveau intact, puis retour au français.

## 7. Configuration `/wt` (T7)

- [ ] **7.1 Statut**
  - Étapes : `/wt status`.
  - Attendu : une ligne dans le chat avec la langue cible et la couverture.
- [ ] **7.2 Override (sert aussi à tester frFR → enUS sans le pack)**
  - Étapes : client enUS, `/wt lang enUS`, puis `/run print(WoWTranslator.Translate("Hurlevent"))`.
  - Attendu : `Stormwind City`. En jeu, l'anglais n'est plus traduit, ce qui est normal.
- [ ] **7.3 Persistance**
  - Étapes : après 7.2, `/reload`, puis `/wt status`.
  - Attendu : l'override est conservé.
- [ ] **7.4 Retour**
  - Étapes : `/wt lang frFR`, puis 1.1.
  - Attendu : comportement normal.
- [ ] **7.5 Entrées invalides**
  - Étapes : `/wt lang deDE`, `/wt lang`, `/wt`, `/wt nimportequoi`.
  - Attendu : un message d'aide, aucun changement de réglage, aucune erreur.
- [ ] **7.6 Changer la langue touche tenue**
  - Étapes : maintenir la touche et taper `/wt lang enUS` (macro), relâcher, puis `/wt lang frFR`.
  - Attendu : au relâchement, l'anglais d'origine. Aucune erreur.

- [ ] **7.7 Activation programmatique (filet non armé)**
  - Étapes : sans tenir la touche, `/run WoWTranslator.SetActive(true)`, attendre 5 s, puis `/run WoWTranslator.SetActive(false)`.
  - Attendu : la minimap reste traduite pendant les 5 s (le filet n'est armé que par la touche), puis revient à l'anglais, sans erreur.

## 8. Donjons et instances (T6) — *si T6 est livré*

- [ ] **8.1 Verrous d'instance**
  - Étapes : ouvrir les infos de raid (`RaidInfoFrame`) avec au moins un verrou, maintenir la touche.
  - Attendu : noms de donjons et raids traduits, puis restaurés.
- [ ] **8.2 Recherche de groupe**
  - Étapes : ouvrir la recherche de groupe (binding `TOGGLEGROUPFINDER`), maintenir la touche.
  - Attendu : noms de donjons traduits, sans erreur ni taint.
- [ ] **8.3 Entrée en instance**
  - Étapes : entrer aux Mortemines, touche tenue après le chargement.
  - Attendu : **Les Mortemines** sur la minimap (et le texte central dans les 3 s).

## 9. Robustesse

- [ ] **9.1 Combat**
  - Étapes : en combat, maintenir puis relâcher la touche.
  - Attendu : même comportement qu'hors combat, sans message « Interface action failed because of an AddOn ».
- [ ] **9.2 Taint**
  - Étapes : après plusieurs appuis, faire des actions protégées (changer de barre, cibler, sacs en combat).
  - Attendu : aucun blocage lié à WoWTranslator.
- [ ] **9.3 Minimap cachée (EllesmereUIMinimap)**
  - Étapes : maintenir et relâcher la touche, changer de zone.
  - Attendu : aucune erreur. La traduction de la minimap est invisible (limite connue, hors v1).
- [ ] **9.4 Valeurs secrètes**
  - Étapes : `/run print(issecretvalue and issecretvalue(GetZoneText()))`.
  - Attendu : `false`. Si `true` dans certaines zones, le texte reste inchangé, sans erreur.
- [ ] **9.5 Textes PvP**
  - Étapes : en territoire contesté, maintenir la touche.
  - Attendu : « (Contested Territory) » et les autres textes PvP ne sont **pas** modifiés.
- [ ] **9.6 Infobulle de la minimap** (si implémentée)
  - Étapes : survoler le nom de zone de la minimap, touche tenue.
  - Attendu : noms traduits ou inchangés, sans erreur.
- [ ] **9.7 Longue session**
  - Étapes : 30 minutes de jeu en utilisant régulièrement la touche.
  - Attendu : pas de ralentissement ni d'erreur, et toujours l'anglais au relâchement.

## 10. Désactivation

- [ ] **10.1 Addon désactivé**
  - Étapes : désactiver WoWTranslator dans la liste des AddOns.
  - Attendu : aucune erreur, et la touche liée ne fait rien.

---

## Rapport

| Scénario | Résultat | Remarque / message d'erreur |
|---|---|---|
| 0.1 | | |
| … | | |

Pour chaque KO, joindre : le texte complet de l'erreur Lua, le lieu exact, les étapes et la sortie de `/wt status`.
