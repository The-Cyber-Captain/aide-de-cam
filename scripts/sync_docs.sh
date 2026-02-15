#!/usr/bin/env bash
set -euo pipefail

declare -A TOPICS=(
  ["docs/README.md"]="README.md addons/aide_de_cam/docs/README.md"
  ["docs/THIRD_PARTY_NOTICES.md"]="THIRD_PARTY_NOTICES.md addons/aide_de_cam/THIRD_PARTY_NOTICES.md"
  ["LICENSE"]="addons/aide_de_cam/LICENSE"
  ["docs/CONTRIBUTING.md"]="CONTRIBUTING.md addons/aide_de_cam/docs/CONTRIBUTING.md"
  #["docs/CHANGELOG.md"]="CHANGELOG.md addons/aide_de_cam/docs/CHANGELOG.md"
)

# 1) Sync fixed-topic docs
for src in "${!TOPICS[@]}"; do
  [[ -f "$src" ]] || { echo "Missing source: $src" >&2; exit 1; }
  for dst in ${TOPICS[$src]}; do
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  done
done

# 2) Sync schema files (any version)
shopt -s nullglob
schema_sources=(docs/*camera-capabilities*.schema.json docs/*camera-capabilities*.schema.md)
shopt -u nullglob

if ((${#schema_sources[@]} == 0)); then
  echo "No schema files found under docs/ matching *camera-capabilities*.schema.(json|md)" >&2
  exit 1
fi

for src in "${schema_sources[@]}"; do
  [[ -f "$src" ]] || continue
  base="$(basename "$src")"

  case "$base" in
    *.schema.json)
      dsts=("addons/aide_de_cam/doc_classes/$base")
      ;;
    *.schema.md)
      dsts=("addons/aide_de_cam/docs/$base")
      ;;
    *)
      continue
      ;;
  esac

  for dst in "${dsts[@]}"; do
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  done
done

echo "Synced canonical docs:"
for src in "${!TOPICS[@]}"; do
  echo "  $src -> ${TOPICS[$src]}"
done
echo "Synced schema files:"
for src in "${schema_sources[@]}"; do
  echo "  $src -> addons/aide_de_cam/(doc_classes|docs)/$(basename "$src")"
done
