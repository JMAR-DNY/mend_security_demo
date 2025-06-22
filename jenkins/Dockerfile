FROM jenkins/jenkins:2.504.2-lts-jdk17

# Switch to root to install system dependencies
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y ca-certificates curl git maven \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Switch back to jenkins user for plugin installation
USER jenkins

# Copy plugins list and install during build
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy Jenkins Configuration as Code
COPY casc_configs/ /usr/share/jenkins/ref/casc_configs/

# Set Configuration as Code environment
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc_configs

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx2g"
ENV JENKINS_OPTS="--httpPort=8080"