#!/usr/bin/env python3
"""Monta todos os brainrots numa grade (mock) e exporta a cena para render."""
import os, sys
from lupa import lua53
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
L = lua53.LuaRuntime(unpack_returned_tuples=True)
L.execute('package.path = "%s/scripts/?.lua;%s/tools/?.lua;" .. package.path' % (ROOT, ROOT))
L.execute(open(os.path.join(ROOT, "tools", "mock_emrapi.lua"), encoding="utf8").read())
L.execute("MOCK.installCS()")
mut = sys.argv[2] if len(sys.argv) > 2 else "none"
rar = sys.argv[3] if len(sys.argv) > 3 else ""
L.execute("""
local K = require("catalog"); local M = require("models"); local A = require("api")
local root = A.empty("g")
local i = 0
for _, d in ipairs(K.list) do
  if "%s" == "" or d.rarity == "%s" then
    local inst = M.build(d, root, "%s")
    local cols = 5
    A.posXYZ(inst.root, (i %% cols) * 1.25 - 2.5, 0, math.floor(i / cols) * 1.6)
    A.rot(inst.root, 0, 180, 0)
    i = i + 1
  end
end
""" % (rar, rar, mut))
open(sys.argv[1], "w").write(L.eval("MOCK.exportScene()"))
print("ok", L.eval("MOCK.countObjects()"))
