#!/bin/bash
# scripts/fix-dt-certificates.sh
# Dependency Track Certificate Fix for External Vulnerability Feeds
set -e

CONTAINER_NAME="dt-apiserver"
SCRIPT_NAME="$(basename "$0")"

# Function to log with timestamp
log() {
    echo "🔐 [$SCRIPT_NAME] $1"
}

# Function to check if container is running
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log "❌ Container $CONTAINER_NAME is not running"
        return 1
    fi
    return 0
}

# Function to apply certificate fixes
apply_certificate_fixes() {
    log "📦 Installing certificate tools and updating system certificates..."
    
    docker exec -u root "$CONTAINER_NAME" sh -c "
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y ca-certificates curl openssl > /dev/null 2>&1
        update-ca-certificates > /dev/null 2>&1
    " 2>/dev/null || {
        log "⚠️ Package installation had issues, continuing..."
        return 1
    }
    
    log "🔐 Downloading and installing certificates for NIST and EPSS endpoints..."
    
    docker exec -u root "$CONTAINER_NAME" sh -c "
        mkdir -p /tmp/certs
        
        # Get certificate chains for key endpoints
        echo | openssl s_client -servername nvd.nist.gov -connect nvd.nist.gov:443 -showcerts 2>/dev/null | \
            sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/certs/nvd-chain.pem
        
        echo | openssl s_client -servername epss.cyentia.com -connect epss.cyentia.com:443 -showcerts 2>/dev/null | \
            sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/certs/epss-chain.pem
        
        # Install into system certificate store
        if [ -f /tmp/certs/nvd-chain.pem ] && [ -s /tmp/certs/nvd-chain.pem ]; then
            cp /tmp/certs/nvd-chain.pem /usr/local/share/ca-certificates/nvd-nist-gov.crt
        fi
        if [ -f /tmp/certs/epss-chain.pem ] && [ -s /tmp/certs/epss-chain.pem ]; then
            cp /tmp/certs/epss-chain.pem /usr/local/share/ca-certificates/epss-cyentia-com.crt
        fi
        
        update-ca-certificates > /dev/null 2>&1
    " 2>/dev/null || {
        log "⚠️ Certificate download had issues, continuing..."
        return 1
    }
    
    log "☕ Updating Java certificate store..."
    
    docker exec -u root "$CONTAINER_NAME" sh -c "
        # Backup Java keystore
        cp /opt/java/openjdk/lib/security/cacerts /opt/java/openjdk/lib/security/cacerts.backup 2>/dev/null || true
        
        # Import system CA bundle into Java keystore
        keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt -alias system-ca-bundle \
            -file /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
        
        # Import specific certificates if available
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
    " 2>/dev/null || {
        log "⚠️ Java keystore update had issues, continuing..."
        return 1
    }
    
    return 0
}

# Function to restart and wait for service
restart_and_wait() {
    log "🔄 Restarting Dependency Track to apply certificate changes..."
    
    docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    
    log "⏳ Waiting for Dependency Track to restart..."
    sleep 30
    
    # Wait for API to respond
    local attempts=0
    local max_attempts=20
    while [ $attempts -lt $max_attempts ]; do
        if curl -f http://localhost:8081/api/version >/dev/null 2>&1; then
            log "✅ Dependency Track restarted successfully"
            return 0
        fi
        if [ $((attempts % 3)) -eq 0 ]; then
            log "   Still waiting for restart... (attempt $((attempts + 1))/$max_attempts)"
        fi
        sleep 15
        ((attempts++))
    done
    
    log "⚠️ Dependency Track restart taking longer than expected"
    return 1
}

