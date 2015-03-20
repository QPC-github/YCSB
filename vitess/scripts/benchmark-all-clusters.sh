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

GKE_ZONE=${GKE_ZONE:-'us-east1-a'} # zone for executing ycsb-runner
BENCHMARKS_BASE_DIR=${BENCHMARKS_BASE_DIR:-~/ycsb_benchmarks} # where to save results
CLUSTERS_CONFIG=${CLUSTERS_CONFIG:-'clusters.json'}

# Bring up a single YCSB runner and reuse it for all cluster configurations
GKE_ZONE=$GKE_ZONE ./ycsb-runner-up.sh

git clone https://github.com/youtube/vitess.git

# Add external load balancer flag to vtgate
echo 'createExternalLoadBalancer: true' >> vitess/examples/kubernetes/vtgate-service.yaml

num_scenarios=`python -c "import json;obj=json.load(open('$CLUSTERS_CONFIG'));print len(obj['clusters'])"`
for i in `seq 0 $(($num_scenarios-1))`; do
  # Convert json line format into environment variable line format
  # e.g. {u'TABLETS_PER_SHARD': u'3', u'SHARDS': u'-80,80-'} becomes
  # TABLETS_PER_SHARD=3 SHARDS=-80,80-
  config=`python -c "import json;obj=json.load(open('$CLUSTERS_CONFIG'));print obj['clusters'][$i]"`
  config=`echo $config | perl -pe "s/(,)(?=(?:[^']|'[^']*')*$)/;/g"` # Replace non quoted , with ;
  config=`echo $config | perl -pe "s/: /:/g"` # Remove extra whitespace
  config=`echo "${config:1:-1}"`  # Get rid of open/close brackets
  params=''
  for i in `echo $config | tr ";" " "`; do
    param_name=`echo $i | cut -f1 -d ':'`
    val=`echo $i | cut -f2 -d ':'`
    params="$params ${param_name:2:-1}=${val:2:-1}"
  done

  benchmarks_dir=`date +"$BENCHMARKS_BASE_DIR/%Y_%m_%d_%H_%M"`
  mkdir -p $benchmarks_dir

  # Bring up the cluster
  cd vitess/examples/kubernetes
  eval $params ./cluster-up.sh 2>&1 | tee $benchmarks_dir/cluster-up.txt
  cd ../../..

  BENCHMARKS_DIR=$benchmarks_dir GKE_ZONE=$GKE_ZONE ./run-all-benchmarks.sh

  # Cleanup - tear down the cluster
  cd vitess/examples/kubernetes
  eval $params ./cluster-down.sh
  cd ../../..
done

rm -rf vitess
GKE_ZONE=$GKE_ZONE ./ycsb-runner-down.sh
