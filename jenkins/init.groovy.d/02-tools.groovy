import jenkins.model.*

def instance = Jenkins.getInstance()
println "Jenkins initialization completed - plugins should be loaded"
instance.save()