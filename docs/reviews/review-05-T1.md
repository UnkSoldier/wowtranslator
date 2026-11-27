# Revue 05 : T1 (source de données : collecteur et générateur)

Date : 2026-11-21. Même exigence qu'aux revues 01 à 04 (9/10 = on livre comme base, il ne reste que des nits). Aucune correction appliquée, aucun fichier existant modifié, dossier du jeu lu en lecture seule (jamais lancé), rien de téléchargé. Les API sont vérifiées par `gh api` sur `Gethe/wow-ui-source`, branche `forever`.

## Méthode

1. Relecture : `WoWTranslatorCollector/{.toc,Collector.lua}`, `tools/build_zone_data.py` (936 lignes), `tools/README.md`, `tools/fixtures/*`, `PLAN.md` (T1, contrat), `docs/client-research.md`, `tests/specs/data_spec.lua`, `tests/README.md`, revues 01 et 04.
2. Vérification des API dans les sources du build :
   - `MapDocumentation.lua:34-47` : `C_Map.GetAreaInfo(areaID) -> name (cstring, Nilable=false)`, `SecretArguments = "AllowedWhenUntainted"`, **pas** de `MayReturnNothing` ;
   - `MapDocumentation.lua:312-326` : `GetMapInfo(uiMapID) -> UiMapDetails`, `MayReturnNothing = true` ;
   - `MapDocumentation.lua:696-705` : champs de `UiMapDetails` ; `MapConstantsDocumentation.lua` : enum `UIMapType` 0..6 (conforme au README) ;
   - `UITimerDocumentation.lua:11-20` : `C_Timer.After(seconds, callback)` ;
   - `AreaLabelDataProvider.lua:86-88` (`C_Map.GetMapInfoAtPosition(...).name`) et `:141` (`MapUtil.FindBestAreaNameAtMouse`) : la carte du monde affiche à la fois des **noms de cartes** et des **noms de zones**.
   - `GetBuildInfo` n'est pas dans les docs générées : ordre `version, build, date, toc` non vérifiable ici (le README le dit déjà).
