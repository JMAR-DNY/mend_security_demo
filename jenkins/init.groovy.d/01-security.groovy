import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()

// 02-minimal.groovy (REPLACE 02-tools.groovy and 03-credentials.groovy)
import jenkins.model.*

def instance = Jenkins.getInstance()
println "Jenkins initialization completed - plugins should be loaded"
instance.save()