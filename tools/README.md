# Outils de génération des données (T1)

Ce dossier contient le générateur des dictionnaires de noms, `build_zone_data.py`, et son autotest. Il ne contacte aucun réseau, n'installe rien, et n'utilise que la bibliothèque standard de Python 3.8 ou plus récent.

Client visé : **WoW: Forever, build 1.60.1.71037** (`## Interface: 16001`). Voir `docs/client-research.md` (§4 à jour : extraction CASC et Spoken_Places non retenues).

## 1. Méthode : collecte en jeu

Les noms viennent du client, lus **en jeu** avec l'API officielle. Un extracteur de fichiers du jeu est exclu (EULA, §1.C.6 « Data Mining »), comme les données tierces (Spoken_Places).

Un addon ne voit que les noms de la langue courante du client. On fait donc deux collectes, une en enUS et une en frFR, avec le même compte. Le générateur joint les deux langues par identifiant.

| Donnée | API (branche `forever` de `Gethe/wow-ui-source`) |
|---|---|
| Nom d'une zone (areaID) | `C_Map.GetAreaInfo(areaID)` : `name` (cstring), `MapDocumentation.lua` l. 34-47. Pas de `MayReturnNothing` : l'identifiant inconnu n'est pas documenté. |
| Nom et type d'une carte (uiMapID) | `C_Map.GetMapInfo(uiMapID)` : `UiMapDetails` (`mapID`, `name`, `mapType`, `parentMapID`, `flags`), `MapDocumentation.lua` l. 312-326 et 696-705. `MayReturnNothing = true`. |
| Types de carte | enum `UIMapType` (0 Cosmic, 1 World, 2 Continent, 3 Zone, 4 Dungeon, 5 Micro, 6 Orphan), `MapConstantsDocumentation.lua` l. 90-104 |
| Lot par tick | `C_Timer.After(seconds, callback)`, `UITimerDocumentation.lua` l. 11-20 |

Non confirmé (à vérifier en jeu) :
- **Bornes** : aucune borne n'est documentée. Les défauts de l'addon (`DEFAULT_MAX_AREA_ID` = 20000, `DEFAULT_MAX_MAP_ID` = 3000) sont des choix, réglables à chaque lancement. Le bloc enregistre les bornes utilisées ; l'addon avertit si le plus grand identifiant trouvé est proche de la borne.
- **Identifiant inconnu** : `GetAreaInfo` peut renvoyer `nil` ou lever une erreur. L'addon appelle l'API sous `pcall` et compte les deux cas comme « sans nom ».
- **`GetBuildInfo()`** : ordre `version, build, date, toc` attendu (`1.60.1`, `71037`, date, `16001`). Test 1 de `docs/client-research.md` §8. L'addon avertit si le `toc` est absent.

Les valeurs secrètes sont ignorées. L'addon teste `issecretvalue` sous `pcall` avant toute opération sur un nom. Si ce test échoue ou lève une erreur, la valeur est traitée comme secrète et comptée. Si `issecretvalue` est absent, aucune valeur n'est secrète.

## 2. Étapes pour l'utilisateur

Vous faites ces étapes vous-même, dans le jeu. Les outils du projet n'écrivent jamais dans `D:\World of Warcraft\_forever_`. L'addon de collecte est dans `WoWTranslatorCollector/` à la racine du projet. Il ne fait **pas** partie de WoWTranslator et n'est jamais distribué.

### 2.1 Installer l'addon de collecte

