#!/usr/bin/env python3
import asyncio, boto3, json, random, requests, os, signal, sys 
from time import sleep

from kubernetes import client, config
from kubernetes.client.rest import ApiException

import click
import redis 
from ec2_metadata import ec2_metadata

# Global variables
gamelift = boto3.client('gamelift', region_name=os.getenv('AWS_REGION'))
ec2 = boto3.client('autoscaling', region_name=os.getenv('AWS_REGION'))
r = redis.from_url('redis://' + os.getenv('REDIS_URL')) # move to cmdline flag?
config.load_incluster_config()
core_v1_client = client.CoreV1Api()
custom_obj_client = client.CustomObjectsApi()
instance_id = ec2_metadata.instance_id
game_server_id = instance_id
game_server_group_name = os.getenv('GAME_SERVER_GROUP_NAME') # move to cmdline flag?
grace_period = 30
loop = asyncio.get_event_loop()

def drain_pods():
    """This method evicts all Kubernetes pods from the specified node that are not in the kube-system namespace."""
    field_selector = 'spec.nodeName=' + ec2_metadata.private_hostname
    try:
        pods = core_v1_client.list_pod_for_all_namespaces(watch=False, field_selector=field_selector)
    except ApiException as e:
        print(f'Exception when calling CoreV1Api->list_pod_for_all_namespaces: {e}\n', flush=True)
    # Create a filtered list of pods not in the kube-system namespace
    filtered_pods = filter(lambda x: x.metadata.namespace != 'kube-system', pods.items)

    for pod in filtered_pods:
        print(f'Deleting pod {pod.metadata.name} in namespace {pod.metadata.namespace}', flush=True)
        if 'grace_period' in globals():
            body = {
                'apiVersion': 'policy/v1beta1',
                'kind': 'Eviction',
                'metadata': {
                    'name': pod.metadata.name,
                    'namespace': pod.metadata.namespace,
                    'grace_period_seconds': grace_period
                }
            }
        else:
            body = {
                'apiVersion': 'policy/v1beta1',
                'kind': 'Eviction',
                'metadata': {
                    'name': pod.metadata.name,
                    'namespace': pod.metadata.namespace
                }
            }
        try:
            core_v1_client.create_namespaced_pod_eviction(pod.metadata.name, pod.metadata.namespace, body)
        except ApiException as e:
            print(f'Exception when calling CoreV1Api->create_namespaced_pod_eviction: {e}\n', flush=True)

async def cordon_and_protect():
    """This method cordons the node, adds an toleration to all of the Agones game servers that are currently in an Allocated
    state, and then adds a taint to the node that evits pods the don't tolerate the taint."""
    cordon_body = {
        "spec": {
            "unschedulable": True
        }
    }
    # Cordon the node so no new game servers are scheduled onto the instance
    try:
        core_v1_client.patch_node(ec2_metadata.private_hostname, cordon_body)
        print(f'Node {instance_id} has been cordoned', flush=True)
    except ApiException as e:
        print(f'Exception when calling CoreV1Api->patch_node: {e}\n', flush=True)
    
    toleration = {
        "effect": "NoExecute",
        "key": "gamelift.status/draining",
        "operator": "Equal",
        "value": "true"
    }
    
    try:
        custom_objs = custom_obj_client.list_cluster_custom_object(group='agones.dev', version='v1', plural='gameservers')
    except ApiException as e:
        print(f'Exception when calling CustomObjectsApi->list_cluster_custom_object: {e}\n', flush=True)
    game_servers = custom_objs['items']
    filtered_list = list(filter(lambda x: x['status']['state']=='Allocated' and x['status']['nodeName']==ec2_metadata.private_hostname, game_servers))
    for item in filtered_list:
        print(f"Updating {item['metadata']['name']} with toleration", flush=True)
        # Patch game server pod with toleration for DRAINING
        try:
            pods = core_v1_client.read_namespaced_pod(name=item['metadata']['name'], namespace=item['metadata']['namespace'])
        except ApiException as e:
            print(f'Exception when calling CoreV1Api->read_namespaced_pod: {e}\n', flush=True)
        tolerations = pods.spec.tolerations
        tolerations.append(toleration)
        toleration_body = {
            "spec": {
                "tolerations": tolerations
            }
        }
        try:
            core_v1_client.patch_namespaced_pod(name=item['metadata']['name'], namespace=item['metadata']['namespace'], body=toleration_body)
        except ApiException as e:
            print(f'Exception when calling CoreV1Api->patch_namespaced_pod: {e}\n', flush=True)
    
    # Change taint to DRAINING
    taint = {
        "key": "gamelift.status/draining",
        "value": "true",
        "effect": "NoExecute"
    }
    try: 
        node = core_v1_client.read_node(ec2_metadata.private_hostname)
    except ApiException as e:
        print(f'Exception when calling CoreV1Api->read_node: {e}\n', flush=True)
    taints = node.spec.taints
    taints.append(taint)
    taint_body = {
        "spec": {
            "taints": taints
        }
    }
    try:
        core_v1_client.patch_node(ec2_metadata.private_hostname, taint_body)
        print(f'Node {ec2_metadata.instance_id} has been tainted', flush=True)
    except ApiException as e:
        print(f'The node has already been tainted with the draining taint', flush=True)
    return True 

