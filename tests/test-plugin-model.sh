#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
node <<NODE
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT;
const code = fs.readFileSync(path.join(root, "Model.js"), "utf8");
eval(code);
function assertEq(name, exp, act) {
  if (String(exp) !== String(act)) {
    console.error("FAIL:", name, "expected", JSON.stringify(exp), "got", JSON.stringify(act));
    process.exit(1);
  }
  console.log("PASS:", name);
}
assertEq("levelLabel 0", "Off", levelLabel(0, 3));
assertEq("levelLabel 1 max3", "Low", levelLabel(1, 3));
assertEq("levelLabel 2 max3", "Med", levelLabel(2, 3));
assertEq("levelLabel 3 max3", "High", levelLabel(3, 3));
assertEq("levelLabel 2 max5", "Level 2", levelLabel(2, 5));
assertEq("clamp", 0, clampLevel(-1, 3));
assertEq("clamp hi", 3, clampLevel(9, 3));
assertEq("auto paused", true, isAutoPausedFromStatus("state: MANUAL_PAUSE\\nmanual_until: 9999999999\\n"));
assertEq("auto active", false, isAutoPausedFromStatus("state: ACTIVE_AUTO\\nmanual_until: 0\\n"));
assertEq("segments max3", 3, segmentCount(3));
assertEq("segments max10", 4, segmentCount(10));
assertEq("restore", 2, restoreOnLevel(0, 2, 3));
assertEq("restore empty last", 3, restoreOnLevel(0, 0, 3));
console.log("all ok");
NODE
