// 03-credentials.groovy
#!groovy
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.*

def instance = Jenkins.getInstance()
def domain = Domain.global()
def store = instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

try {
    // Get API key from environment variable
    def dtApiKey = System.getenv('DT_API_KEY') ?: 'odt_admin_api_key_placeholder'

    def dtApiKeyCredential = new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        "dt-api-key",
        "Dependency Track API Key",
        dtApiKey
    )

    store.addCredentials(domain, dtApiKeyCredential)
    println "Credentials configured successfully with API key: ${dtApiKey.take(10)}..."
    
} catch (Exception e) {
    println "Credential configuration failed: ${e.getMessage()}"
    // Create a basic placeholder credential
    def placeholderCred = new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        "dt-api-key",
        "Dependency Track API Key (Placeholder)",
        "placeholder-key"
    )
    store.addCredentials(domain, placeholderCred)
    println "Placeholder credential created"
}

instance.save()