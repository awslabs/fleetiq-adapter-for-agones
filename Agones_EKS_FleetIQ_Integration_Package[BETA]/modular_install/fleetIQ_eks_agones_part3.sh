#!/bin/bash

# FleetIQ-EKS-Agones Integration Part 3: Cluster configuration

#Script variables
BASEUSERDATAFILENAME=launchtemplate
MODIFIEDUSERDATAFILENAME=modlaunchtemplate
B64USERDATAFILENAME=b64modlaunchtemplate
SGDESCRIPTION=Agones_nodegroup_SG
SGNAME=eksctl-"${EKSCLUSTERNAME}"-nodegroup-ng-2-SG
SGINGRESSRULESFILENAME=sgingress
LTINPUTFILENAME=ltinput
LTNAME=eksctl-"${EKSCLUSTERNAME}"-nodegroup-ng-2
LTDESCRIPTION=FleetIQ_GameServerGroup_LT
VOLUMESIZE=80
VOLUMETYPE="gp2"
GAMELIFTSERVERGROUPROLENAME=GameLiftServerGroupRole
GAMESERVERGROUPFILENAME=gsgconfig
GSGMINSIZE=1
GSGMAXSIZE=10
GSGINSTANCEDEFINITIONS='[{'\"'InstanceType'\"': '\"'c4.large'\"','\"'WeightedCapacity'\"': '\"'2'\"'},{'\"'InstanceType'\"': '\"'c4.2xlarge'\"','\"'WeightedCapacity'\"': '\"'1'\"'}]'
GSGNAME=agones-game-servers
CAPOLICYFILENAME=capolicy
CAPOLICYNAME=cluster-autoscaler-policy
CAMANIFESTFILENAME=camanifest
GAMELIFTDAEMONPOLICYFILENAME=gameliftdaemonpolicy
GAMELIFTDAEMONPOLICYNAME=gamelift-daemon-policy
GAMELIFTDAEMONSERVICEACCOUNTNAME=gamelift-daemonset

echo "[1/11] Creating Launch Template User Data"

NG_STACK=$(aws cloudformation describe-stacks --region ${AWS_REGION}| jq -r '.Stacks[] | .StackId' | grep ${NODEGROUP0NAME})

LAUNCH_TEMPLATE_ID=$(aws cloudformation describe-stack-resources --region ${AWS_REGION} --stack-name $NG_STACK \
| jq -r '.StackResources | map(select(.LogicalResourceId == "NodeGroupLaunchTemplate")
| .PhysicalResourceId)[0]')

aws ec2 describe-launch-template-versions --region ${AWS_REGION} --launch-template-id $LAUNCH_TEMPLATE_ID \
| jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
| base64 -d | gunzip > ${BASEUSERDATAFILENAME}.yaml

awk -v var="$(grep -n NODE_LABELS=alpha ./${BASEUSERDATAFILENAME}.yaml | cut -d : -f 1)" 'NR==var {$0="    NODE_LABELS=alpha.eksctl.io/cluster-name=agones,alpha.eksctl.io/nodegroup-name=game-servers,role=game-servers"} 1' ${BASEUSERDATAFILENAME}.yaml > templt.yaml
awk -v var="$(grep -n NODE_TAINTS= ./${BASEUSERDATAFILENAME}.yaml | cut -d : -f 1)" 'NR==var {$0="    NODE_TAINTS=agones.dev/gameservers=true:NoExecute"} 1' templt.yaml > ${MODIFIEDUSERDATAFILENAME}.yaml
rm templt.yaml
base64 -w 0 ${MODIFIEDUSERDATAFILENAME}.yaml > ${B64USERDATAFILENAME}

echo "[2/11] Creating the Launch Template"

