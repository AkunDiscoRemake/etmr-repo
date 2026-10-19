#!/usr/bin/env python3
"""Renderiza os avatares (Bacon Hair / Acorn Girl) em poses diferentes."""
import os, sys
from lupa import lua53
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
L = lua53.LuaRuntime(unpack_returned_tuples=True)
L.execute('package.path = "%s/scripts/?.lua;%s/tools/?.lua;" .. package.path' % (ROOT, ROOT))
L.execute(open(os.path.join(ROOT, "tools", "mock_emrapi.lua"), encoding="utf8").read())
L.execute("MOCK.installCS()")
L.execute("""
local AV = require("avatars"); local A = require("api"); local K = require("catalog"); local M = require("models")
local root = A.empty("g")
local poses = { {"bacon",1,"idle"}, {"acorn",7,"walk"}, {"bacon",2,"carry"}, {"acorn",5,"hold"}, {"bacon",4,"stun"} }
for i, p in ipairs(poses) do
  local av = AV.new({ kind = p[1], outfit = p[2], name = p[1]:upper(), parent = root })
  AV.place(av, { (i - 3) * 1.2, 0, 0 }, 180)
  for k = 1, 10 do AV.animate(av, 0.05, p[3], p[3] == "walk" and 3 or 0, nil) end
  if p[3] == "carry" then local inst = M.build(K.byId["tralalero"], av.carryPoint, "none") end
end
""")
open(sys.argv[1], "w").write(L.eval("MOCK.exportScene()"))
