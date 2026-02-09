#!/usr/bin/env bash
set -euo pipefail

SRC="docs/README.md"

targets=(
  "README.md"
  "addons/aide_de_cam/docs/README.md"
)

for t in "${targets[@]}"; do
  mkdir -p "$(dirname "$t")"
  cp "$SRC" "$t"
done

echo "Synced README to: ${targets[*]}"
