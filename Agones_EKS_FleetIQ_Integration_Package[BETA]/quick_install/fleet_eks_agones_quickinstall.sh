#!/bin/bash

#Part 2 Script variables
EKSCLUSTERNAME=agones
AVAILABILITYZONES=["${AWS_REGION}a","${AWS_REGION}b","${AWS_REGION}c"]
FLEETIQREADPOLICYNAME=FleetIQpermissionsEC2
CLUSTERCONFIGFILENAME=config
NODEGROUP0NAME=ng-system
NODEGROUP0INSTANCETYPE=m5.large
NODEGROUP0INSTANCECAPACITY=2
NODEGROUP1NAME=ng-agones
NODEGROUP1INSTANCETYPE=m5.xlarge
NODEGROUP1INSTANCECAPACITY=2
#Part 3 Script variables
BASEUSERDATAFILENAME=launchtemplate
MODIFIEDUSERDATAFILENAME=modlaunchtemplate
B64USERDATAFILENAME=b64modlaunchtemplate
SGDESCRIPTION=Agones_nodegroup_SG
SGNAME=eksctl-"${EKSCLUSTERNAME}"-nodegroup-ng-1-SG
SGINGRESSRULESFILENAME=sgingress
LTINPUTFILENAME=ltinput
LTNAME=eksctl-"${EKSCLUSTERNAME}"-nodegroup-ng-1
LTDESCRIPTION=FleetIQ_GameServerGroup_LT
VOLUMESIZE=80
VOLUMETYPE="gp2"
GAMELIFTSERVERGROUPROLENAME=GameLiftServerGroupRole
GAMESERVERGROUPFILENAME=gsgconfig
GSGMINSIZE=1
GSGMAXSIZE=10
GSGINSTANCEDEFINITIONS='[{'\"'InstanceType'\"': '\"'c4.large'\"','\"'WeightedCapacity'\"': '\"'2'\"'},{'\"'InstanceType'\"': '\"'c4.2xlarge'\"','\"'WeightedCapacity'\"': '\"'1'\"'}]'
GSGNAME=agones-game-server-group-01
CAPOLICYFILENAME=capolicy
CAPOLICYNAME=cluster-autoscaler-policy
CAMANIFESTFILENAME=camanifest
GAMELIFTDAEMONPOLICYFILENAME=gameliftdaemonpolicy
GAMELIFTDAEMONPOLICYNAME=gamelift-daemon-policy
GAMELIFTDAEMONSERVICEACCOUNTNAME=gamelift-daemonset

# FleetIQ-EKS-Agones Integration Part 1: Environment setup and K8s tools installation

echo "Installing Kubernetes tools"

echo "[1/22] Installing kubectl"

sudo curl --silent --location -o /usr/local/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl

echo "[2/22] Updating awscli"

sudo pip install --upgrade awscli && hash -r

echo "[3/22] Installing jq, envsubst and bash completion"

sudo yum -y install jq gettext bash-completion moreutils

echo "[4/22] Verifying that binaries are in path of the executable"

for command in kubectl jq envsubst aws
do
which $command &>/dev/null && echo "$command in path" || echo "$command NOT FOUND"
done

echo "Part 1 complete."

# FleetIQ-EKS-Agones Integration Part 2: Environment setup and K8s tools installation

echo "[5/22] Ensure AWS region is set in configuration"

export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

echo "[6/22] Dowloading eksctl"

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin

echo $(eksctl version)
#eksctl completion bash >> ~/.bash_completion
#. /etc/profile.d/bash_completion.sh
#. ~/.bash_completion

echo "[7/22] Create FleetIQ read policy"

# echo $(aws iam create-policy --policy-name ${FLEETIQREADPOLICYNAME} --policy-document '{"Version": "2012-10-17","Statement": [{"Sid": "VisualEditor0","Effect": "Allow","Action": ["gamelift:DescribeGameServerGroup","gamelift:DescribeGameServerInstances","gamelift:DescribeGameServer"],"Resource": "*"}]}')

# IAM tends to be verbose about resources existing which can lead to interesting variable values, so we're checking if these resources exist first
TESTEXISTS=$((aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${FLEETIQREADPOLICYNAME} | jq '.Policy.Arn') 2>&1)
TESTARN='"'arn:aws:iam::${ACCOUNT_ID}:policy/${FLEETIQREADPOLICYNAME}'"'
if [ "${TESTEXISTS}" = "${TESTARN}" ]
then
  echo "Policy already exists, reusing existing policy"
