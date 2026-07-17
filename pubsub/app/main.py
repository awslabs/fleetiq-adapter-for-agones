import json, os, time
import boto3
import redis

def get_config_dict():
    with open("/etc/fleetiq/fleetiq.conf", "r") as f:
        return json.load(f)

def _build_redis_url():
    """Build the Redis connection URL, optionally with AUTH and TLS.

    Backwards compatible: with only REDIS_URL set this behaves exactly as
    before (redis://host:port, no password). Set REDIS_PASSWORD to enable AUTH
    and REDIS_TLS=true for an encrypted (rediss://) connection, e.g. ElastiCache
    with in-transit encryption enabled."""
    host = os.getenv('REDIS_URL')
    password = os.getenv('REDIS_PASSWORD')
    use_tls = os.getenv('REDIS_TLS', '').lower() in ('1', 'true', 'yes')
    scheme = 'rediss' if use_tls else 'redis'
    auth = f':{password}@' if password else ''
    return f'{scheme}://{auth}{host}'

r = redis.from_url(_build_redis_url())

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