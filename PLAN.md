# WoWTranslator — plan de découpage

## Objectif
Addon pour WoW: Forever : produit Blizzard officiel sur le moteur retail moderne, build 1.60.1.71037, `## Interface: 16001`. Voir `docs/client-research.md`. Tant qu'une touche est maintenue, les **noms de zones et de lieux** (villes, donjons, sous-zones) s'affichent dans l'autre langue. Au relâchement, retour à la langue du jeu.

- Paires de langues : enUS vers frFR, et frFR vers enUS.
- La langue cible est l'inverse de `GetLocale()`, avec un réglage possible.
- Périmètre v1 : noms de zones et de lieux uniquement. Quêtes, objets et sorts viendront plus tard, avec le même mécanisme de modules.

## Contraintes techniques
- Un addon ne peut pas changer la locale du client. Il remplace donc le texte affiché grâce à un dictionnaire embarqué.
- Pas d'accès réseau : les données sont générées hors jeu par un script, puis commitées sous forme de fichiers Lua.
- Touche maintenue : `Bindings.xml` avec `runOnUp="true"`, la fonction reçoit `keystate` ("down" ou "up").
- Le texte peut changer pendant que la touche est tenue (changement de zone). Les hooks doivent donc réappliquer la traduction à ce moment-là.
- Un relâchement manqué (écran de chargement, perte de focus) ne doit jamais laisser la traduction active.

## Arborescence cible
```
WoWTranslator/
  WoWTranslator.toc
  Bindings.xml
  Core.lua            # état, API publique, registre de modules
  Config.lua          # SavedVariables, /wt
  Modules/
    ZoneText.lua      # texte d'arrivée dans une zone, minimap
    WorldMap.lua      # carte du monde
    Instances.lua     # noms de donjons / raids (LFG, verrous)
  Data/
    Zones_enUS_frFR.lua   # généré
    Zones_frFR_enUS.lua   # généré
WoWTranslatorCollector/  # addon de collecte (outil de dev, jamais distribué) — T1
  WoWTranslatorCollector.toc
  Collector.lua
tools/
  build_zone_data.py  # générateur de dictionnaires
  README.md
docs/
  client-research.md
  test-checklist.md
  reviews/            # revues de code
tests/
  run.lua, wow_mock.lua, specs/, fixtures/, tools/luarun.py
  mutants/            # oracle de référence + mutants (run_mutants.py)
```

**Règle sur l'oracle** : `tests/mutants/reference/` sert uniquement à prouver que la suite est satisfaisable et à faire tourner les mutants. T2 à T7 **ne partent pas** de ce code, ni de ses données ni de son API hors contrat. On ne le copie pas dans `WoWTranslator/`.

## Contrat d'interface (à figer dans T2, utilisé par T4-T6)
```lua
-- Namespace de l'addon : `local addonName, WT = ...` dans chaque fichier.
-- Seule globale publique : WoWTranslator (= WT). Pas de globale `WT` (risque de collision).
-- Globale requise par Bindings.xml : WoWTranslator_OnHoldKey(keystate).
WT.IsActive()                  -- true tant que le mode traduit est actif (touche ou SetActive(true))
WT.SetActive(bool)             -- seul point de bascule (touche, reset, filet de sécurité) ; idempotent
WT.Translate(text)             -- recherche EXACTE ; string traduite, ou nil si inconnue/non-string/secrète
                               -- (jamais d'erreur). issecretvalue est testé AVANT toute comparaison
                               -- ou indexation, via pcall (une erreur = traité comme secret). Translate ne retire ni codes couleur ni suffixes :
                               -- c'est au module de découper son texte (ex. suffixe de niveau, T5).
WT.GetTargetLocale()           -- "enUS", "frFR", ou nil si la langue du jeu n'est pas gérée
WT.SetTargetLocale(locale)     -- "enUS", "frFR", ou nil (automatique) ; false si refusé. Un changement
                               -- désactive d'abord le mode traduit. Ne persiste rien : T7 s'en charge
                               -- dans la SavedVariable WoWTranslatorDB, déclarée dans le .toc.
WT.RegisterModule(name, {      -- erreur si la définition est invalide ou le nom déjà pris ;
                               -- Apply est appelé tout de suite si le mode traduit est déjà actif
  Apply   = function() end,    -- appelé au passage en mode traduit
  Restore = function() end,    -- appelé au relâchement et en cas de reset
})
```
Règles pour les modules :
- Ils mémorisent le texte d'origine.
- Ils utilisent `hooksecurefunc` sur les `SetText`, jamais de remplacement de fonction.
- Si le texte est inconnu, ils laissent l'original.

## Tâches

