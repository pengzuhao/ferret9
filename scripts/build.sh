#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/bin}"
mkdir -p "$OUT"
SDK="$(xcrun --show-sdk-path)"
CORE=(Sources/CofferCore/*.swift)
FLAGS=(-O -target arm64-apple-macosx14.0 -sdk "$SDK" -framework Security -framework Foundation)
swiftc "${FLAGS[@]}" "${CORE[@]}" Sources/CofferService/main.swift -o "$OUT/ferret9-service"
swiftc "${FLAGS[@]}" "${CORE[@]}" Sources/CofferCLI/main.swift -o "$OUT/ferret9-cli"
swiftc "${FLAGS[@]}" -framework AppKit "${CORE[@]}" Sources/CofferApp/main.swift -o "$OUT/Ferret9"
swiftc -g -target arm64-apple-macosx14.0 -sdk "$SDK" -framework Security -framework Foundation \
    "${CORE[@]}" Tests/CofferCoreTests/main.swift -o "$OUT/ferret9-tests"
echo "$OUT"
