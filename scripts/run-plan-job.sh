#!/bin/bash
set -e
echo '--- [PLAN] Installing Dependencies ---'
apt-get update && apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update && apt-get install -y terraform

echo '--- [PLAN] Running Terraform ---'
cd ./infra/terraform
terraform init
terraform plan -input=false -var='nva_instance_count=1' -var="branch_name=${GITHUB_HEAD_REF}" -var="app_version=${GITHUB_PULL_REQUEST_HEAD_SHA}" -var-file='terraform.tfvars'