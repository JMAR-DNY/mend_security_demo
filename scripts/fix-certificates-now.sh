# Continue from where it left off - just check if DT is ready now
attempts=0
max_attempts=20
while [ $attempts -lt $max_attempts ]; do
    if curl -f http://localhost:8081/api/version >/dev/null 2>&1; then
        echo "✅ Dependency Track API is ready"
        break
    fi
    echo "   Waiting... (attempt $((attempts + 1))/$max_attempts)"
    sleep 15
    ((attempts++))
done

# Then check the results
echo "📋 Checking recent download activity..."
RECENT_DOWNLOADS=$(docker logs dt-apiserver --since 2m 2>&1 | grep -E "(download.*success|successfully.*download|completed.*download)" | wc -l || echo "0")
RECENT_ERRORS=$(docker logs dt-apiserver --since 2m 2>&1 | grep -c "PKIX path building failed" || echo "0")

echo ""
echo "🎯 CERTIFICATE FIX RESULTS:"
echo "=========================="
if [ "$RECENT_ERRORS" -eq "0" ]; then
    echo "✅ SUCCESS: No new PKIX certificate errors detected!"
    if [ "$RECENT_DOWNLOADS" -gt "0" ]; then
        echo "🎉 BONUS: $RECENT_DOWNLOADS successful downloads detected!"
    else
        echo "ℹ️ Downloads may take a few more minutes to retry automatically"
    fi
    echo ""
    echo "🌟 Certificate fix appears to be working!"
else
    echo "⚠️ PARTIAL: Still seeing $RECENT_ERRORS certificate errors"
    echo "💡 This may improve over the next few minutes as feeds retry"
fi

echo ""
echo "📊 Monitor logs with: docker logs dt-apiserver -f | grep -E '(download|PKIX)'"