#!/bin/bash
#
# Cleanup development/test environments created by setup scripts
#
# Usage:
#   ./hack/cleanup-env.sh [OPTIONS]
#
# Options:
#   --minikube             Delete minikube cluster
#   --openshift            Delete OpenShift namespace and resources
#   --cluster-name NAME    Minikube cluster name (default: minikube-shipwright)
#   --namespace NAME       OpenShift namespace (default: my-app)
#   --all                  Cleanup both minikube and openshift
#   --help                 Show this help
#
set -euo pipefail

CLEANUP_MINIKUBE=false
CLEANUP_OPENSHIFT=false
CLUSTER_NAME="${CLUSTER_NAME:-minikube-shipwright}"
NAMESPACE="${NAMESPACE:-my-app}"

log() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

parse_args() {
    if [ $# -eq 0 ]; then
        show_help
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --minikube)
                CLEANUP_MINIKUBE=true
                shift
                ;;
            --openshift)
                CLEANUP_OPENSHIFT=true
                shift
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --all)
                CLEANUP_MINIKUBE=true
                CLEANUP_OPENSHIFT=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

cleanup_minikube() {
    log "Cleaning up minikube cluster: $CLUSTER_NAME"

    if ! command -v minikube >/dev/null 2>&1; then
        log "minikube not found, skipping"
        return
    fi

    if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
        read -p "Delete minikube cluster '$CLUSTER_NAME'? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting cluster..."
            minikube delete -p "$CLUSTER_NAME"
            log "Cluster deleted"
        else
            log "Skipped"
        fi
    else
        log "Cluster '$CLUSTER_NAME' not found"
    fi
}

cleanup_openshift() {
    log "Cleaning up OpenShift namespace: $NAMESPACE"

    if ! command -v oc >/dev/null 2>&1; then
        log "oc not found, skipping"
        return
    fi

    if ! oc whoami &>/dev/null; then
        log "Not connected to OpenShift cluster, skipping"
        return
    fi

    if oc get namespace "$NAMESPACE" &>/dev/null; then
        read -p "Delete namespace '$NAMESPACE' and all resources in it? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting namespace..."
            oc delete namespace "$NAMESPACE"
            log "Namespace deleted"
        else
            log "Skipped"
        fi
    else
        log "Namespace '$NAMESPACE' not found"
    fi

    # Optionally cleanup operator
    if oc get subscription openshift-builds-operator -n openshift-operators &>/dev/null; then
        read -p "Also remove OpenShift Builds Operator? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Removing operator subscription..."
            oc delete subscription openshift-builds-operator -n openshift-operators || true
            log "Note: ClusterServiceVersion and CRDs may remain. Remove manually if needed."
        fi
    fi
}

main() {
    parse_args "$@"

    if [ "$CLEANUP_MINIKUBE" = true ]; then
        cleanup_minikube
    fi

    if [ "$CLEANUP_OPENSHIFT" = true ]; then
        cleanup_openshift
    fi

    log "Cleanup complete"
}

main "$@"
