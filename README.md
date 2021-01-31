## Introduction

This project allows you to run containerized game servers on Spot instances while decreasing the likelihood of Spot interruptions. Interruptions are minimized by using [Gamelift FleetIQ](https://docs.aws.amazon.com/gamelift/latest/fleetiqguide/gsg-intro.html) which periodically adjusts the instance types used by an AWS Autoscaling Group (ASG) using an algorithm that assesses an instance's viability. Instances with [claimed](https://docs.aws.amazon.com/gamelift/latest/apireference/API_ClaimGameServer.html) game servers are temporarily protected from termination.

## Components
### Agones
[Agones](https://agones.dev/site/) provides lifecycle management operations for running containerized game servers on Kubernetes. This project was specifically designed to work with Agones running on Amazon EKS or a self-managed Kubernetes cluster running in the AWS Cloud.

### The daemonset
The daemonset is an "agent" that runs on worker nodes that have been designated to run containerized game servers, i.e. instances with the `role=game-servers` label. On EKS, labels can be automatically added to instances by modifying the kubelet parametes in the instance's [user data](https://aws.amazon.com/blogs/opensource/improvements-eks-worker-node-provisioning/) or by modifying the launch template referenced by the ASG for the game server node group. 

When the daemonset starts, it immediately registers the instance with Gamelift FleetIQ, runs [ClaimGameServer](https://docs.aws.amazon.com/gamelift/latest/apireference/API_ClaimGameServer.html), and calls [UpdateGameServer](https://docs.aws.amazon.com/gamelift/latest/apireference/API_UpdateGameServer.html#API_UpdateGameServer_RequestSyntax) 1x per minute thereafter to maintain the instance's health. It also starts polling a Redis channel for the instance's viability. When an instance's status changes from `ACTIVE` to `DRAINING`, the daemon cordons the node to prevent new game servers from being scheduled onto the node. Then it adds a toleration to all [allocated](https://agones.dev/site/docs/guides/client-sdks/#allocate) game servers. Afterwards, it taints the node, forcing pods that do not have a toleration for the taint, i.e. un-allocated game servers, to be evicted. When the last allocated game server is [shutdown](https://agones.dev/site/docs/guides/client-sdks/#shutdown), the daemon calls [DeregisterGameServer](https://docs.aws.amazon.com/gamelift/latest/apireference/API_DeregisterGameServer.html) which deregisters the instance from FleetIQ and waits for the instance to be terminated.

### The pubsub application
The pubsub application runs a loop that calls [DescribeGameServerInstances](https://docs.aws.amazon.com/gamelift/latest/apireference/API_DescribeGameServerInstances.html), parses the results, and publishes the status for each instance to a Redis channel for that instance. Although we could have built the daemon to call `DescribeGameServerInstances` directly, we chose to use a pub/sub model to avoid exceeded the rate limit for the Gamelift APIs. 

The pubsub application supports _n_ [game server groups](https://docs.aws.amazon.com/gamelift/latest/fleetiqguide/gsg-integrate-gameservergroup.html). On startup, the application reads the list of game server groups from the `fleetiqconfig` ConfigMap. 

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: fleetiqconfig
  namespace: default
data:
  fleetiq.conf: '{"GameServerGroups": [ "agones-game-servers" ]}'
```

The instructions for installing the pubsub application, along with Redis, can be found [here](https://github.com/awslabs/fleetiq-adapter-for-agones/tree/master/pubsub). 

> The pubsub application and Redis should be installed prior to the gamelift daemon.

### Redis
Redis is used to publish `InstanceStatus` to a channel for each instance. We elected to use Redis instead of SNS to avoid taking a dependency on another AWS service. That said, you can use Redis ElastiCache as your Redis endpoint or you can choose to run it locally in your Kubernetes cluster. The Redis endpoint can be configured by updating the `REDIS_URL` environment variable for the pubsub application and the daemonset.

## Installation
Please follow the instructions in the [FleetIQ ESK Agones Integration Guide](https://github.com/awslabs/fleetiq-adapter-for-agones/blob/master/Agones_EKS_FleetIQ_Integration_Package%5BBETA%5D/FleetIQ%20EKS%20Agones%20Integration%20Guide%20%5BBETA%5D.docx) to install the solution. 

> We recommend that you build the images for the daemonset and the pubsub application from the Dockerfiles in this repository. Be aware that you will need to update the daemonset and deployment manifests with the appropriate image URIs if you do. Both charts allow you to override the defaults for image and tag with your own values. 

## Issues
If you have an issue with the Guide or with any of the solution's components, please file an [issue](https://github.com/awslabs/fleetiq-adapter-for-agones/issues/new/choose). 

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.

