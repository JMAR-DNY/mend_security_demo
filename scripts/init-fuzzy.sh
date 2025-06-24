#!/bin/bash
set -euo pipefail

API_KEY="odt_uvE4xpiX_tIT1dIA0EyTJekzqtMlZvLglqRy3drHt"
BASE_URL="http://localhost:8081/api/v1"
HEADERS=(-H "X-API-Key: $API_KEY" -H "Content-Type: application/json")

echo "🔧 Applying analyzer settings via Dependency-Track API..."

# Construct correct payload (array of property objects)
cat <<EOF > payload.json
[
  {"groupName":"analyzer","propertyName":"internal.analyzer.fuzzy.enabled","propertyValue":"true"},
  {"groupName":"analyzer","propertyName":"internal.analyzer.fuzzy.purl.enabled","propertyValue":"true"},
  {"groupName":"analyzer","propertyName":"internal.analyzer.fuzzy.internal.enabled","propertyValue":"true"},
  {"groupName":"analyzer","propertyName":"internal.analyzer.ossindex.enabled","propertyValue":"true"},
  {"groupName":"analyzer","propertyName":"internal.analyzer.retirejs.enabled","propertyValue":"true"}
]
EOF

# Send batch update
resp=$(curl -s -o /tmp/resp.json -w "%{http_code}" \
  -X POST "${BASE_URL}/configProperty/aggregate" "${HEADERS[@]}" \
  -d @payload.json)

if [[ "${resp: -3}" =~ ^2 ]]; then
  echo "✅ Settings updated successfully."
else
  echo "❌ Failed (HTTP ${resp: -3})"
  cat /tmp/resp.json
  exit 1
fi

echo -e "\n🔍 Verifying active analyzer settings:"
curl -s "${HEADERS[@]}" "${BASE_URL}/configProperty?groupName=analyzer" | \
  jq -r '.[] | select(.propertyValue=="true") | "✅ \(.propertyName)"'

rm -f payload.json /tmp/resp.json
