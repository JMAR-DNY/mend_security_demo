#!/bin/bash
set -e

echo "🔧 Initializing Dependency Track admin account..."

# Wait until API responds
until curl -fs http://localhost:8081/api/version; do
  echo "⏳ waiting for /api/version"
  sleep 5
done

# Then poll readiness
echo "🔄 Waiting for Dependency‑Track to be fully ready (health/ready)…"
for i in {1..30}; do
  status=$(curl -fs http://localhost:8081/health/ready 2>/dev/null | jq -r '.status' || echo "")
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
    http://localhost:8081/api/v1/user/forceChangePassword 2>/dev/null || echo "FAILED")

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
    http://localhost:8081/api/v1/user/login 2>/dev/null || echo "")

if [[ $LOGIN_TEST != "" ]] && [[ $LOGIN_TEST != *"error"* ]]; then
    echo "✅ Admin account is ready with new credentials"
else
    echo "❌ Admin login still requires manual setup"
    echo "📝 Manual step: Go to http://localhost:8081, login with admin/admin, and set new password to 'admin'"
fi

echo "🎯 Dependency Track initialization complete"