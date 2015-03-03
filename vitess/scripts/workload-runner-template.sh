#!/bin/bash

# This is a template script where VTGATE_HOST is replaced with the actual value
# when the cluster is created.  It is passed to the instance that runs the
# YCSB benchmarks through ssh.

VTGATE_HOST={{VTGATE_HOST}}

mkdir ~/workloadlogs

# Run all workloads (a through f)
for wl in $(echo 'a b c d e f'); do
  YCSB/bin/ycsb load vitess -P YCSB/workloads/workload${wl} -p hosts=$VTGATE_HOST -p keyspace=test_keyspace -s > ~/workloadlogs/load${wl}.txt
  YCSB/bin/ycsb run vitess -P YCSB/workloads/workload${wl} -p hosts=$VTGATE_HOST -p keyspace=test_keyspace -p createTable=skip -s > ~/workloadlogs/run${wl}.txt
done