else
  FLEETIQROLEPOLICYARN=$((aws iam create-policy --policy-name ${FLEETIQREADPOLICYNAME} --policy-document '{"Version": "2012-10-17","Statement": [{"Sid": "VisualEditor0","Effect": "Allow","Action": ["gamelift:DescribeGameServerGroup","gamelift:DescribeGameServerInstances","gamelift:DescribeGameServer"],"Resource": "*"}]}' | jq '.Policy.Arn') 2>&1)
fi
echo "[8/22] Create deployment file"

cat << EOF > ${CLUSTERCONFIGFILENAME}.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKSCLUSTERNAME}
  region: ${AWS_REGION}
  version: "1.18"

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
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
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
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        - arn:aws:iam::${ACCOUNT_ID}:policy/${FLEETIQREADPOLICYNAME}
EOF

echo "[9/22] Creating EKS cluster (this will take ~15 minutes)"

eksctl create cluster -f ${CLUSTERCONFIGFILENAME}.yaml

echo "Part 2 complete."

# FleetIQ-EKS-Agones Integration Part 3: Cluster configuration

echo "[10/22] Creating Launch Template User Data"

NG_STACK=$(aws cloudformation describe-stacks --region ${AWS_REGION}| jq -r '.Stacks[] | .StackId' | grep ${NODEGROUP0NAME})

LAUNCH_TEMPLATE_ID=$(aws cloudformation describe-stack-resources --region ${AWS_REGION} --stack-name $NG_STACK \
| jq -r '.StackResources | map(select(.LogicalResourceId == "NodeGroupLaunchTemplate")
| .PhysicalResourceId)[0]')

aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID \
| jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
| base64 -d | gunzip > ${BASEUSERDATAFILENAME}.yaml

awk -v var="$(grep -n NODE_LABELS=alpha ./${BASEUSERDATAFILENAME}.yaml | cut -d : -f 1)" 'NR==var {$0="    NODE_LABELS=alpha.eksctl.io/cluster-name='$EKSCLUSTERNAME',alpha.eksctl.io/nodegroup-name=game-servers,role=game-servers"} 1' ${BASEUSERDATAFILENAME}.yaml > templt.yaml
awk -v var="$(grep -m1 -n NODE_TAINTS= ./${BASEUSERDATAFILENAME}.yaml | cut -d : -f 1)" 'NR==var {$0="    NODE_TAINTS=agones.dev/gameservers=true:NoExecute"} 1' templt.yaml > ${MODIFIEDUSERDATAFILENAME}.yaml
rm templt.yaml
base64 -w 0 ${MODIFIEDUSERDATAFILENAME}.yaml > ${B64USERDATAFILENAME}

echo "[11/22] Creating the Launch Template"

VPCID=$((aws ec2 describe-vpcs --region ${AWS_REGION} --filter Name=tag:alpha.eksctl.io/cluster-name,Values=${EKSCLUSTERNAME} | jq -r '.Vpcs[0].VpcId') 2>&1)
echo ${VPCID}

SGID=$((aws ec2 create-security-group --description ${SGDESCRIPTION} --group-name ${SGNAME} --vpc-id ${VPCID} | jq -r '.GroupId') 2>&1)
echo ${SGID}

SGINGRESSRULES=$((aws ec2 describe-security-groups --region ${AWS_REGION} --filter Name=tag:alpha.eksctl.io/nodegroup-name,Values=${NODEGROUP0NAME} | jq '.SecurityGroups[0].IpPermissions') 2>&1)
echo ${SGINGRESSRULES}

echo '{"GroupId":"'$SGID'","IpPermissions":'$SGINGRESSRULES'}' > $SGINGRESSRULESFILENAME.json
aws ec2 authorize-security-group-ingress --cli-input-json file://${SGINGRESSRULESFILENAME}.json --region ${AWS_REGION}

aws ec2 authorize-security-group-ingress --group-id ${SGID} --ip-permissions FromPort=7000,IpProtocol="udp",IpRanges=[{CidrIp="0.0.0.0/0"}],ToPort=8000 --region ${AWS_REGION}

IAMINSTANCEPROFILE=$((aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID | jq '.LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Arn') 2>&1)
echo ${IAMINSTANCEPROFILE}

NG0SG1=$((aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID | jq '.LaunchTemplateVersions[0].LaunchTemplateData.NetworkInterfaces[0].Groups[0]') 2>&1)
echo ${NG0SG1}

NG0SG2=$((aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID | jq '.LaunchTemplateVersions[0].LaunchTemplateData.NetworkInterfaces[0].Groups[1]') 2>&1)
echo ${NG0SG2}

