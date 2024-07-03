---
description: Infrastructure tools for the OpenHIM Platform
---

# Provisioning remote servers

Deploying from your local environment to a remote server or cluster is easy. All you have to do is ensure the remote servers are setup as a Docker Swarm cluster. Then, from your local environment you may target a remote environment by using the \`DOCKER\_HOST\` env var. e.g.

```
DOCKER_HOST=ssh://ubuntu@<ip> instant package init ...
```

## Setting up new servers

In addition, as part of the OpenHIM Platform Github repository we also provide scripts to easily setup new servers. The Terraform script are able to instantiate server in AWS and the Ansible script are able to configure those server to be ready to accept OpenHIM Platform packages.

### Ansible

See [here](https://github.com/jembi/platform/tree/main/infrastructure/ansible).

It is used for:&#x20;

* Adding users to the remote servers
* Provision of the remote servers in single and cluster mode: user and firewall configurations, docker installation, docker authentication and docker swarm provision.

All the passwords are saved securely using Keepass.

In the inventories, there is different environment configuration (development, production and staging) that contains: users and their ssh keys list, docker credentials and definition of the hosts.

### Terraform

Is used to create and set AWS servers. See [here](https://github.com/jembi/platform/tree/main/infrastructure/terraform).