| # | Tâche | Dépend de | Fichiers possédés |
|---|-------|-----------|-------------------|
| T0 | Recherche client | — | `docs/client-research.md` |
| T1 | Source de données et générateur | — | `tools/*`, `WoWTranslatorCollector/*` |
| T2 | Squelette de l'addon et noyau | T0 | `.toc`, `Bindings.xml`, `Core.lua` |
| T3 | Génération des données | T1 | `Data/*` |
| T4 | Module texte de zone et minimap | T2 | `Modules/ZoneText.lua` |
| T5 | Module carte du monde | T2 | `Modules/WorldMap.lua` |
| T6 | Module donjons / instances | T2 | `Modules/Instances.lua` |
| T7 | Config et commande `/wt` | T2 | `Config.lua` |
| T8 | QA et checklist de test en jeu | T3-T7 | `docs/test-checklist.md` |

Vagues : **T0 et T1** en parallèle, puis **T2 et T3**, puis **T4, T5, T6 et T7** en parallèle, puis **T8**.

### T0 — Recherche client
Dans le dossier du jeu, trouver :
- le numéro `## Interface:` à utiliser (lire des `.toc` d'addons existants) ;
- la version du client (`GetBuildInfo`) ;
- quelles locales sont installées (dossiers `Data\enUS`, `Data\frFR`) ;
- si `runOnUp` dans `Bindings.xml` fonctionne ;
- les noms exacts des frames de texte de zone, de minimap et de carte du monde dans cette version.

Sortie : `docs/client-research.md`. Fait quand T2 à T6 n'ont plus rien à deviner.
**Statut : partiel.** La recherche sur disque et dans les sources est faite. Il reste les vérifications en jeu (§8 du document).

### T1 — Source de données et générateur
**Source retenue : collecte en jeu par l'API officielle** (décision du 21/11/2026).
- On écarte les extracteurs CASC (EULA 1.C.6 « Data Mining »), les exports tiers et Spoken_Places (couverture partielle, données extraites).
- Addon séparé `WoWTranslatorCollector/`, jamais distribué avec l'addon :
  - il parcourt les identifiants de zone avec `C_Map.GetAreaInfo` et les cartes avec `C_Map.GetMapInfo`, par lots pour ne pas figer le jeu ;
  - il enregistre les noms dans ses SavedVariables, rangés par `GetLocale()` ;
  - l'utilisateur le lance une fois avec le client en enUS, puis une fois en frFR.
- `tools/build_zone_data.py` lit ce fichier de SavedVariables, apparie les deux langues par identifiant, puis produit deux fichiers Lua, un par direction.
- Gérer les collisions : un même nom pour plusieurs zones, ou plusieurs traductions. Rapport des cas ambigus.
- Format : `local _, WT = ...; WT.data = WT.data or {}; WT.data.enUS_frFR = { ["Stormwind City"] = "Hurlevent", ... }`.
- Chaque fichier porte aussi une liste des noms natifs de la langue cible, `WT.data.native_<source>_<cible>` (noms identiques dans les deux langues). Ce ne sont pas des traductions : `Translate` ne les consulte pas. Tout code qui lit les dictionnaires (Core, `/wt status` de T7) les désigne par leur nom (`enUS_frFR`, `frFR_enUS`), sans parcourir `WT.data` avec `pairs`. Un nom natif n'a jamais d'entrée inverse.

Fait quand le script se relance de zéro et que le rapport de couverture est produit.

### T2 — Squelette et noyau
- `.toc` (interface fixée par T0, `SavedVariables`).
- `Bindings.xml` avec une action « Afficher l'autre langue » en `runOnUp`.
- `Core.lua` : état actif/inactif, `Translate` (lookup dans le dictionnaire de la langue cible), registre de modules, appel d'`Apply`/`Restore`.
- Reset de sécurité : `WT.SetActive(false)` sur `PLAYER_LEAVING_WORLD` et `PLAYER_ENTERING_WORLD`.
- Perte de focus : il n'existe pas d'événement. Le filet de sécurité est armé **uniquement par la touche** (`WoWTranslator_OnHoldKey("down")`), à **chaque** `down`, même si l'addon est déjà actif. Un `WT.SetActive(true)` venant d'ailleurs ne l'arme pas. Il est désarmé dès la désactivation.
  - Un sondage léger (`C_Timer.NewTicker`, `C_Timer.After` ou OnUpdate, au choix de l'implémentation) lit **toutes** les touches liées (`GetBindingKey` en renvoie jusqu'à deux) et retire les modificateurs pour garder la touche de base.
  - Il interroge `IsKeyDown` sur chacune. Il appelle `WT.SetActive(false)` seulement si **toutes** renvoient explicitement `false`. Si une seule renvoie `true` ou `nil` (état inconnu), on ne coupe pas.
  - Sans `IsKeyDown` ou sans touche liée, le filet est inactif et l'addon fonctionne quand même.
- `issecretvalue` peut être absent : dans ce cas, aucune valeur n'est considérée comme secrète et la traduction fonctionne normalement.
- Règle sur les valeurs secrètes : un module ne mémorise ni ne réécrit jamais un texte secret (règle 2 de `docs/client-research.md` §5.6).

Fait quand l'addon charge sans erreur et que le contrat est stable.

### T3 — Génération des données
Faire les deux collectes en jeu (voir `tools/README.md`), puis générer dans `tools/out/`. Lire le rapport de couverture et de collisions. Vérifier l'échantillon (au moins les capitales, les donjons et raids, et les zones de départ). Ensuite seulement, installer avec `--install` dans `WoWTranslator/Data/`.

### T4 — Module texte de zone et minimap
Hooker les zones de texte d'arrivée (zone et sous-zone) et le texte de la minimap. Mémoriser l'original, réappliquer si le texte change pendant l'appui.

### T5 — Module carte du monde
Noms de zones sur la carte du monde : label au survol, avec le suffixe de niveau conservé (le module découpe le suffixe et appelle `Translate` sur le nom seul). La carte peut exister avant le chargement de l'addon. Le fil d'Ariane (`NavBar`) est **hors v1**. Si un même nom anglais a une traduction différente comme zone et comme carte, T5 utilise celle de la zone (priorité « zone sur carte » appliquée par le générateur, `tools/README.md` §4.3). Décision du 23/11/2026 : un seul dictionnaire, la zone partout. Limite connue et acceptée : quand le client français nomme différemment la zone et la carte (ex. zone « Thunder Bluff », carte « Les Pitons-du-Tonnerre »), la carte du monde affiche le nom de zone. Le titre de la fenêtre (« Carte du monde ») n'est pas traduit. Même règles que T4.

### T6 — Module donjons / instances
Tests 6 et 7 faits le 26/11/2026 (`docs/client-research.md` §8). Cibles confirmées : la recherche de groupe (`LFGVanilla_ToggleFrame`, filtre « activité » et nom d'activité de chaque groupe) et la fenêtre des verrous (`RaidInfoFrame`). Pas de guide de l'aventurier (`WRONG_GAME_TYPE`).
**Bloqué par les données** : la recherche de groupe affiche des noms d'activité (« Deadmines », « Dire Maul (North) », « Upper Blackrock Spire »), absents pour 14 sur 34 du dictionnaire de zones. Il faut une collecte de ces noms dans les deux langues (extension du collecteur, à étudier). Reste aussi à inspecter les frames internes de la fenêtre.

### T7 — Config et `/wt`
- `/wt lang <enUS|frFR>` : forcer la langue cible.
- `/wt status` : état et couverture des dictionnaires.
- Valeurs par défaut sûres dans `SavedVariables`.

### T8 — QA et checklist
Écrire `docs/test-checklist.md`, avec des scénarios manuels :
- changement de zone en tenant la touche ;
- relâchement pendant un écran de chargement ;
- nom inconnu ;
- les deux sens (enUS vers frFR et frFR vers enUS) ;
- aucune erreur Lua (`/console scriptErrors 1`).

## Questions ouvertes
1. Vérifications en jeu de T0 : valeurs secrètes, `IsKeyDown` avec modificateur, cibles T6. Pack frFR à installer pour le sens frFR → enUS.
2. Existence et comportement de `C_Map.GetAreaInfo` / `C_Map.GetMapInfo` dans Forever ; plage d'identifiants à parcourir (T1).
3. Quelles interfaces de nom de lieu comptent le plus pour la v1 (T4 à T6 pourront être réordonnés).
4. **Générateur : mauvais choix entre plusieurs écritures d'un même nom** (constaté le 26/11/2026, correction reportée). Quand le jeu donne plusieurs noms français pour un même nom anglais, le générateur n'en garde qu'un, parfois le mauvais. Le rapport de couverture compte 40 paires écartées (section « Pertes »), dont 29 ne diffèrent que par l'écriture (apostrophe `'` ou `’`, majuscules, espaces).
   - Elwynn Forest : la zone 12 et la carte écrivent « Forêt d'Elwynn », mais « Forêt d’Elwynn » est retenu. Un client frFR qui affiche « Forêt d'Elwynn » ne le traduit pas.
   - Darkshire : la zone 42 donne « Sombre-Comté », mais le nom inchangé « Darkshire » est retenu. Aucune traduction dans les deux sens.
   - Piste : préférer les noms des zones d'origine (hypothèse à vérifier : les identifiants à partir de 15 000 sont des ajouts) et, au sens frFR → enUS, accepter toutes les écritures d'un même nom.
   - Effet sur les tests : `data_spec` (échantillons dans les deux sens) échoue sur Elwynn Forest tant que ce n'est pas corrigé.

## Backlog
Travail reporté, à reprendre plus tard. Ajouté le 26/11/2026.

| # | Sujet | Détail |
|---|---|---|
| B1 | Générateur : choix entre plusieurs écritures d'un même nom | Question ouverte 4 ci-dessus (Forêt d'Elwynn, Darkshire). Deux tests de `data_spec` échouent tant que ce n'est pas corrigé. |
| B2 | T6 : noms de donjons de la recherche de groupe | 14 noms d'activité sur 34 absents du dictionnaire (« Deadmines », « Dire Maul (North) », « Upper Blackrock Spire »…). Étudier leur collecte dans les deux langues (extension du collecteur), puis inspecter les frames de la fenêtre (`LFGVanilla_ToggleFrame`) et de `RaidInfoFrame`. Voir T6 et `docs/client-research.md` §8, test 6. |
