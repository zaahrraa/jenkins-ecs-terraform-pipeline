#!/bin/bash
set -e

dnf update -y
dnf install -y java-21-amazon-corretto docker git python3 python3-pip
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user

# 1. Create a dedicated agent workspace and large temp directory on the main EBS volume
mkdir -p /home/ec2-user/agent/tmp
chown -R ec2-user:ec2-user /home/ec2-user/agent

# 2. Force Java globally to use the large EBS directory for temp files instead of the 480MB /tmp tmpfs
echo 'JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=/home/ec2-user/agent/tmp"' >> /etc/environment

echo "Agent bootstrap script finished."