def termination_handler(GameServerGroupName: str, GameServerId: str):
    """This method calls the drain pods method to evict non-essential pods from the node
    and waits to receive the termination signal from EC2 metadata."""
    # This method is never called because the instance never receives a termination signal
    
    print('Shutting down', flush=True)
    # Drain pods from the instance
    drain_pods()

    # Wait for termination signal
    while ec2_metadata.spot_instance_action == None:
        print('Waiting for termination notification', flush=True)
        sleep(10)
    exit(0)

def initialize_game_server(GameServerGroupName: str, GameServerId: str, InstanceId: str):
    """This method registers the instance as a game server with Gamelift FleetIQ using the instance's Id as game server name.
    After registering the instance, it looks at result of DescribeAutoscalingInstances to see whether the instance is HEALTHY. 
    When HEALTHY, the instance is CLAIMED and its status is changed to UTILIZED. Finally, the taint gamelift.aws/status:ACTIVE,NoExecute
    is added to the node. Agones game servers need to have a toleration for this taint before they can run on this instance."""
    try:
        # Register game server instance
        print('Registering game server', flush=True)  
        gamelift.register_game_server(
            GameServerGroupName=GameServerGroupName,
            GameServerId=GameServerId,
            InstanceId=InstanceId
        )
    except gamelift.exceptions.ConflictException as error:
        print('The game server is already registered', flush=True)
        pass
    # Update the game server status to healthy
    # TODO(jicowan@amazon.com) Change this to use the new FleetIQ API DescribeGameServerInstances
    # TODO(jicowan@amazon.com) Consider using a decorator and backoff library to implement the backoff
    backoff = random.randint(1,5)
    while is_healthy(InstanceId) != 'HEALTHY':
        print(f'Instance is not healthy, re-trying in {backoff}', flush=True)
        sleep(backoff)
    print('Updating game server health', flush=True)
    gamelift.update_game_server(
        GameServerGroupName=GameServerGroupName,
        GameServerId=GameServerId,
        HealthCheck='HEALTHY'
    )
    
    # Claim the game server
    print('Claiming game server', flush=True)
    try: 
        gamelift.claim_game_server(
            GameServerGroupName=GameServerGroupName,
            GameServerId=GameServerId
        )
    except gamelift.exceptions.ConflictException as error: 
        print('The instance has already been claimed', flush=True)
    
    # Update game server status 
    print('Changing status to utilized', flush=True)
    gamelift.update_game_server(
        GameServerGroupName=GameServerGroupName,
        GameServerId=GameServerId,
        UtilizationStatus='UTILIZED'
    )
    
    # Adding taint to node
    # TODO(jicowan@amazon.com) Make tainting a node a separate method call because it's used multiple times.
    taint = {
        "key": "gamelift.status/active",
        "value": "true",
        "effect": "NoExecute"
    }
    try: 
        node = core_v1_client.read_node(ec2_metadata.private_hostname)
    except ApiException as e:
        print(f'Exception when calling CoreV1Api->read_node: {e}\n', flush=True)
    taints = node.spec.taints
    taints.append(taint)
    taint_body = {
        "spec": {
            "taints": taints
        }
    }
    try:
        core_v1_client.patch_node(ec2_metadata.private_hostname, taint_body)
        print(f'Node {InstanceId} has been tainted', flush=True)
    except ApiException as e:
        print(f'The node {InstanceId} has already been tainted', flush=True)

def is_healthy(InstanceId: str):
    """This method calls the DescribeAutoscalingInstance API to get the health status of the instance."""
    asg_instance = ec2.describe_auto_scaling_instances(
        InstanceIds=[
            InstanceId
        ]
    )
    instance_health = asg_instance['AutoScalingInstances'][0]['HealthStatus']
    print(f'The instance is {instance_health}', flush=True)
    return instance_health   

async def update_health_status(GameServerGroupName: str, GameServerId: str):
    while True:
        try: 
            gamelift.update_game_server(
                GameServerGroupName=GameServerGroupName,
                GameServerId=GameServerId,
                HealthCheck='HEALTHY'
            )
            print('Updated Gamelift game server health', flush=True)
        except gamelift.exceptions.NotFoundException as e:
            print(f'Skipping healthcheck, the node {GameServerId} is not registered', flush=True)
        await asyncio.sleep(30)

