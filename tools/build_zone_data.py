#!/usr/bin/env python3
"""Genere les dictionnaires de noms WoWTranslator (PLAN T1) depuis la collecte en jeu.

Entree unique : le fichier SavedVariables de l'addon WoWTranslatorCollector,
``WTF\\Account\\<COMPTE>\\SavedVariables\\WoWTranslatorCollector.lua``. Il est lu
comme des donnees, jamais execute. Il doit contenir deux blocs complets, enUS et
frFR, collectes avec le meme compte, le meme client et le meme build.

Sorties, ecrites atomiquement (fichier temporaire puis os.replace), seulement
quand toutes les verifications passent :
    Zones_enUS_frFR.lua   WT.data.enUS_frFR = { ... }
    Zones_frFR_enUS.lua   WT.data.frFR_enUS = { ... }
Le rapport (rapport_couverture.md) est toujours ecrit dans tools/out/, sauf --report.

Dossier de sortie : tools/out/ par defaut (ignore par git). --install ecrit dans
WoWTranslator/Data : a faire seulement a l'etape T3, apres relecture du rapport.

Codes de sortie :
    0  succes
    1  entree invalide ou refusee (blocs incomplets, builds differents, avertissement
       avec --strict, fichier genere absent...) : aucun fichier ecrit
    2  seuil --min-entries non atteint : seul le rapport est ecrit

Regles (detail dans tools/README.md, section 4). Stdlib uniquement, Python 3.8+.
"""

import argparse
import json
import os
import re
import sys
import tempfile
import time

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TOOLS_DIR)
STAGING_DIR = os.path.join(TOOLS_DIR, "out")
INSTALL_DIR = os.path.join(REPO_DIR, "WoWTranslator", "Data")
REPORT_NAME = "rapport_couverture.md"
FIXTURES = os.path.join(TOOLS_DIR, "fixtures")

OVERRIDES_DEFAULT = os.path.join(TOOLS_DIR, "overrides.json")
FILE_FWD = "Zones_enUS_frFR.lua"
FILE_BWD = "Zones_frFR_enUS.lua"
TABLE_FWD = "enUS_frFR"
TABLE_BWD = "frFR_enUS"
NATIVE_FWD = "native_enUS_frFR"  # noms identiques dans les deux langues (pas des entrees)
NATIVE_BWD = "native_frFR_enUS"
GENERATED_MARK = "genere par tools/build_zone_data.py"
REPORT_MARK = "# Rapport de couverture"

SV_NAME = "WoWTranslatorCollectorDB"
SV_LOCALES = ("enUS", "frFR")
SCHEMA = 2
ABSOLUTE_MAX = 100000        # borne maximale acceptee (comme l'addon)
MAP_ID_OFFSET = 1000000      # uiMapID -> meme espace que les areaID
MAX_DEPTH = 50               # imbrication maximale des tables
COVERAGE_WARN = 0.02         # part d'identifiants presents d'un seul cote
COLLISION_RATIO = 5          # collision avec identite : identifiants concurrents >= 5 x identiques
NEAR_BOUND = 0.9             # trouve au-dela de 90 % de la borne : borne suspecte
ZONE, MAP = 0, 1
_MISSING = object()


class DataError(Exception):
    """Entree invalide ou refusee : arret, aucun fichier de donnees ecrit."""


def bkey(s):
    return s.encode("utf-8")


def origin_of(ident):
    return MAP if ident >= MAP_ID_OFFSET else ZONE


def normalised(s):
    """Forme normalisee (espaces) : sert seulement a DETECTER les ecarts, jamais a reecrire."""
    return re.sub(r"\s+", " ", s).strip()


def fold(s):
    """Forme de comparaison : espaces, casse, apostrophe typographique."""
    return normalised(s).lower().replace("\u2019", "'")


# ---------------------------------------------------------------------------
# Lecture du SavedVariables : analyseur de tables Lua litterales, sans execution
# ---------------------------------------------------------------------------

_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUM_RE = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][-+]?[0-9]+)?)")
_LONG_OPEN_RE = re.compile(r"--\[(=*)\[")
_SIMPLE_ESC = {
    "n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
    "\\": "\\", '"': '"', "'": "'", "\n": "\n",
}


