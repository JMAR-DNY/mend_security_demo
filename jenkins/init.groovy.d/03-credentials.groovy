import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*

def instance = Jenkins.getInstance()
def domain = Domain.global()
def store = instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

try {
    // Get API key from environment variable
    def dtApiKey = System.getenv('DT_API_KEY') ?: 'placeholder-api-key'

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
}

instance.save()