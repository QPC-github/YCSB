#!/bin/bash

GKE_ZONE=${GKE_ZONE:-'us-east1-a'}
gcloud compute instances delete ycsb-runner --zone $GKE_ZONE -q