async def get_game_servers():
    """This is an asynchronous method call that checks to see whether there are any Agones game servers in the Allocated state.
    It runs once per minute and will continue running until there are no more Allocated game servers in the instance. So long as there are
    Allocated game servers, the instance is protected from scale-in by the ASG and cluster-autoscaler."""
    while True:
        print('Scanning instance for game servers', flush=True)
        try:
            custom_objs = custom_obj_client.list_cluster_custom_object(group='agones.dev', version='v1', plural='gameservers')
        except ApiException as e:
            print(f'Exception when calling CustomObjectsApi->list_cluster_custom_object: {e}')
        game_servers = custom_objs['items']
        filtered_list = list(filter(lambda x: x['status']['state']=='Allocated' and x['status']['nodeName']==ec2_metadata.private_hostname, game_servers))
        print(f'There are {len(filtered_list)} Allocated game servers running on this instance', flush=True)
        if filtered_list == []:
            return True
        else:          
            await asyncio.sleep(60)

async def get_health_status(InstanceId: str, GameServerGroupName: str, GameServerId: str, HealthcheckInterval: int):
    """This is another asynchronous method that checks the health of the viability of the instance according to FleetIQ.
    It is subscribing to a Redis channel for updates because the DescribeGameServerInstances API has a low throttling rate.
    For this to work, a separate application has to be deployed onto the cluster.  This application gets the viability of 
    each instance and publishes it on a separate channel for each instance.  When the viability changes to DRAINING, the node
    is cordoned and tainted, preventing Agones from scheduling new game servers on the instance.  Game servers in the non-Allocated
    state will be rescheduled onto other instances."""
    # Check instance health
    pubsub = r.pubsub()
    pubsub.subscribe(InstanceId)
    print('Starting message loop', flush=True)
    is_cordoned = False
    is_ready_shutdown = False
    is_waiting_for_termination = False
    for raw_message in pubsub.listen():
        print(f'is_cordoned: {is_cordoned}, is_ready_shutdown: {is_ready_shutdown}, is_waiting_for_termination: {is_waiting_for_termination}', flush=True)
        if raw_message['type'] != "message":
            continue
        message = json.loads(raw_message['data'])
        status = message['InstanceStatus']
        print(f"Instance {message['InstanceId']} status is: {message['InstanceStatus']}", flush=True)
        
        if is_waiting_for_termination == True and status == 'DRAINING':
            print(f'Waiting for termination signal', flush=True)
            
        elif is_waiting_for_termination == True and status == 'SPOT_TERMINATING':
        # This is never invoked because the status never equals SPOT_TERMINATING    
            print(f'Received termination signal', flush=True)
            loop.stop()
            termination_handler(GameServerGroupName, GameServerId)
        
        elif is_ready_shutdown == True:
            try:
                gamelift.deregister_game_server(
                    GameServerGroupName=GameServerGroupName,
                    GameServerId=GameServerId
                )
                print(f'Instance {message["InstanceId"]} has been deregistered from GameLift', flush=True)
                is_waiting_for_termination = True
            except gamelift.exceptions.NotFoundException as e:
                pass
        
        elif status == 'DRAINING' and is_cordoned == True:
            # This seems to be a block call.  Delays the main loop, get_health_status, until resolved.
            # I think I neeed to spawn a new thread here. 
            is_ready_shutdown = await get_game_servers()
        
        elif status == 'DRAINING' and is_cordoned == False:
            print('Instance is no longer viable', flush=True)
            is_cordoned = await asyncio.wait_for(cordon_and_protect(), timeout=30)
        
        else:
            pass
        
        print('Finished get health status loop', flush=True)
        await asyncio.sleep(HealthcheckInterval)

@click.command()
@click.option('--failure-threshold', help='Number of times to try before giving up', type=click.IntRange(1, 5, clamp=True), default=3)
@click.option('--healthcheck-interval', help='How often in seconds to perform the healthcheck', type=click.IntRange(5, 60, clamp=True), default=60)
def main(failure_threshold, healthcheck_interval):
    initialize_game_server(GameServerGroupName=game_server_group_name, GameServerId=game_server_id, InstanceId=instance_id)
    try: 
        asyncio.ensure_future(update_health_status(GameServerGroupName=game_server_group_name, GameServerId=game_server_id))
        asyncio.ensure_future(get_health_status(InstanceId=instance_id, GameServerGroupName=game_server_group_name, GameServerId=game_server_id, HealthcheckInterval=healthcheck_interval))
        loop.run_forever()
    except Exception as e: 
        pass
    finally:
        loop.close()

def sigterm_handler(signal, frame):
    """A handler for when the daemon receives a SIGTERM signal.  Before shutting down, the daemon will deregister the instance from FleetIQ."""
    # degister game server on exit
    try: 
        gamelift.deregister_game_server(
        GameServerGroupName=game_server_group_name,
        GameServerId=game_server_id
    )
    except gamelift.exceptions.NotFoundException as e:
        print(f'Instance has already been deregistered', flush=True)
    sys.exit(0)

#logging.basicConfig(format='%(asctime)s [%(levelname)s] - %(message)s', datefmt='%d-%b-%y %H:%M:%S', level=logging.INFO)
signal.signal(signal.SIGTERM, sigterm_handler)
if __name__ == "__main__":
    main()