[Unit]
Description=Jenkins Agent
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/agent
ExecStart=/usr/bin/java -jar /home/ec2-user/agent/agent.jar -url http://${jenkins_master_ip}:8080/ -secret ${agent_secret} -name "docker-agent" -webSocket -workDir "/home/ec2-user/agent"
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=jenkins-agent

[Install]
WantedBy=multi-user.target