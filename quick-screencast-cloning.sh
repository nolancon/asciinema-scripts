#!/bin/bash 

PV='pv -qL'

function wait_for_pvc() {
    retries=20
    while [[ $retries -ge 0 ]];do
        phase=$(kubectl get pvc -n storageos $1 -o jsonpath="{.status.phase}")
        if [[ $phase == "Bound" ]];then
            echo "$1 is Bound successfully"
            break
        fi
        echo "Waiting for PVC to become Bound, currently $phase..."
        ((retries--))
        sleep 5
    done
}

function wait_for_deployment() {
    retries=20
    while [[ $retries -ge 0 ]];do

        unavailable_replicas=$(kubectl get deployment -n storageos $1 -o jsonpath="{.status.unavailableReplicas}")
        if [[ $unavailable_replicas -eq 0 ]];then
            echo "$1 pod is now running"
            break
        fi
        echo "Waiting for deployment pod to enter running phase..."
        sleep 5
        ((retries--))
    done
}

command()
{
  speed=$2
  [ -z "$speed" ] && speed=10

  echo "> $1" | $PV $speed
  sh -c "$1"
  echo | $PV $speed
}

out()
{
  speed=$2
  [ -z "$speed" ] && speed=10

  echo "$1" | $PV $speed
  echo | $PV $speed
}

cleanup()
{
  clear
  command "kubectl delete deploy source-deployment clone-deployment -n storageos" 100
  command "kubectl delete pvc source-pvc clone-pvc -n storageos" 100
}

record()
{
  clear
  out 'Record this screencast'
  command "asciinema rec -t 'Ondat Cloning Demo'  Ondat-Cloning-Demo.cast -c 'bash $0 play'" 100
}



screen1()
{
  clear
  command "kubectl apply -f -<<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-pvc
  namespace: storageos
spec:
  storageClassName: storageos
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF" 500

  wait_for_pvc source-pvc
}

screen2()
{
  command "kubectl apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: source-deployment
  namespace: storageos
  labels:
    app: clone-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clone-demo
  template:
    metadata:
      labels:
        app: clone-demo
    spec:
      containers:
      - name: debian
        image: debian:9-slim
        command: [\"/bin/sleep\"]
        args: [ \"infinity\" ]
        volumeMounts:
          - mountPath: /mnt
            name: v1
      volumes:
      - name: v1
        persistentVolumeClaim:
          claimName: source-pvc

EOF" 500

  wait_for_deployment source-deployment
}

screen3()
{
  SRC_POD=$(kubectl get -n storageos pod -l app=clone-demo -o jsonpath="{.items[0].metadata.name}")
  command "kubectl exec -it $SRC_POD -n storageos -- bash -c \"mkdir -p /mnt/test ; echo 'Ondat: Free Your Data!' > /mnt/test/ondat_clone_demo ; sync /mnt/test/ondat_clone_demo\"" 500
  DATA=$(kubectl exec -it $SRC_POD -n storageos -- bash -c "cat /mnt/test/ondat_clone_demo")
  out "$DATA"
}

screen4()
{
  clear
  command "kubectl apply -f -<<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: clone-pvc
  namespace: storageos
spec:
  storageClassName: storageos
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  dataSource:
    kind: PersistentVolumeClaim
    name: source-pvc
EOF" 500
  wait_for_pvc clone-pvc
}

screen5()
{
  command "kubectl apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clone-deployment
  namespace: storageos
  labels:
    app: clone-demo-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clone-demo-2
  template:
    metadata:
      labels:
        app: clone-demo-2
    spec:
      containers:
      - name: debian
        image: debian:9-slim
        command: [\"/bin/sleep\"]
        args: [ \"infinity\" ]
        volumeMounts:
          - mountPath: /mnt
            name: v1
      volumes:
      - name: v1
        persistentVolumeClaim:
          claimName: clone-pvc

EOF" 500

  wait_for_deployment clone-deployment
}

screen6(){
  CLONE_POD=$(kubectl get -n storageos pod -l app=clone-demo-2 -o jsonpath="{.items[0].metadata.name}")
  command "kubectl exec -it $CLONE_POD -n storageos -- bash -c \"cat /mnt/test/ondat_clone_demo\"" 100
}

if [ "$1" == 'play' ] ; then
  if [ -n "$2" ] ; then
    screen$2
  else
    for n in $(seq 6) ; do screen$n ; sleep 1; done
  fi
elif [ "$1" == 'cleanup' ] ; then
  cleanup
elif [ "$1" == 'record' ] ; then
  record
else
   echo "Usage: $0 [--help|help|-h] | [play [<screen number>]] | [cleanup] | [record]"
fi
