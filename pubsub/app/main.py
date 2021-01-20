import json, os, time
import boto3
import redis

def get_config_dict():
    with open("/etc/fleetiq/fleetiq.conf", "r") as f:
        return json.load(f)

r = redis.from_url('redis://' + os.getenv('REDIS_URL'))

try:
    if r.ping() == True:
        print(f'Connection to database {os.getenv("REDIS_URL")} was successful', flush=True)
except redis.RedisError as e:
    print(f'Could not connect to redis\n{e}', flush=True)

gamelift = boto3.client('gamelift', region_name=os.getenv('AWS_REGION'))

while True:
    paginator = gamelift.get_paginator('describe_game_server_instances')
    #TODO get GAME_SERVER_GROUP_NAME from a ConfigMap and loop through the values
    groups = get_config_dict()
    for group in groups['GameServerGroups']:
        pages = paginator.paginate(GameServerGroupName=group)
        for page in pages:
            for game_server in page['GameServerInstances']:
                print(f'Publishing status on channel {game_server["InstanceId"]}', flush=True)
                print(f'{game_server}', flush=True)
                try:
                    r.publish(game_server['InstanceId'], json.dumps(game_server))
                except redis.RedisError as e:
                    print(f'Could not publish status for {game_server["InstanceId"]}\n{e}', flush=True)
    time.sleep(60)