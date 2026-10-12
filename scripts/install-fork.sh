#!/usr/bin/env bash
set -euo pipefail

IDENTITY="Reframed Local Signing"
KEYCHAIN="$HOME/Library/Keychains/reframed-signing.keychain-db"
REPO="${REPO:-hwong103/Reframed}"
BRANCH="${BRANCH:-feat/rename-blur-and-export-naming}"
TARGET="/Applications/Reframed.app"
BACKUP_DIR="$HOME/Library/Application Support/Reframed-Fork"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
  echo "signing identity '$IDENTITY' not found; run scripts/setup-signing-identity.sh" >&2
  exit 1
fi

SOURCE_APP="${1:-}"
if [ -z "$SOURCE_APP" ]; then
  WORK="$(mktemp -d)"
  RUN_ID="$(gh run list --repo "$REPO" --branch "$BRANCH" --status success --limit 1 \
    --json databaseId --jq '.[0].databaseId')"
  if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    echo "no successful build found for $BRANCH" >&2
    exit 1
  fi
  echo "downloading build $RUN_ID of $BRANCH from $REPO"
  gh run download "$RUN_ID" --repo "$REPO" --name Reframed --dir "$WORK" >/dev/null
  (cd "$WORK" && unzip -q Reframed.zip)
  SOURCE_APP="$WORK/Reframed.app"
fi

if [ ! -d "$SOURCE_APP" ]; then
  echo "not an app bundle: $SOURCE_APP" >&2
  exit 1
fi

if pgrep -f "$TARGET/Contents/MacOS/Reframed" >/dev/null 2>&1; then
  echo "quitting Reframed"
  osascript -e 'quit app "Reframed"' >/dev/null 2>&1 || true
  sleep 3
fi

mkdir -p "$BACKUP_DIR"
if [ -d "$TARGET" ]; then
  mv "$TARGET" "$BACKUP_DIR/Reframed-$(date +%Y%m%d-%H%M%S).app"
fi

ditto "$SOURCE_APP" "$TARGET"
codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" \
  --entitlements "$REPO_ROOT/Reframed/Reframed.entitlements" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

codesign --verify --deep --strict "$TARGET"
echo "installed $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"
codesign -dv --verbose=2 "$TARGET" 2>&1 | grep -E "Identifier|Authority"
codesign -d -r- "$TARGET" 2>&1 | tail -1
echo "previous build backed up to $BACKUP_DIR"
open -a "$TARGET"
