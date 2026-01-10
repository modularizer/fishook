 #!/usr/bin/env bash
set -euo pipefail

# Get old and new versions
OLD_VER=$(old | jq -r .version 2>/dev/null || echo "")
NEW_VER=$(new | jq -r .version 2>/dev/null || echo "")
echo "checking $OLD_VER vs $NEW_VER"

# Exit if version unchanged
[[ "$OLD_VER" == "$NEW_VER" ]] && exit 0

echo "📦 Version changed: $OLD_VER → $NEW_VER"

# Update package-lock.json
if [[ -f package-lock.json ]]; then
  jq ".version = \"$NEW_VER\"" package-lock.json > /tmp/pkg-lock.json
  mv /tmp/pkg-lock.json package-lock.json
  git add package-lock.json
  echo "  ✓ Updated package-lock.json"
fi

# Update pyproject.toml
if [[ -f pyproject.toml ]]; then
  sed -i "s/^version = .*/version = \"$NEW_VER\"/" pyproject.toml
  git add pyproject.toml
  echo "  ✓ Updated pyproject.toml"
fi

echo "✅ Version sync complete"