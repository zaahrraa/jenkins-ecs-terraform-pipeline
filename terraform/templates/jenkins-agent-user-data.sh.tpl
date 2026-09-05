#!/bin/bash
dnf update -y
dnf install -y java-17-amazon-corretto docker git
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user
mkdir -p /home/ec2-user/agent
chown ec2-user:ec2-user /home/ec2-user/agent