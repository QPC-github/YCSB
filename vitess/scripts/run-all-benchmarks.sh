#!/bin/bash

# This script loops through the cluster configurations specified in
# clusters.json, bringing up the cluster as defined and then running
# all the YCSB benchmarks against it, and then pulls the results.

# ensure google cloud project is set
project_id=`gcloud config list project | sed -n 2p | cut -d " " -f 3`
if [ -z $project_id ]
then
  echo Project ID not set, use 'gcloud config set project PROJECT' to set it
  exit -1
fi

GKE_ZONE=${GKE_ZONE:-'us-east1-a'}
BENCHMARKS_BASE_DIR=${BENCHMARKS_BASE_DIR:-~/ycsb_benchmarks}

# create and setup instance for running ycsb tasks - reused for all clusters
gcloud compute instances create ycsb-runner --machine-type n1-standard-1 --zone $GKE_ZONE
sleep 30
gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'bash -s' < ycsb-runner-setup.sh

git clone https://github.com/youtube/vitess.git

# Add external load balancer flag to vtgate
echo 'createExternalLoadBalancer: true' >> vitess/examples/kubernetes/vtgate-service.yaml

num_scenarios=`python -c 'import json;obj=json.load(open("clusters.json"));print len(obj["clusters"])'`
for i in `seq 0 $(($num_scenarios-1))`; do
  # Convert json line format into environment variable line format
  # e.g. {u'TABLETS_PER_SHARD': u'3', u'SHARDS': u'-80,80-'} becomes
  # TABLETS_PER_SHARD=3 SHARDS=-80,80-
  config=`python -c "import json;obj=json.load(open('clusters.json'));print obj['clusters'][$i]"`
  config=`echo $config | perl -pe "s/(,)(?=(?:[^']|'[^']*')*$)/;/g"` # Replace non quoted , with ;
  config=`echo $config | perl -pe "s/: /:/g"` # Remove extra whitespace
  config=`echo "${config:1:-1}"`  # Get rid of open/close brackets
  params=''
  for i in `echo $config | tr ";" " "`; do
    param_name=`echo $i | cut -f1 -d ':'`
    val=`echo $i | cut -f2 -d ':'`
    params="$params ${param_name:2:-1}=${val:2:-1}"
  done

  # Creates a cluster, runs the six YCSB benchmarks, and grabs the log files
  benchmarks_dir=`date +"$BENCHMARKS_BASE_DIR/%Y_%m_%d_%H_%M"`
  mkdir -p $benchmarks_dir

  # Bring up the cluster
  cd vitess/examples/kubernetes
  eval $params ./cluster-up.sh 2>&1 | tee $benchmarks_dir/cluster-up.txt
  cd ../../..

  # Bringing the cluster up should result in a proper external vtgate ip
  vtgate_port=15001
  vtgate_ip=`gcloud compute forwarding-rules list | awk '$1=="vtgate" {print $3}'`
  if [ -z "$vtgate_ip" ]
  then
    echo No vtgate forwarding-rule found
    continue
  else
    export VTGATE_HOST="$vtgate_ip:$vtgate_port"
  fi

  # Create a temporary script which includes the proper vtgate ip and give it
  # to the ycsb-runner instance to execute
  cat workload-runner-template.sh | sed -e "s/{{VTGATE_HOST}}/${VTGATE_HOST}/g;" > workload-runner.sh
  gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'bash -s' < workload-runner.sh

  # Save off data - benchmark results + gcloud information
  gcloud compute copy-files ycsb-runner:workloadlogs $benchmarks_dir --zone $GKE_ZONE
  gcloud preview container kubectl get pods > $benchmarks_dir/gcloud-pods.txt
  gcloud compute instances list > $benchmarks_dir/gcloud-instances.txt

  # Cleanup - tear down the cluster, log directories, temporary scripts, etc.
  gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'rm -rf ~/workloadlogs'
  rm workload-runner.sh
  cd vitess/examples/kubernetes
  eval $params ./cluster-down.sh
  cd ../../..
done

rm -rf vitess
gcloud compute instances delete ycsb-runner -q --zone $GKE_ZONE
