#!/usr/bin/env bash
set -euo pipefail

# One canonical file per topic (source) -> one or more destination copies
declare -A TOPICS=(
  ["docs/README.md"]="README.md addons/aide_de_cam/docs/README.md"
  ["docs/THIRD_PARTY_NOTICES.md"]="THIRD_PARTY_NOTICES.md addons/aide_de_cam/THIRD_PARTY_NOTICES.md"
  ["LICENSE"]="addons/aide_de_cam/LICENSE"
  ["docs/CONTRIBUTING.md"]="CONTRIBUTING.md addons/aide_de_cam/docs/CONTRIBUTING.md"
  #["docs/CHANGELOG.md"]="CHANGELOG.md addons/aide_de_cam/docs/CHANGELOG.md"
)

for src in "${!TOPICS[@]}"; do
  # sanity
  [[ -f "$src" ]] || { echo "Missing source: $src" >&2; exit 1; }

  for dst in ${TOPICS[$src]}; do
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  done
done

echo "Synced canonical docs:"
for src in "${!TOPICS[@]}"; do
  echo "  $src -> ${TOPICS[$src]}"
done