3. Exécutions (toutes hors projet, dans le scratchpad) :
   - `python tools/build_zone_data.py --selftest` : **63 ok, 0 KO**, conforme à l'annonce ;
   - `python tests/tools/luarun.py tests/run.lua` : **28 ok, 134 échecs « addon absent »**, inchangé ;
   - **Lint 5.1** (`M.lint51`) sur `Collector.lua` : 0 problème ;
   - **Banc de simulation du collecteur** (`C_Map` et `C_Timer` simulés, LuaJIT d'OBS) : exécution normale par défaut (20000 zones, 3000 cartes) = **92 ticks**, 100 zones et 50 cartes trouvées dans mon faux monde ; interruption en cours de collecte ; valeur secrète ; arguments absurdes ;
   - **Analyseur sur 132 vrais fichiers SavedVariables** du dossier `WTF` du jeu (lecture seule), `.bak` compris : **132 analysés, 0 erreur**. Ces fichiers sont écrits en CRLF, sans indentation, avec `\"`, des UTF-8 bruts, des nombres du type `-7.62939453125e-05` et des listes positionnelles. L'analyseur tient le format réel ;
   - **Assemblage d'un addon temporaire** : j'ai fabriqué un SavedVariables **au format réel** (CRLF, compact, 15 noms de l'échantillon de `data_spec` + 600 paires synthétiques + 2 cartes), lancé le générateur, copié l'oracle dans le scratchpad en remplaçant `Data/`, et lancé `data` : **6 ok sur 6**. Suite complète sur cet assemblage : 161 ok, 1 échec (le garde-fou anti-oracle, voulu car le Core est celui de l'oracle) ;
   - **Entrées hostiles** sur l'analyseur (voir G7) et mesure de débit : 2,5 Mo (2 × 20000 zones + 3000 cartes) analysés en **0,42 s**.
4. J'ai supprimé `tools/__pycache__` que mes importations avaient créé. Le projet est dans l'état initial.

---

## 1. Notes

| | Note |
|---|---|
| **Globale** | **7/10** |
| Collecteur (`WoWTranslatorCollector/`) | **7,5/10** |
| Générateur (`tools/build_zone_data.py`) | **7/10** |
| Docs (`tools/README.md`, PLAN, client-research) | **6,5/10** |

**Collecteur.** Le code est propre et défensif : `issecretvalue` testé avant tout, sous `pcall`, absence tolérée ; `GetAreaInfo` et `GetMapInfo` sous `pcall`, `nil` et chaîne vide traités ; Lua 5.1 conforme ; une seule globale utile ; lots de 250 par tick, 92 ticks au total, quelques secondes, sans risque de gel. L'architecture (un bloc par locale, par lots) est bonne. Le défaut principal est la **robustesse des données écrites** : un bloc complet est écrasé dès le démarrage, et un bloc interrompu ressemble à un bloc terminé (C1). Rien ne garde les bornes ni le plus grand identifiant trouvé, donc rien ne détecte une borne trop basse (C2).

**Générateur.** L'analyseur est la partie solide : liste blanche stricte, aucun `exec`, tient les 132 fichiers réels, hostile-safe pour l'essentiel. Le déterminisme est bon et l'invariant de `data_spec` est vérifié. Mais : écriture **avant** le contrôle du seuil dans l'emplacement de livraison par défaut (G1), blocs partiels acceptés sans broncher (G2), règle du sens inverse qui n'est pas celle que le README annonce (G3) et qui peut produire une traduction fausse pour un nom identique (G4).

**Docs.** Le README est bien écrit et honnête sur les inconnues, mais la commande qu'il donne à l'utilisateur écrit dans `WoWTranslator/Data` alors que la même page l'interdit (D1) ; `client-research.md` présente encore des pistes officiellement écartées (D2) ; plusieurs étapes utilisateur sont incomplètes (D3).

Rien ne bloque le lancement de la collecte par l'utilisateur. En revanche, T3 ne doit pas démarrer avant G1, G2 et D1 : ce sont eux qui protègent la livraison.

---

## 2. Réponses aux questions posées

- **Joindre par identifiant est-il juste ?** Oui : l'API renvoie des noms de la locale courante, les `areaID` et `uiMapID` sont communs aux deux locales d'un même build. Le garde-fou des builds différents est présent (`build_zone_data.py:621-629`), mais ne couvre pas la complétude (G2).
- **Zones et cartes, les deux sont-elles nécessaires ?** Oui. `AreaLabelDataProvider.lua:86-88` affiche `GetMapInfoAtPosition(...).name` (nom de **carte**) et `:141` un nom de **zone**. Les zones servent aussi à T4 (texte de zone, minimap). Elles viennent de deux tables différentes du client (AreaTable et UiMap), donc des traductions divergentes pour un même nom anglais sont possibles (casse, apostrophe, variante). Le générateur les mélange dans **un seul** espace et tranche par fréquence : voir G6.
- **Normalisation (apostrophes `’` et `'`).** Aucune conversion n'est faite, et c'est juste tant que les clés viennent du client, puisque `Translate` est une recherche exacte (`PLAN.md:53`). Le problème est ailleurs : la normalisation des **espaces** modifie des clés que le client ne modifie pas (G5), et une divergence purement typographique entre zone et carte est comptée comme ambiguïté sans le dire (G5).
- **Sortie conforme à `data_spec.lua` ?** Oui sur données réalistes (6/6, voir méthode). Le générateur re-vérifie l'invariant d'inverse à chaque exécution (`:578-597`).
- **Écrire avant de vérifier le seuil ?** Mauvais choix : G1.
- **Chemin de sortie par défaut dangereux ?** Oui : G1 et D1.
- **Aucun test automatisé du collecteur ?** Insuffisant : C7. Mon banc de simulation montre que c'est faisable en une centaine de lignes avec le mock existant (`C_Timer` y est déjà).

---

## 3. Constats

Sévérités : **bloquant**, **majeur**, **mineur**, **nit**.

### C — Collecteur

**C1 — majeur — `Collector.lua:181-189`, `:125`, `:162-204`**
*Problème* : `db[locale] = block` est exécuté au **démarrage** (`:189`). Conséquences vérifiées au banc :
1. un bloc **complet** précédent est détruit dès `/wtcollect start`, avant tout résultat ;
2. un `/reload`, un plantage ou une déconnexion en cours de collecte écrit un bloc **partiel** dans les SavedVariables, avec `collectedAt = 0` (seul signe, jamais lu par le générateur, voir G2) : « apres interruption : areas 100, collectedAt 0, ancien bloc OLD present : false ».
*Correction* : remplir un bloc **local** (`state.block`) et ne l'affecter à `db[locale]` qu'à `finish()` (un bloc n'existe dans la base que s'il est complet). Si l'on veut garder la reprise, ajouter un champ explicite `complete = true` posé à `finish()` et laisser `status` afficher « incomplet ». Dans les deux cas, le générateur doit refuser un bloc non complet (G2).

**C2 — mineur — `Collector.lua:181-188`, `:19-20`**
*Problème* : les bornes utilisées, le plus grand identifiant trouvé et les compteurs d'erreurs ne sont pas enregistrés. Aucun moyen de savoir, en lisant le fichier, si la borne (20000 / 3000, non confirmée) était trop basse : il suffit qu'une zone ait l'identifiant 20001. Un bloc frFR collecté avec `start 5000` ne se distingue pas d'un bloc complet.
*Correction* : écrire dans le bloc `maxAreaId`, `maxMapId` (bornes demandées), `lastAreaFound`, `lastMapFound`, `errors`, `secret`, `empty`. Afficher à la fin un avertissement si `lastAreaFound > 0,9 × maxAreaId` (idem cartes) : « borne peut-être trop basse, relancer avec une borne plus grande ». Le générateur compare les deux blocs (G2).

**C3 — mineur — `Collector.lua:86-90`, `:127-129`**
*Problème* : `GetAreaInfo` est documenté sans `nil` (`Nilable = false`, pas de `MayReturnNothing`). Pour un identifiant inexistant, le client peut lever une erreur : le banc, avec une API qui lève, affiche « erreurs API : 19900 » à la fin. Le message est alarmant et mélange « API absente » et « identifiant inconnu ». Ce n'est pas un bogue de logique : `pcall` absorbe tout, sans passer par le gestionnaire d'erreurs.
*Correction* : distinguer `unknown` (erreur ou `nil` sur un id) du reste ; ne signaler comme alarmant que « 0 nom trouvé ». Message : « N identifiants inconnus (normal) ».

**C4 — nit — `Collector.lua:135-160`**
*Problème* : `step` n'est pas protégé. Une erreur Lua inattendue (autre que dans l'API appelée, qui est sous `pcall`) laisse `state.running = true` : `start` répond « déjà en cours », `reset` refuse, et il n'existe pas de `stop`. Seul `/reload` débloque.
*Correction* : `local ok, err = pcall(stepBody)` ; si `not ok`, `state.running = false` et `say("erreur : " .. tostring(err))`. Ajouter `/wtcollect stop` (met `running = false`, ne touche pas à la base).

**C5 — nit — `Collector.lua:22-23`**
`DELAY = 0.01` ne ralentit pas (une trame dure davantage) et `BATCH = 250` est prudent : 92 ticks, quelques secondes. Aucune action requise. Si un jour la durée gêne, `BATCH = 1000` reste sans risque (appels sous `pcall`, pas de tables retenues).

**C6 — nit — `Collector.lua:232`, `:229-231`**
`showStatus` n'affiche pas `build`/`version` du bloc comparés au build courant (`GetBuildInfo`). Après une mise à jour du jeu, `status` devrait signaler « bloc d'un autre build ». Le générateur le fait déjà entre enUS et frFR, mais pas entre le bloc et le client courant.

**C7 — mineur — absence de test automatisé du collecteur**
*Problème* : aucune spec ne couvre `Collector.lua`, ni dans `tests/specs/`, ni dans `SPECS` de `tests/run.lua`. L'auteur n'a pas pu modifier `run.lua` (consigne), mais rien n'a été **proposé** non plus. C1, C3 et C4 sont exactement le genre de défauts qu'un test de 100 lignes attrape. Le mock a déjà `C_Timer` (`wow_mock.lua:784-808`) ; il manque `C_Map` (à stubber dans la spec).
*Correction* : écrire `tests/specs/collector_spec.lua` (qui charge `WoWTranslatorCollector/Collector.lua` dans un environnement simulé) et demander l'ajout de `"collector"` à `SPECS`. Cas minimaux : collecte normale (nombre d'entrées, bloc seulement à la fin), valeur secrète ignorée, `issecretvalue` absent, `issecretvalue` qui lève, API qui lève sur les ids inconnus, interruption (pas de bloc partiel), bornes invalides (`0`, `abc`, `1.5`, `100001`), `start` pendant une collecte, `reset` pendant une collecte, lint 5.1 de `Collector.lua`. Mon banc `coll.lua` (scratchpad de cette revue) peut servir de base.

### G — Générateur

**G1 — majeur — `build_zone_data.py:662-677`, `:57`, `:561-575`**
*Problème* : trois défauts liés.
1. `emit` appelle `write_outputs` (`:667`) **avant** de tester le seuil (`small` est calculé en `:666`, utilisé en `:674`). Avec `--min-entries` non atteint, les deux fichiers et le rapport sont écrits, puis le code `2` est renvoyé. J'ai reproduit : fixture de 8 entrées, `rc=2`, deux fichiers présents.
2. Le dossier par défaut est `WoWTranslator/Data` **à la racine du dépôt** (`:57`), c'est-à-dire l'emplacement de livraison de T3. Une exécution sans `--out-dir` (y compris la commande du README, voir D1) y écrit, et **écrase** des données valides par des données incomplètes. Le projet n'a pas de gestionnaire de versions (`git` : non), donc aucune récupération. C'est ce qui est arrivé à l'agent (création accidentelle de `WoWTranslator/` à la racine).
3. L'écriture n'est pas atomique : le fichier direct est écrit, puis l'inverse. Une erreur entre les deux laisse deux fichiers d'exécutions différentes.
*Correction* :
- tout valider **avant** d'écrire (seuil, invariants, complétude, G2) ; si le seuil échoue : aucun fichier de données, seulement le rapport (utile pour diagnostiquer) ;
- `--out-dir` sans valeur par défaut vers `WoWTranslator/Data` : défaut sur un dossier de mise en attente, par exemple `tools/out/`, ignoré du dépôt. Le passage dans `WoWTranslator/Data` se fait par une option explicite `--install` (ou par une copie manuelle documentée, relevant de T3) ;
- écrire les deux fichiers sous un nom temporaire puis `os.replace` ;
- refuser d'écraser un `--out-dir` non vide contenant des fichiers non générés (garde sur l'en-tête « genere par tools/build_zone_data.py »).

