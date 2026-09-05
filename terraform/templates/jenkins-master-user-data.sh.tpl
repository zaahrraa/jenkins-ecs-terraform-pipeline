#!/bin/bash
set -e

dnf update -y
dnf install -y java-21-amazon-corretto docker git wget unzip
alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

mkdir -p /var/lib/jenkins/casc_configs
echo "${jenkins_casc_yaml}" | base64 -d > /var/lib/jenkins/casc_configs/jenkins.yaml
echo "${jenkins_plugins_txt}" | base64 -d > /var/lib/jenkins/plugins.txt

echo 'CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml' >> /etc/sysconfig/jenkins
echo 'JENKINS_JAVA_OPTIONS="-Djenkins.install.runSetupWizard=false"' >> /etc/sysconfig/jenkins

chown -R jenkins:jenkins /var/lib/jenkins
systemctl enable jenkins

echo "Resolving latest plugin-installation-manager-tool release..."
PLUGIN_MANAGER_URL=$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+\.jar' | head -n1 | tr -d '\r')

PLUGIN_INSTALL_OK=false

if [ -z "$PLUGIN_MANAGER_URL" ]; then
  echo "WARNING: could not resolve plugin-installation-manager-tool download URL" >&2
else
  echo "Downloading plugin manager from: $PLUGIN_MANAGER_URL"
  curl -fL -o /opt/plugin-manager.jar "$PLUGIN_MANAGER_URL"
  if unzip -l /opt/plugin-manager.jar > /dev/null 2>&1; then
    PLUGIN_INSTALL_OK=true
  else
    echo "WARNING: downloaded file is not a valid jar" >&2
  fi
fi

if [ "$PLUGIN_INSTALL_OK" = true ]; then
  JENKINS_WAR=$(rpm -ql jenkins | grep jenkins.war)
  mkdir -p /var/lib/jenkins/plugins
  java -jar /opt/plugin-manager.jar --war "$JENKINS_WAR" --plugin-file /var/lib/jenkins/plugins.txt --plugin-download-directory /var/lib/jenkins/plugins || echo "WARNING: plugin install failed, continuing anyway" >&2
  chown -R jenkins:jenkins /var/lib/jenkins
fi

systemctl start jenkins
echo "Bootstrap script finished."