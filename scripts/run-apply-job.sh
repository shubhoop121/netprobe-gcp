#!/bin/bash
set -e
echo '--- [APPLY] Installing Dependencies ---'
apt-get update && apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update && apt-get install -y terraform

echo '--- [APPLY] Running Terraform Apply ---'
cd ./infra/terraform
terraform init
terraform apply -auto-approve -var='nva_instance_count=2' -var='branch_name=main' -var="app_version=${GITHUB_SHA}" -var-file='terraform.tfvars'

echo '--- [APPLY] Creating Database Schema ---'
DB_IP=$(terraform output -raw netprobe_db_private_ip)
chmod +x ../../scripts/create-schema.sh
../../scripts/create-schema.sh $DB_IP