**G2 — majeur — `build_zone_data.py:272-295`, `:615-647`**
*Problème* : `load_collector_blocks` vérifie seulement que `areas` et `maps` sont des tables. Un bloc partiel (`collectedAt = 0`, C1) est accepté : j'ai généré 609 entrées par ce chemin avec `rc=0` et sans avertissement, le rapport affichant juste « date inconnue ». Aucune comparaison des bornes, ni du plus grand identifiant, ni de `version`/`toc` entre les deux blocs. Une collecte frFR arrêtée à mi-chemin produit donc des dictionnaires silencieusement amputés (les identifiants « seulement enUS » sont comptés, jamais jugés).
*Correction* : (a) `collectedAt` absent ou 0, ou `complete ~= true`, donc **erreur code 1** ; (b) avertissement si `version` ou `toc` diffèrent (pas seulement `build`, `:621`) ; (c) avertissement (ou erreur avec `--strict`) si la proportion d'identifiants présents d'un seul côté dépasse un seuil (par exemple 2 %) ; (d) avec les champs de C2, avertir si les bornes diffèrent entre les deux blocs ou si le dernier identifiant trouvé est proche de la borne.

**G3 — mineur — `build_zone_data.py:431-438`, `tools/README.md:126`**
*Problème* : le sens inverse n'applique **pas** « la même règle » (README 4.2). `inv_occ` contient **une seule** occurrence par paire gardée, avec son plus petit identifiant (`rep_id`, `:433-437`) : la fréquence est perdue, le rang se joue donc toujours au plus petit identifiant. Vérifié : `en = {1:"Rare", 2..6:"Common"}`, `fr = "X"` pour tous : `fwd` garde les deux, mais `bwd["X"] = "Rare"` alors que `Common` correspond à 5 identifiants contre 1. Dans le rapport, la colonne « nombre d'identifiants » du sens inverse vaut donc toujours 1.
*Correction* : compter, par paire `(s, t)` gardée, le nombre d'identifiants (`len(ids)`) et construire `inv_occ` avec toutes les occurrences (ou passer des effectifs à `resolve`). Ou corriger le README : « sens inverse : plus petit identifiant ». Le premier choix vaut mieux (un nom anglais qui couvre 5 sous-zones est plus probable qu'un nom qui en couvre une).