VPCID=$((aws ec2 describe-vpcs --region ${AWS_REGION} --filter Name=tag:alpha.eksctl.io/cluster-name,Values=agones | jq -r '.Vpcs[0].VpcId') 2>&1)
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
"Key": "kubernetes.io/cluster/agones",
"Value": "owned"
},
{
"Key": "k8s.io/cluster-autoscaler/agones",
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

echo "[3/11] Creating the FleetIQ Service Role"

GSGROLEARN=$(( aws iam create-role --role-name ${GAMELIFTSERVERGROUPROLENAME} --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["gamelift.amazonaws.com","autoscaling.amazonaws.com"]},"Action":"sts:AssumeRole"}]}' | jq '.Role.Arn' ) 2>&1)
echo ${GSGROLEARN}

aws iam attach-role-policy --role-name ${GAMELIFTSERVERGROUPROLENAME} --policy-arn arn:aws:iam::aws:policy/GameLiftGameServerGroupPolicy

echo "[4/11]Creating the FleetIQ Game Server Group"

PUBLICSUBNETIDS=$((aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPCID --region ${AWS_REGION} | jq '[.Subnets[] | {subnetid: .SubnetId, mapPublicIP: .MapPublicIpOnLaunch}]' | jq 'group_by(.mapPublicIP)' | jq '[.[1][].subnetid]') 2>&1)
echo ${PUBLICSUBNETIDS}

cat << EOF > ${GAMESERVERGROUPFILENAME}.json
{
"GameServerGroupName": "${GSGNAME}",
"RoleArn": ${GSGROLEARN},
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

echo "[5/11] Tagging underlying AutoScaling Group"

aws autoscaling create-or-update-tags --tags ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/agones,Value=owned,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/agones,Value=enabled,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=Name,Value=FleetIQ,PropagateAtLaunch=true ResourceId=gamelift-gameservergroup-${GSGNAME},ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true --region ${AWS_REGION}

echo "[6/11] Creating OIDC endpoint for cluster"

eksctl utils associate-iam-oidc-provider --cluster ${EKSCLUSTERNAME} --approve

echo "[7/11] Creating Cluster Autoscaler Policy and Service Account/IAM role mapping"

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

aws iam create-policy --policy-name ${CAPOLICYNAME} --policy-document file://${CAPOLICYFILENAME}.json

eksctl create iamserviceaccount --cluster ${EKSCLUSTERNAME} --namespace kube-system --name cluster-autoscaler --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${CAPOLICYNAME} --approve

echo "[8/11] Creating Cluster Autoscaler Manifest and apply to cluster"

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
        - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.16.5
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
            - --expander=least-waste
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/agones
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
EOF

kubectl apply -f ${CAMANIFESTFILENAME}.yaml

echo "[9/11] Installing Helm"

curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

helm version --short

echo "[10/11] Configuring GameLift-Daemonset service account"

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

aws iam create-policy --policy-name ${GAMELIFTDAEMONPOLICYNAME} --policy-document file://${GAMELIFTDAEMONPOLICYFILENAME}.json

eksctl create iamserviceaccount --cluster ${EKSCLUSTERNAME} --name ${GAMELIFTDAEMONSERVICEACCOUNTNAME} --namespace kube-system --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${GAMELIFTDAEMONPOLICYNAME} --override-existing-serviceaccounts --approve

echo "[11/11] Pulling the Helm chart from ECR and installation"

export HELM_EXPERIMENTAL_OCI=1
DAEMONSETREGISTRYURL=820537372947.dkr.ecr.us-west-2.amazonaws.com
DAEMONSETREGISTRYNAME=gamelift-daemon
DAEMONSETREGISTRYVERSION=0.1.0

aws ecr get-login-password --region us-west-2 | helm registry login --username AWS --password-stdin ${DAEMONSETREGISTRYURL}

helm chart pull ${DAEMONSETREGISTRYURL}/${DAEMONSETREGISTRYNAME}:${DAEMONSETREGISTRYVERSION}

helm chart export ${DAEMONSETREGISTRYURL}/${DAEMONSETREGISTRYNAME}:${DAEMONSETREGISTRYVERSION}

helm install --set aws.region=${AWS_REGION} --set gameliftDaemon.serviceAccount=${GAMELIFTDAEMONSERVICEACCOUNTNAME} --set gameServerGroupName=${GSGNAME} gamelift-daemonset ./gamelift-daemonset/

echo "Part 3 complete."
