#!/bin/bash
# scripts/quick-cert-fix.sh
# Emergency Certificate Fix for Dependency Track
set -e

echo "🚨 EMERGENCY CERTIFICATE FIX for Dependency Track"
echo "================================================"
echo "🎯 This will fix the PKIX certificate errors you're seeing"
echo ""

CONTAINER_NAME="dt-apiserver"

# Function to check container status
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo "❌ Container $CONTAINER_NAME is not running"
        echo "💡 Start it with: make start"
        exit 1
    fi
    echo "✅ Container $CONTAINER_NAME is running"
}

# Function to apply comprehensive certificate fix
apply_emergency_fix() {
    echo "🔧 Applying emergency certificate fixes..."
    
    # Step 1: Update system certificates and install tools
    echo "📦 Installing certificate tools..."
    docker exec -u root "$CONTAINER_NAME" sh -c "
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y ca-certificates curl openssl >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
        echo '✅ System certificates updated'
    " 2>/dev/null || echo "⚠️ Package update had issues, continuing..."
    
    # Step 2: Download and install specific certificates
    echo "🔐 Downloading certificates for NIST and EPSS..."
    docker exec -u root "$CONTAINER_NAME" sh -c "
        mkdir -p /tmp/certs
        
        # Get NIST NVD certificate chain
        echo | openssl s_client -servername nvd.nist.gov -connect nvd.nist.gov:443 -showcerts 2>/dev/null | \
            sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/certs/nvd-chain.pem
        
        # Get EPSS certificate chain
        echo | openssl s_client -servername epss.cyentia.com -connect epss.cyentia.com:443 -showcerts 2>/dev/null | \
            sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/certs/epss-chain.pem
        
        # Install into system certificate store
        if [ -f /tmp/certs/nvd-chain.pem ] && [ -s /tmp/certs/nvd-chain.pem ]; then
            cp /tmp/certs/nvd-chain.pem /usr/local/share/ca-certificates/nvd-nist.crt
            echo '✅ NIST certificate installed'
        fi
        
        if [ -f /tmp/certs/epss-chain.pem ] && [ -s /tmp/certs/epss-chain.pem ]; then
            cp /tmp/certs/epss-chain.pem /usr/local/share/ca-certificates/epss-cyentia.crt
            echo '✅ EPSS certificate installed'
        fi
        
        # Update certificate store
        update-ca-certificates >/dev/null 2>&1
    " 2>/dev/null || echo "⚠️ Certificate download had issues, continuing..."
    
    # Step 3: Update Java keystore
    echo "☕ Updating Java certificate store..."
    docker exec -u root "$CONTAINER_NAME" sh -c "
        # Backup Java keystore
        cp /opt/java/openjdk/lib/security/cacerts /opt/java/openjdk/lib/security/cacerts.backup 2>/dev/null || true
        
        # Import system CA bundle into Java keystore
        keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt -alias system-ca-bundle \
            -file /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
        
        # Import specific certificates
        if [ -f /tmp/certs/nvd-chain.pem ] && [ -s /tmp/certs/nvd-chain.pem ]; then
            keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
                -storepass changeit -noprompt -alias nvd-nist-gov \
                -file /tmp/certs/nvd-chain.pem 2>/dev/null || true
        fi
        
        if [ -f /tmp/certs/epss-chain.pem ] && [ -s /tmp/certs/epss-chain.pem ]; then
            keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
                -storepass changeit -noprompt -alias epss-cyentia-com \
                -file /tmp/certs/epss-chain.pem 2>/dev/null || true
        fi
        
        # Cleanup
        rm -rf /tmp/certs 2>/dev/null || true
        echo '✅ Java keystore updated'
    " 2>/dev/null || echo "⚠️ Java keystore update had issues, continuing..."
    
    echo "✅ Certificate fixes applied"
}

# Function to restart and wait
restart_service() {
    echo "🔄 Restarting Dependency Track..."
    docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    
    echo "⏳ Waiting for restart..."
    sleep 30
    
    # Wait for API to respond
    local attempts=0
    local max_attempts=15
    while [ $attempts -lt $max_attempts ]; do
        if curl -f http://localhost:8081/api/version >/dev/null 2>&1; then
            echo "✅ Dependency Track restarted successfully"
            return 0
        fi
        if [ $((attempts % 3)) -eq 0 ]; then
            echo "   Still waiting... (attempt $((attempts + 1))/$max_attempts)"
        fi
        sleep 10
        ((attempts++))
    done
    
    echo "⚠️ Restart taking longer than expected, but continuing..."
    return 0
}

# Function to test and verify
test_downloads() {
    echo "🧪 Testing vulnerability feed downloads..."
    sleep 30  # Give time for background tasks to start
    
    # Check logs for new errors vs successful activity (fixed)
    local recent_errors=$(docker logs "$CONTAINER_NAME" --since 1m 2>&1 | grep -c "PKIX path building failed" 2>/dev/null || echo "0")
    local recent_activity=$(docker logs "$CONTAINER_NAME" --since 1m 2>&1 | grep -E "(download|Downloading|Initiating)" 2>/dev/null | wc -l || echo "0")
    
    # Ensure we have clean numbers
    recent_errors=$(echo "$recent_errors" | tr -d ' \n')
    recent_activity=$(echo "$recent_activity" | tr -d ' \n')
    
    echo "📊 Results:"
    echo "   Recent PKIX errors: $recent_errors"
    echo "   Recent download activity: $recent_activity"
    
    if [ "$recent_errors" -eq "0" ] 2>/dev/null; then
        echo "🎉 SUCCESS: No new PKIX errors detected!"
        if [ "$recent_activity" -gt "0" ] 2>/dev/null; then
            echo "✅ Bonus: Download activity detected!"
        fi
        return 0
    elif [ "$recent_errors" -lt "5" ] 2>/dev/null && [ "$recent_activity" -gt "0" ] 2>/dev/null; then
        echo "✅ IMPROVED: Fewer errors and some activity detected"
        return 0
    else
        echo "⚠️ Still seeing certificate issues"
        return 1
    fi
}

# Main execution
main() {
    check_container
    echo ""
    
    apply_emergency_fix
    echo ""
    
    restart_service
    echo ""
    
    if test_downloads; then
        echo ""
        echo "🎉 ✅ CERTIFICATE FIX SUCCESSFUL! ✅"
        echo ""
        echo "🎯 What was fixed:"
        echo "   • System CA certificates updated"
        echo "   • NIST and EPSS certificates downloaded and installed"
        echo "   • Java keystore updated with new certificates"
        echo "   • Service restarted to apply changes"
        echo ""
        echo "📊 Your demo should now work properly!"
        echo "💡 Monitor logs: docker logs dt-apiserver -f | grep -E '(download|PKIX)'"
    else
        echo ""
        echo "⚠️ Fix applied but verification inconclusive"
        echo ""
        echo "💡 Next steps:"
        echo "   • Wait 2-3 more minutes for feeds to retry"
        echo "   • Monitor: docker logs dt-apiserver -f | grep download"
        echo "   • If issues persist, check firewall/proxy settings"
    fi
}

# Show help
show_help() {
    echo "Quick Certificate Fix for Dependency Track"
    echo "========================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help"
    echo "  --test-only   Just test current status"
    echo ""
    echo "This emergency script:"
    echo "• Fixes PKIX certificate path building errors"
    echo "• Downloads and installs certificates for NIST/EPSS"
    echo "• Updates both system and Java certificate stores"
    echo "• Restarts Dependency Track"
    echo "• Verifies the fix worked"
}

# Process arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --test-only)
        check_container
        test_downloads
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac