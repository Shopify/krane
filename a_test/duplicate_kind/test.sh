#!/bin/sh
set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

kubectl config use-context kind-krane
kubectl apply -f "${SCRIPT_DIR}/crd.yml"

kubectl delete ns example || true
kubectl create ns example

(cd "${SCRIPT_DIR}/../../" && bundle exec exe/krane deploy example kind-krane -f "${SCRIPT_DIR}/manifest.yml" --global-timeout=1m)