1. Copier le dossier `WoWTranslatorCollector` (avec `WoWTranslatorCollector.toc` et `Collector.lua`) dans :
   `D:\World of Warcraft\_forever_\Interface\AddOns\WoWTranslatorCollector\`
2. Sur l'écran de sélection du personnage, ouvrir la liste des addons et vérifier que **WoWTranslator Collector** est coché (activé).

### 2.2 Collecte en enUS

Régler la langue **avant** de lancer le jeu, jeu fermé :

3. Battle.net > WoW: Forever > Paramètres du jeu > **Langue du texte = English**. Lancer le jeu.
4. **Se connecter avec le compte que vous utiliserez pour les deux collectes.** Les SavedVariables sont par compte : les deux blocs doivent se trouver dans le même fichier.
5. Vérifier la langue : `/run print(GetLocale())` doit afficher `enUS`.
6. `/wtcollect status` : aucun bloc pour l'instant.
7. `/wtcollect start` (ou `/wtcollect start 25000 4000` pour changer les bornes zone et carte).
8. **Ne pas faire `/reload` et ne pas se déconnecter pendant la collecte** : rien ne serait enregistré (la collecte ne s'écrit qu'à la fin). `/wtcollect stop` arrête sans rien écrire.
9. Attendre le message `termine (enUS) : zones ..., cartes ...`. Lire les lignes qui suivent : `ATTENTION` signale une collecte probablement fausse ou une borne trop basse.
10. **Contrôle de plausibilité** : `/wtcollect status` doit afficher `enUS : build 71037 (1.60.1), bornes ..., zones <N>, cartes <M>`, avec un nombre de zones de l'ordre de **plusieurs milliers**. Si le nombre est **inférieur à 200**, ne pas continuer : le message `ATTENTION` l'indique. Relancer la collecte ou vérifier le client.
11. Se déconnecter (`/logout` ou quitter le personnage). Les SavedVariables sont écrits à ce moment.

### 2.3 Collecte en frFR

12. Battle.net > WoW: Forever > Paramètres du jeu > **Langue du texte = Français**. Relancer le jeu.
13. **Se connecter avec le même compte** qu'à l'étape 4.
14. `/run print(GetLocale())` doit afficher `frFR`.
15. `/wtcollect status` : le bloc enUS de l'étape 9 doit toujours être présent et complet.
16. `/wtcollect start`, puis les mêmes précautions qu'aux étapes 8 à 10 (pas de `/reload`, pas de déconnexion avant la fin).
17. `/wtcollect status` : les deux blocs `enUS` et `frFR` doivent être présents, avec le même build et des compteurs proches.
18. Se déconnecter.

### 2.4 Désactiver l'addon de collecte

19. Décocher **WoWTranslator Collector** dans la liste des addons (ou retirer le dossier `Interface\AddOns\WoWTranslatorCollector\`). Ses SavedVariables, de l'ordre du mégaoctet, seraient rechargés à chaque connexion.

### 2.5 Trouver le fichier SavedVariables

Le fichier est écrit dans le dossier du compte :

```
D:\World of Warcraft\_forever_\WTF\Account\<COMPTE>\SavedVariables\WoWTranslatorCollector.lua
```

Le dossier `WTF\Account\` contient un dossier par compte. Il peut y en avoir deux, dont l'un porte un suffixe `#1`. Pour trouver le fichier, en lecture seule, depuis PowerShell :

```
Get-ChildItem "D:\World of Warcraft\_forever_\WTF\Account" -Recurse -Filter WoWTranslatorCollector.lua
```

Un seul fichier doit apparaître, dans le dossier du compte utilisé aux étapes 4 et 13. S'il y en a plusieurs, prendre celui qui contient les deux blocs (le générateur refuse un fichier sans les deux blocs complets, et le dit). Ne modifiez pas ce fichier.

### 2.6 Générer les dictionnaires

20. Depuis la racine du projet :

```
python tools/build_zone_data.py --from-savedvariables "D:\World of Warcraft\_forever_\WTF\Account\<COMPTE>\SavedVariables\WoWTranslatorCollector.lua"
```

Le générateur écrit dans `tools/out/` : `Zones_enUS_frFR.lua`, `Zones_frFR_enUS.lua` et `rapport_couverture.md`. **Il n'écrit rien dans `WoWTranslator/Data`.** Relire le rapport, en particulier la section « Pertes » et les avertissements, avant toute suite. L'installation dans `WoWTranslator/Data` est une étape distincte, réservée à T3 (voir §3).

## 3. Lancer le générateur

```
python tools/build_zone_data.py --from-savedvariables CHEMIN\WoWTranslatorCollector.lua
```