NG0AMI=$((aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID | jq '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId') 2>&1)
echo ${NG0AMI}

B64USERDATA=$(cat ${B64USERDATAFILENAME})
echo ${B64USERDATA}

cat << EOF > ${LTINPUTFILENAME}.json
{
"LaunchTemplateName": "${LTNAME}",
"VersionDescription": "${LTDESCRIPTION}",
"LaunchTemplateData": {
"EbsOptimized": true,
"IamInstanceProfile": {
"Arn": ${IAMINSTANCEPROFILE}
},
"BlockDeviceMappings": [
{
"DeviceName": "/dev/xvda",
"Ebs": {
"Encrypted": false,
"DeleteOnTermination": true,
"VolumeSize": ${VOLUMESIZE},
"VolumeType": "${VOLUMETYPE}"
}
}
],
"NetworkInterfaces": [
{
"DeviceIndex": 0,
"Groups": [
${NG0SG1},
${NG0SG2},
"${SGID}"
]
}
],
"ImageId": $NG0AMI,
"Monitoring": {
"Enabled": true
},
"UserData": "${B64USERDATA}",
"TagSpecifications": [
{
"ResourceType": "instance",
"Tags": [
{
"Key": "kubernetes.io/cluster/${EKSCLUSTERNAME}",
"Value": "owned"
},
{
"Key": "k8s.io/cluster-autoscaler/${EKSCLUSTERNAME}",
"Value": "enabled"
},
{
"Key": "Name",
"Value": "FleetIQ"
}
]
}
],
"MetadataOptions": {
"HttpTokens": "optional",
"HttpPutResponseHopLimit": 2
}
}
}
EOF

GSGLTID=$((aws ec2 create-launch-template --cli-input-json file://${LTINPUTFILENAME}.json --region ${AWS_REGION} | jq '.LaunchTemplate.LaunchTemplateId') 2>&1)

echo "[12/22] Creating the FleetIQ Service Role"

#GSGROLEARN=$(( aws iam create-role --role-name ${GAMELIFTSERVERGROUPROLENAME} --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["gamelift.amazonaws.com","autoscaling.amazonaws.com"]},"Action":"sts:AssumeRole"}]}' | jq '.Role.Arn' ) 2>&1)

# IAM tends to be verbose about resources existing which can lead to interesting variable values, so we're checking if these resources exist first
ROLETESTEXISTS=$((aws iam get-role --role-name ${GAMELIFTSERVERGROUPROLENAME} | jq '.Role.Arn') 2>&1)
ROLETESTARN='"'arn:aws:iam::${ACCOUNT_ID}:role/${GAMELIFTSERVERGROUPROLENAME}'"'
if [ "${ROLETESTEXISTS}" = "${ROLETESTARN}" ]
then
  echo "Role already exists, reusing existing role"
else
  GSGROLEARN=$(( aws iam create-role --role-name ${GAMELIFTSERVERGROUPROLENAME} --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["gamelift.amazonaws.com","autoscaling.amazonaws.com"]},"Action":"sts:AssumeRole"}]}' | jq '.Role.Arn' ) 2>&1)
fi

aws iam attach-role-policy --role-name ${GAMELIFTSERVERGROUPROLENAME} --policy-arn arn:aws:iam::aws:policy/GameLiftGameServerGroupPolicy

echo "[13/22]Creating the FleetIQ Game Server Group"

PUBLICSUBNETIDS=$((aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPCID --region ${AWS_REGION} | jq '[.Subnets[] | {subnetid: .SubnetId, mapPublicIP: .MapPublicIpOnLaunch}]' | jq 'group_by(.mapPublicIP)' | jq '[.[1][].subnetid]') 2>&1)
echo ${PUBLICSUBNETIDS}

cat << EOF > ${GAMESERVERGROUPFILENAME}.json
{
"GameServerGroupName": "${GSGNAME}",
"RoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/${GAMELIFTSERVERGROUPROLENAME}",
"MinSize": ${GSGMINSIZE},
"MaxSize": ${GSGMAXSIZE},
"LaunchTemplate": {
"LaunchTemplateId": ${GSGLTID},
"Version": "1"
},
"InstanceDefinitions": ${GSGINSTANCEDEFINITIONS},
"BalancingStrategy": "SPOT_PREFERRED",
"GameServerProtectionPolicy": "FULL_PROTECTION",
"VpcSubnets": ${PUBLICSUBNETIDS}
}
EOF

aws gamelift create-game-server-group --region ${AWS_REGION} --cli-input-json file://${GAMESERVERGROUPFILENAME}.json

