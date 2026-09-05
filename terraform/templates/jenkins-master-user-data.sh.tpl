#!/bin/bash
set -e

dnf update -y
dnf install -y java-21-amazon-corretto docker git wget unzip nc
alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user

# 1. Install Jenkins repository and package FIRST
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# 2. Setup configuration directories & files
mkdir -p /var/lib/jenkins/casc_configs
echo "${jenkins_casc_yaml}" | base64 -d > /var/lib/jenkins/casc_configs/jenkins.yaml
echo "${jenkins_plugins_txt}" | base64 -d > /var/lib/jenkins/plugins.txt

mkdir -p /etc/systemd/system/jenkins.service.d
cat <<EOF > /etc/systemd/system/jenkins.service.d/environment.conf
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml"
EOF

# Pass threshold flags directly into JENKINS_JAVA_OPTIONS where the Jenkins service reads them
echo 'JENKINS_JAVA_OPTIONS="-Djenkins.install.runSetupWizard=false -Dhudson.node_monitors.DiskSpaceMonitor.freeSpaceThreshold=100MB -Dhudson.node_monitors.DiskSpaceMonitor.freeSpaceWarningThreshold=200MB -Dhudson.node_monitors.TempSpaceMonitor.freeSpaceThreshold=100MB -Dhudson.node_monitors.TempSpaceMonitor.freeSpaceWarningThreshold=200MB"' >> /etc/sysconfig/jenkins

chown -R jenkins:jenkins /var/lib/jenkins
systemctl daemon-reload

# 3. Install plugins using the plugin manager tool AFTER package installation
echo "Resolving latest plugin-installation-manager-tool release..."
PLUGIN_MANAGER_URL=$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+\.jar' | head -n1 | tr -d '\r')

if [ -n "$PLUGIN_MANAGER_URL" ]; then
  echo "Downloading plugin manager from: $PLUGIN_MANAGER_URL"
  curl -fL -o /opt/plugin-manager.jar "$PLUGIN_MANAGER_URL"
  JENKINS_WAR=$(rpm -ql jenkins | grep jenkins.war)
  mkdir -p /var/lib/jenkins/plugins
  java -jar /opt/plugin-manager.jar --war "$JENKINS_WAR" --plugin-file /var/lib/jenkins/plugins.txt --plugin-download-directory /var/lib/jenkins/plugins || echo "WARNING: plugin install failed, continuing anyway" >&2
  chown -R jenkins:jenkins /var/lib/jenkins
fi

# 4. Wait for the agent before starting
echo "Waiting for Jenkins agent at ${agent_private_ip}:22 to become reachable..."
until nc -z -w 5 ${agent_private_ip} 22; do
  sleep 5
done
echo "Agent is online. Enabling and starting Jenkins..."

systemctl enable jenkins
systemctl start jenkins
echo "Bootstrap script finished."