| Option | Défaut | Rôle |
|---|---|---|
| `--from-savedvariables` | (requis) | fichier SavedVariables de WoWTranslatorCollector |
| `--out-dir` | `tools/out` | dossier de sortie (dossier de travail, jetable : le supprimer avant toute copie) |
| `--install` | | écrit dans `WoWTranslator/Data` (**étape T3 seulement**, incompatible avec `--out-dir`) |
| `--report` | `tools/out/rapport_couverture.md` | rapport Markdown. Refuse d'écraser un fichier qui n'a pas été généré par ce script |
| `--min-entries` | `200` | nombre minimal d'entrées par table (comme `WT_MIN_ENTRIES`) |
| `--strict` | | traite tout avertissement comme une erreur (rien n'est écrit) |
| `--allow-mismatch` | | build, version ou toc différents entre les deux blocs : avertissement au lieu d'erreur |
| `--overrides PATH` | `tools/overrides.json` s'il existe | fichier de corrections manuelles (§4.1bis) |
| `--no-overrides` | | n'applique aucune correction manuelle |
| `--accept-collision NOM` | | répétable. Examine et accepte une collision avec identité pour ce nom natif : lève son avertissement et l'erreur de `--strict`, et le consigne au rapport (« accepté par l'utilisateur »). N'oblige pas l'inverse : le nom natif reste sans entrée inverse  Un nom qui n'est pas une collision est un avertissement, **erreur sous `--strict`** (faute de frappe). Un nom dont le rapport est sous le seuil (5) est signalé en note (« acceptation sans effet »), avertissement dans les deux modes, jamais une erreur |
| `--selftest` | | autotest (copie du générateur dans un dossier temporaire pour les chemins par défaut et `--install`) |

**Ordre de travail** : toutes les vérifications sont faites **avant** toute écriture. Chaque fichier est écrit sous un nom temporaire dans son dossier, puis remplacé (`os.replace`). Un fichier `Zones_*.lua` ou un rapport qui n'a pas été produit par ce script n'est jamais écrasé.

**Atomicité** : chaque fichier est remplacé atomiquement, mais les trois remplacements (deux données, un rapport) ne sont pas simultanés. Une interruption entre deux remplacements peut laisser des fichiers de deux exécutions. Relancer le générateur corrige la situation ; le rapport indique le build et les dates de collecte.

Codes de sortie :

| Code | Sens | Ce qui est écrit |
|---|---|---|
| `0` | succès | les deux `.lua` et le rapport |
| `1` | entrée invalide ou refusée (bloc incomplet, builds différents sans `--allow-mismatch`, avertissement avec `--strict`, fichier non généré à écraser, fichier mal formé) | rien |
| `2` | seuil `--min-entries` non atteint | le rapport seul, pour diagnostic |

Le code `2` ne doit pas être utilisé pour une installation.

### Autotest

```
python tools/build_zone_data.py --selftest
```

L'autotest utilise `tools/fixtures/WoWTranslatorCollector.lua`, écrit **au format réel** (CRLF, compact, sans indentation, comme le client l'écrit). Il vérifie : la sortie déterministe, les règles de la section 4, les refus (bloc incomplet, bloc frFR absent, fichier tronqué, code non littéral, bornes hors plage, compteur faux), les avertissements et `--strict`, la garde d'écrasement (données et rapport), le seuil (rapport seul), l'analyseur, le **chemin par défaut** (`tools/out/`), `--install` et son refus d'écraser (testés dans une copie temporaire du script, jamais dans le projet), et le **pont** : les `.lua` produits sont identiques à `tests/fixtures/collector/`, que la suite Lua (`tests/specs/collector_spec.lua`) relit avec les mêmes invariants que `tests/specs/data_spec.lua`.

Si la fixture change, regénérer le pont :

```
python tools/build_zone_data.py --from-savedvariables tools/fixtures/WoWTranslatorCollector.lua --out-dir tests/fixtures/collector --min-entries 1 --no-overrides
```

### Installer dans le projet (étape T3)

Après relecture du rapport (sections « Pertes » et « Noms identiques » surtout) et du seuil, et seulement alors :

```
python tools/build_zone_data.py --from-savedvariables CHEMIN\WoWTranslatorCollector.lua --install
```

## 4. Règles

Les règles sont appliquées dans cet ordre. Elles sont déterministes.

### 4.1 Validation (avant toute écriture)

