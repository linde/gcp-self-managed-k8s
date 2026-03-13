#!/bin/bash
# Syncs Kubernetes Node PodCIDRs to GCP VPC Routes
NETWORK="k8s-network-ipv6-${local.rand_suffix}"
PROJECT=$(gcloud config get-value project)

while true; do
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}' | while read NODE CIDR; do
    if [ -n "$CIDR" ]; then
      ROUTE_NAME="k8s-pod-route-${NODE}"
      if ! gcloud compute routes describe $ROUTE_NAME --project=$PROJECT --quiet >/dev/null 2>&1; then
        echo "Creating route $ROUTE_NAME for $NODE ($CIDR)..."
        gcloud compute routes create $ROUTE_NAME \
          --network=$NETWORK \
          --next-hop-instance=$NODE \
          --next-hop-instance-zone=$(gcloud compute instances list --filter="name=($NODE)" --format="value(zone)") \
          --destination-range=$CIDR \
          --project=$PROJECT
      fi
    fi
  done
  sleep 60
done
