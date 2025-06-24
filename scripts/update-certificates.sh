#!/bin/bash
# scripts/update-certificates.sh
set -e

echo "🔐 Updating Dependency Track SSL certificates..."

# Function to update certificates in running container
update_container_certificates() {
    local container_name="dt-apiserver"
    
    echo "📋 Checking if container is running..."
    if ! docker ps | grep -q "$container_name"; then
        echo "❌ Container $container_name is not running"
        return 1
    fi
    
    echo "🔄 Updating CA certificates in container..."
    docker exec -u root "$container_name" sh -c "
        apt-get update -qq && 
        apt-get install -y ca-certificates curl openssl && 
        update-ca-certificates &&
        apt-get clean &&
        rm -rf /var/lib/apt/lists/*
    "
    
    echo "☕ Updating Java certificate store..."
    docker exec -u root "$container_name" sh -c "
        # Backup original Java keystore
        cp /opt/java/openjdk/lib/security/cacerts /opt/java/openjdk/lib/security/cacerts.backup
        
        # Import system certificates into Java keystore
        for cert in /etc/ssl/certs/*.pem; do
            if [ -f \"\$cert\" ]; then
                alias=\$(basename \"\$cert\" .pem)
                keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
                    -storepass changeit -noprompt -alias \"\$alias\" -file \"\$cert\" 2>/dev/null || true
            fi
        done
    "
    
    echo "🔄 Restarting Dependency Track to apply certificate changes..."
    docker restart "$container_name"
    
    echo "⏳ Waiting for Dependency Track to restart..."
    sleep 30
    
    # Wait for health check
    local attempts=0
    local max_attempts=20
    while [ $attempts -lt $max_attempts ]; do
        if curl -f http://localhost:8081/api/version >/dev/null 2>&1; then
            echo "✅ Dependency Track restarted successfully"
            return 0
        fi
        echo "   Waiting for restart... (attempt $((attempts + 1))/$max_attempts)"
        sleep 15
        ((attempts++))
    done
    
    echo "❌ Dependency Track failed to restart properly"
    return 1
}

# Function to test SSL connectivity
test_ssl_connectivity() {
    local container_name="dt-apiserver"
    
    echo "🧪 Testing SSL connectivity to external sources..."
    
    # Test NIST NVD
    echo "📋 Testing NIST NVD connection..."
    if docker exec "$container_name" curl -s --max-time 10 https://nvd.nist.gov/feeds/json/cve/1.1/nvdcve-1.1-modified.meta >/dev/null; then
        echo "✅ NIST NVD connection successful"
    else
        echo "❌ NIST NVD connection failed"
    fi
    
    # Test EPSS
    echo "📊 Testing EPSS connection..."
    if docker exec "$container_name" curl -s --max-time 10 https://epss.cyentia.com/epss_scores-current.csv.gz >/dev/null; then
        echo "✅ EPSS connection successful"
    else
        echo "❌ EPSS connection failed"
    fi
}

# Function to manually add specific certificates if needed
add_specific_certificates() {
    local container_name="dt-apiserver"
    
    echo "🔐 Adding specific certificates for known endpoints..."
    
    # Get certificates for key endpoints
    docker exec "$container_name" sh -c "
        # Create temp directory
        mkdir -p /tmp/certs
        
        # Get NIST certificate
        echo | openssl s_client -servername nvd.nist.gov -connect nvd.nist.gov:443 2>/dev/null | \
            openssl x509 > /tmp/certs/nvd.nist.gov.crt
        
        # Get EPSS certificate  
        echo | openssl s_client -servername epss.cyentia.com -connect epss.cyentia.com:443 2>/dev/null | \
            openssl x509 > /tmp/certs/epss.cyentia.com.crt
        
        # Import into Java keystore
        keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt -alias nvd-nist-gov -file /tmp/certs/nvd.nist.gov.crt 2>/dev/null || true
            
        keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt -alias epss-cyentia-com -file /tmp/certs/epss.cyentia.com.crt 2>/dev/null || true
        
        # Cleanup
        rm -rf /tmp/certs
    "
    
    echo "✅ Specific certificates added"
}

# Main execution
main() {
    echo "🔐 Dependency Track Certificate Update Utility"
    echo "=============================================="
    echo ""
    
    # Stop here if container isn't running
    if ! docker ps | grep -q "dt-apiserver"; then
        echo "❌ Dependency Track container is not running"
        echo "💡 Start it first with: make start"
        exit 1
    fi
    
    echo "🎯 This script will:"
    echo "   1. Update system CA certificates in the container"
    echo "   2. Refresh Java certificate store"
    echo "   3. Add specific certificates for known endpoints"
    echo "   4. Restart Dependency Track"
    echo "   5. Test SSL connectivity"
    echo ""
    
    if update_container_certificates; then
        echo ""
        add_specific_certificates
        echo ""
        echo "🔄 Restarting again to ensure all changes take effect..."
        docker restart dt-apiserver
        sleep 30
        echo ""
        test_ssl_connectivity
        echo ""
        echo "🎉 ✅ Certificate update completed!"
        echo ""
        echo "💡 Next steps:"
        echo "   • Monitor logs: docker logs dt-apiserver -f"
        echo "   • Check vulnerability feed downloads in a few minutes"
        echo "   • If issues persist, check corporate firewall/proxy settings"
    else
        echo ""
        echo "❌ Certificate update failed"
        echo ""
        echo "🔧 Manual troubleshooting:"
        echo "   • Check container logs: docker logs dt-apiserver"
        echo "   • Verify network connectivity: docker exec dt-apiserver curl -I https://nvd.nist.gov"
        echo "   • Consider corporate proxy configuration if behind firewall"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Dependency Track Certificate Update Script"
    echo "========================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --test-only       Only test SSL connectivity"
    echo ""
    echo "This script addresses SSL certificate issues by:"
    echo "• Updating system CA certificates"
    echo "• Refreshing Java certificate store"
    echo "• Adding certificates for specific endpoints"
    echo "• Testing connectivity to external sources"
}

# Process arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --test-only)
        test_ssl_connectivity
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac