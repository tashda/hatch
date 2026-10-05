#!/bin/sh
# Writes an Icon Composer file (decision AI4) from the drawings in StageIcon.swift: two full-bleed layers, the light
# colouring and the dark one, each shown in its own appearance. macOS masks the artwork and renders every size from it.
#
#   tools/make-icon-file.sh STAGE_BINARY KIND OUT.icon        KIND: hatch, stage or designer
set -e
BIN="$1"; KIND="$2"; OUT="$3"
rm -rf "$OUT"; mkdir -p "$OUT/Assets"
"$BIN" --render-icon "$OUT/Assets/light.png" --"$KIND" --full
"$BIN" --render-icon "$OUT/Assets/dark.png" --"$KIND" --full --dark
cat > "$OUT/icon.json" <<JSON
{
  "fill" : "automatic",
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "hidden-specializations" : [
            { "value" : true },
            { "appearance" : "dark", "value" : false }
          ],
          "image-name" : "dark.png",
          "name" : "dark"
        },
        {
          "glass" : false,
          "hidden-specializations" : [
            { "appearance" : "dark", "value" : true }
          ],
          "image-name" : "light.png",
          "name" : "light"
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON
