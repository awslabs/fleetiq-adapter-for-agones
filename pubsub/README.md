## Installing the pubsub application
### Using Helm v3
The pubsub application, along with Redis, can be installed by applying the chart in the [helm-chart](https://github.com/awslabs/fleetiq-adapter-for-agones/tree/master/pubsub/helm-chart) directory. If you didn't clone this repository, you can pull this chart from an ECR registry by running the following commands:

Log in to ECR:
```
aws ecr get-login-password --region us-west-2 | helm registry login --username AWS --password-stdin 820537372947.dkr.ecr.us-west-2.amazonaws.com
```
Pull the chart down from the repository: 
```
helm chart pull 820537372947.dkr.ecr.us-west-2.amazonaws.com/gamelift-common-services:0.1.0
```
Export the chart to a directory:
```
helm chart export 820537372947.dkr.ecr.us-west-2.amazonaws.com/gamelift-common-services:0.1.0
```
Install the chart:
```
helm install \
--set aws.region=${AWS_REGION} \
gamelift-common-services ./gamelift-common-services/
```
> If the pod crashes, verify your Game Server Groups appear in the fleetiqconfig ConfigMap. 