# Function to verify the fixes worked
verify_fixes() {
    log "⏳ Allowing time for vulnerability feed downloads to begin..."
    sleep 45
    
    # Check for certificate errors vs successful downloads
    local recent_errors=$(docker logs "$CONTAINER_NAME" --since 2m 2>&1 | grep -c "PKIX path building failed" 2>/dev/null || echo "0")
    local recent_downloads=$(docker logs "$CONTAINER_NAME" --since 2m 2>&1 | grep -E "(Downloading|Uncompressing)" | wc -l 2>/dev/null || echo "0")
    
    if [ "$recent_errors" -eq "0" ] && [ "$recent_downloads" -gt "0" ]; then
        log "🎉 Certificate fixes successful! Vulnerability feeds are downloading."
        return 0
    elif [ "$recent_downloads" -gt "0" ]; then
        log "✅ Vulnerability feeds are downloading (some cert warnings may persist)"
        return 0
    else
        log "ℹ️ Downloads may take a few more minutes to retry automatically"
        log "💡 Monitor with: docker logs $CONTAINER_NAME -f | grep -E '(download|PKIX)'"
        return 1
    fi
}

# Function to check if fixes are needed
check_if_fixes_needed() {
    log "🔍 Checking if certificate fixes are needed..."
    
    # Give DT time to start background tasks and potentially encounter cert issues
    sleep 30
    
    local cert_errors=$(docker logs "$CONTAINER_NAME" --since 1m 2>&1 | grep -c "PKIX path building failed" 2>/dev/null || echo "0")
    
    if [ "$cert_errors" -gt "0" ]; then
        log "🔧 Certificate issues detected ($cert_errors errors found) - applying fixes..."
        return 0  # Fixes needed
    else
        log "✅ No SSL certificate issues detected in recent logs"
        return 1  # No fixes needed
    fi
}

# Main execution function
main() {
    log "Starting Dependency Track SSL Certificate Fix"
    
    # Check if container is running
    if ! check_container; then
        log "❌ Cannot proceed - container not running"
        exit 1
    fi
    
    # Check if fixes are actually needed
    if ! check_if_fixes_needed; then
        log "🎯 No certificate fixes needed - vulnerability feeds appear to be working"
        exit 0
    fi
    
    # Apply the fixes
    if apply_certificate_fixes; then
        log "✅ Certificate fixes applied successfully"
    else
        log "⚠️ Some certificate fixes had issues, but continuing..."
    fi
    
    # Restart the service
    if restart_and_wait; then
        log "✅ Service restarted successfully"
    else
        log "❌ Service restart had issues"
        exit 1
    fi
    
    # Verify the fixes worked
    if verify_fixes; then
        log "🎉 Certificate fix process completed successfully!"
        log "📊 Vulnerability feeds should now download automatically"
    else
        log "⚠️ Certificate fixes applied, but verification inconclusive"
        log "💡 Monitor logs for continued improvement"
    fi
    
    log "Certificate fix process complete"
}

# Help function
show_help() {
    echo "Dependency Track Certificate Fix Script"
    echo "======================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --force           Skip certificate issue detection and force fixes"
    echo "  --verify-only     Only verify current certificate status"
    echo ""
    echo "This script:"
    echo "• Detects SSL certificate issues with external vulnerability feeds"
    echo "• Downloads and installs certificates for NIST and EPSS endpoints"
    echo "• Updates both system and Java certificate stores"
    echo "• Restarts Dependency Track to apply changes"
    echo "• Verifies that vulnerability feeds start downloading"
    echo ""
    echo "Examples:"
    echo "  $0                Fix certificates if issues detected"
    echo "  $0 --force        Apply fixes regardless of current status"
    echo "  $0 --verify-only  Check current certificate status"
}

# Process command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --force)
        log "Force mode - applying certificate fixes regardless of current status"
        check_container || exit 1
        apply_certificate_fixes
        restart_and_wait
        verify_fixes
        ;;
    --verify-only)
        log "Verify mode - checking certificate status only"
        check_container || exit 1
        check_if_fixes_needed && echo "Certificate fixes needed" || echo "No certificate fixes needed"
        ;;
    *)
        main "$@"
        ;;
esac