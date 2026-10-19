#!/usr/bin/env python3
"""Empacota o jogo como .emrd (ZIP sem criptografia, app.json na raiz).

Uso: python3 tools/build_emrd.py
Saida: dist/StealABrainrotVR.emrd

Para instalar: copie o .emrd para o celular e abra com o EnJoyTheMR
(Arquivos / "Compartilhar" -> EnJoyTheMR). O app mostra o dialogo de instalacao.
"""
import json
import os
import zipfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIST = os.path.join(ROOT, "dist")
INCLUDE_DIRS = ["scripts", "sounds", "images"]
EXTRA = ["app.json", "icon.png"]


def main():
    man = json.load(open(os.path.join(ROOT, "app.json"), encoding="utf8"))
    for k in ("id", "name", "entry"):
        assert man.get(k), "app.json sem " + k
    assert os.path.isfile(os.path.join(ROOT, man["entry"])), "entry nao existe"
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, "StealABrainrotVR.emrd")
    files = []
    for f in EXTRA:
        if os.path.isfile(os.path.join(ROOT, f)):
            files.append(f)
    for d in INCLUDE_DIRS:
        for name in sorted(os.listdir(os.path.join(ROOT, d))):
            files.append(d + "/" + name)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in files:
            info = zipfile.ZipInfo(f, date_time=(2026, 10, 19, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, open(os.path.join(ROOT, f), "rb").read())
    print("ok", out, "%.2f MB" % (os.path.getsize(out) / 1e6), len(files), "arquivos")


if __name__ == "__main__":
    main()