class LuaLiteralParser:
    """Sous-ensemble Lua 5.1 ecrit par le client dans les SavedVariables.

    Accepte : affectations ``NOM = valeur`` au premier niveau ; tables ``{}`` avec
    ``[cle] = valeur``, ``nom = valeur`` ou valeurs positionnelles, separees par
    ``,`` ou ``;`` ; chaines avec les echappements Lua (\\n, \\", \\ddd...) ; nombres
    (decimaux, exposant, hexadecimaux) ; true, false, nil ; commentaires ``--`` et
    ``--[==[ ]==]``. Tout le reste est refuse. Aucun code n'est execute.
    Le texte est lu octet par octet (latin-1), les chaines sont decodees en UTF-8.
    """

    def __init__(self, text, path):
        self.s = text
        self.i = 0
        self.path = path
        self.depth = 0

    def fail(self, msg, pos=None):
        pos = self.i if pos is None else pos
        line = self.s.count("\n", 0, pos) + 1
        raise DataError("%s, ligne %d : %s" % (self.path, line, msg))

    def skip(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n\f\v":
                self.i += 1
                continue
            if s.startswith("--", self.i):
                m = _LONG_OPEN_RE.match(s, self.i)
                if m:
                    close = "]" + m.group(1) + "]"
                    j = s.find(close, m.end())
                    if j < 0:
                        self.fail("commentaire long non ferme")
                    self.i = j + len(close)
                else:
                    j = s.find("\n", self.i)
                    self.i = n if j < 0 else j + 1
                continue
            break

    def peek(self):
        self.skip()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expect(self, ch):
        if self.peek() != ch:
            self.fail("'%s' attendu" % ch)
        self.i += 1

    def ident_here(self):
        self.skip()
        return _IDENT_RE.match(self.s, self.i)

    def value(self):
        c = self.peek()
        if c == "":
            self.fail("fin de fichier inattendue")
        if c == "{":
            return self.table()
        if c in ('"', "'"):
            return self.string()
        if c in "-.0123456789":
            return self.number()
        m = self.ident_here()
        if m:
            word = m.group()
            self.i = m.end()
            if word == "true":
                return True
            if word == "false":
                return False
            if word == "nil":
                return None
            self.fail("valeur non autorisee %r" % word, m.start())
        self.fail("caractere inattendu %r" % c)

    def number(self):
        m = _NUM_RE.match(self.s, self.i)
        if not m:
            self.fail("nombre invalide")
        self.i = m.end()
        txt = m.group()
        neg = txt.startswith("-")
        body = txt[1:] if neg else txt
        try:
            if body[:2] in ("0x", "0X"):
                val = int(body, 16)
                return -val if neg else val
            if "." in body or "e" in body or "E" in body:
                return float(txt)
            return int(txt)
        except (ValueError, OverflowError):
            self.fail("nombre hors limite")

    def string(self):
        s, n = self.s, len(self.s)
        q = s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= n:
                self.fail("chaine non terminee")
            c = s[self.i]
            if c == q:
                self.i += 1
                break
            if c == "\n":
                self.fail("fin de ligne dans une chaine")
            if c != "\\":
                out.append(c)
                self.i += 1
                continue
            self.i += 1
            if self.i >= n:
                self.fail("echappement incomplet")
            e = s[self.i]
            if e == "\r":  # saut de ligne echappe en CRLF
                self.i += 1
                if self.i < n and s[self.i] == "\n":
                    self.i += 1
                out.append("\n")
            elif e in _SIMPLE_ESC:
                out.append(_SIMPLE_ESC[e])
                self.i += 1
            elif e in "0123456789":
                j = self.i
                while j < n and j < self.i + 3 and s[j] in "0123456789":
                    j += 1
                code = int(s[self.i:j])
                if code > 255:
                    self.fail("echappement decimal hors limite")
                out.append(chr(code))
                self.i = j
            else:
                self.fail("echappement inconnu \\%s" % e)
        raw = "".join(out).encode("latin-1")
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            self.fail("chaine non UTF-8")

    def table(self):
        self.expect("{")
        self.depth += 1
        if self.depth > MAX_DEPTH:
            self.fail("imbrication trop profonde (plus de %d niveaux)" % MAX_DEPTH)
        result = {}
        positional = 0
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                self.depth -= 1
                return result
            if c == "[":
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                val = self.value()
                if val is not None:          # en Lua, t[k] = nil signifie « absent »
                    result[key] = val
            else:
                m = self.ident_here()
                named = False
                if m:
                    save = self.i
                    self.i = m.end()
                    if self.peek() == "=":
                        named = True
                        self.i += 1
                        result[m.group()] = self.value()
                    else:
                        self.i = save
                if not named:
                    # Le client ecrit la partie tableau en positionnel, avec des « nil » pour
                    # les trous ({"A", nil, nil, "D"}) : l'index avance, mais rien n'est stocke.
                    positional += 1
                    val = self.value()
                    if val is not None:
                        result[positional] = val
            c = self.peek()
            if c in (",", ";"):
                self.i += 1
            elif c != "}":
                self.fail("',' ou '}' attendu dans une table")


def parse_savedvariables(data, path):
    """data : octets du fichier. Retourne {nom global : valeur}, sans execution."""
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        p = LuaLiteralParser(data.decode("latin-1"), path)
        top = {}
        while p.peek() != "":
            m = p.ident_here()
            if not m:
                p.fail("nom de variable attendu")
            p.i = m.end()
            p.expect("=")
            top[m.group()] = p.value()
            if p.peek() == ";":
                p.i += 1
        return top
    except RecursionError:
        raise DataError("%s : structure trop imbriquee" % path)


# ---------------------------------------------------------------------------
# Validation des blocs (avant toute ecriture)
# ---------------------------------------------------------------------------

def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def validate_block(block, loc, path):
    def bad(msg):
        raise DataError("%s, bloc %s : %s" % (path, loc, msg))

    if block.get("complete") is not True:
        bad("bloc incomplet (complete != true). La collecte n'est pas terminee, ou le bloc "
            "vient d'une ancienne version de l'addon. Refaire /wtcollect start dans cette "
            "langue et attendre le message 'termine'.")
    if block.get("schema") != SCHEMA:
        bad("schema %r non supporte (attendu %d)" % (block.get("schema"), SCHEMA))
    if block.get("locale") != loc:
        bad("locale %r, attendu %r" % (block.get("locale"), loc))
    for key in ("version", "build"):
        if not isinstance(block.get(key), str) or not block.get(key):
            bad("champ %r absent ou vide" % key)
    if not _is_int(block.get("toc")):
        bad("champ 'toc' absent ou non entier")
    for key in ("maxAreaId", "maxMapId"):
        v = block.get(key)
        if not _is_int(v) or v < 1 or v > ABSOLUTE_MAX:
            bad("borne %r invalide : %r" % (key, v))
    if not _is_int(block.get("collectedAt")) or block["collectedAt"] <= 0:
        bad("date de collecte absente")
    areas, maps = block.get("areas"), block.get("maps")
    if not isinstance(areas, dict) or not isinstance(maps, dict):
        bad("tables 'areas' ou 'maps' absentes")
    if block.get("areasFound") != len(areas) or block.get("mapsFound") != len(maps):
        bad("compteurs incoherents avec le contenu (areasFound / mapsFound)")
    for ident, name in areas.items():
        if not _is_int(ident) or not (1 <= ident <= block["maxAreaId"]):
            bad("areaID %r hors des bornes 1..%d" % (ident, block["maxAreaId"]))
        if not isinstance(name, str):
            bad("nom de zone %r non textuel" % ident)
    for ident, entry in maps.items():
        if not _is_int(ident) or not (1 <= ident <= block["maxMapId"]):
            bad("uiMapID %r hors des bornes 1..%d" % (ident, block["maxMapId"]))
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            bad("carte %r sans nom textuel" % ident)
    if block.get("maxFoundAreaId") != (max(areas) if areas else 0):
        bad("maxFoundAreaId incoherent avec les zones")
    if block.get("maxFoundMapId") != (max(maps) if maps else 0):
        bad("maxFoundMapId incoherent avec les cartes")


def check_pair(en, fr, allow_mismatch, warnings):
    """Compare les deux blocs. Leve DataError si le build differe (sauf --allow-mismatch)."""
    for key in ("version", "build", "toc"):
        if en[key] != fr[key]:
            msg = "%s different entre les blocs (enUS %r, frFR %r)" % (key, en[key], fr[key])
            if not allow_mismatch:
                raise DataError(msg + ". Refaire les deux collectes sur le meme client, "
                                "ou --allow-mismatch si c'est voulu.")
            warnings.append(msg)
    if en["maxAreaId"] != fr["maxAreaId"] or en["maxMapId"] != fr["maxMapId"]:
        warnings.append("bornes differentes (enUS %d / %d, frFR %d / %d) : couverture possiblement inegale"
                        % (en["maxAreaId"], en["maxMapId"], fr["maxAreaId"], fr["maxMapId"]))
    for label, key, bound in (("zones", "areas", "maxAreaId"), ("cartes", "maps", "maxMapId")):
        a, b = set(en[key]), set(fr[key])
        union = a | b
        only = len(a ^ b)
        if union and only / float(len(union)) > COVERAGE_WARN:
            warnings.append("ecart de couverture (%s) : %d identifiant(s) sur %d presents d'un seul cote (%.1f %%)"
                            % (label, only, len(union), 100.0 * only / len(union)))
    for loc, block in (("enUS", en), ("frFR", fr)):
        for label, key, bound in (("zone", "maxFoundAreaId", "maxAreaId"), ("carte", "maxFoundMapId", "maxMapId")):
            if block[key] >= NEAR_BOUND * block[bound]:
                warnings.append("%s : %s trouvee a l'id %d, pres de la borne %d : borne peut-etre trop basse"
                                % (loc, label, block[key], block[bound]))


def load_collector_blocks(path):
    """Retourne (bloc enUS, bloc frFR), tous deux valides."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise DataError("lecture impossible : %s (%s)" % (path, e))
    top = parse_savedvariables(data, path)
    db = top.get(SV_NAME)
    if not isinstance(db, dict):
        raise DataError("%s : variable %s absente (aucune collecte enregistree)" % (path, SV_NAME))
    blocks = {}
    for loc in SV_LOCALES:
        block = db.get(loc)
        if not isinstance(block, dict):
            raise DataError("%s : bloc %r absent. Lancer /wtcollect start avec la langue %s, "
                            "puis se deconnecter (voir tools/README.md)" % (path, loc, loc))
        validate_block(block, loc, path)
        blocks[loc] = block
    return blocks["enUS"], blocks["frFR"]


def rows_of(block):
    """ident -> nom brut, ou None si vide. Zones : areaID ; cartes : MAP_ID_OFFSET + uiMapID."""
    rows = {}
    for ident, name in block["areas"].items():
        rows[ident] = name if name.strip() else None
    for ident, entry in block["maps"].items():
        name = entry["name"]
        rows[MAP_ID_OFFSET + ident] = name if name.strip() else None
    return rows


_PAREN_SUFFIX_RE = re.compile(r"^(.*\S) \(([^()]+)\)$")


def strip_english_suffixes(en_rows, fr_rows):
    """Retire le suffixe « (X) » d'un nom quand X est le nom de l'AUTRE langue pour le MEME identifiant.

    Exemple client : frFR « Terres ingrates (Badlands) » pour l'identifiant dont enUS est « Badlands ».
    Comparaison : apres normalisation des espaces (normalised). Symetrique. Un seul retrait par nom.
    Jamais de retrait si X differe du nom de l'autre langue (un « (...) » legitime est conserve).
    Retourne (lignes enUS, lignes frFR, retraits [(identifiant, langue, nom brut, nom retenu)]).
    """
    en2, fr2, stripped = dict(en_rows), dict(fr_rows), []
    for ident in sorted(set(en_rows) & set(fr_rows)):
        en, fr = en_rows[ident], fr_rows[ident]
        if en is None or fr is None:
            continue
        m = _PAREN_SUFFIX_RE.match(fr)
        if m and normalised(m.group(2)) == normalised(en):
            fr2[ident] = m.group(1)
            stripped.append((ident, "frFR", fr, m.group(1)))
        m = _PAREN_SUFFIX_RE.match(en)
        if m and normalised(m.group(2)) == normalised(fr):
            en2[ident] = m.group(1)
            stripped.append((ident, "enUS", en, m.group(1)))
    return en2, fr2, stripped


# ---------------------------------------------------------------------------
# Construction des dictionnaires
# ---------------------------------------------------------------------------

def join(en_rows, fr_rows):
    """Retourne (paires (id, en, fr) gardables, compteurs ventiles zones / cartes).

    Les paires identiques sont des paires comme les autres : elles sont comptees
    ici et departagees dans build() (regle d'identite, voir README 4.4).
    """
    pairs = []
    stats = {"matched": 0, "identity_rows": 0, "empty_pair": 0}
    for kind in ("zone", "carte"):
        stats["en_only_" + kind] = 0
        stats["fr_only_" + kind] = 0
    for ident in sorted(set(en_rows) | set(fr_rows)):
        kind = "carte" if origin_of(ident) == MAP else "zone"
        en = en_rows.get(ident, _MISSING)
        fr = fr_rows.get(ident, _MISSING)
        if en is _MISSING:
            stats["fr_only_" + kind] += 1
            continue
        if fr is _MISSING:
            stats["en_only_" + kind] += 1
            continue
        if en is None or fr is None:
            stats["empty_pair"] += 1
            continue
        stats["matched"] += 1
        if en == fr:
            stats["identity_rows"] += 1
        pairs.append((ident, en, fr))
    return pairs, stats


def choose(groups, prefer=None):
    """groups : cible -> liste d'identifiants (zones et/ou cartes).

    Regle : si une cible a au moins une zone, seules les zones comptent (les cartes
    ne priment jamais sur une zone). Ensuite, le plus d'identifiants retenus gagne ;
    a egalite, la cible `prefer` (l'identite) gagne ; a egalite encore, le plus petit
    identifiant, puis l'ordre alphabetique.
    Retourne (cible retenue, classement [(cible, nb, plus_petit_id, origine)],
    cibles cartes ecartees ou None).
    """
    has_zone = {t: any(origin_of(i) == ZONE for i in ids) for t, ids in groups.items()}
    zone_mode = any(has_zone.values())
    use = {}
    for t, ids in groups.items():
        sel = [i for i in ids if origin_of(i) == ZONE] if zone_mode else list(ids)
        if sel:
            use[t] = sel
    ranked = sorted(
        use.items(),
        key=lambda kv: (-len(kv[1]), 0 if kv[0] == prefer else 1, min(kv[1]), bkey(kv[0])),
    )
    chosen = ranked[0][0]
    rows = [(t, len(ids), min(ids), "zone" if has_zone[t] else "carte") for t, ids in ranked]
    dropped = None
    if zone_mode:
        maps_only = sorted((t for t in groups if not has_zone[t]), key=bkey)
        dropped = maps_only or None
    return chosen, rows, dropped


def load_overrides(path):
    """Lit tools/overrides.json (ou --overrides PATH) : retourne [(nom enUS, nom frFR)].

    Format : {"enUS_frFR": {"enUS": "frFR", ...}, "frFR_enUS": {"frFR": "enUS", ...}}, les
    deux cles etant facultatives. Les deux sens sont fusionnes en paires. Erreurs (code 1) :
    JSON invalide, cle inconnue, valeur non chaine, chaine vide, auto-boucle (enUS == frFR),
    deux corrections contradictoires pour un meme nom. Un nom absent des donnees n'est PAS
    une erreur : c'est une note (voir run).
    """
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise DataError("corrections manuelles : lecture impossible ou JSON invalide (%s) : %s" % (path, e))
    if not isinstance(data, dict):
        raise DataError("corrections manuelles : %s doit contenir un objet JSON" % path)
    unknown = set(data) - {"enUS_frFR", "frFR_enUS"}
    if unknown:
        raise DataError("corrections manuelles : cles inconnues %s (attendu : enUS_frFR, frFR_enUS)"
                        % ", ".join(sorted(unknown)))
    pairs = []
    for key, mapping in (("enUS_frFR", data.get("enUS_frFR", {})), ("frFR_enUS", data.get("frFR_enUS", {}))):
        if not isinstance(mapping, dict):
            raise DataError("corrections manuelles : %s doit etre un objet" % key)
        for k, v in mapping.items():
            en, fr = (k, v) if key == "enUS_frFR" else (v, k)
            if not isinstance(en, str) or not isinstance(fr, str):
                raise DataError("corrections manuelles : %s : noms non textuels (%r, %r)" % (key, k, v))
            if not normalised(en) or not normalised(fr):
                raise DataError("corrections manuelles : %s : nom vide (%r, %r)" % (key, k, v))
            if en == fr:
                raise DataError("corrections manuelles : auto-boucle %r (enUS == frFR) : supprimer la ligne" % en)
            pairs.append((en, fr, key))
    by_en, by_fr, out = {}, {}, []
    for en, fr, key in pairs:
        if en in by_en and by_en[en] != fr:
            raise DataError("corrections manuelles : %r a deux corrections (%r et %r)" % (en, by_en[en], fr))
        if fr in by_fr and by_fr[fr] != en:
            raise DataError("corrections manuelles : %r a deux corrections (%r et %r)" % (fr, by_fr[fr], en))
        if en not in by_en:
            by_en[en] = fr
            by_fr[fr] = en
            out.append((en, fr))
    return out


def overrides_for(args):
    """Corrections a appliquer : --no-overrides, --overrides PATH, ou tools/overrides.json s'il existe."""
    if args.no_overrides:
        return [], None
    path = args.overrides
    if path is None:
        if not os.path.exists(OVERRIDES_DEFAULT):
            return [], None
        path = OVERRIDES_DEFAULT
    return load_overrides(path), path


def build(en_rows, fr_rows, overrides=()):
    """Construit les deux dictionnaires (regles : README, section 4).

    * Nom natif = nom identique dans les deux langues pour au moins un identifiant.
      Il est un candidat du sens direct, et il gagne les egalites (choose, prefer).
    * Sens direct : chaque nom source garde sa cible gagnante. Pas d'entree si la
      cible gagnante est le nom lui-meme (identite gagnante).
    * Sens inverse : pour une cible t qui n'est PAS un nom natif, la source gagnante
      est choisie parmi les seules sources dont la cible gagnante est t (effectifs
      reels). Ainsi toute entree directe vers t a une entree inverse.
    * Nom natif comme cible : aucune entree inverse (un client frFR qui voit ce nom
      n'a rien a traduire). Les sources qui y mènent sont listees (collision avec
      identite), et leur entree directe reste (une valeur peut etre une cle inverse
      absente, cf. data_spec et le champ native).
    * Une paire perdue n'est jamais supprimee par une garde : elle est perdue
      seulement parce que sa source a une autre cible gagnante, ou parce que
      l'identite gagne le nom natif. Chaque cas est listé au rapport.
    """
    pairs, stats = join(en_rows, fr_rows)
    by_src, by_tgt = {}, {}
    for i, s, t in pairs:
        by_src.setdefault(s, {}).setdefault(t, []).append(i)
        by_tgt.setdefault(t, {}).setdefault(s, []).append(i)

    identity = sorted({s for s in by_src if s in by_src[s]}, key=bkey)
    ident_set = set(identity)

    fwd_win, amb_fwd, zm_fwd = {}, [], []
    for s in sorted(by_src, key=bkey):
        chosen, ranked, dropped = choose(by_src[s], prefer=s)
        fwd_win[s] = chosen
        if len(by_src[s]) > 1:
            amb_fwd.append((s, ranked, chosen))
        if dropped:
            zm_fwd.append((s, chosen, dropped))

    fwd = {s: t for s, t in fwd_win.items() if t != s}
    # Corrections manuelles : gagnent sur tout (y compris l'identite et les noms natifs).
    ov_map = {en: fr for en, fr in overrides}
    ov_bwd = {fr: en for en, fr in overrides}
    for en, fr in overrides:
        fwd[en] = fr

    # Sens inverse : candidats = sources dont la cible gagnante est t (G17).
    # Une cible corrigee a son inverse fixe ; les autres sont recalculees sur les sources restantes.
    cand = {}
    for s, t in fwd.items():
        if t not in ov_bwd:
            cand.setdefault(t, {})[s] = sorted(by_src.get(s, {}).get(t, []))
    bwd, amb_bwd, zm_bwd = {}, [], []
    collisions_identity = []
    for t in sorted(cand, key=bkey):
        if t in ident_set:
            collisions_identity.append((t, sorted(by_src[t][t]),
                                        sorted(cand[t].items(), key=lambda kv: bkey(kv[0]))))
            continue
        chosen, ranked, dropped = choose(cand[t])
        bwd[t] = chosen
        if len(cand[t]) > 1:
            amb_bwd.append((t, ranked, chosen))
        if dropped:
            zm_bwd.append((t, chosen, dropped))
    for t, en in ov_bwd.items():
        bwd[t] = en

    def _ratio(c):
        comp = sum(len(ids) for _, ids in c[2])
        return comp / float(max(1, len(c[1])))

    collisions_identity.sort(key=lambda c: (-_ratio(c), bkey(c[0])))

    lost = []
    for s in sorted(by_src, key=bkey):
        for t in sorted(by_src[s], key=bkey):
            if fwd.get(s) == t:
                continue
            if s in ov_map:
                lost.append((s, t, sorted(by_src[s][t]), "remplacee par une correction manuelle"))
                continue
            if s == t and fwd_win[s] == s:
                continue  # identite gagnante : nom garde, pas une perte
            if s == t:
                why = "identite perdue : cible gagnante %s" % fwd_win[s]
            else:
                why = "sens direct : cible gagnante %s" % fwd_win[s]
            lost.append((s, t, sorted(by_src[s][t]), why))

    identity_status = {}
    for s in identity:
        identity_status[s] = {
            "ids": sorted(by_src[s][s]),
            "kept": fwd_win[s] == s,
        }

    origin_fwd = {"zone": 0, "carte": 0}
    for s, t in fwd.items():
        ids = by_src.get(s, {}).get(t, [])
        if not ids:
            continue  # correction manuelle : pas d'identifiant, hors decompte d'origine
        origin_fwd["zone" if any(origin_of(i) == ZONE for i in ids) else "carte"] += 1

    raw_diff = set()
    for rows in (en_rows, fr_rows):
        for name in rows.values():
            if name is not None and normalised(name) != name:
                raw_diff.add(name)

    stats["lost"] = len(lost)
    stats["lost_ids"] = sum(len(ids) for _, _, ids, _ in lost)
    return {
        "fwd": fwd,
        "bwd": bwd,
        "native": sorted((c[0] for c in collisions_identity), key=bkey),
        "ov_map": ov_map,
        "stats": stats,
        "amb_fwd": amb_fwd,
        "amb_bwd": amb_bwd,
        "zone_map_fwd": zm_fwd,
        "zone_map_bwd": zm_bwd,
        "identity": identity,
        "identity_status": identity_status,
        "collisions_identity": collisions_identity,
        "lost": lost,
        "origin_fwd": origin_fwd,
        "raw_diff": sorted(raw_diff, key=bkey),
        "en_rows": len(en_rows),
        "fr_rows": len(fr_rows),
        "en_empty": sum(1 for v in en_rows.values() if v is None),
        "fr_empty": sum(1 for v in fr_rows.values() if v is None),
    }


def collision_warnings(res, accepted=()):
    """Avertissement par collision avec identite forte (identifiants concurrents >= COLLISION_RATIO x identiques).

    Un nom passe par --accept-collision ne produit pas d'avertissement (decision humaine, consignee au rapport).
    """
    out = []
    for t, ident_ids, srcs in res["collisions_identity"]:
        if t in accepted:
            continue
        comp = sum(len(ids) for _, ids in srcs)
        if comp >= COLLISION_RATIO * max(1, len(ident_ids)):
            out.append("collision avec identite forte : nom natif %s (%d identifiant(s) identique(s)) contre %d "
                       "identifiant(s) vers d'autres cibles (sources : %s). Arbitrer avant --install."
                       % (t, len(ident_ids), comp, ", ".join(s for s, _ in srcs)))
    return out


def check_invariants(fwd, bwd, native=()):
    """Reprend les invariants de tests/specs/data_spec.lua (sans copier ses donnees).

    Exception, comme dans data_spec : une valeur du sens direct qui est un nom natif
    (liste native) n'a pas d'entree inverse. Partout ailleurs, l'inverse est exige.
    """
    native = set(native)
    problems = []
    for k, v in fwd.items():
        if v in native:
            continue
        r = bwd.get(v)
        if r is None:
            problems.append("%s[%s] absent de %s" % (TABLE_FWD, k, TABLE_BWD))
        elif fwd.get(r) != v:
            problems.append("collision %s : %s pointe vers %s qui n'y mene pas" % (v, TABLE_BWD, r))
    for v, k in bwd.items():
        if fwd.get(k) != v:
            problems.append("%s[%s] incoherent" % (TABLE_BWD, v))
        if v in native:
            problems.append("nom natif %s avec une entree inverse" % v)
    return problems


def lua_str(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def render_lua(table_name, mapping, header_lines, native_name, native):
    """Table principale, puis la liste des noms natifs (identiques dans les deux langues).

    La liste native n'est pas une entree de traduction : elle dit a data_spec quelles
    valeurs du sens direct n'ont pas d'entree inverse (README 4.4 et tests/README).
    """
    lines = ["-- " + h if h else "--" for h in header_lines]
    lines.append("")
    lines.append("local _, WT = ...")
    lines.append("WT.data = WT.data or {}")
    lines.append("WT.data.%s = {" % table_name)
    for k in sorted(mapping, key=bkey):
        lines.append("  [%s] = %s," % (lua_str(k), lua_str(mapping[k])))
    lines.append("}")
    lines.append("WT.data.%s = {" % native_name)
    for n in sorted(native, key=bkey):
        lines.append("  [%s] = %s," % (lua_str(n), lua_str(n)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def short_ids(ids, limit=5):
    """Cinq identifiants lisibles, puis '(+N)' (G26)."""
    head = ", ".join(fmt_id(i) for i in ids[:limit])
    return head + (" ... (+%d)" % (len(ids) - limit) if len(ids) > limit else "")


def fmt_id(ident):
    """Identifiant lisible : 'zone 14' ou 'carte 2000' (uiMapID retire du decalage)."""
    if origin_of(ident) == MAP:
        return "carte %d" % (ident - MAP_ID_OFFSET)
    return "zone %d" % ident


def md_cell(s):
    return s.replace("\\", "\\\\").replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def _pct(a, b):
    return "0 %" if not b else "%.1f %%" % (100.0 * a / b)


def _auto_label(value, is_identity):
    """Ce que l'automatique avait choisi : une cible, « identite (aucune entree) » ou « aucune »."""
    if value:
        return "`%s`" % md_cell(value)
    return "identite (aucune entree)" if is_identity else "aucune"


def render_report(res, meta):
    st = res["stats"]
    fwd, bwd = res["fwd"], res["bwd"]
    out = []
    out.append("# Rapport de couverture : dictionnaires de zones et de cartes (T1)")
    out.append("")
    out.append("Genere par `tools/build_zone_data.py`. Ne pas editer a la main.")
    out.append("")
    out.append("## Sources")
    out.append("")
    out.append("- Build : `%s`" % meta["build"])
    out.append("- Source : %s" % meta["source"])
    out.append("- enUS : %s" % meta["en_src"])
    out.append("- frFR : %s" % meta["fr_src"])
    out.append("")
    out.append("## Avertissements")
    out.append("")
    if meta["warnings"]:
        for w in meta["warnings"]:
            out.append("- %s" % md_cell(w))
    else:
        out.append("Aucun.")
    for name in meta.get("accepted", []):
        out.append("- Collision acceptee par l'utilisateur (--accept-collision) : `%s`" % md_cell(name))
    for note in meta.get("notes", []):
        out.append("- Note : %s" % md_cell(note))
    out.append("")
    out.append("## Couverture")
    out.append("")
    out.append("| Indicateur | Valeur |")
    out.append("|---|---|")
    out.append("| Lignes enUS (zones + cartes) | %d |" % res["en_rows"])
    out.append("| Lignes frFR (zones + cartes) | %d |" % res["fr_rows"])
    out.append("| Noms vides ignores (enUS / frFR) | %d / %d |" % (res["en_empty"], res["fr_empty"]))
    out.append("| Identifiants joints (paires) | %d |" % st["matched"])
    out.append("| Identifiants seulement enUS, zones / cartes (ignores) | %d / %d |"
               % (st["en_only_zone"], st["en_only_carte"]))
    out.append("| Identifiants seulement frFR, zones / cartes (ignores) | %d / %d |"
               % (st["fr_only_zone"], st["fr_only_carte"]))
    out.append("| Paires avec un nom vide (ignorees) | %d |" % st["empty_pair"])
    out.append("| Suffixes « (X) » retires (X = nom de l'autre langue, meme identifiant) | %d |"
               % len(res.get("stripped", [])))
    out.append("| Corrections manuelles (tools/overrides.json) | %d |" % len(res.get("overrides_info", [])))
    out.append("| Paires non retenues (voir la section Pertes) | %d (%d identifiants) |"
               % (st["lost"], st["lost_ids"]))
    out.append("| Noms natifs (identiques dans les deux langues) | %d |" % len(res["identity"]))
    strong = len([c for c in res["collisions_identity"]
                   if sum(len(i) for _, i in c[2]) >= COLLISION_RATIO * max(1, len(c[1]))])
    out.append("| Collisions avec identite (cible native, aucune entree inverse) | %d (dont %d fortes, rapport >= %d) |"
               % (len(res["collisions_identity"]), strong, COLLISION_RATIO))
    out.append("| Noms source gardes enUS -> frFR | %d |" % len(fwd))
    out.append("| Noms source gardes frFR -> enUS | %d |" % len(bwd))
    out.append("| Entrees enUS -> frFR par origine (zone / carte seule) | %d / %d |"
               % (res["origin_fwd"]["zone"], res["origin_fwd"]["carte"]))
    out.append("| Noms dont la forme brute differe de la forme normalisee | %d |" % len(res["raw_diff"]))
    out.append("| Seuil minimal par table (--min-entries) | %d |" % meta["min_entries"])
    ok = len(fwd) >= meta["min_entries"] and len(bwd) >= meta["min_entries"]
    out.append("| Seuil atteint | %s |" % ("oui" if ok else "**non**"))
    out.append("")
    out.append("## Regles appliquees")
    out.append("")
    out.append("- Zone prime sur carte : si un nom a une zone pour cible, les cartes ne comptent pas pour ce nom.")
    out.append("- Nom natif : une paire identique est un candidat comme les autres (effectifs) ; a egalite, le nom natif gagne.")
    out.append("- Chaque entree directe vers une cible non native a son entree inverse. Aucune entree inverse vers un nom natif.")
    out.append("- Sens inverse : effectifs reels (identifiants de chaque paire). Cles et valeurs brutes, sans nettoyage.")
    out.append("")
    out.append("## Corrections manuelles")
    out.append("")
    out.append("Corrections de tools/overrides.json : elles gagnent sur tout (automatique, identite, natif). "
               "Les colonnes « remplacee » montrent ce que l'automatique avait choisi.")
    out.append("")
    if not res.get("overrides_info"):
        out.append("Aucune.")
    else:
        out.append("| Nom enUS | Nom frFR | enUS dans les donnees | frFR dans les donnees | Entree enUS->frFR automatique remplacee | Entree frFR->enUS automatique remplacee |")
        out.append("|---|---|---|---|---|---|")
        for info in res["overrides_info"]:
            out.append("| `%s` | `%s` | %s | %s | %s | %s |" % (
                md_cell(info["en"]), md_cell(info["fr"]),
                "oui" if info["en_present"] else "non", "oui" if info["fr_present"] else "non",
                _auto_label(info["prev_fwd"], info["en"] in res["identity"]),
                _auto_label(info["prev_bwd"], info["fr"] in res["identity"])))
    out.append("")
    out.append("## Suffixes retires")
    out.append("")
    out.append("Nom « (X) » ramené au nom seul : X est le nom de l'autre langue pour le même identifiant. "
               "Relire : un retrait faux serait une traduction fausse.")
    out.append("")
    if not res.get("stripped"):
        out.append("Aucun.")
    else:
        out.append("| Identifiant | Langue | Nom brut | Nom retenu |")
        out.append("|---|---|---|---|")
        for ident, lang, raw, kept in res["stripped"]:
            out.append("| %s | %s | `%s` | `%s` |" % (fmt_id(ident), lang, md_cell(raw), md_cell(kept)))
    out.append("")
    out.append("## Pertes : paires non retenues")
    out.append("")
    out.append("Chaque ligne est une paire qui n'a pas d'entree, avec ses identifiants et la raison.")
    out.append("")
    if not res["lost"]:
        out.append("Aucune.")
    else:
        out.append("| Nom source | Cible | Identifiants (nombre) | Raison |")
        out.append("|---|---|---|---|")
        for s, t, ids, why in res["lost"]:
            shown = ", ".join(fmt_id(i) for i in ids[:20]) + (" ..." if len(ids) > 20 else "")
            out.append("| `%s` | `%s` | %d (%s) | %s |" % (md_cell(s), md_cell(t), len(ids), shown, md_cell(why)))
    out.append("")
    out.append("## Noms natifs (identiques dans les deux langues)")
    out.append("")
    collided = {c[0] for c in res["collisions_identity"]}
    if not res["identity"]:
        out.append("Aucun.")
    else:
        out.append("| Nom | Identifiants identiques | Statut |")
        out.append("|---|---|---|")
        for n in res["identity"]:
            info = res["identity_status"][n]
            statut = "garde sans traduction" if info["kept"] else "traduction ailleurs au sens direct (voir Pertes)"
            if n in collided:
                statut += " ; cible d'autres sources (voir Collisions avec identite)"
            out.append("| `%s` | %d (%s) | %s |" % (md_cell(n), len(info["ids"]),
                                                  ", ".join(fmt_id(i) for i in info["ids"][:20]), statut))
    out.append("")
    out.append("## Collisions avec identite")
    out.append("")
    out.append("Un nom natif (identique dans les deux langues) est cible d'une autre source. Il n'a pas d'entree inverse : "
               "un client frFR qui affiche ce nom ne le voit pas traduit. Les entrees directes restent. A relire avant --install.")
    out.append("")
    if not res["collisions_identity"]:
        out.append("Aucune.")
    else:
        out.append("Tri : rapport decroissant entre identifiants concurrents et identifiants identiques. "
                   "Le rapport >= %d est signale en avertissement." % COLLISION_RATIO)
        out.append("")
        out.append("| Nom natif | Identifiants identiques (n) | Identifiants concurrents (m) | m / n | Sources : identifiants |")
        out.append("|---|---|---|---|---|")
        for t, ident_ids, srcs in res["collisions_identity"]:
            comp = sum(len(ids) for _, ids in srcs)
            desc = " ; ".join("`%s` (%d : %s)" % (md_cell(s), len(ids), short_ids(ids))
                              for s, ids in srcs)
            name_cell = "`%s`" % md_cell(t)
            if t in meta.get("accepted", []):
                name_cell += " (accepte par l'utilisateur)"
            out.append("| %s | %d (%s) | %d | %.1f | %s |" % (
                name_cell, len(ident_ids), short_ids(ident_ids),
                comp, comp / float(max(1, len(ident_ids))), desc))
    out.append("")
    out.append("## Cas ambigus (sens enUS -> frFR)")
    out.append("")
    out.append("Un meme nom anglais correspond a plusieurs cibles. Colonnes : cible, identifiants retenus, plus petit identifiant, origine.")
    out.append("")
    _ambiguity_table(out, res["amb_fwd"], "Nom enUS", "Traduction")
    out.append("")
    out.append("## Collisions cibles (sens frFR -> enUS)")
    out.append("")
    out.append("Plusieurs noms source ont la meme cible. Memes regles, sur les effectifs reels.")
    out.append("")
    _ambiguity_table(out, res["amb_bwd"], "Nom frFR", "Nom enUS")
    out.append("")
    out.append("## Conflits zone contre carte")
    out.append("")
    out.append("Une cible de carte seule a ete ecartee au profit d'une zone (zone prime).")
    out.append("")
    conflicts = [("enUS -> frFR", r) for r in res["zone_map_fwd"]] + [("frFR -> enUS", r) for r in res["zone_map_bwd"]]
    if not conflicts:
        out.append("Aucun.")
    else:
        out.append("| Sens | Nom source | Retenue (zone) | Ecartees (carte seule) |")
        out.append("|---|---|---|---|")
        for sense, (name, chosen, dropped) in conflicts:
            out.append("| %s | `%s` | `%s` | %s |" % (sense, md_cell(name), md_cell(chosen),
                                                    " ; ".join("`%s`" % md_cell(d) for d in dropped)))
    out.append("")
    out.append("## Formes brutes differentes de la forme normalisee")
    out.append("")
    out.append("Ces noms gardent leurs espaces d'origine (aucune cle n'est modifiee). Liste limitee a 20.")
    out.append("")
    if not res["raw_diff"]:
        out.append("Aucun.")
    else:
        for name in res["raw_diff"][:20]:
            out.append("- `%s`" % md_cell(repr(name)))
    out.append("")
    return "\n".join(out) + "\n"


def _ambiguity_table(out, rows, src_label, tgt_label):
    if not rows:
        out.append("Aucun.")
        return
    out.append("| %s | %s (identifiants retenus, plus petit identifiant, origine) | Retenue | Variantes typographiques seulement |"
               % (src_label, tgt_label))
    out.append("|---|---|---|---|")
    for name, ranked, chosen in rows:
        desc = " ; ".join("`%s` (%d, %d, %s)" % (md_cell(t), n, m, origin) for t, n, m, origin in ranked)
        variant = "oui" if len({fold(t) for t, _, _, _ in ranked}) == 1 else "non"
        out.append("| `%s` | %s | `%s` | %s |" % (md_cell(name), desc, md_cell(chosen), variant))


def _fmt_time(value):
    if _is_int(value) and value > 0:
        return time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(value))
    return "date inconnue"


def render_outputs(res, meta):
    header = [
        FILE_FWD + "  --  " + GENERATED_MARK + ". Ne pas editer a la main.",
        "Source : collecte en jeu, " + meta["build"] + ", addon WoWTranslatorCollector (API C_Map).",
        "Collecte : enUS " + meta["collected_en"] + ", frFR " + meta["collected_fr"] + ".",
        "Commande : " + meta["command"],
        "Regles : voir tools/README.md, section 4.",
    ]
    fwd_text = render_lua(TABLE_FWD, res["fwd"], header, NATIVE_FWD, res["native"])
    bwd_header = list(header)
    bwd_header[0] = FILE_BWD + "  --  " + GENERATED_MARK + ". Ne pas editer a la main."
    bwd_text = render_lua(TABLE_BWD, res["bwd"], bwd_header, NATIVE_BWD, res["native"])
    return {FILE_FWD: fwd_text, FILE_BWD: bwd_text}


def write_atomic(pairs):
    """pairs : [(chemin, texte)]. Ecrit des temporaires, puis remplace. Rien n'est
    remplace si l'une des ecritures echoue."""
    staged = []
    try:
        for path, text in pairs:
            d = os.path.dirname(os.path.abspath(path))
            os.makedirs(d, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
            staged.append((tmp, path))
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        for tmp, path in staged:
            os.replace(tmp, path)
        staged = []
    finally:
        for tmp, _ in staged:
            try:
                os.remove(tmp)
            except OSError:
                pass


def is_generated(path, mark=GENERATED_MARK):
    """Vrai si le fichier n'existe pas, ou s'il porte la marque d'un fichier genere."""
    if not os.path.exists(path):
        return True
    with open(path, encoding="utf-8", errors="replace") as f:
        return mark in f.read(400)


def run(args, out_dir, report_path):
    path = args.from_savedvariables
    en_block, fr_block = load_collector_blocks(path)
    warnings = []
    check_pair(en_block, fr_block, args.allow_mismatch, warnings)
    en_rows, fr_rows, stripped = strip_english_suffixes(rows_of(en_block), rows_of(fr_block))
    overrides, ov_path = overrides_for(args)
    res_auto = build(en_rows, fr_rows)
    res = build(en_rows, fr_rows, overrides) if overrides else res_auto
    res["stripped"] = stripped
    notes = []
    en_vals = {v for v in en_rows.values() if v is not None}
    fr_vals = {v for v in fr_rows.values() if v is not None}
    ov_info = []
    for en, fr in overrides:
        info = {"en": en, "fr": fr, "en_present": en in en_vals, "fr_present": fr in fr_vals,
                "prev_fwd": res_auto["fwd"].get(en), "prev_bwd": res_auto["bwd"].get(fr)}
        ov_info.append(info)
        # Note et non avertissement : meme sous --strict (un nouveau nom peut etre absent des donnees)
        if not info["en_present"]:
            notes.append("correction manuelle : nom enUS absent des donnees collectees : %s (conservee)" % en)
        if not info["fr_present"]:
            notes.append("correction manuelle : nom frFR absent des donnees collectees : %s (conservee)" % fr)
    res["overrides_info"] = ov_info
    accepted = sorted(set(args.accept_collision or []), key=bkey)
    by_name = {c[0]: c for c in res["collisions_identity"]}
    for name in accepted:
        if name not in by_name:
            # G27 : faute de frappe ou nom inconnu : avertissement, erreur sous --strict
            warnings.append("--accept-collision %s : ce nom n'est pas une collision avec identite" % name)
            continue
        _, ident_ids, srcs = by_name[name]
        ratio = sum(len(ids) for _, ids in srcs) / float(max(1, len(ident_ids)))
        if ratio < COLLISION_RATIO:
            # G29 : acceptation sans effet, signalee (avertissement, meme sous --strict)
            note = ("acceptation sans effet pour %s : rapport %.1f < %d, aucun avertissement a lever"
                    % (name, ratio, COLLISION_RATIO))
            notes.append(note)
            print("AVERTISSEMENT : " + note, file=sys.stderr)
    warnings += collision_warnings(res, set(accepted))
    if args.strict and warnings:
        raise DataError("--strict : avertissements, arret avant toute ecriture :\n  " + "\n  ".join(warnings))
    for w in warnings:
        print("AVERTISSEMENT : " + w, file=sys.stderr)
    problems = check_invariants(res["fwd"], res["bwd"], res["native"])
    if problems:
        raise DataError("incoherence interne :\n  " + "\n  ".join(problems[:10]))

    if en_block["version"] == fr_block["version"] and en_block["build"] == fr_block["build"]:
        build_label = "%s.%s (toc %d)" % (en_block["version"], en_block["build"], en_block["toc"])
    else:
        build_label = "enUS %s.%s / frFR %s.%s" % (en_block["version"], en_block["build"],
                                                   fr_block["version"], fr_block["build"])
    name = os.path.basename(path)
    meta = {
        "build": build_label,
        "source": "addon WoWTranslatorCollector, API C_Map (GetAreaInfo, GetMapInfo)",
        "en_src": "`%s`, bloc enUS : %d zones (bornes 1..%d), %d cartes (bornes 1..%d), collecte %s"
        % (name, en_block["areasFound"], en_block["maxAreaId"], en_block["mapsFound"],
           en_block["maxMapId"], _fmt_time(en_block["collectedAt"])),
        "fr_src": "`%s`, bloc frFR : %d zones (bornes 1..%d), %d cartes (bornes 1..%d), collecte %s"
        % (name, fr_block["areasFound"], fr_block["maxAreaId"], fr_block["mapsFound"],
           fr_block["maxMapId"], _fmt_time(fr_block["collectedAt"])),
        "collected_en": _fmt_time(en_block["collectedAt"]),
        "collected_fr": _fmt_time(fr_block["collectedAt"]),
        "command": "python tools/build_zone_data.py --from-savedvariables %s" % name,
        "warnings": warnings,
        "min_entries": args.min_entries,
        "accepted": accepted,
        "notes": notes,
    }
    texts = render_outputs(res, meta)
    report_text = render_report(res, meta)

    if not is_generated(report_path, REPORT_MARK):
        raise DataError("%s existe et n'a pas ete genere par ce script : refus d'ecraser (utiliser un autre --report)"
                        % report_path)

    small = [n for n, t in ((TABLE_FWD, res["fwd"]), (TABLE_BWD, res["bwd"])) if len(t) < args.min_entries]
    if small:
        write_atomic([(report_path, report_text)])
        print("ECHEC : moins de %d entrees dans %s. Aucun fichier de donnees ecrit ; rapport : %s"
              % (args.min_entries, ", ".join(small), report_path), file=sys.stderr)
        return 2

    targets = [os.path.join(out_dir, FILE_FWD), os.path.join(out_dir, FILE_BWD)]
    for t in targets:
        if not is_generated(t):
            raise DataError("%s existe et n'a pas ete genere par ce script : refus d'ecraser" % t)
    # Ordre : donnees puis rapport. write_atomic remplace chaque fichier avec os.replace ;
    # les trois remplacements ne sont pas simultanes (voir tools/README.md, section 3).
    write_atomic([(targets[0], texts[FILE_FWD]), (targets[1], texts[FILE_BWD]),
                  (report_path, report_text)])
    print("Ecrit : %s (%d entrees)" % (targets[0], len(res["fwd"])))
    print("Ecrit : %s (%d entrees)" % (targets[1], len(res["bwd"])))
    print("Rapport : %s" % report_path)
    return 0


def build_parser():
    p = argparse.ArgumentParser(description="Genere les dictionnaires WoWTranslator depuis la collecte en jeu.")
    p.add_argument("--from-savedvariables", metavar="PATH",
                   help="fichier WoWTranslatorCollector.lua (SavedVariables du compte)")
    p.add_argument("--out-dir", default=None,
                   help="dossier de sortie (defaut : tools/out, ignore par git)")
    p.add_argument("--install", action="store_true",
                   help="ecrit dans WoWTranslator/Data (etape T3 seulement, incompatible avec --out-dir)")
    p.add_argument("--report", default=None,
                   help="rapport Markdown (defaut : tools/out/rapport_couverture.md)")
    p.add_argument("--min-entries", type=int, default=200,
                   help="nombre minimal d'entrees par table (defaut : 200, comme WT_MIN_ENTRIES)")
    p.add_argument("--strict", action="store_true",
                   help="traite tout avertissement comme une erreur (aucune ecriture)")
    p.add_argument("--accept-collision", action="append", default=[], metavar="NOM",
                   help="nom natif dont la collision avec identite est examinee et acceptee : leve l'avertissement "
                        "et --strict pour ce nom, et le consigne au rapport (repetable)")
    p.add_argument("--overrides", metavar="PATH", default=None,
                   help="fichier de corrections manuelles (defaut : tools/overrides.json s'il existe)")
    p.add_argument("--no-overrides", action="store_true",
                   help="n'applique aucune correction manuelle")
    p.add_argument("--allow-mismatch", action="store_true",
                   help="builds ou versions differents entre les blocs : avertissement au lieu d'erreur")
    p.add_argument("--selftest", action="store_true", help="lance l'autotest sur tools/fixtures/")
    return p


def main(argv=None):
    p = build_parser()
    args = p.parse_args(argv)
    if args.selftest:
        return selftest(os.path.abspath(__file__))
    if not args.from_savedvariables:
        p.error("--from-savedvariables PATH est requis (ou --selftest)")
    if args.install and args.out_dir:
        p.error("--install et --out-dir sont incompatibles")
    if args.overrides and args.no_overrides:
        p.error("--overrides et --no-overrides sont incompatibles")
    out_dir = INSTALL_DIR if args.install else (args.out_dir or STAGING_DIR)
    report_path = args.report or os.path.join(STAGING_DIR, REPORT_NAME)
    try:
        return run(args, out_dir, report_path)
    except DataError as e:
        print("ERREUR : " + str(e), file=sys.stderr)
        return 1


# ---------------------------------------------------------------------------
# Autotest
# ---------------------------------------------------------------------------

def selftest(script):
    import filecmp
    import shutil
    import subprocess
    import tempfile as tf

    failures = []

    def expect(cond, label):
        if not cond:
            failures.append(label)
            print("  KO  " + label)
        else:
            print("  ok  " + label)

    def gen(src, out, report, extra=()):
        cmd = [sys.executable, script, "--from-savedvariables", src, "--out-dir", out,
               "--report", report, "--no-overrides"] + list(extra)
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        return proc.returncode, proc.stderr.decode("utf-8", "replace")

    def read(path):
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()

    def read_bytes(path):
        with open(path, "rb") as f:
            return f.read()

    def entries(text):
        return re.findall(r'^  \[', text, re.M)

    tmp = tf.mkdtemp(prefix="wt_t1_")
    fix = os.path.join(FIXTURES, "WoWTranslatorCollector.lua")
    collector_fixture_dir = os.path.join(REPO_DIR, "tests", "fixtures", "collector")
    try:
        # --- Sortie de reference, deterministe -------------------------------------
        o1, o2 = os.path.join(tmp, "o1"), os.path.join(tmp, "o2")
        rc1, _ = gen(fix, o1, os.path.join(tmp, "r1.md"), ["--min-entries", "1"])
        rc2, _ = gen(fix, o2, os.path.join(tmp, "r2.md"), ["--min-entries", "1"])
        expect(rc1 == 0, "fixture au format reel : generation, code 0 (obtenu %d)" % rc1)
        expect(rc2 == 0, "relance : code 0")
        for name in (FILE_FWD, FILE_BWD):
            expect(read_bytes(os.path.join(o1, name)) == read_bytes(os.path.join(o2, name)),
                   "sortie deterministe : " + name)
        expect(read_bytes(os.path.join(tmp, "r1.md")) == read_bytes(os.path.join(tmp, "r2.md")),
               "rapport deterministe")
        expect(not [n for n in os.listdir(o1) if n.startswith(".tmp-")], "aucun fichier temporaire restant")

        fwd_full, bwd_full = read(os.path.join(o1, FILE_FWD)), read(os.path.join(o1, FILE_BWD))
        fwd = fwd_full.split("WT.data.native_enUS_frFR")[0]   # table de traduction seule
        bwd = bwd_full.split("WT.data.native_frFR_enUS")[0]
        rep = read(os.path.join(tmp, "r1.md"))
        expect("WT.data.enUS_frFR = {" in fwd and "WT.data.frFR_enUS = {" in bwd, "tables attendues")
        expect("local _, WT = ..." in fwd and "WT.data = WT.data or {}" in fwd, "en-tete Lua")
        expect("\r" not in fwd and not fwd.startswith("﻿"), "pas de BOM ni de CRLF en sortie")
        expect(len(entries(fwd)) == 12 and len(entries(bwd)) == 9,
               "12 / 9 entrees attendues (obtenu %d / %d)" % (len(entries(fwd)), len(entries(bwd))))
        expect('["Elwynn Forest"] = "Forêt d\'Elwynn",' in fwd, "zone et carte identiques : une entree")
        expect('["The Barrens"] = "Les Barrens",' in fwd, "ambiguite : la plus frequente")
        expect('["  Thousand    Needles "] = "Mille Pointes",' in fwd, "cle brute conservee (espaces d'origine)")
        expect('["Mille Pointes"] = "  Thousand    Needles ",' in bwd, "sens inverse : valeur brute")
        expect('["Shrine of the \\"Dawn\\""] = "Sanctuaire de l\'\\"Aube\\"",' in fwd, "guillemets echappes")
        expect('["Lake \\\\ Path"] = "Lac \\\\ Chemin",' in fwd, "antislash echappe")
        expect('["Ragefire"] = "Gouffre de Ragefeu",' in fwd, "deux noms enUS vers le meme frFR (les deux gardes)")
        expect('["Gouffre de Ragefeu"] = "Ragefire Chasm",' in bwd,
               "collision cible : plus d'identifiants, puis plus petit identifiant")
        expect('["Côte d\'Ouest"] = "Westfall Coast",' in bwd,
               "sens inverse : effectifs reels (3 identifiants contre 1)")
        expect('["Westfall Coast"] = "Côte d\'Ouest",' in fwd, "zone prime : Westfall Coast -> zone")
        expect("Côte de Ponant" not in fwd, "zone prime : la carte seule ne remplace pas la zone")
        expect('["Deadwind Pass"] = "Col de la Mort-Vent",' in fwd, "carte seule : entree (origine carte)")
        expect('["Col de la Mort-Vent"] = "Deadwind Pass",' in bwd, "carte seule : entree inverse")
        # Identite : candidat comme les autres (G13)
        expect('["Orgrimmar Gate"] = "Orgrimmar",' in fwd,
               "identite : Orgrimmar Gate -> Orgrimmar garde (2 identifiants contre 1 identique)")
        expect('["Orgrimmar"]' not in bwd,
               "identite : nom natif Orgrimmar sans entree inverse (un client frFR le garde)")
        expect('["Orgrimmar"]' not in fwd, "identite : Orgrimmar sans traduction dans le sens direct")
        expect('["Dun Morogh"]' not in fwd and '["Dun Morogh"]' not in bwd,
               "identite : Dun Morogh garde sans traduction")
        expect('["Azeroth"]' not in fwd and '["Azeroth"]' not in bwd, "identite : carte Azeroth gardee sans traduction")
        expect('["Unmatched Zone"]' not in fwd and '["Empty Pair Zone"]' not in fwd,
               "identifiant seulement enUS : ignore")
        expect("Zone Française Seule" not in fwd + bwd, "identifiant seulement frFR : ignore")
        expect("| Identifiants joints (paires) | 23 |" in rep, "rapport : 23 paires jointes")
        expect("| Noms natifs (identiques dans les deux langues) | 3 |" in rep, "rapport : 3 noms natifs")
        expect("| Collisions avec identite (cible native, aucune entree inverse) | 1 (dont 0 fortes, rapport >= 5) |" in rep,
               "rapport : 1 collision avec identite")
        expect("| `Orgrimmar` | 1 (zone 14) | 2 | 2.0 | `Orgrimmar Gate` (2 : zone 22, zone 23) |" in rep,
               "rapport : la source qui mene a un nom natif est listee")
        expect("| Paires non retenues (voir la section Pertes) | 2 (2 identifiants) |" in rep,
               "rapport : 2 paires perdues, 2 identifiants")
        expect("| `Westfall Coast` | `Côte de Ponant` | 1 (carte 2000) |" in rep,
               "rapport : perte listee avec son identifiant lisible")
        expect("| `The Barrens` | `Barrens` | 1 (zone 5) |" in rep, "rapport : perte d'une cible minoritaire")
        expect("## Conflits zone contre carte" in rep and "`Côte de Ponant`" in rep,
               "rapport : conflit zone contre carte liste")
        expect("| Entrees enUS -> frFR par origine (zone / carte seule) | 11 / 1 |" in rep,
               "rapport : origine des entrees (11 zone, 1 carte seule)")
        expect("| Identifiants seulement enUS, zones / cartes (ignores) | 2 / 0 |" in rep,
               "rapport : identifiants seulement enUS, ventiles zones / cartes")
        expect("- `'  Thousand    Needles '`" in rep, "rapport : forme brute signalee")
        expect("- Build : `1.60.1.71037 (toc 16001)`" in rep, "rapport : build version.build (toc)")

        # --- Liste native : noms identiques, jamais des entrees ------------------------
        native_part = fwd_full.split("WT.data.native_enUS_frFR")
        expect(len(native_part) == 2, "liste native presente dans le sens direct")
        expect('["Orgrimmar"] = "Orgrimmar",' in native_part[1], "liste native : Orgrimmar")
        expect('["Orgrimmar"]' not in native_part[0], "aucune entree d'identite dans les tables de traduction")
        expect('["Azeroth"]' not in native_part[1] and '["Dun Morogh"]' not in native_part[1],
               "G23 : noms identiques non exemptes absents de la liste native")
        expect('WT.data.native_frFR_enUS' in bwd_full, "liste native presente dans le sens inverse")

        # --- Unites : G17 (gagnant inverse parmi les sources gagnantes), G18 (identite) -
        g17 = build({1: "W", 10: "S1", 2: "W", 3: "W", 4: "W", 5: "W", 6: "W"},
                    {1: "T", 10: "T", 2: "T2", 3: "T2", 4: "T2", 5: "T2", 6: "T2"})
        expect(g17["fwd"] == {"W": "T2", "S1": "T"}, "G17 : S1 -> T garde (W -> T2 gagne pour W)")
        expect(g17["bwd"] == {"T2": "W", "T": "S1"}, "G17 : inverse T -> S1 et T2 -> W")
        g18 = build({1: "A", 2: "B"}, {1: "B", 2: "B"})
        expect(g18["fwd"] == {"A": "B"}, "G18 : A -> B garde")
        expect(g18["bwd"] == {}, "G18 : aucune entree inverse vers le nom natif B (pas de B -> A)")
        expect(g18["native"] == ["B"] and g18["collisions_identity"][0][0] == "B",
               "G18 : collision avec identite signalee")
        strong = build({1: "N", 2: "X", 3: "X", 4: "X", 5: "X", 6: "X", 7: "X"},
                       {1: "N", 2: "N", 3: "N", 4: "N", 5: "N", 6: "N", 7: "N"})
        expect(len(collision_warnings(strong)) == 1,
               "G20 : 6 identifiants concurrents contre 1 identique : avertissement (seuil 5)")
        weak = build({1: "N", 2: "X", 3: "X"}, {1: "N", 2: "N", 3: "N"})
        expect(collision_warnings(weak) == [], "G20 : 2 contre 1 : pas d'avertissement")
        expect(strong["collisions_identity"][0][1] == [1] and len(strong["collisions_identity"][0][2][0][1]) == 6,
               "G20 : effectifs des deux cotes disponibles")
        en_fx, fr_fx = load_collector_blocks(fix)
        res_fix = build(rows_of(en_fx), rows_of(fr_fx))
        # G23 : la liste native ne contient que les noms exemptes (valeurs d'une entree directe)
        expect(sorted(res_fix["native"]) == ["Orgrimmar"],
               "G23 : liste native = seul Orgrimmar (les autres noms identiques ne sont pas exemptes)")
        big_en = {i: "Tr %d" % i for i in range(1, 610)}
        big_fr = {i: "Ft %d" % i for i in range(1, 610)}
        for j in range(250):
            big_en[2000 + j] = "Ident %d" % j
            big_fr[2000 + j] = "Ident %d" % j
        big_en[5000] = "Collision"
        big_fr[5000] = "Ident 0"
        big = build(big_en, big_fr)
        expect(big["native"] == ["Ident 0"], "G23 : 609 traduits + 250 identiques : une seule exemption listee")
        expect(len(big["identity"]) == 250, "G23 : les 250 noms identiques restent au rapport")
        expect(check_invariants(big["fwd"], big["bwd"], big["native"]) == [],
               "G23 : invariants du jeu 609 + 250 respectes")
        # G26 : sources tronquees
        expect(short_ids(list(range(1, 9))) == "zone 1, zone 2, zone 3, zone 4, zone 5 ... (+3)",
               "G26 : cinq identifiants puis (+N)")
        # G25 : --accept-collision leve l'avertissement de cette collision
        strong_acc = build({1: "N", 2: "X", 3: "X", 4: "X", 5: "X", 6: "X", 7: "X"},
                           {1: "N", 2: "N", 3: "N", 4: "N", 5: "N", 6: "N", 7: "N"})
        expect(collision_warnings(strong_acc, {"N"}) == [], "G25 : nom accepte, pas d'avertissement")
        meta_acc = {"build": "x", "source": "s", "en_src": "e", "fr_src": "f", "warnings": [],
                    "min_entries": 1, "accepted": ["N"]}
        rep_acc = render_report(strong_acc, meta_acc)
        expect("Collision acceptee par l'utilisateur" in rep_acc and "| `N` (accepte par l'utilisateur) | 1 (zone 1) | 6 |" in rep_acc,
               "G25 : acceptation consignee au rapport (avertissements et tableau)")

        # G27 : nom accepte qui n'est pas une collision : erreur sous --strict, avertissement sinon
        out_g27 = os.path.join(tmp, "g27")
        rc, err = gen(fix, out_g27, os.path.join(tmp, "g27.md"),
                      ["--min-entries", "1", "--accept-collision", "Nope", "--strict"])
        expect(rc == 1 and not os.path.exists(os.path.join(out_g27, FILE_FWD)),
               "G27 : --strict et nom accepte inconnu : code 1, rien d'ecrit")
        rc, err = gen(fix, os.path.join(tmp, "g27b"), os.path.join(tmp, "g27b.md"),
                      ["--min-entries", "1", "--accept-collision", "Nope"])
        expect(rc == 0 and "n'est pas une collision" in err, "G27 : sans --strict, avertissement seul, code 0")
        # G29 : acceptation d'une collision sous le seuil : avertissement, meme sous --strict
        # (la fixture a un ecart de couverture : --strict n'est pas utilisable ici ; la note ne
        # rejoint jamais la liste des avertissements --strict, voir collision_warnings)
        rc, err = gen(fix, os.path.join(tmp, "g29"), os.path.join(tmp, "g29.md"),
                      ["--min-entries", "1", "--accept-collision", "Orgrimmar"])
        expect(rc == 0 and "acceptation sans effet" in err,
               "G29 : collision sous le seuil acceptee : avertissement, code 0")
        expect("acceptation sans effet pour Orgrimmar" in read(os.path.join(tmp, "g29.md")),
               "G29 : acceptation sans effet consignee au rapport")
        # Suffixe « (X) » : retire seulement si X est le nom de l'autre langue, meme identifiant
        e1, f1, st1 = strip_english_suffixes({1: "Badlands"}, {1: "Terres ingrates (Badlands)"})
        expect(f1[1] == "Terres ingrates" and e1[1] == "Badlands" and len(st1) == 1,
               "suffixe : « Terres ingrates (Badlands) » ramene a « Terres ingrates »")
        e2, f2, st2 = strip_english_suffixes({1: "Badlands"}, {1: "Terres (Westfall)"})
        expect(f2[1] == "Terres (Westfall)" and st2 == [], "suffixe : X different du nom anglais, pas de retrait")
        e3, f3, st3 = strip_english_suffixes({1: "Foo (Bar)"}, {1: "Foo (Bar)"})
        expect(e3[1] == "Foo (Bar)" and f3[1] == "Foo (Bar)" and st3 == [],
               "suffixe : parentheses legitimes (X = nom entier, pas l'autre langue) conservees")
        e4, f4, st4 = strip_english_suffixes({1: "Dun Morogh"}, {1: "Terres (du Nord) sud"})
        expect(f4[1] == "Terres (du Nord) sud" and st4 == [], "suffixe : parentheses au milieu du nom conservees")
        e5, f5, st5 = strip_english_suffixes({1: "Sombrivage (Darkshore)"}, {1: "Darkshore"})
        expect(e5[1] == "Sombrivage" and f5[1] == "Darkshore" and st5[0][1] == "enUS",
               "suffixe : symetrique, retrait cote enUS")
        e6, f6, st6 = strip_english_suffixes({1: "Badlands"}, {1: "Terres ingrates (Badlands )"})
        expect(f6[1] == "Terres ingrates", "suffixe : espaces normalises dans la comparaison")
        e7, f7, st7 = strip_english_suffixes({1: "Badlands", 2: "Autre"}, {1: "Terres ingrates (Badlands)", 2: "Autre"})
        expect(len(st7) == 1, "suffixe : un seul retrait pour une seule paire concernee")
        suf = build(*strip_english_suffixes({1: "Badlands", 2: "Ailleurs"},
                                            {1: "Terres ingrates (Badlands)", 2: "Autre"})[:2])
        expect(suf["fwd"].get("Badlands") == "Terres ingrates" and suf["bwd"].get("Terres ingrates") == "Badlands",
               "suffixe : Badlands -> Terres ingrates gagne dans les deux sens apres retrait")
        # Corrections manuelles (tools/overrides.json)
        ov_ok = os.path.join(tmp, "ov_ok.json")
        with open(ov_ok, "w", encoding="utf-8") as f:
            json.dump({"enUS_frFR": {"Thunder Bluff": "Pitons-du-Tonnerre"},
                       "frFR_enUS": {"Pitons-du-Tonnerre": "Thunder Bluff"}}, f)
        expect(load_overrides(ov_ok) == [("Thunder Bluff", "Pitons-du-Tonnerre")],
               "correction : les deux sens fusionnes en une seule paire")
        bad_cases = {
            "type": {"enUS_frFR": {"A": 3}},
            "vide": {"enUS_frFR": {"  ": "B"}},
            "auto": {"enUS_frFR": {"A": "A"}},
            "conflit": {"enUS_frFR": {"A": "B"}, "frFR_enUS": {"C": "A"}},
            "cle": {"autre": {}},
            "racine": [],
            "json": None,
        }
        for label, content in bad_cases.items():
            bad_path = os.path.join(tmp, "ov_bad_" + label + ".json")
            with open(bad_path, "w", encoding="utf-8") as f:
                if content is None:
                    f.write("{ pas du json")
                else:
                    json.dump(content, f)
            try:
                load_overrides(bad_path)
                expect(False, "correction refusee (%s)" % label)
            except DataError:
                expect(True, "correction refusee (%s) : erreur, code 1" % label)
        ovb = build({1: "Thunder Bluff", 2: "Other"}, {1: "Les Pitons", 2: "Autre"},
                    [("Thunder Bluff", "Pitons-du-Tonnerre")])
        expect(ovb["fwd"]["Thunder Bluff"] == "Pitons-du-Tonnerre"
               and ovb["bwd"]["Pitons-du-Tonnerre"] == "Thunder Bluff",
               "correction : sens direct et inverse")
        expect("Les Pitons" not in ovb["bwd"], "correction : l'inverse automatique remplace n'existe plus")
        expect(check_invariants(ovb["fwd"], ovb["bwd"], ovb["native"]) == [], "correction : invariants respectes")
        ovn = build({1: "A", 2: "Nat"}, {1: "B", 2: "Nat"}, [("A", "Nat")])
        expect(ovn["bwd"].get("Nat") == "A" and "Nat" not in ovn["native"],
               "correction : gagne sur le nom natif (le natif ne reste pas exempte)")
        expect(check_invariants(ovn["fwd"], ovn["bwd"], ovn["native"]) == [], "correction sur natif : invariants")
        # Bout en bout sur la fixture : une correction d'un nom present modifie les deux sens
        ov_elw = os.path.join(tmp, "ov_elw.json")
        with open(ov_elw, "w", encoding="utf-8") as f:
            json.dump({"enUS_frFR": {"Elwynn Forest": "Foret de l'Elwynn"}}, f)
        out_elw = os.path.join(tmp, "elw")
        proc = subprocess.run([sys.executable, script, "--from-savedvariables", fix, "--out-dir", out_elw,
                               "--report", os.path.join(tmp, "elw.md"), "--min-entries", "1",
                               "--overrides", ov_elw], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        ef = read(os.path.join(out_elw, FILE_FWD))
        eb = read(os.path.join(out_elw, FILE_BWD))
        expect(proc.returncode == 0 and '["Elwynn Forest"] = "Foret de l\'Elwynn",' in ef
               and "[\"Foret de l'Elwynn\"] = \"Elwynn Forest\"," in eb,
               "correction : sortie corrigee dans les deux sens")
        expect("[\"Foret d'Elwynn\"]" not in eb, "correction : l'inverse automatique n'est plus ecrit")
        # Nom absent des donnees : note, conservee, rc 0 meme sous --strict (fixture : pas de --strict)
        ov_ghost = os.path.join(tmp, "ov_ghost.json")
        with open(ov_ghost, "w", encoding="utf-8") as f:
            json.dump({"enUS_frFR": {"Pitons-fantome": "Pitons-du-Tonnerre"}}, f)
        rep_ghost = os.path.join(tmp, "ghost.md")
        proc = subprocess.run([sys.executable, script, "--from-savedvariables", fix,
                               "--out-dir", os.path.join(tmp, "ghost"), "--report", rep_ghost,
                               "--min-entries", "1", "--overrides", ov_ghost],
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        ghost_rep = read(rep_ghost)
        expect(proc.returncode == 0 and "absent des donnees collectees : Pitons-fantome" in ghost_rep
               and "| `Pitons-fantome` | `Pitons-du-Tonnerre` | non | non |" in ghost_rep,
               "correction : nom absent = note, rc 0, section « Corrections manuelles »")
        expect("--no-overrides" not in ghost_rep, "correction : rapport propre")
        g18b = build({1: "X", 2: "X"}, {1: "X", 2: "Y"})
        expect("X" not in g18b["fwd"], "G18 : a egalite d'effectifs, le nom natif gagne (aucune entree directe)")

        # --- Pont : sorties figees dans tests/fixtures/collector, lues par la suite Lua --
        for name in (FILE_FWD, FILE_BWD):
            ref = os.path.join(collector_fixture_dir, name)
            expect(os.path.isfile(ref), "pont : fixture Lua presente : " + name)
            if os.path.isfile(ref):
                expect(filecmp.cmp(os.path.join(o1, name), ref, shallow=False),
                       "pont : sortie identique a tests/fixtures/collector/" + name
                       + " (regenerer si le fixture change)")

        # --- Seuil : rapport seulement, aucun fichier de donnees -------------------------
        ts = os.path.join(tmp, "seuil")
        rc, _ = gen(fix, ts, os.path.join(ts, "r.md"), ["--min-entries", "9999"])
        expect(rc == 2, "seuil non atteint : code 2")
        expect(not os.path.exists(os.path.join(ts, FILE_FWD)) and not os.path.exists(os.path.join(ts, FILE_BWD)),
               "seuil non atteint : aucun fichier de donnees")
        expect(os.path.isfile(os.path.join(ts, "r.md")), "seuil non atteint : rapport ecrit")

        # --- Refus : code 1, aucun fichier -----------------------------------------------
        base = read(fix)

        def refused(label, text, extra=()):
            src = os.path.join(tmp, label + ".lua")
            with open(src, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            out = os.path.join(tmp, "out_" + label)
            rc, _ = gen(src, out, os.path.join(tmp, label + ".md"), ["--min-entries", "1"] + list(extra))
            expect(rc == 1 and not os.path.exists(os.path.join(out, FILE_FWD)),
                   "refuse (%s) : code 1, aucun fichier" % label)

        idx = base.index('["frFR"]')
        refused("incomplet", base.replace('["complete"]=true', '["complete"]=false'))
        refused("ancien_format", base.replace('["schema"]=2', '["schema"]=1'))
        refused("frFR_absent", base[:idx] + "}\r\n")
        refused("tronque", base[: len(base) // 2])
        refused("code_non_litteral", "WoWTranslatorCollectorDB = os.exit(3)\r\n")
        refused("zone_hors_bornes", base.replace('[14]="Orgrimmar"', '[99999]="Orgrimmar"', 1))
        refused("build_different", base[:idx] + base[idx:].replace('["build"]="71037"', '["build"]="71038"', 1))
        refused("compteur_faux", base.replace('["areasFound"]=20', '["areasFound"]=19', 1))

        mism = os.path.join(tmp, "mismatch.lua")
        with open(mism, "w", encoding="utf-8", newline="") as f:
            f.write(base[:idx] + base[idx:].replace('["build"]="71037"', '["build"]="71038"', 1))
        rc, _ = gen(mism, os.path.join(tmp, "mm2"), os.path.join(tmp, "mm2.md"), ["--min-entries", "1"])
        expect(rc == 1, "builds differents : refus, code 1")
        rc, err = gen(mism, os.path.join(tmp, "mm3"), os.path.join(tmp, "mm3.md"),
                      ["--min-entries", "1", "--allow-mismatch"])
        expect(rc == 0 and "build different" in err, "--allow-mismatch : code 0 et avertissement")

        # Ecart de couverture : avertissement, puis refus avec --strict
        cov = base[:idx] + base[idx:].replace('[16]="Côte d\'Ouest",\r\n', "", 1)
        cov = cov[:idx] + cov[idx:].replace('["areasFound"]=19', '["areasFound"]=18', 1)
        covf = os.path.join(tmp, "cov.lua")
        with open(covf, "w", encoding="utf-8", newline="") as f:
            f.write(cov)
        rc, err = gen(covf, os.path.join(tmp, "cov_ok"), os.path.join(tmp, "cov_ok.md"), ["--min-entries", "1"])
        expect(rc == 0 and "ecart de couverture" in err, "ecart de couverture : avertissement, code 0")
        rc, err = gen(covf, os.path.join(tmp, "cov_s"), os.path.join(tmp, "cov_s.md"),
                      ["--min-entries", "1", "--strict"])
        expect(rc == 1 and not os.path.exists(os.path.join(tmp, "cov_s", FILE_FWD)),
               "--strict : avertissement traite en erreur, code 1, aucun fichier")

        # Garde d'ecrasement des donnees et du rapport
        gd = os.path.join(tmp, "guard")
        os.makedirs(gd)
        with open(os.path.join(gd, FILE_FWD), "w", encoding="utf-8", newline="\n") as f:
            f.write("-- fichier perso\n")
        rc, _ = gen(fix, gd, os.path.join(tmp, "guard.md"), ["--min-entries", "1"])
        expect(rc == 1 and read(os.path.join(gd, FILE_FWD)) == "-- fichier perso\n",
               "garde : fichier de donnees non genere non ecrase (code 1)")
        precious = os.path.join(tmp, "precious.txt")
        with open(precious, "w", encoding="utf-8", newline="\n") as f:
            f.write("ne pas ecraser\n")
        rc, _ = gen(fix, os.path.join(tmp, "gr"), precious, ["--min-entries", "1"])
        expect(rc == 1 and read(precious) == "ne pas ecraser\n",
               "garde : rapport non genere non ecrase (code 1), aucun fichier")

        # --- Chemins par defaut, --install, garde d'installation (copie de tools/) -------
        def fresh_project(name):
            root = os.path.join(tmp, name)
            os.makedirs(os.path.join(root, "tools"))
            shutil.copy(script, os.path.join(root, "tools", "build_zone_data.py"))
            return root, [sys.executable, os.path.join(root, "tools", "build_zone_data.py"),
                          "--from-savedvariables", fix, "--min-entries", "1"]

        proj, cmd = fresh_project("proj")
        rc = subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        staging = os.path.join(proj, "tools", "out")
        expect(rc == 0 and os.path.isfile(os.path.join(staging, FILE_FWD))
               and os.path.isfile(os.path.join(staging, FILE_BWD))
               and os.path.isfile(os.path.join(staging, REPORT_NAME)),
               "chemin par defaut : tools/out/ contient les deux donnees et le rapport")
        expect(not os.path.exists(os.path.join(proj, "WoWTranslator")),
               "chemin par defaut : aucun WoWTranslator/ cree")
        rc = subprocess.call(cmd + ["--install"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        installed = os.path.join(proj, "WoWTranslator", "Data")
        expect(rc == 0 and os.path.isfile(os.path.join(installed, FILE_FWD))
               and os.path.isfile(os.path.join(installed, FILE_BWD)),
               "--install : donnees ecrites dans WoWTranslator/Data")

        proj2, cmd2 = fresh_project("proj2")
        os.makedirs(os.path.join(proj2, "WoWTranslator", "Data"))
        perso = os.path.join(proj2, "WoWTranslator", "Data", FILE_FWD)
        with open(perso, "w", encoding="utf-8", newline="\n") as f:
            f.write("-- fichier de l'oracle, ne pas ecraser\n")
        rc = subprocess.call(cmd2 + ["--install"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        expect(rc == 1 and read(perso) == "-- fichier de l'oracle, ne pas ecraser\n",
               "--install : fichier non genere refuse, code 1, inchange")
        expect(not os.path.exists(os.path.join(proj2, "WoWTranslator", "Data", FILE_BWD)),
               "--install refuse : le second fichier n'est pas ecrit")
        rc = subprocess.call(cmd2 + ["--install", "--out-dir", os.path.join(proj2, "x")],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        expect(rc == 2, "--install et --out-dir : refus (code 2 d'argparse)")

        # --- Analyseur : format reel, echappements, nombres, commentaires -------------
        top = parse_savedvariables(
            ('﻿X = {\r\n["a"]="\\195\\169t\\195\\169\\n",--c\r\n'
             'b={1,-2.5,1e3,0x10,true,false,nil},\r\nc=\'it\\\'s\',\r\n[3]="x";\r\n'
             '--[==[ long ]] commentaire ]==]\r\n}\r\nY="z"\r\n').encode("utf-8"), "mem")
        x = top.get("X", {})
        expect(x.get("a") == "été\n", "analyseur : echappements decimaux UTF-8 et \\n")
        expect(x.get("c") == "it's" and x.get(3) == "x" and top.get("Y") == "z", "analyseur : apostrophe, [n]=, ;")
        b = x.get("b", {})
        expect(b.get(2) == -2.5 and b.get(3) == 1000.0 and b.get(4) == 16 and b.get(5) is True and b.get(6) is False,
               "analyseur : nombres, hexa, booleens")
        expect(7 not in b and len(b) == 6, "analyseur : nil positionnel = absent")
        holes = parse_savedvariables(
            b'T = {\n["areas"] = {\n"Dun Morogh",\n"Longrivage",\nnil,\nnil,\n"Crique",\n},\n["k"] = nil,\n}\n',
            "mem").get("T", {})
        expect(holes.get("areas") == {1: "Dun Morogh", 2: "Longrivage", 5: "Crique"} and "k" not in holes,
               "analyseur : tableau a trous du client (nil) et [k] = nil ignores, index conserves")
        for bad in (b'X = os.exit(1)', b'X = "\\q"', b'X = {1 2}', b'X = [[long]]', b'X = 1..2',
                    b'X = ' + b'{' * 60 + b'}' * 60, b'X = "\xff"', b'X = ' + b'9' * 5000):
            try:
                parse_savedvariables(bad, "mem")
                expect(False, "analyseur : refuse %r" % bad[:24])
            except DataError:
                expect(True, "analyseur : refuse %r" % bad[:24])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    if failures:
        print("SELFTEST ECHEC : %d verification(s)" % len(failures))
        return 1
    print("SELFTEST OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
