#!/bin/bash

# FleetIQ-EKS-Agones Integration Part 1: Environment setup and K8s tools installation

echo "Installing Kubernetes tools"

echo "[1/4] Installing kubectl"

sudo curl --silent --location -o /usr/local/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl

echo "[2/4] Updating awscli"

sudo pip install --upgrade awscli && hash -r

echo "[3/4] Installing jq, envsubst and bash completion"

sudo yum -y install jq gettext bash-completion moreutils

echo "[4/4] Verifying that binaries are in path of the executable"

for command in kubectl jq envsubst aws
do
which $command &>/dev/null && echo "$command in path" || echo "$command NOT FOUND"
done

echo "Part 1 complete."
