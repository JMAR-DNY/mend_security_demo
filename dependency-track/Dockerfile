# Create a custom Dockerfile for Dependency Track with updated certificates
FROM dependencytrack/apiserver:latest

# Switch to root to update certificates
USER root

# Update CA certificates and install additional certificate tools
RUN apt-get update && \
    apt-get install -y ca-certificates curl openssl && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Ensure Java uses the system certificate store
ENV JAVA_OPTS="-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts -Djavax.net.ssl.trustStoreType=JKS"

# Switch back to the original user
USER dtrack