#!/usr/bin/env python3
"""Non-regression de la suite elle-meme : reference + mutants.

    python tests/mutants/run_mutants.py            # tout
    python tests/mutants/run_mutants.py M1 N2      # seulement ces mutants
    python tests/mutants/run_mutants.py -v         # affiche les tests en echec

Pour chaque mutant (tests/mutants/patches/<ID>.patch) : copie de
tests/mutants/reference/WoWTranslator dans un dossier temporaire, application du
patch, puis `tests/run.lua --addon=<copie>`. Compare le statut attendu
(`# Expect: pass|fail`) au statut obtenu. Code de sortie 0 si tout est conforme.

Interpreteur : `lua5.1` ou `luajit` s'ils sont dans le PATH, sinon
tests/tools/luarun.py (DLL Lua 5.1 existante, voir --dll / WT_LUA_DLL).

Format d'un patch :
    # Description: ...
    # Expect: pass|fail
    @@ edit <fichier relatif>       remplacement exact (une occurrence exigee)
    <<<<
    texte cherche
    ====
    texte de remplacement
    >>>>
    @@ replace-file <fichier>       le contenu qui suit remplace le fichier
    @@ append <fichier>             le contenu qui suit est ajoute a la fin
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
REFERENCE = os.path.join(HERE, "reference", "WoWTranslator")
PATCHES = os.path.join(HERE, "patches")
RUN_LUA = os.path.join(ROOT, "tests", "run.lua")
LUARUN = os.path.join(ROOT, "tests", "tools", "luarun.py")
RESULT_RE = re.compile(r"Resultat : (\d+) ok, (\d+) echec\(s\), (\d+) ignore")

ORACLE_RE = re.compile(r"Mode --oracle : (\d+) echec")

# Garde-fous : la suite REFUSE l'oracle lui-meme comme addon (tests marques
# T.oracleGuard : marqueurs de la reference, WoWTranslator._ref, donnees
# synthetiques "Zone N"). run.lua est donc toujours lance avec --oracle :
# ces tests y deviennent des echecs attendus (xfail) ; s'ils passaient,
# run.lua les compterait comme echecs. Reference conforme = 0 echec reel et
# au moins un xfail. Un mutant est juge sur ses echecs reels.


def interpreter():
    for exe in ("lua5.1", "luajit"):
        path = shutil.which(exe)
        if path:
            return [path]
    return [sys.executable, LUARUN]


def run_suite(addon_dir):
    cmd = interpreter() + [RUN_LUA, "--oracle", "--addon=" + addon_dir.replace("\\", "/")]
    p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    m = RESULT_RE.search(out)
    counts = tuple(int(x) for x in m.groups()) if m else None
    fails = [l.strip()[6:] for l in out.splitlines() if l.startswith("  FAIL  ")]
    mo = ORACLE_RE.search(out)
    xfails = [l.strip()[6:] for l in out.splitlines() if l.startswith("  xfail ")]
    return p.returncode, counts, fails, out, (int(mo.group(1)) if mo else 0), xfails


def parse_patch(path):
    meta, ops, cur = {}, [], None
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for line in lines:
        if cur is None and line.startswith("# "):
            k, _, v = line[2:].partition(":")
            meta[k.strip().lower()] = v.strip()
        elif line.startswith("@@ "):
            op, _, target = line[3:].partition(" ")
            cur = {"op": op, "file": target.strip(), "lines": []}
            ops.append(cur)
        elif cur is not None:
            cur["lines"].append(line)
    for o in ops:
        body = "\n".join(o["lines"])
        if o["op"] == "edit":
            m = re.match(r"^<<<<\n(.*?)\n?====\n(.*?)\n?>>>>\s*$", body, re.S)
            if not m:
                raise ValueError("%s : bloc edit mal forme pour %s" % (path, o["file"]))
            o["find"], o["replace"] = m.group(1), m.group(2)
        else:
            o["content"] = body.rstrip("\n") + "\n"
    return meta, ops


def apply_patch(addon_dir, ops, name):
    for o in ops:
        target = os.path.join(addon_dir, o["file"])
        if o["op"] == "replace-file":
            with open(target, "w", encoding="utf-8", newline="\n") as f:
                f.write(o["content"])
            continue
        with open(target, encoding="utf-8") as f:
            src = f.read()
        if o["op"] == "append":
            src = src.rstrip("\n") + "\n" + o["content"]
        elif o["op"] == "edit":
            n = src.count(o["find"])
            if n != 1:
                raise ValueError("%s : texte cherche trouve %d fois dans %s" % (name, n, o["file"]))
            src = src.replace(o["find"], o["replace"])
        else:
            raise ValueError("%s : operation inconnue %s" % (name, o["op"]))
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(src)


def main(argv):
    verbose = "-v" in argv
    wanted = [a for a in argv if not a.startswith("-")]
    ok_all = True
    print("Reference : %s" % os.path.relpath(REFERENCE, ROOT))
    rc, counts, fails, out, nxfail, xfails = run_suite(REFERENCE)
    ref_ok = counts is not None and rc == 0 and counts[1] == 0 and nxfail >= 1
    print("  reference (--oracle) : %s, %d echec(s) attendu(s) (garde-fous) -> %s"
          % ("%d ok, %d echec(s) reel(s)" % counts[:2] if counts else "resultat illisible",
             nxfail, "conforme" if ref_ok else "NON CONFORME"))
    for f in xfails:
        print("      xfail : " + f)
    if not ref_ok:
        ok_all = False
        for f in fails:
            print("      echec inattendu : " + f)
    print("")
    print("%-6s %-8s %-8s %-14s %s" % ("id", "attendu", "obtenu", "echecs/total", "description"))
    for fname in sorted(os.listdir(PATCHES)):
        if not fname.endswith(".patch"):
            continue
        mid = fname[:-6]
        if wanted and mid not in wanted:
            continue
        meta, ops = parse_patch(os.path.join(PATCHES, fname))
        expect = meta.get("expect", "fail")
        tmp = tempfile.mkdtemp(prefix="wt_mutant_")
        try:
            addon = os.path.join(tmp, "WoWTranslator")
            shutil.copytree(REFERENCE, addon)
            apply_patch(addon, ops, mid)
            rc, counts, fails, out, nxfail, _ = run_suite(addon)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if counts is None:
            got, detail = "ERREUR", "resultat illisible"
        else:
            got = "pass" if counts[1] == 0 else "fail"
            detail = "%d/%d" % (counts[1], counts[0] + counts[1] + nxfail)
        good = got == expect
        ok_all = ok_all and good
        print("%-6s %-8s %-8s %-14s %s%s" % (mid, expect, got, detail, meta.get("description", ""),
                                             "" if good else "   <== NON CONFORME"))
        if verbose or not good:
            for f in fails[:8]:
                print("         - " + f)
    print("")
    print("Tout est conforme." if ok_all else "NON CONFORME : voir ci-dessus.")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
