#!/bin/bash

# FleetIQ-EKS-Agones Integration Part 4: Agones installation and configuration

echo "[1/2] Installing Agones using Helm"

helm repo add agones https://agones.dev/chart/stable

helm install my-release --namespace agones-system --create-namespace agones/agones

echo "[2/2] Creating Agones Fleet"

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
