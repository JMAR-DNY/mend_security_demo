#!/bin/bash
set -e

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "📋 Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a  # stop auto-exporting
else
    echo "⚠️ No .env file found, using defaults or Docker environment"
fi

# Set defaults if variables aren't defined
DT_ADMIN_USER=${DT_ADMIN_USER:-admin}
DT_ADMIN_PASSWORD=${DT_ADMIN_PASSWORD:-admin}
DT_NEW_ADMIN_USER=${DT_NEW_ADMIN_USER:-admin}
DT_NEW_ADMIN_PASSWORD=${DT_NEW_ADMIN_PASSWORD:-admin1}
DT_API_URL=${DT_API_URL:-http://localhost:8081}

echo "🔧 Initializing Dependency Track admin account..."
echo "   Using admin user: $DT_ADMIN_USER"
echo "   API URL: $DT_API_URL"

# Wait until API responds
until curl -fs ${DT_API_URL}/api/version; do
  echo "⏳ waiting for /api/version"
  sleep 5
done

# Then poll readiness
echo "🔄 Waiting for Dependency‑Track to be fully ready (health/ready)…"
for i in {1..30}; do
  status=$(curl -fs ${DT_API_URL}/health/ready 2>/dev/null | jq -r '.status' || echo "")
  if [[ "$status" == "UP" ]]; then
    echo "✅ Readiness check passed."
    break
  fi
  echo "   Attempt $i/30 – status: ${status:-not ready}"
  sleep 5
done

echo "🔑 Attempting to change admin password via API..."

# Try the actual force change password endpoint from the API docs
CHANGE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${DT_ADMIN_USER}&password=${DT_ADMIN_PASSWORD}&newPassword=${DT_NEW_ADMIN_PASSWORD}&confirmPassword=${DT_NEW_ADMIN_PASSWORD}" \
    ${DT_API_URL}/api/v1/user/forceChangePassword 2>/dev/null || echo "FAILED")

if [[ $CHANGE_RESPONSE != "FAILED" ]]; then
    echo "✅ Password change attempt completed"
else
    echo "⚠️ Force password change failed, trying login to check status"
fi

# Test if we can login normally now
echo "🧪 Testing admin login..."
LOGIN_TEST=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${DT_ADMIN_USER}&password=${DT_NEW_ADMIN_PASSWORD}" \
    ${DT_API_URL}/api/v1/user/login 2>/dev/null || echo "")

if [[ $LOGIN_TEST != "" ]] && [[ $LOGIN_TEST != *"error"* ]]; then
    echo "✅ Admin account is ready with new credentials (${DT_ADMIN_USER}/${DT_NEW_ADMIN_PASSWORD})"
else
    echo "❌ Admin login still requires manual setup"
    echo "📝 Manual step: Go to ${DT_API_URL}, login with ${DT_ADMIN_USER}/${DT_ADMIN_PASSWORD}, and set new password to '${DT_NEW_ADMIN_PASSWORD}'"
fi

echo "🎯 Dependency Track initialization complete"