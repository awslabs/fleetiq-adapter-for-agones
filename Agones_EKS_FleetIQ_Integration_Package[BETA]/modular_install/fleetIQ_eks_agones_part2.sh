#!/bin/bash

# FleetIQ-EKS-Agones Integration Part 2: Environment setup and K8s tools installation

echo "[1/6] Ensure AWS region is set in configuration"

export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

#Script variables
EKSCLUSTERNAME=agones
AVAILABILITYZONES=["${AWS_REGION}a","${AWS_REGION}b","${AWS_REGION}c"]
FLEETIQREADPOLICYNAME=FleetIQpermissionsEC2
CLUSTERCONFIGFILENAME=config
NODEGROUP0NAME=ng-0
NODEGROUP0INSTANCETYPE=m5.large
NODEGROUP0INSTANCECAPACITY=1
NODEGROUP1NAME=ng-1
NODEGROUP1INSTANCETYPE=m5.xlarge
NODEGROUP1INSTANCECAPACITY=2
#----------------
#needed for part 3 script; explicitely creating the variable for external referencing
EKSCLUSTERNAME=${EKSCLUSTERNAME}
NODEGROUP0NAME=${NODEGROUP0NAME}

echo "[2/6] Dowloading eksctl binary"

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin

echo "[3/6] Check version"

echo $(eksctl version)

echo "[4/6] Create FleetIQ read policy"

echo $(aws iam create-policy --policy-name ${FLEETIQREADPOLICYNAME} --policy-document '{"Version": "2012-10-17","Statement": [{"Sid": "VisualEditor0","Effect": "Allow","Action": ["gamelift:DescribeGameServerGroup","gamelift:DescribeGameServerInstances","gamelift:DescribeGameServer"],"Resource": "*"}]}')

echo "[5/6] Create deployment file"

cat << EOF > ${CLUSTERCONFIGFILENAME}.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKSCLUSTERNAME}
  region: ${AWS_REGION}
  version: "1.16"

availabilityZones: ${AVAILABILITYZONES}

nodeGroups:
  - name: ${NODEGROUP0NAME}
    instanceType: ${NODEGROUP0INSTANCETYPE}
    desiredCapacity: ${NODEGROUP0INSTANCECAPACITY}
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
        - arn:aws:iam::${ACCOUNT_ID}:policy/${FLEETIQREADPOLICYNAME}
  - name: ${NODEGROUP1NAME}
    instanceType: ${NODEGROUP1INSTANCETYPE}
    desiredCapacity: ${NODEGROUP1INSTANCECAPACITY}
    labels:
      agones.dev/agones-system: "true"
    taints:
      agones.dev/agones-system: "true:NoExecute"
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
        - arn:aws:iam::${ACCOUNT_ID}:policy/${FLEETIQREADPOLICYNAME}
EOF

echo "[6/6] Creating EKS cluster (this will take ~15 minutes)"

eksctl create cluster -f ${CLUSTERCONFIGFILENAME}.yaml

echo "Part 2 complete."
