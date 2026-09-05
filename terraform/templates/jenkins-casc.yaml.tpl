jenkins:
  systemMessage: "Provisioned automatically by Terraform -- do not add nodes manually."
  numExecutors: 0
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${admin_user}"
          password: "${admin_password}"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
  nodes:
    - permanent:
        name: "docker-agent"
        remoteFS: "/home/ec2-user/agent"
        numExecutors: 2
        labelString: "docker-agent"
        launcher:
          ssh:
            host: "${agent_private_ip}"
            port: 22
            credentialsId: "agent-ssh-key"
            sshHostKeyVerificationStrategy:
              nonVerifyingKeyVerificationStrategy: {}
        retentionStrategy: "always"

credentials:
  system:
    domainCredentials:
      - credentials:
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: "agent-ssh-key"
              username: "ec2-user"
              privateKeySource:
                directEntrySource:
                  privateKey: |
                    ${indent(20, agent_ssh_private_key)}