- **Bloc complet** : `complete = true`, `schema = 2`, `locale` égal à la langue du bloc, `version`, `build`, `toc`, `collectedAt` présents. Un bloc sans `complete = true` (collecte interrompue, ancienne version de l'addon) est **refusé** (code 1).
- **Bornes et contenu** : identifiants dans `1..maxAreaId` et `1..maxMapId` ; compteurs `areasFound` et `mapsFound` égaux au contenu ; `maxFoundAreaId` et `maxFoundMapId` égaux au plus grand identifiant présent.
- **Mêmes conditions** : `version`, `build` et `toc` identiques entre enUS et frFR. Sinon **erreur** (code 1), sauf `--allow-mismatch` (avertissement).
- **Couverture** : avertissement si plus de 2 % des identifiants (zones, ou cartes) sont présents dans une seule langue. Avertissement si le plus grand identifiant trouvé dépasse 90 % de la borne (borne peut-être trop basse). Avertissement si les bornes diffèrent entre les deux blocs.
- `--strict` : tout avertissement arrête le programme avant écriture (code 1).

### 4.1bis Corrections manuelles (`tools/overrides.json`)

Pour les cas que l'automatique ne tranche pas bien, on écrit la paire voulue à la main. Fichier par défaut : `tools/overrides.json`, lu s'il existe. Autre fichier : `--overrides PATH`. Aucune correction : `--no-overrides`.

Format (UTF-8, les deux sections sont facultatives) :

```
{
  "enUS_frFR": { "Thunder Bluff": "Pitons-du-Tonnerre" },
  "frFR_enUS": { "Pitons-du-Tonnerre": "Thunder Bluff" }
}
```

Règles :
- Les deux sections sont fusionnées en paires (enUS, frFR). Une paire donnée dans les deux sens est comptée une fois.
- Une correction **gagne sur tout** : sur le choix automatique, sur l'identité (un nom natif peut devenir une cible corrigée), et sur la règle « pas d'entrée inverse pour un nom natif ». Son inverse est fixé à la correction ; l'inverse automatique qu'elle remplace n'est plus écrit (la source concernée n'a plus de cible automatique).
- Validation (erreur, code 1, rien écrit) : JSON valide, seules les clés `enUS_frFR` et `frFR_enUS`, valeurs et clés de chaînes non vides, pas d'auto-boucle (enUS = frFR), pas de contradiction (un même nom avec deux corrections).
- Un nom absent des données collectées (« Pitons-du-Tonnerre » par exemple, si le client ne l'affiche jamais) est une **note**, pas un avertissement : elle n'arrête jamais le générateur, même sous `--strict`. La correction est conservée.
- Le rapport liste chaque correction (« Corrections manuelles ») avec la présence des noms dans les données et ce que l'automatique avait choisi.
- Les invariants (inverse présent, listes natives) sont revérifiés après correction, comme pour le reste.

### 4.2 Clés et valeurs

- **Suffixe « (X) »** : le client ajoute parfois le nom anglais entre parenthèses au nom frFR (« Terres ingrates (Badlands) »). Le suffixe est retiré si X est, après normalisation des espaces, exactement le nom de l'**autre** langue pour le **même** identifiant. Symétrique (un suffixe enUS aussi). Jamais de retrait si X diffère de ce nom (« Elwynn Forest (Blue Whelpling Inn Prototype) » reste tel quel). Un seul retrait par nom. Chaque retrait est listé dans la section « Suffixes retirés » du rapport, à relire : un retrait faux serait une traduction fausse.

- Les noms sont **gardés tels que le client les donne** : espaces, casse, apostrophes (`'` ou `’`), espace insécable. Une clé que le client ne produira jamais serait une couverture perdue. Une chaîne vide (après suppression des espaces) n'est pas une entrée.
- Le rapport liste les noms dont la forme brute diffère de la forme normalisée (20 premiers), et signale dans les cas ambigus les variantes purement typographiques (casse, espaces, `’` contre `'`).

### 4.3 Zones et cartes : origine et priorité

Les zones (areaID) et les cartes (uiMapID) entrent dans le même dictionnaire. Chaque identifiant garde son origine.

**Règle de priorité : une zone prime sur une carte.** Si un nom a au moins une zone pour cible, les cibles qui n'existent que comme carte sont écartées pour ce nom. Elles figurent dans la section « Conflits zone contre carte » du rapport. Motif : T4 (texte de zone) doit recevoir la traduction de zone ; T5 (carte du monde) reçoit la même entrée, dont la valeur est celle de la zone (report dans `PLAN.md`, T5).

Le rapport donne le nombre d'entrées par origine (zone, ou carte seule), et les identifiants de zones et de cartes séparément pour les noms seulement présents d'un côté.

### 4.4 Noms natifs : identiques dans les deux langues

Un **nom natif** est un nom identique en enUS et en frFR pour au moins un identifiant (par exemple « Orgrimmar », « Dun Morogh »). Un client frFR qui affiche ce nom n'a rien à traduire.

- Une paire identique est un **candidat comme les autres** du sens direct. Elle gagne à égalité d'effectifs, et jamais au-delà : une autre cible qui a plus d'identifiants l'emporte.
- Un nom natif n'a **jamais d'entrée inverse** : un client frFR qui le voit le garde. Les sources qui mènent à ce nom sont listées dans « Collisions avec identité » (rapport : identifiants identiques d'un côté, identifiants concurrents de l'autre, avec les zones et cartes concernées).
- **Arbitrage** : une collision à fort déséquilibre est une décision humaine. Lire la section « Collisions avec identité » du rapport, puis, si la collision est juste, relancer avec `--accept-collision NOM` (sinon `--strict` refuse). Le générateur ne force jamais l'inverse d'un nom natif.
- **Seuil d'avertissement** : `COLLISION_RATIO = 5`. Une collision dont les identifiants concurrents atteignent 5 fois les identifiants identiques est signalée sur stderr et dans les avertissements du rapport. Le tableau est trié par déséquilibre décroissant. Ce seuil est un garde-fou pour l'arbitrage humain, pas une règle de traduction : rien n'est modifié automatiquement.
- Un nom natif peut avoir une entrée **directe** (« Orgrimmar Gate » → « Orgrimmar »), si une autre source l'emporte en effectifs. La source concernée est listée au rapport avec ses identifiants.
- La liste native ne contient **que les noms exemptés** : les noms natifs qui sont valeur d'une entrée directe (cas « collision avec identité »). Les autres noms identiques ne sont pas listés, parce qu'aucune entrée n'a besoin d'exemption. `data_spec` vérifie qu'elle ne dépasse ni 2 % des entrées directes (`WT_NATIVE_MAX_RATIO`) ni 30 noms (`WT_NATIVE_MAX_COUNT`). Ces deux bornes sont provisoires, à recaler sur le premier rapport réel.
- Les noms natifs sont listés dans `WT.data.native_enUS_frFR` et `WT.data.native_frFR_enUS`. Ce ne sont pas des entrées de traduction. Elles permettent à `tests/specs/data_spec.lua` de savoir quelles valeurs n'ont pas d'entrée inverse (`tests/README.md`, « Hypothèse de data_spec »).

Exemples :
- « Spire » vaut « Spire » pour un identifiant et « Flèche » pour cinq autres : « Spire » → « Flèche » est gardé (5 contre 1). La paire identique (un identifiant) est perdue, et figure au rapport.
- « Orgrimmar Gate » vaut « Orgrimmar » pour deux identifiants, et « Orgrimmar » vaut « Orgrimmar » pour un identifiant : « Orgrimmar Gate » → « Orgrimmar » est gardé. Il n'y a pas d'entrée inverse « Orgrimmar » → « Orgrimmar Gate ».
- `{1: A → B, 2: B → B}` : « A » → « B » est gardé, et « B » (natif) n'a pas d'entrée inverse. Pas de « B » → « A ».

### 4.5 Sens direct (enUS vers frFR)

Pour chaque nom source, toutes les cibles candidates (paires identiques comprises) sont classées :
1. zones seules si une zone existe pour ce nom (4.3) ;
2. nombre d'identifiants de la paire ;
3. le nom natif (la cible identique au nom) l'emporte à égalité ;
4. plus petit identifiant ;
5. ordre alphabétique de la cible.

La première cible est la **cible gagnante** du nom. Si c'est le nom lui-même, il n'y a pas d'entrée.

### 4.6 Sens inverse (frFR vers enUS) et pertes

Pour une cible frFR `t` qui **n'est pas** un nom natif, les **candidats** sont les seules sources dont la cible gagnante (4.5) est `t`. Chaque candidat compte ses identifiants réels. Le classement (zone avant carte, effectifs, plus petit identifiant, ordre alphabétique) désigne la source gagnante.

Conséquence : toute entrée directe `s → t` (`t` non natif) a son entrée inverse `t → w`, où `w` est une source qui mène à `t` (peut-être `s`). Une source qui mène à `t` sans gagner l'inverse garde son entrée directe : c'est une collision, et le sens inverse n'en retient qu'une.

**Ce que la règle peut écarter**, exhaustivement :
1. **Une paire perdue au sens direct** : la source a une autre cible gagnante (ex. « The Barrens » → « Barrens » perd contre « Les Barrens »). La paire n'a pas d'entrée, et ses identifiants sont listés au rapport, section « Pertes ».
2. **Une identité perdue** : le nom natif a une autre cible gagnante (il perd contre une traduction plus fréquente). Listé dans « Pertes ».
3. **Une paire vers une cible carte seule** : écartée au profit d'une zone (4.3), listée dans « Conflits zone contre carte ».

Il n'y a **pas** d'autre suppression : une source qui perd le sens inverse garde son entrée directe. Il n'y a pas de garde mutuelle qui supprimerait une paire parce que sa cible va ailleurs au sens inverse.

Pourquoi l'inverse n'est pas exigé pour un nom natif : un client frFR qui affiche le nom natif ne doit rien traduire ; une entrée inverse ferait traduire ce nom en un autre nom (faux).

Exemple : « Côte d'Ouest » est la cible de « Westfall Coast » (trois identifiants) et de « Westfall Shore » (un identifiant). Le sens inverse retient « Westfall Coast ». Les deux paires vers « Côte d'Ouest » gardent leur entrée directe.

Propriété vérifiée par le générateur et par `data_spec` : pour chaque entrée directe `s → t`, soit `t` est un nom natif, soit `frFR_enUS[t]` existe et `enUS_frFR[frFR_enUS[t]] = t`. Pour chaque entrée inverse `t → s`, `enUS_frFR[s] = t`.

### 4.7 Identifiants sans paire

- Identifiant présent dans une seule langue : ignoré, compté dans le rapport, ventilé zones et cartes.
- Nom vide dans l'une des langues : paire ignorée, comptée.

### 4.8 Chaînes dans le fichier Lua

Chaînes entre guillemets doubles. `\`, `"`, `\n`, `\r`, `\t` et les autres caractères de contrôle sont échappés (`\ddd`). Les caractères non ASCII sont écrits en UTF-8, sans BOM. Aucune date dans les fichiers : la sortie est identique d'une exécution à l'autre, et l'en-tête donne les dates de collecte.

## 5. Rapport (`rapport_couverture.md`)

Sections « Suffixes retirés » (§4.2) et « Pertes » (§4.6) incluses, avant « Collisions avec identité ».

Le rapport contient : le build, la source, les bornes et dates de chaque bloc ; les avertissements ; les compteurs (lignes, vides, paires jointes, identifiants d'une seule langue ventilés zones et cartes, paires non retenues, noms identiques, entrées par origine, formes brutes, seuil) ; la section **Pertes : paires non retenues** (nom source, cible, identifiants lisibles, raison) ; les **noms natifs** avec leur statut, les **collisions avec identité** (cibles natives, sans entrée inverse) ; les cas ambigus dans chaque sens (avec origine et indicateur « variantes typographiques seulement ») ; les conflits zone contre carte ; les formes brutes différentes de la forme normalisée.

Le rapport est généré. Ne pas le modifier à la main.

## 6. Anciens chemins non conservés

- **Extraction CASC et export CSV de AreaTable** (wow.tools.local, CASCExplorer, CascLib, DBCD, WoWDBDefs, DBC2CSV) : **non conservés**. Décision du 21/11/2026 (EULA §1.C.6). Le mode CSV a été retiré du générateur, et ses fixtures aussi.
- **Spoken_Places** (addon tiers, tables dérivées de AreaTable, licence incertaine, lore CC BY-SA) : **non conservé**. Rien n'en est copié ni lu.

`docs/client-research.md` §4 le signale pour T1.

## 7. Fichiers

| Fichier | Rôle |
|---|---|
| `build_zone_data.py` | générateur et autotest |
| `fixtures/WoWTranslatorCollector.lua` | SavedVariables au format réel, deux langues, cas limites (pas de données du jeu) |
| `.gitignore` | ignore `out/` si le projet passe sous git (ce n'est pas un dépôt git aujourd'hui, le fichier est inerte) |
| `README.md` | ce document |

Hors de ce dossier :
- `WoWTranslatorCollector/` (addon de collecte, à la racine) ;
- `tests/fixtures/collector/` : sorties du générateur pour le pont avec la suite Lua (`tests/specs/collector_spec.lua`).

Les fixtures ne sont pas des données du jeu : ce sont des noms d'exemple, avec des cas limites volontaires.

## 8. Questions ouvertes

1. Bornes réelles des identifiants (zones et cartes) : à mesurer en jeu. Le rapport et les avertissements de `/wtcollect` servent de garde-fou.
2. Comportement de `GetAreaInfo` sur un identifiant inconnu (`nil`, chaîne vide ou erreur) : l'addon traite les trois cas, à confirmer en jeu.
3. Ordre de `GetBuildInfo()` : à confirmer en jeu.
4. Balise `## Title-frFR` du `.toc` : à confirmer au chargement.
5. Droits sur les noms collectés depuis le client : à trancher avant toute publication (décision non prise).
6. Nombre de noms identiques et de pertes sur les données réelles : inconnu avant la première collecte. Lire la section « Pertes » du premier rapport.