GSGSTATUS=$((aws gamelift describe-game-server-group --game-server-group-name ${GSGNAME} --region $AWS_REGION | jq '.GameServerGroup.Status') 2>&1)
echo ${GSGSTATUS}

while [ $GSGSTATUS != "\""ACTIVE"\"" ]
do
  echo "Waiting for Game Server Group autoscaling group to become active..."
  sleep 10
  GSGSTATUS=$((aws gamelift describe-game-server-group --game-server-group-name ${GSGNAME} --region $AWS_REGION | jq '.GameServerGroup.Status') 2>&1)
done

echo "[14/22] Tagging underlying AutoScaling Group"

aws autoscaling create-or-update-tags --tags ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/${EKSCLUSTERNAME},Value=owned,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/${EKSCLUSTERNAME},Value=enabled,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=Name,Value=FleetIQ,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true --region ${AWS_REGION}

echo "[15/22] Creating OIDC endpoint for cluster"

eksctl utils associate-iam-oidc-provider --cluster ${EKSCLUSTERNAME} --approve

echo "[16/22] Creating Cluster Autoscaler Policy and Service Account/IAM role mapping"

cat << EOF > ${CAPOLICYFILENAME}.json
{
"Version": "2012-10-17",
"Statement": [
{
"Effect": "Allow",
"Action": [
"autoscaling:DescribeAutoScalingGroups",
"autoscaling:DescribeAutoScalingInstances",
"autoscaling:DescribeLaunchConfigurations",
"autoscaling:DescribeTags",
"autoscaling:SetDesiredCapacity",
"autoscaling:TerminateInstanceInAutoScalingGroup"
],
"Resource": "*"
}
]
}
EOF

#aws iam create-policy --policy-name ${CAPOLICYNAME} --policy-document file://${CAPOLICYFILENAME}.json

# IAM tends to be verbose about resources existing which can lead to interesting variable values, so we're checking if these resources exist first
TESTCAEXISTS=$((aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${CAPOLICYNAME} | jq '.Policy.Arn') 2>&1)
TESTCAARN='"'arn:aws:iam::${ACCOUNT_ID}:policy/${CAPOLICYNAME}'"'
if [ "${TESTCAEXISTS}" = "${TESTCAARN}" ]
then
  echo "Policy already exists, reusing existing policy"
else
  aws iam create-policy --policy-name ${CAPOLICYNAME} --policy-document file://${CAPOLICYFILENAME}.json
fi

eksctl create iamserviceaccount --cluster ${EKSCLUSTERNAME} --namespace kube-system --name cluster-autoscaler --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${CAPOLICYNAME} --approve

echo "[17/22] Creating Cluster Autoscaler Manifest and apply to cluster"

