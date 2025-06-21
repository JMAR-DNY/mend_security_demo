#!groovy
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.*

def instance = Jenkins.getInstance()
def domain = Domain.global()
def store = instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// Add Dependency Track API Key credential
def dtApiKey = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "dt-api-key",
    "Dependency Track API Key",
    "odt_admin_api_key_placeholder"  // This will be replaced during setup
)

store.addCredentials(domain, dtApiKey)

// Add GitHub credentials for private repos (if needed)
def githubCredentials = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "github-credentials",
    "GitHub Access",
    "github-user",
    "github-token"
)

store.addCredentials(domain, githubCredentials)

instance.save()
println "Credentials configured successfully"