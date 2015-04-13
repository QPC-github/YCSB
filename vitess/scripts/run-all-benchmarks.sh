#!/bin/bash

# This script runs all benchmarks against an existing cluster and grabs log files

BENCHMARKS_BASE_DIR=${BENCHMARKS_BASE_DIR:-~/ycsb_benchmarks}
GKE_ZONE=${GKE_ZONE:-'us-east1-a'} # zone for executing ycsb-runner
GKE_CLUSTER_NAME=${GKE_CLUSTER_NAME:-'example'}
BENCHMARKS_DIR=${BENCHMARKS_DIR:-`date +"$BENCHMARKS_BASE_DIR/%Y_%m_%d_%H_%M"`} # where to save results
VTGATE_HOST=${VTGATE_HOST:-''}
YCSB_RUNNER_NAME=${YCSB_RUNNER_NAME:-'ycsb-runner'}

mkdir -p $BENCHMARKS_DIR

if [ -z $VTGATE_HOST ]
then
  # get the external vtgate ip from the existing cluster
  vtgate_port=15001
  vtgate_ip=`gcloud compute forwarding-rules list | grep $GKE_CLUSTER_NAME | grep vtgate | awk '{print $3}'`
  if [ -z "$vtgate_ip" ]
  then
    echo No vtgate forwarding-rule found
    exit -1
  else
    VTGATE_HOST="$vtgate_ip:$vtgate_port"
  fi
fi

gcloud compute ssh $YCSB_RUNNER_NAME --zone $GKE_ZONE --command 'mkdir ~/workloadlogs'

# Create a temporary script which includes the proper vtgate ip and give it
# to the ycsb-runner instance to execute
python workload-runner-generator.py $VTGATE_HOST
gcloud compute ssh $YCSB_RUNNER_NAME --zone $GKE_ZONE --command 'bash -s' < workload-runner.sh

# Save off data - benchmark results + gcloud information
gcloud compute copy-files $YCSB_RUNNER_NAME:workloadlogs $BENCHMARKS_DIR --zone $GKE_ZONE
gcloud alpha container kubectl get pods > $BENCHMARKS_DIR/gcloud-pods.txt
gcloud compute instances list > $BENCHMARKS_DIR/gcloud-instances.txt

# Cleanup - tear down log directories, temporary scripts, etc.
gcloud compute ssh $YCSB_RUNNER_NAME --zone $GKE_ZONE --command 'rm -rf ~/workloadlogs'

cp workload-runner.sh $BENCHMARKS_DIR/workload-runner.sh
rm workload-runner.sh
