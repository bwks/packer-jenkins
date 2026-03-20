#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
JENKINS_HOME=/var/lib/jenkins
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-sherpa}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-Everest1953!}"

# ---------------------------------------------------------------------------
# 1. Add Jenkins LTS repository
# ---------------------------------------------------------------------------
echo "==> Adding Jenkins LTS repository"
# The Jenkins repo requires key 7198F4B714ABFC68.
# Download from the Ubuntu keyserver to guarantee the correct key.
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 7198F4B714ABFC68
gpg --export 7198F4B714ABFC68 | tee /usr/share/keyrings/jenkins-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] \
    https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list

# ---------------------------------------------------------------------------
# 2. Configure skip-wizard BEFORE installing Jenkins so it never runs the
#    setup wizard even on the first (automatic) start triggered by apt.
# ---------------------------------------------------------------------------
echo "==> Pre-configuring Jenkins systemd override (skip setup wizard)"
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'SYSTEMD_EOF'
[Service]
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
SYSTEMD_EOF

# ---------------------------------------------------------------------------
# 3. Install Jenkins - this also starts it automatically via the apt post-hook.
#    We stop it immediately so we can configure it properly before a clean start.
# ---------------------------------------------------------------------------
apt-get update
apt-get install -y jenkins
systemctl daemon-reload

echo "==> Stopping Jenkins (installed by apt, will restart after full setup)"
systemctl stop jenkins || true
# Give it a moment to fully stop
sleep 5

echo "==> Jenkins package version: $(dpkg -s jenkins | grep '^Version')"

# ---------------------------------------------------------------------------
# 4. Write Groovy init scripts
#    These run on every Jenkins startup while present in init.groovy.d.
# ---------------------------------------------------------------------------
echo "==> Writing Jenkins init Groovy scripts"
mkdir -p "${JENKINS_HOME}/init.groovy.d"

# CSRF protection
cat > "${JENKINS_HOME}/init.groovy.d/01-security.groovy" << 'GROOVY_EOF'
import jenkins.model.*
import hudson.security.csrf.DefaultCrumbIssuer

def instance = Jenkins.get()
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))
instance.save()
println "INIT: CSRF protection enabled"
GROOVY_EOF

# Admin user + security realm
cat > "${JENKINS_HOME}/init.groovy.d/02-admin-user.groovy" << GROOVY_EOF
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("${JENKINS_ADMIN_USER}", "${JENKINS_ADMIN_PASSWORD}")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println "INIT: Admin user '${JENKINS_ADMIN_USER}' created"
GROOVY_EOF

chown -R jenkins:jenkins "${JENKINS_HOME}/init.groovy.d"

# ---------------------------------------------------------------------------
# 5. Pre-install plugins using the Plugin Installation Manager Tool (PIMT)
#    This runs WITHOUT Jenkins running, resolving all dependencies automatically.
# ---------------------------------------------------------------------------
echo "==> Downloading Plugin Installation Manager Tool"
PIMT_VERSION="2.12.16"
wget -q \
    "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PIMT_VERSION}/jenkins-plugin-manager-${PIMT_VERSION}.jar" \
    -O /tmp/jenkins-plugin-manager.jar

echo "==> Installing Jenkins plugins (this may take several minutes)"
cat > /tmp/plugins.txt << 'PLUGINS_EOF'
git
workflow-aggregator
pipeline-stage-view
blueocean
docker-workflow
docker-plugin
credentials-binding
ssh-agent
matrix-auth
role-strategy
github
github-branch-source
pipeline-github-lib
timestamper
ws-cleanup
build-timeout
email-ext
mailer
configuration-as-code
job-dsl
ansicolor
junit
htmlpublisher
slack
sonar
ansible
nodejs
PLUGINS_EOF

java -jar /tmp/jenkins-plugin-manager.jar \
    --war /usr/share/java/jenkins.war \
    --plugin-download-directory "${JENKINS_HOME}/plugins" \
    --plugin-file /tmp/plugins.txt \
    2>&1 | tee /tmp/plugin-install.log

echo "==> Plugin installation complete"
chown -R jenkins:jenkins "${JENKINS_HOME}/plugins"

# ---------------------------------------------------------------------------
# 6. Start Jenkins with everything in place:
#    - skip wizard env var active
#    - groovy init scripts present (admin user will be created)
#    - plugins pre-installed
# ---------------------------------------------------------------------------
echo "==> Starting Jenkins (clean start with full configuration)"
systemctl enable jenkins
systemctl start jenkins

echo "==> Waiting for Jenkins to come up..."
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "==> Jenkins login page responded after ${ELAPSED}s"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "    ... waiting (${ELAPSED}s / ${TIMEOUT}s, last HTTP: ${HTTP_CODE})"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Jenkins failed to start within ${TIMEOUT}s"
    echo "--- Last 50 lines of jenkins.log ---"
    tail -50 /var/log/jenkins/jenkins.log 2>/dev/null || true
    exit 1
fi

# Wait for the Groovy init scripts to complete.
# They run asynchronously during Jenkins startup; 60s is conservative.
echo "==> Waiting 60s for Groovy init scripts to complete..."
sleep 60

# ---------------------------------------------------------------------------
# 7. Verify admin login
# ---------------------------------------------------------------------------
echo "==> Verifying admin login"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    http://localhost:8080/api/json)

if [ "$HTTP_CODE" = "200" ]; then
    echo "==> Admin login verified (HTTP ${HTTP_CODE})"
else
    echo "ERROR: Admin login returned HTTP ${HTTP_CODE} - build will fail"
    echo "--- Jenkins log tail ---"
    tail -50 /var/log/jenkins/jenkins.log 2>/dev/null || true
    exit 1
fi

# ---------------------------------------------------------------------------
# 8. Stop Jenkins - systemd will start it on deployment
# ---------------------------------------------------------------------------
echo "==> Stopping Jenkins"
systemctl stop jenkins

# ---------------------------------------------------------------------------
# 9. Cleanup build artifacts
# ---------------------------------------------------------------------------
rm -f /tmp/jenkins-plugin-manager.jar /tmp/plugins.txt /tmp/plugin-install.log

echo "==> Jenkins setup complete"
