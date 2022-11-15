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
  out "This video demonstrates CSI Volume Cloning with Ondat in a few easy steps"
}

screen2()
{
  clear
  out "1. First, let's ensure that Ondat is installed on our Kubernetes cluster"
  sleep 1
  command "kubectl get pods -n storageos"
}

screen3()
{
  clear
  out "2. Create a new PVC, we'll call this the source PVC!"
  sleep 1
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
EOF" 50

  wait_for_pvc source-pvc
}

screen4()
{
  clear
  out "3. Create a Pod that uses the source PVC"
  sleep 1
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

EOF" 100

  wait_for_deployment source-deployment
}

screen5()
{
  clear
  out "4. Write some data to the source PVC"
  SRC_POD=$(kubectl get -n storageos pod -l app=clone-demo -o jsonpath="{.items[0].metadata.name}")
  command "kubectl exec -it $SRC_POD -n storageos -- bash -c \"echo 'Ondat: Free Your Data!' > /mnt/ondat_clone_demo\""
  out "The data we've written to our source PVC is (remember this for later):"
  DATA=$(kubectl exec -it $SRC_POD -n storageos -- bash -c "cat /mnt/ondat_clone_demo")
  out "$DATA"
}

screen6()
{
  clear
  out "5. Now let's create a new PVC that will clone the source PVC"
  sleep 1
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
EOF" 50
  sleep 1
  out "Notice we have set the new PVC's dataSource to the name of the PVC we wish to clone"
  sleep 3
  wait_for_pvc clone-pvc
  out "This means that the clone operation has taken place and the cloned PVC is ready to use"
  sleep 3
  out "We can check the Ondat CLI to see more details on our PVCs"  
  CLI_POD=$(kubectl get -n storageos pod -l app=storageos-cli -o jsonpath="{.items[0].metadata.name}")
  command "kubectl --namespace=storageos exec $CLI_POD -- storageos get volumes -n storageos"
  sleep 3
}

screen7()
{
  clear
  out "6. Create a new Pod that uses the clone PVC, then we can check for the cloned data!"
  sleep 1
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

EOF" 100

  wait_for_deployment clone-deployment
}

screen8(){
  clear
  out "7. Now let's read the data from our clone PVC to verify that the clone operation was successful"
  sleep 2
  CLONE_POD=$(kubectl get -n storageos pod -l app=clone-demo-2 -o jsonpath="{.items[0].metadata.name}")
  command "kubectl exec -it $CLONE_POD -n storageos -- bash -c \"cat /mnt/*/ondat_clone_demo\""
  sleep 2
  out "We can see our data has been successfully cloned from source PVC to clone PVC"
  sleep 2
  out "Thanks for watching!"
}

if [ "$1" == 'play' ] ; then
  if [ -n "$2" ] ; then
    screen$2
  else
    for n in $(seq 8) ; do screen$n ; sleep 3; done
  fi
elif [ "$1" == 'cleanup' ] ; then
  cleanup
elif [ "$1" == 'record' ] ; then
  record
else
   echo "Usage: $0 [--help|help|-h] | [play [<screen number>]] | [cleanup] | [record]"
fi
