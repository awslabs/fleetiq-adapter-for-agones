## Introduction

This project allows you to run containerized game servers on Spot instances while decreasing the likelihood of Spot interruptions. Interruptions are minimized by using [Gamelift FleetIQ](https://docs.aws.amazon.com/gamelift/latest/fleetiqguide/gsg-intro.html) which will periodically adjust the instance types used by an AWS Autoscaling Group (ASG) using an algorithm that assesses an instance's viability. Additionally, instances with [claimed](https://docs.aws.amazon.com/gamelift/latest/apireference/API_ClaimGameServer.html) game servers are temporarily protected from termination.

## Components
### Agones

### The daemonset

### The pubsub application

* Change the title in this README
* Edit your repository description on GitHub

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.

