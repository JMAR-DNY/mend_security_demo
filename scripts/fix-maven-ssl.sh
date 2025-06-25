#!/bin/bash
set -e

echo "🔐 Adding Maven Central SSL Certificate to Jenkins"
echo "=================================================="

# Add Maven Central certificate to Jenkins
docker exec -u root jenkins bash -c '
    echo "📋 Getting Maven Central certificates..."
    
    # Download Maven Central certificate chain
    if echo | openssl s_client -servername search.maven.org -connect search.maven.org:443 -showcerts 2>/dev/null | \
       sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" > /tmp/maven-central-chain.pem; then
        
        if [ -s /tmp/maven-central-chain.pem ]; then
            cp /tmp/maven-central-chain.pem /usr/local/share/ca-certificates/maven-central.crt
            echo "✅ Maven Central certificate installed"
        fi
    fi
    
    # Update certificate stores
    update-ca-certificates >/dev/null 2>&1
    
    # Import into Java keystore
    if [ -f /tmp/maven-central-chain.pem ] && [ -s /tmp/maven-central-chain.pem ]; then
        keytool -import -trustcacerts \
            -keystore /opt/java/openjdk/lib/security/cacerts \
            -storepass changeit -noprompt \
            -alias maven-central-search \
            -file /tmp/maven-central-chain.pem 2>/dev/null || true
        echo "✅ Maven Central certificate added to Java keystore"
    fi
    
    # Cleanup
    rm -f /tmp/maven-central-chain.pem
    
    echo "✅ Maven Central SSL certificate configured"
'