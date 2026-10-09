#!/usr/bin/env bash
# Installs the PlantUML jar pinned in spec/plantuml/pin.json as `plantuml`.
# Refuses any jar whose sha256 differs from the pin. Needs Java and jq.
set -euo pipefail

pin="$(dirname "$0")/../spec/plantuml/pin.json"
url="$(jq -er .toolchain.plantuml_jar_url "$pin")"
sha="$(jq -er .toolchain.plantuml_jar_sha256 "$pin")"
jar="${PLANTUML_JAR:-/usr/local/lib/plantuml.jar}"
bin="${PLANTUML_BIN:-/usr/local/bin/plantuml}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl --fail --silent --show-error --location --retry 3 --output "$tmp" "$url"
echo "$sha  $tmp" | sha256sum --check --strict

sudo install -D -m 0644 "$tmp" "$jar"
printf '#!/bin/sh\nexec java -Djava.awt.headless=true -jar %s "$@"\n' "$jar" |
  sudo tee "$bin" > /dev/null
sudo chmod 0755 "$bin"