**G4 — mineur — `build_zone_data.py:423-438`, `:393-415`**
*Problème* : les noms identiques (`identity`) sont écartés du sens direct, mais ne participent pas au tri du sens inverse. Vérifié : `en = {1:"A", 2:"B"}`, `fr = {1:"B", 2:"B"}` : `fwd = {A: B}` (l'identité `B -> B` est abandonnée), `bwd = {B: A}`. Un joueur frFR **dans la zone 2**, dont le vrai nom est « B », la verra traduite en « A », qui est le nom anglais de la zone 1. En pratique : une zone dont le nom est identique dans les deux langues (Darnassus, Orgrimmar, Durotar, Teldrassil, Mulgore, Dun Morogh figurent dans `data_spec.lua`) et dont ce même nom est aussi la traduction d'un nom anglais différent. Rare, mais la règle du sens direct (« l'identité retenue donne aucune entrée ») doit s'appliquer pareillement ici.
*Correction* : alimenter `resolve` du sens inverse avec **toutes** les occurrences, identités comprises, puis retirer l'entrée si l'identité l'emporte, et lister ces cas dans le rapport (section « noms cibles qui sont aussi des noms sources »).

**G5 — mineur — `build_zone_data.py:328-333`, `:298-321`, README 4.8**
*Problème* : trois points.
1. `normalise` réduit les espaces **dans les clés**, alors que `Translate` est une recherche exacte sur le texte brut du client (`PLAN.md:53`, `tests/README.md:189`). Une zone dont le nom contient une espace en fin, doublée ou insécable (le client les renvoie telles quelles) est stockée sous une clé que le client ne produira jamais : couverture perdue sans trace. Le rapport ne compte pas les noms modifiés.
2. L'espace insécable est supprimé en clé comme en valeur : la valeur affichée perd le caractère voulu par Blizzard.
3. Les écarts purement typographiques entre deux traductions d'un même nom (`'` et `’`, casse, espace) sont comptés comme des ambiguïtés comme les autres, noyant les vrais conflits dans le rapport.
*Correction* : ne **pas** normaliser les clés (garder le brut du client) ; normaliser seulement pour **détecter** : compter dans le rapport « noms dont la forme brute diffère de la forme normalisée » et lister les 20 premiers. Dans les ambiguïtés, ajouter un indicateur « variantes typographiques seulement » (comparaison sous normalisation + casse + `’` -> `'`).

**G6 — mineur — `build_zone_data.py:313-320`, `:393-415`, README 4.7**
*Problème* : zones et cartes entrent dans le même espace d'identifiants, avec un tri par fréquence. Ce choix est défendable (les zones sont nombreuses, donc gagnent), mais il n'est ni explicite ni visible : le rapport ne dit pas si les identifiants en conflit sont des zones ou des cartes (il faut deviner par `>= 1000000`), et un nom qui n'existe que comme carte peut entrer en conflit avec une zone sans que l'on sache lequel prime. Pour T4 (texte de zone) la traduction de **zone** doit primer ; pour T5 (carte) la traduction de **carte** serait préférable, or le contrat n'offre qu'un dictionnaire par sens.
*Correction* : décider et écrire la règle : « zone prime sur carte, puis fréquence, puis plus petit identifiant ». Ajouter au rapport une colonne « origine » (zone / carte) et une section « conflits zone contre carte » listée à part. Noter dans `PLAN.md` que T5 hérite de la traduction de zone en cas de conflit (ou prévoir un second dictionnaire si l'inspection du rapport réel le justifie).

**G7 — nit — `build_zone_data.py:110-123`, `:160-173`, `:256`**
*Analyseur, entrées hostiles essayées* : 
- sûr : `os.exit(1)`, `f("a")`, `"a" .. "b"`, `1 + 2`, `[[long]]`, `1..2`, `inf`, `-`, `0x`, `\256`, `\q`, chaîne non terminée, UTF-8 invalide : tous en `DataError` (code 1, aucun fichier) ;
- correct : `\0651` = `A1` (trois chiffres au maximum), `-0x10`, `1e999`, `.5`, `5.`, `\0`, `;` comme séparateur, clés `true` ou flottantes (rejetées plus tard par `rows_from_block`) ;
- **imprécis** : (a) imbrication à 5000 niveaux : `RecursionError` non rattrapée (trace Python, code 1, aucun fichier écrit : acceptable, mais le message est illisible) ; (b) entier de 5000 chiffres : `ValueError` (limite Python 3.11+), idem ; (c) BOM UTF-8 en tête : « nom de variable attendu » (message trompeur) ; (d) `--[[ ... ]]` traité comme un commentaire de ligne : le contenu des lignes suivantes est analysé comme des données ; (e) `\` suivi de CRLF : « échappement inconnu ». Le client n'écrit aucun de ces cas (vérifié sur les 132 fichiers réels).
*Correction* : `except (RecursionError, ValueError)` dans `main` avec un `DataError` clair ; accepter ou refuser nettement le BOM ; gérer `--[[`/`--[==[` (le client ne les écrit pas, mais un fichier édité à la main peut en contenir) ; limiter la profondeur à, disons, 50.

**G8 — nit — `build_zone_data.py:375-379`**
Les marqueurs « absent » sont la **chaîne** `"absent"` : une zone dont le nom est « absent » est comptée comme absente (vérifié : `{1:"absent"}` donne `fr_only = 1`). Utiliser un objet sentinelle (`_MISSING = object()`).

**G9 — nit — `build_zone_data.py:618-629`, `:565`**
Le libellé de build est `71037` (le bloc ne contient que `build`), alors que tous les documents écrivent `1.60.1.71037`. Utiliser `version` + `.` + `build`. L'en-tête « Commande » perd le chemin du SavedVariables ; acceptable (déterminisme), à documenter.

**G10 — nit — `build_zone_data.py:541-543`, `:555`**
Les noms sont insérés tels quels dans des cellules Markdown : un `|` ou un retour à la ligne dans un nom casse le tableau. Échapper `|`.

**G11 — mineur — `selftest` `build_zone_data.py:700-915`**
*Problème* : les 63 vérifications sont bonnes, mais :
1. la fixture SavedVariables est écrite à la main au format « tabulations + LF + commentaires » ; le **vrai** format du client (CRLF, sans indentation, listes positionnelles, notation scientifique) n'est pas testé. L'analyseur le tient (132 fichiers réels), mais c'est ma vérification, pas la sienne ;
2. aucun test d'un bloc incomplet ou de bornes différentes (G2) ;
3. le test « seuil non atteint : code 2 » (`:794-797`) ne vérifie pas ce qui est écrit : il valide le comportement à corriger en G1 ;
4. aucun test du chemin de sortie par défaut ; 
5. aucun pont avec la suite Lua : le générateur n'est jamais confronté à `data_spec.lua` dans le dépôt. Les « invariants de data_spec » sont recopiés en Python (`:578-597`) ; si l'un des deux évolue, rien ne le signale.
*Correction* : ajouter une fixture au format réel (CRLF, compacte), un test de bloc incomplet, un test « seuil non atteint : aucun fichier de données », un test des deux tables de sortie chargées par un vrai interpréteur Lua quand `tests/tools/luarun.py` est disponible (ou au minimum, mettre dans `tests/README.md` la procédure que j'ai utilisée : assembler un addon temporaire dans un dossier hors dépôt et lancer `run.lua data --addon=...`).

**G12 — nit — `build_zone_data.py:6-15`, `:336-367`, `:600-612`**
Le mode CSV est conservé « pour garder le code testé » alors que le README (§6) dit qu'il est « non conservé » et exclu (EULA). C'est du code mort assumé, avec des noms de colonnes par défaut (`AreaName_lang`) venant des extracteurs écartés, et une source par défaut `AreaTable, produit wowf` (`:69`). Soit le supprimer (et ses fixtures CSV), soit l'étiqueter « hors décision du 21/11, ne pas utiliser » dans `--help`.

### D — Docs

**D1 — majeur — `tools/README.md:70`, `:80`, `:86`, `:102`**
*Problème* : la commande donnée à l'utilisateur en §2.5 (`--from-savedvariables CHEMIN`) n'a pas `--out-dir` : elle écrit dans `WoWTranslator/Data` (`:86`, défaut), alors que la ligne `:102` dit « Ne pas écrire dans `WoWTranslator/Data` avant l'étape T3 ». Contradiction exécutable, et c'est précisément la cause de l'incident de l'agent. Le code `2` (« la sortie ne doit pas être committée », `:98`) confirme le risque.
*Correction* : donner partout `--out-dir tools\out` (ou le nouveau défaut de G1) et réserver `WoWTranslator/Data` à T3 par une copie explicite.

**D2 — mineur — `docs/client-research.md:89-95`, `:103-105`, `:349`**
*Problème* : le §4 « Conséquences pour T1 » décrit toujours CascLib, DBCD, wow.tools.local, « l'utilisateur doit accepter d'installer un de ces outils » et Spoken_Places comme alternative ; la question ouverte 12 (`:349`) demande encore de décider sur Spoken_Places. `PLAN.md:94-95` et `tools/README.md:9`, `:165-168` ont tranché (collecte en jeu, extracteurs et Spoken_Places écartés).
*Correction* : remplacer ces paragraphes par un renvoi à `PLAN.md` (T1) et marquer la question 12 comme close, ou ajouter en tête « SUPPLANTÉ le 21/11/2026 ».

**D3 — mineur — `tools/README.md:26-73`**
*Problème* : étapes utilisateur incomplètes ou imprécises :
1. Rien ne dit d'**activer** l'addon à l'écran de sélection de personnage (il est actif par défaut avec `Interface: 16001`, mais la vérification est une ligne) ni de le **désactiver ou retirer** après la collecte : ses SavedVariables (~ 1 Mo) seraient rechargées à chaque connexion.
2. Rien ne dit que les **deux collectes doivent se faire sous le même compte** : les SavedVariables sont par compte. Sur la machine auditée, `WTF\Account` contient deux dossiers (`1455056#1` avec 3 fichiers, et `UNKNOWNSSOLDIER` avec tous les autres) : le README laisse l'utilisateur deviner lequel (`:61`). Dire : « le dossier qui contient déjà `Blizzard_*.lua` », ou donner la recherche `dir /s /b WoWTranslatorCollector.lua`.
3. Pas de **critère de plausibilité** avant de se déconnecter : dire de lancer `/wtcollect status` et d'attendre « zones : plusieurs milliers » ; en dessous de 200, ne pas passer à l'étape suivante.
4. Ne pas lancer `/reload` **pendant** la collecte (voir C1) : à écrire.
5. Il faudra relancer le jeu pour changer de langue : l'étape 6 le dit, mais pas que la langue (Battle.net) se règle **avant** le lancement, jeu fermé.
6. `tools/README.md:186` nomme `MAX_AREA_ID` / `MAX_MAP_ID`, qui n'existent pas : les constantes sont `DEFAULT_MAX_AREA_ID` / `DEFAULT_MAX_MAP_ID` (`Collector.lua:19-20`).
*Correction* : ajouter ces points aux §2.1 à §2.4.

**D4 — nit — `PLAN.md:17-41`, `:68-78`**
L'arborescence cible n'a pas `WoWTranslatorCollector/`, et la table des tâches donne à T1 « Fichiers possédés : `tools/*` ». Ajouter `WoWTranslatorCollector/` aux deux endroits. `tests/README.md` et `docs/test-checklist.md` ne mentionnent pas non plus le collecteur : une ligne « hors périmètre des tests, voir C7 » suffit.

**D5 — nit — vérifications positives**
- `## Title-frFR` et `## Notes-frFR` sont des balises valides ; UTF-8 sans BOM, fins de ligne LF (`WoWTranslatorCollector.toc`).
- Les citations de lignes de `tools/README.md:15-17` (`MapDocumentation.lua`, `MapConstantsDocumentation.lua`) sont correctes.
- Le compte « 63 vérifications » est exact.
- Le chemin `WTF\Account\<COMPTE>\SavedVariables\WoWTranslatorCollector.lua` correspond à la disposition réelle du jeu (SavedVariables de compte), et un SavedVariables survit à la collecte de l'autre langue : le bloc enUS reste.

---

## 4. Pour atteindre 9/10

Dans l'ordre :

1. **G1** : tout valider avant d'écrire, écriture atomique, plus de défaut vers `WoWTranslator/Data` (staging + installation explicite). **D1** en conséquence.
2. **C1 + G2** : le collecteur n'écrit un bloc qu'à la fin (ou marque `complete`) ; le générateur refuse un bloc non complet et compare `version`/`toc`/bornes. C2 fournit les champs.
3. **G3 + G4** : sens inverse avec les effectifs réels et prise en compte des identités. Mettre à jour la section 4.2 du README en conséquence.
4. **C7** : spec du collecteur et ajout à `SPECS` (par le propriétaire de `run.lua`) ; **G11** : fixture au format réel, test de bloc incomplet, pont vers `data_spec`.
5. **G5 + G6** : clés brutes, rapport des variantes typographiques, origine zone/carte, règle de priorité écrite.
6. **D2 + D3 + D4** : documents alignés, étapes utilisateur complètes.
7. Nits : C3 à C6, G7 à G10, G12.

Les points 1 à 3 sont de l'ordre de la demi-journée ; ils ne changent ni l'architecture ni le format de sortie. Avec eux et la spec du collecteur, la base est à 9/10. Le seul inconnu qui restera est hors de portée des auteurs : le comportement réel de `GetAreaInfo` sur un identifiant inconnu, les bornes réelles et la couverture des deux collectes, qui ne seront connus qu'après la première exécution en jeu. Le rapport de couverture sera alors la première donnée à relire, avec C2 en garde-fou.
