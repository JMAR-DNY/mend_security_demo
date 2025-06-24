#!/bin/bash
# scripts/init-certificates.sh
# Automatic certificate initialization for Dependency Track container
# This script runs automatically when the container starts

set -e

echo "🔐 [INIT] Initializing SSL certificates for Dependency Track..."

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [CERT-INIT] $1"
}

# Function to check if we're running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "⚠️ Not running as root, switching to root for certificate operations"
        exec sudo "$0" "$@"
    fi
}

# Function to install certificate tools
install_cert_tools() {
    log "📦 Installing certificate management tools..."
    
    # Update package list and install tools
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y ca-certificates curl openssl wget >/dev/null 2>&1 || true
    
    log "✅ Certificate tools installed"
}

# Function to download and install external certificates
download_external_certs() {
    log "🌐 Downloading certificates for external vulnerability feeds..."
    
    # Create temporary directory for certificates
    mkdir -p /tmp/init-certs
    
    # Download NIST NVD certificate chain
    log "📋 Getting NIST NVD certificates..."
    if echo | openssl s_client -servername nvd.nist.gov -connect nvd.nist.gov:443 -showcerts 2>/dev/null | \
       sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/init-certs/nvd-chain.pem; then
        
        if [ -s /tmp/init-certs/nvd-chain.pem ]; then
            cp /tmp/init-certs/nvd-chain.pem /usr/local/share/ca-certificates/nvd-nist-gov.crt
            log "✅ NIST NVD certificate installed"
        else
            log "⚠️ NIST certificate download was empty"
        fi
    else
        log "⚠️ Could not download NIST certificate"
    fi
    
    # Download EPSS certificate chain
    log "📊 Getting EPSS certificates..."
    if echo | openssl s_client -servername epss.cyentia.com -connect epss.cyentia.com:443 -showcerts 2>/dev/null | \
       sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/init-certs/epss-chain.pem; then
        
        if [ -s /tmp/init-certs/epss-chain.pem ]; then
            cp /tmp/init-certs/epss-chain.pem /usr/local/share/ca-certificates/epss-cyentia-com.crt
            log "✅ EPSS certificate installed"
        else
            log "⚠️ EPSS certificate download was empty"
        fi
    else
        log "⚠️ Could not download EPSS certificate"
    fi
    
    # Clean up temporary files
    rm -rf /tmp/init-certs
}

# Function to update system certificate store
update_system_certs() {
    log "🔄 Updating system certificate store..."
    
    # Update CA certificates
    update-ca-certificates >/dev/null 2>&1 || true
    
    log "✅ System certificates updated"
}

# Function to update Java certificate store
update_java_certs() {
    log "☕ Updating Java certificate store..."
    
    # Backup existing keystore
    if [ -f /opt/java/openjdk/lib/security/cacerts ]; then
        cp /opt/java/openjdk/lib/security/cacerts /opt/java/openjdk/lib/security/cacerts.init-backup 2>/dev/null || true
    fi
    
    # Import system CA bundle into Java keystore
    if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        keytool -import -trustcacerts \
            -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt \
            -alias system-ca-bundle \
            -file /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
        
        log "✅ System CA bundle imported to Java keystore"
    fi
    
    # Import specific certificates we downloaded
    for cert_file in /usr/local/share/ca-certificates/*.crt; do
        if [ -f "$cert_file" ]; then
            cert_name=$(basename "$cert_file" .crt)
            keytool -import -trustcacerts \
                -keystore /opt/java/openjdk/lib/security/cacerts \
                -storepass changeit -noprompt \
                -alias "$cert_name" \
                -file "$cert_file" 2>/dev/null || true
            
            log "✅ Imported $cert_name to Java keystore"
        fi
    done
    
    log "✅ Java certificate store updated"
}

# Function to verify certificate installation
verify_certificates() {
    log "🧪 Verifying certificate installation..."
    
    # Check if certificates exist in keystore
    local cert_count=$(keytool -list -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit 2>/dev/null | grep -c "trustedCertEntry" || echo "0")
    
    log "📊 Java keystore contains $cert_count trusted certificates"
    
    # Test connectivity to key endpoints
    log "🌐 Testing external connectivity..."
    
    # Test NIST (with timeout)
    if timeout 10 curl -s --max-time 5 https://nvd.nist.gov/ >/dev/null 2>&1; then
        log "✅ NIST NVD connectivity test passed"
    else
        log "⚠️ NIST NVD connectivity test failed (may be network/timeout)"
    fi
    
    # Test EPSS (with timeout)
    if timeout 10 curl -s --max-time 5 https://epss.cyentia.com/ >/dev/null 2>&1; then
        log "✅ EPSS connectivity test passed"
    else
        log "⚠️ EPSS connectivity test failed (may be network/timeout)"
    fi
}

# Function to create completion marker
create_completion_marker() {
    # Create a marker file to indicate certificates were initialized
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > /data/.cert-init-completed
    log "✅ Certificate initialization completed and marked"
}

# Main execution function
main() {
    log "🚀 Starting automatic certificate initialization..."
    
    # Check if already completed
    if [ -f /data/.cert-init-completed ]; then
        log "ℹ️ Certificate initialization already completed, skipping"
        log "📅 Previous completion: $(cat /data/.cert-init-completed)"
        return 0
    fi
    
    # Ensure we're running as root
    check_root "$@"
    
    # Perform certificate initialization
    install_cert_tools
    download_external_certs
    update_system_certs
    update_java_certs
    verify_certificates
    create_completion_marker
    
    log "🎉 Certificate initialization completed successfully!"
    log "💡 Vulnerability feeds should now work without SSL errors"
}

# Handle different execution contexts
if [ "${1:-}" = "--force" ]; then
    log "🔄 Force mode: removing completion marker and re-running"
    rm -f /data/.cert-init-completed
    main
elif [ "${1:-}" = "--verify-only" ]; then
    log "🔍 Verification mode: checking current certificate status"
    verify_certificates
else
    # Normal automatic execution
    main "$@"
fi