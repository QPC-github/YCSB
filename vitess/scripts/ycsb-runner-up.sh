#!/bin/bash

GKE_ZONE=${GKE_ZONE:-'us-east1-a'}

gcloud compute instances create ycsb-runner --machine-type n1-standard-1 --zone $GKE_ZONE
sleep 30
gcloud compute ssh ycsb-runner --zone $GKE_ZONE --command 'bash -s' < ycsb-runner-setup.sh