cat << EOF > ${CAMANIFESTFILENAME}.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "update"]
  - apiGroups: [""]
    resources:
      - "pods"
      - "services"
      - "replicationcontrollers"
      - "persistentvolumeclaims"
      - "persistentvolumes"
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create","list","watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs: ["delete", "get", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: 'false'
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '8085'
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.18.3
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --expander=priority
            - --nodes=0:10:gamelift-gameservergroup-${GSGNAME}
            - --balance-similar-node-groups
            - --skip-nodes-with-system-pods=false
          env:
            - name: AWS_REGION
              value: ${AWS_REGION}
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          imagePullPolicy: "Always"
      volumes:
        - name: ssl-certs
          hostPath:
            path: "/etc/ssl/certs/ca-bundle.crt"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |-
    10:
      - .*-non-existing-entry.*
    20:
      - gamelift-gameservergroup-${GSGNAME}
EOF


kubectl apply -f ${CAMANIFESTFILENAME}.yaml

echo "[18/22] Installing Helm"

curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

helm version --short

echo "[19/22] Configuring GameLift-Daemonset service account"

cat << EOF > ${GAMELIFTDAEMONPOLICYFILENAME}.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "gamelift:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

#aws iam create-policy --policy-name ${GAMELIFTDAEMONPOLICYNAME} --policy-document file://${GAMELIFTDAEMONPOLICYFILENAME}.json

# IAM tends to be verbose about resources existing which can lead to interesting variable values, so we're checking if these resources exist first
TESTGLEXISTS=$((aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${GAMELIFTDAEMONPOLICYNAME} | jq '.Policy.Arn') 2>&1)
TESTGLARN='"'arn:aws:iam::${ACCOUNT_ID}:policy/${GAMELIFTDAEMONPOLICYNAME}'"'
if [ "${TESTGLEXISTS}" = "${TESTGLARN}" ]
then
  echo "Policy already exists, reusing existing policy"
else
  aws iam create-policy --policy-name ${GAMELIFTDAEMONPOLICYNAME} --policy-document file://${GAMELIFTDAEMONPOLICYFILENAME}.json
fi

eksctl create iamserviceaccount --cluster ${EKSCLUSTERNAME} --name ${GAMELIFTDAEMONSERVICEACCOUNTNAME} --namespace kube-system --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${GAMELIFTDAEMONPOLICYNAME} --override-existing-serviceaccounts --approve

echo "[20/22] Pulling the Helm chart from ECR and installation"

export HELM_EXPERIMENTAL_OCI=1
COMMONREGISTRYURL=820537372947.dkr.ecr.us-west-2.amazonaws.com
COMMONREGISTRYNAME=gamelift-common-services
COMMONREGISTRYVERSION=0.1.0
DAEMONSETREGISTRYURL=820537372947.dkr.ecr.us-west-2.amazonaws.com
DAEMONSETREGISTRYNAME=gamelift-daemon
DAEMONSETREGISTRYVERSION=0.1.1


aws ecr get-login-password --region us-west-2 | helm registry login --username AWS --password-stdin ${DAEMONSETREGISTRYURL}

helm chart pull ${DAEMONSETREGISTRYURL}/${DAEMONSETREGISTRYNAME}:${DAEMONSETREGISTRYVERSION}
helm chart pull ${COMMONREGISTRYURL}/${COMMONREGISTRYNAME}:${COMMONREGISTRYVERSION}

helm chart export ${DAEMONSETREGISTRYURL}/${DAEMONSETREGISTRYNAME}:${DAEMONSETREGISTRYVERSION}
helm chart export ${COMMONREGISTRYURL}/${COMMONREGISTRYNAME}:${COMMONREGISTRYVERSION}

helm install --set aws.region=${AWS_REGION} gamelift-common-services ./gamelift-common-services/
helm install --set aws.region=${AWS_REGION} --set gameliftDaemon.serviceAccount=${GAMELIFTDAEMONSERVICEACCOUNTNAME} --set gameliftDaemon.gameServerGroupName=${GSGNAME} gamelift-daemonset ./gamelift-daemonset/


echo "Part 3 complete."

# FleetIQ-EKS-Agones Integration Part 4: Agones installation and configuration

echo "[21/22] Installing Agones using Helm"

helm repo add agones https://agones.dev/chart/stable

helm install my-release --namespace agones-system --create-namespace agones/agones

echo "[22/22] Creating Agones Fleet"

cat << EOF > agonesfleetconfig.yaml
kind: Fleet
apiVersion: agones.dev/v1
metadata:
  annotations:
    agones.dev/sdk-version: 1.8.0
  name: stk-fleet
  namespace: default
spec:
  replicas: 5
  scheduling: Packed
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: stk
    spec:
      health:
        failureThreshold: 3
        initialDelaySeconds: 30
        periodSeconds: 10
      ports:
        - containerPort: 8080
          name: default
          portPolicy: Dynamic
      sdkServer: {}
      template:
        metadata: {}
        spec:
          containers:
            - command:
                - /start.sh
              env:
                - name: WAIT_TO_PLAYERS
                  value: '120'
                - name: FREQ_CHECK_SESSION
                  value: '10'
                - name: NUM_IDLE_SESSION
                  value: '5'
                - name: SHARED_FOLDER
                  value: /sharedata
                - name: WAIT_TO_PLAYERS
                  value: '120'
                - name: GAME_SERVER_GROUP_NAME
                  value: ${GSGNAME}
                - name: GAME_MODE
                  value: "1"
                - name: POD_NAME
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.name
                - name: NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
              image: '163538056407.dkr.ecr.us-west-2.amazonaws.com/stk:0.4'
              imagePullPolicy: Always
              lifecycle:
                preStop:
                  exec:
                    command:
                      - /bin/sh
                      - '-c'
                      - /pre-stop.sh
              name: stk
              resources: {}
          nodeSelector:
            role: game-servers
          tolerations:
            - effect: NoExecute
              key: agones.dev/gameservers
              operator: Equal
              value: 'true'
            - effect: NoExecute
              key: gamelift.status/active
              operator: Equal
              value: 'true'
          volumes:
            - emptyDir: {}
              name: shared-data
EOF

echo "Waiting for service startup..."
sleep 30

kubectl apply -f agonesfleetconfig.yaml

echo "Part 4 complete."
