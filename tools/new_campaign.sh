#!/usr/bin/env bash
# Start a new campaign by copying the template.   Usage: tools/new_campaign.sh my_campaign "My Campaign"
set -euo pipefail
cd "$(dirname "$0")/.."
ID="${1:-}"
NAME="${2:-$ID}"
if ! [[ "$ID" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "usage: tools/new_campaign.sh <id> [\"Display name\"]   (id: lower-case letters, digits, underscores)" >&2
  exit 2
fi
if [ -e "campaigns/$ID" ]; then
  echo "campaigns/$ID already exists." >&2
  exit 1
fi
cp -r campaigns/_template "campaigns/$ID"
rm -rf "campaigns/$ID/voice" "campaigns/$ID/music" "campaigns/$ID/portraits"
python3 - "$ID" "$NAME" <<'PY'
import json, sys
path = f"campaigns/{sys.argv[1]}/campaign.json"
data = json.load(open(path))
data["name"] = sys.argv[2]
data["author"] = ""
data["description"] = "Describe your campaign here."
json.dump(data, open(path, "w"), indent=2)
PY
echo "Created campaigns/$ID. Read docs/CAMPAIGN_FORMAT.md, edit the files, then run ./check.sh."
