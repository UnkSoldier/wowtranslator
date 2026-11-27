#!/usr/bin/env python3
"""Lance un script Lua 5.1 via une DLL Lua 5.1 / LuaJIT existante (ctypes).

Sert quand aucun interpreteur `lua5.1` / `luajit` n'est installe, mais qu'une
DLL compatible est presente (ex. le LuaJIT fourni avec OBS Studio). Rien n'est
telecharge ni installe.

Usage :
    python tests/tools/luarun.py [--dll CHEMIN] tests/run.lua [args...]

Choix de la DLL, dans l'ordre :
    1. --dll CHEMIN
    2. variable d'environnement WT_LUA_DLL
    3. emplacements connus (voir CANDIDATES)

Code de sortie : celui du script (os.exit), 3 si erreur Lua non rattrapee,
4 si aucune DLL n'est trouvee.

Attention : LuaJIT accepte des constructions refusees par le Lua 5.1 du jeu
(goto, \\x, \\u{}, 1LL...). La spec `structure` les signale (lint Lua 5.1).
"""
import ctypes
import os
import sys

CANDIDATES = [
    r"D:\obs-studio\bin\64bit\lua51.dll",
    r"C:\Program Files\obs-studio\bin\64bit\lua51.dll",
    r"C:\Program Files (x86)\obs-studio\bin\64bit\lua51.dll",
]


def find_dll(argv):
    if len(argv) >= 2 and argv[0] == "--dll":
        return argv[1], argv[2:]
    env = os.environ.get("WT_LUA_DLL")
    if env:
        return env, argv
    for c in CANDIDATES:
        if os.path.isfile(c):
            return c, argv
    return None, argv


def lua_long_string(s):
    level = "=" * 3
    while ("]" + level + "]") in s:
        level += "="
    return "[" + level + "[" + s + "]" + level + "]"


def main():
    dll_path, rest = find_dll(sys.argv[1:])
    if not dll_path or not os.path.isfile(dll_path):
        sys.stderr.write("luarun: aucune DLL Lua 5.1 trouvee (--dll CHEMIN ou WT_LUA_DLL)\n")
        return 4
    if not rest:
        sys.stderr.write(__doc__)
        return 4
    dll = ctypes.CDLL(dll_path)
    dll.luaL_newstate.restype = ctypes.c_void_p
    dll.luaL_openlibs.argtypes = [ctypes.c_void_p]
    dll.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    dll.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    dll.lua_tolstring.restype = ctypes.c_char_p
    L = dll.luaL_newstate()
    dll.luaL_openlibs(L)
    script, args = rest[0], rest[1:]
    arg_items = "".join(", " + lua_long_string(a) for a in args)
    code = ("io.stdout:setvbuf('no') arg = {[0]=" + lua_long_string(script) + arg_items + "} "
            "return dofile(arg[0])")
    if dll.luaL_loadstring(L, code.encode("utf-8")) != 0 or dll.lua_pcall(L, 0, 0, 0) != 0:
        msg = dll.lua_tolstring(L, -1, None)
        sys.stderr.write("luarun: erreur Lua : %s\n" % (msg.decode("utf-8", "replace") if msg else "?"))
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
