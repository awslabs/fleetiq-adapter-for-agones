## Install gamelift daemonset

The instructions for installing the gamelift daemonset can be found in the [FleetIQ Agones Installation Guides](https://github.com/awslabs/fleetiq-adapter-for-agones/tree/master/Agones_EKS_FleetIQ_Integration_Package%5BBETA%5D). Be sure to create the IAM role and k8s ServiceAccount for the gamelift daemonset before installing the chart, otherwise the daemon will fail to start. The daemon and its ServiceAccount should be created in the kube-system namespace.  
