## Introduction

This project allows you to run containerized game servers on Spot instances while decreasing the likelihood of Spot interruptions. Interruptions are minimized by using [Gamelift FleetIQ](https://docs.aws.amazon.com/gamelift/latest/fleetiqguide/gsg-intro.html) which will periodically adjust the instance types used by an AWS Autoscaling Group (ASG) using an algorithm that assesses an instance's viability. Instances with [claimed](https://docs.aws.amazon.com/gamelift/latest/apireference/API_ClaimGameServer.html) game servers are temporarily protected from termination.

## Components
### Agones
[Agones](https://agones.dev/site/) provides lifecycle management operations for running containerized game servers on Kubernetes. This project was specifically designed to work with Agones running on Amazon EKS or a self-managed Kubernetes cluster running in AWS Cloud.

### The daemonset
The daemonset is an "agent" that runs on worker nodes that have been designated to run containerized game servers, i.e. instances with the `role=game-servers` label. On EKS, labels can be automatically added to instances by modifying the kubelet parametes in the instance's [user data](https://aws.amazon.com/blogs/opensource/improvements-eks-worker-node-provisioning/) or by modifying the launch template referenced by the ASG for the game server node group. When the daemonset starts, it immediately registers the instance with Gamelift FleetIQ, runs ClaimGameServer, and calls [UpdateGameServer](https://docs.aws.amazon.com/gamelift/latest/apireference/API_UpdateGameServer.html#API_UpdateGameServer_RequestSyntax) 1x per minute thereafter to keep the instance healthy. 

### The pubsub application

* Change the title in this README
* Edit your repository description on GitHub

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.

