#!/bin/bash
set -e

echo "🔧 Initializing Dependency Track for demo-friendly login..."
echo "   Strategy: Round-trip password change to bypass forced reset"
echo "   Final credentials will be: admin/admin (demo-friendly)"

DT_API_URL="http://localhost:8081"

# Wait until API responds
echo "⏳ Waiting for Dependency Track API to respond..."
until curl -fs ${DT_API_URL}/api/version >/dev/null 2>&1; do
  echo "   Still waiting for /api/version..."
  sleep 5
done

# Then poll readiness
echo "🔄 Waiting for Dependency Track to be fully ready..."
for i in {1..30}; do
  status=$(curl -fs ${DT_API_URL}/health/ready 2>/dev/null | jq -r '.status' 2>/dev/null || echo "")
  if [[ "$status" == "UP" ]]; then
    echo "✅ Readiness check passed."
    break
  fi
  echo "   Attempt $i/30 – status: ${status:-not ready}"
  sleep 5
done

echo ""
echo "🔄 Step 1: Changing password from default to temporary password..."
echo "   This satisfies the initial password change requirement"

# First change: admin/admin -> admin/admin1 (satisfies forced change requirement)
CHANGE_RESPONSE_1=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin&password=admin&newPassword=admin1&confirmPassword=admin1" \
    ${DT_API_URL}/api/v1/user/forceChangePassword 2>/dev/null || echo "FAILED")

if [[ $CHANGE_RESPONSE_1 != "FAILED" ]]; then
    echo "✅ First password change completed (admin -> admin1)"
    
    # Small delay to ensure the change is processed
    sleep 2
    
    echo ""
    echo "🔄 Step 2: Changing password back to demo-friendly credentials..."
    echo "   This allows easy demo access without password reset screens"
    
    # Second change: admin/admin1 -> admin/admin (demo-friendly)
    CHANGE_RESPONSE_2=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=admin1&newPassword=admin&confirmPassword=admin" \
        ${DT_API_URL}/api/v1/user/forceChangePassword 2>/dev/null || echo "FAILED")
    
    if [[ $CHANGE_RESPONSE_2 != "FAILED" ]]; then
        echo "✅ Second password change completed (admin1 -> admin)"
        echo "🎉 Round-trip password change successful!"
    else
        echo "⚠️ Second password change failed, but first change succeeded"
        echo "📝 Current credentials: admin/admin1"
    fi
else
    echo "⚠️ Initial password change failed"
    echo "💡 This might be normal if password was already changed"
fi

echo ""
echo "🧪 Testing final login credentials..."

# Test login with admin/admin (our desired demo credentials)
LOGIN_TEST_DEMO=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin&password=admin" \
    ${DT_API_URL}/api/v1/user/login 2>/dev/null || echo "")

if [[ $LOGIN_TEST_DEMO != "" ]] && [[ $LOGIN_TEST_DEMO != *"error"* ]] && [[ $LOGIN_TEST_DEMO != *"401"* ]]; then
    echo "✅ Demo credentials working: admin/admin"
    echo "🎯 Perfect for demo! No password reset screen will appear."
else
    # Fallback: test with admin1 password
    echo "⚠️ Demo credentials (admin/admin) not working, testing fallback..."
    
    LOGIN_TEST_FALLBACK=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=admin1" \
        ${DT_API_URL}/api/v1/user/login 2>/dev/null || echo "")
    
    if [[ $LOGIN_TEST_FALLBACK != "" ]] && [[ $LOGIN_TEST_FALLBACK != *"error"* ]] && [[ $LOGIN_TEST_FALLBACK != *"401"* ]]; then
        echo "✅ Fallback credentials working: admin/admin1"
        echo "📝 Use admin/admin1 to login (will need manual password change)"
    else
        echo "❌ Both credential sets failed"
        echo "📝 Manual setup required:"
        echo "   1. Go to ${DT_API_URL}"
        echo "   2. Try admin/admin or admin/admin1"
        echo "   3. Complete any required password changes"
    fi
fi

echo ""
echo "🎯 Dependency Track Initialization Summary:"
echo "=========================================="
echo "🌐 Web Interface: ${DT_API_URL}"
echo "🎬 Demo Login Strategy:"

# Final status determination
if [[ $LOGIN_TEST_DEMO != "" ]] && [[ $LOGIN_TEST_DEMO != *"error"* ]] && [[ $LOGIN_TEST_DEMO != *"401"* ]]; then
    echo "   ✅ Use: admin/admin (no password reset required)"
    echo "   🎉 Perfect demo experience!"
elif [[ $LOGIN_TEST_FALLBACK != "" ]] && [[ $LOGIN_TEST_FALLBACK != *"error"* ]] && [[ $LOGIN_TEST_FALLBACK != *"401"* ]]; then
    echo "   ⚠️ Use: admin/admin1 (may require one-time password change)"
    echo "   💡 Change password back to 'admin' for future demos"
else
    echo "   ❌ Manual login setup required"
    echo "   🔧 Try admin/admin or admin/admin1 and follow prompts"
fi

echo ""
echo "✅ Dependency Track initialization complete!"