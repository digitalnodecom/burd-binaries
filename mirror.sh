#!/usr/bin/env bash
# Mirror a prebuilt upstream binary into the portable burd package layout
# (bin/<binary>) with a manifest, ready to publish alongside the bottle builds.
#
# Usage: ./mirror.sh <name> <arch>   (arch: arm64 | x86_64)
set -euo pipefail
NAME="${1:?usage: mirror.sh <name> <arch>}"
ARCH="${2:?usage: mirror.sh <name> <arch>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$DIR/mirrors/$NAME.json"
[ -f "$CFG" ] || { echo "no mirror config: $CFG" >&2; exit 1; }

version=$(jq -r .version "$CFG")
repo=$(jq -r .github_repo "$CFG")
asset=$(jq -r ".asset.\"$ARCH\"" "$CFG" | sed "s/{version}/$version/g")
main=$(jq -r .main_binary "$CFG")

out="$DIR/output/$NAME/$version-$ARCH"
rm -rf "$out"; mkdir -p "$out/bin"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "Fetching $repo $version ($asset)..."
curl -fsSL "https://github.com/$repo/releases/download/v$version/$asset" -o "$tmp/a.tgz"
tar -xzf "$tmp/a.tgz" -C "$tmp"

# Copy the wanted binaries (search the extracted tree; upstream layouts vary).
for b in $(jq -r '.binaries[]' "$CFG"); do
  src=$(find "$tmp" -type f -name "$b" -perm -u+x | head -1)
  [ -n "$src" ] || { echo "binary $b not found in $asset" >&2; exit 1; }
  cp "$src" "$out/bin/$b"; chmod +x "$out/bin/$b"
done

# Manifest with per-binary checksums.
{
  echo "{"
  echo "  \"name\": \"$NAME\", \"version\": \"$version\", \"source\": \"upstream\","
  echo "  \"source_repo\": \"$repo\", \"architecture\": \"$ARCH\","
  echo "  \"binaries\": {"
  first=1
  for b in $(jq -r '.binaries[]' "$CFG"); do
    sha=$(shasum -a 256 "$out/bin/$b" | cut -d' ' -f1)
    [ $first -eq 1 ] || echo ","
    first=0
    printf '    "%s": { "path": "bin/%s", "sha256": "%s" }' "$b" "$b" "$sha"
  done
  echo ""
  echo "  }"
  echo "}"
} > "$out/manifest.json"

echo "Mirrored $NAME $version ($ARCH) -> $out (main: $main)"
