#!/usr/bin/env python3
"""Gera a versao HTML (arquivo unico) dos jogos do EnJoyTheMR.

Uso:
  python3 web/build.py                 # os 3 jogos
  python3 web/build.py brainrot        # so um

Cada jogo vira web/dist/<Nome>.html com TUDO dentro: three.js, cannon-es, wasmoon
(Lua 5.4 em WebAssembly), SDK do Photon, o runtime EMRAPI, os scripts Lua do jogo
(sem nenhuma alteracao), texturas e sons. Abre direto no navegador (ate offline;
o online do Brainrot precisa de internet).
"""
import base64
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..")
RT = os.path.join(HERE, "runtime")
LIBS = os.path.join(HERE, "libs")
DIST = os.path.join(HERE, "dist")

GAMES = {
    "bonelab": {
        "dir": "bonelab_remake", "out": "BonelabRemake.html", "virtualHands": True,
        "subtitle": "Fan remake do BONELAB · armas, bots, física, mãos articuladas",
    },
    "superhot": {
        "dir": "superhot_remake", "out": "SuperhotRemake.html", "virtualHands": True,
        "subtitle": "O tempo só anda quando você se move",
    },
    "brainrot": {
        "dir": "brainrot_remake", "out": "StealABrainrotVR.html", "virtualHands": False,
        "subtitle": "Steal a Brainrot · online (Photon) · até 8 jogadores",
    },
}

RUNTIME_JS = ["engine.js", "input.js", "audio_storage.js", "ui3d.js", "physics.js", "net.js"]


def read(p, mode="r"):
    with open(p, mode, encoding=None if "b" in mode else "utf8") as f:
        return f.read()


def js_safe(src):
    # nunca deixar "</script" dentro de um <script>
    return src.replace("</script", "<\\/script").replace("<!--", "<\\!--")


def build(key):
    cfg = GAMES[key]
    gdir = os.path.join(REPO, cfg["dir"])
    app = json.loads(read(os.path.join(gdir, "app.json")))
    scripts = {}
    for name in sorted(os.listdir(os.path.join(gdir, "scripts"))):
        if name.endswith(".lua"):
            scripts["scripts/" + name] = read(os.path.join(gdir, "scripts", name))
    assets = {}
    for sub in ("images", "sounds"):
        base = os.path.join(gdir, sub)
        for root, dirs, files in os.walk(base):
            dirs.sort()
            for f in sorted(files):
                if f.startswith("_"):
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, gdir).replace(os.sep, "/")
                assets[rel] = base64.b64encode(read(full, "rb")).decode("ascii")
    data = {
        "app": {
            "id": app.get("id"), "name": app.get("name"), "version": app.get("version"),
            "entry": app.get("entry", "scripts/main.lua"), "permissions": app.get("permissions", []),
            "photonAppId": app.get("photonAppId", ""), "photonRegion": app.get("photonRegion", "eu"),
        },
        "web": {"virtualHands": cfg["virtualHands"]},
        "scripts": scripts,
        "core": read(os.path.join(RT, "emr_core.lua")),
        "assets": assets,
        "wasm": base64.b64encode(read(os.path.join(LIBS, "wasmoon-glue.wasm"), "rb")).decode("ascii"),
    }
    data_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")

    libs = [
        "<script>" + js_safe(read(os.path.join(LIBS, "three.r160.min.js"))) + "</script>",
        "<script>" + js_safe(read(os.path.join(LIBS, "wasmoon.js"))) + "</script>",
        '<script type="text/plain" id="lib-cannon">' + js_safe(read(os.path.join(LIBS, "cannon-es.js"))) + "</script>",
    ]
    if "multiplayer" in data["app"]["permissions"]:
        libs.append("<script>" + js_safe(read(os.path.join(LIBS, "photon-realtime.browser.js"))) + "</script>")
    runtime = "\n".join("<script>" + js_safe(read(os.path.join(RT, f))) + "</script>" for f in RUNTIME_JS)

    icon = base64.b64encode(read(os.path.join(gdir, "icon.png"), "rb")).decode("ascii")
    html = read(os.path.join(RT, "shell.html"))
    html = html.replace("{{TITLE}}", app.get("name", key)).replace("{{SUBTITLE}}", cfg["subtitle"]).replace("{{ICON}}", icon)
    html = html.replace("<!--LIBS-->", "\n".join(libs))
    html = html.replace("<!--RUNTIME-->", runtime)
    html = html.replace("<!--DATA-->", '<script type="application/json" id="emr-data">' + data_json + "</script>")
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, cfg["out"])
    with open(out, "w", encoding="utf8") as f:
        f.write(html)
    print("ok %-28s %6.1f MB  (%d scripts, %d assets)" % (cfg["out"], os.path.getsize(out) / 1e6, len(scripts), len(assets)))
    return out


def main():
    keys = sys.argv[1:] or list(GAMES)
    for k in keys:
        build(k)


if __name__ == "__main__":
    main()
