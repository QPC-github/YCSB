#!/bin/bash

# This script runs all benchmarks against an existing cluster and grabs log files

GKE_ZONE=${GKE_ZONE:-'us-east1-a'} # zone for executing ycsb-runner
BENCHMARKS_DIR=${BENCHMARKS_DIR:-`date +"~/ycsb_benchmarks/%Y_%m_%d_%H_%M"`} # where to save results

mkdir -p $BENCHMARKS_DIR

# get the external vtgate ip from the existing cluster
vtgate_port=15001
vtgate_ip=`gcloud compute forwarding-rules list | awk '$1=="vtgate" {print $3}'`
if [ -z "$vtgate_ip" ]
then
  echo No vtgate forwarding-rule found
  exit -1
else
  export VTGATE_HOST="$vtgate_ip:$vtgate_port"
fi

# Create a temporary script which includes the proper vtgate ip and give it
# to the ycsb-runner instance to execute
cat workload-runner-template.sh | sed -e "s/{{VTGATE_HOST}}/${VTGATE_HOST}/g;" > workload-runner.sh
gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'bash -s' < workload-runner.sh

# Save off data - benchmark results + gcloud information
gcloud compute copy-files ycsb-runner:workloadlogs $BENCHMARKS_DIR --zone $GKE_ZONE
gcloud preview container kubectl get pods > $BENCHMARKS_DIR/gcloud-pods.txt
gcloud compute instances list > $BENCHMARKS_DIR/gcloud-instances.txt

# Cleanup - tear down log directories, temporary scripts, etc.
gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'rm -rf ~/workloadlogs'
rm workload-runner.sh
