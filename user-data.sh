#!/bin/bash

labauto ansible
ansible-pull -i localhost, -U https://github.com/raviteja-devops/roboshop-ansible.git roboshop.yml -e ROLE_NAME=${component} -e env=${env} | tee /opt/ansible.log
