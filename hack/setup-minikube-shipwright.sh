#!/bin/bash
#
# Setup Minikube cluster with Shipwright Build for development and E2E testing
#
# Prerequisites:
#   - minikube
#   - kubectl
#   - helm (optional, for Shipwright installation via Helm)
#
# Usage:
#   ./hack/setup-minikube-shipwright.sh [OPTIONS]
#
# Options:
#   --cluster-name NAME    Minikube profile name (default: minikube-shipwright)
#   --k8s-version VERSION  Kubernetes version (default: v1.34.10)
#   --cpus N               CPU count (default: 4)
#   --memory MB            Memory in MB (default: 8192)
#   --driver DRIVER        Minikube driver (default: auto-detect)
#   --shipwright-version   Shipwright version (default: v0.20.11)
#   --skip-cluster-create  Skip cluster creation, only install Shipwright
#   --help                 Show this help
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-minikube-shipwright}"
K8S_VERSION="${K8S_VERSION:-v1.34.10}"
CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-8192}"
DRIVER="${DRIVER:-}"
SHIPWRIGHT_VERSION="${SHIPWRIGHT_VERSION:-v0.20.11}"
SKIP_CLUSTER_CREATE=false

log() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

check_prereqs() {
    local missing=()
    command -v minikube >/dev/null 2>&1 || missing+=("minikube")
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --cpus)
                CPUS="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --driver)
                DRIVER="$2"
                shift 2
                ;;
            --shipwright-version)
                SHIPWRIGHT_VERSION="$2"
                shift 2
                ;;
            --skip-cluster-create)
                SKIP_CLUSTER_CREATE=true
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

create_cluster() {
    if [ "$SKIP_CLUSTER_CREATE" = true ]; then
        log "Skipping cluster creation (--skip-cluster-create)"
        return
    fi

    log "Creating minikube cluster: $CLUSTER_NAME"
    log "  Kubernetes version: $K8S_VERSION"
    log "  CPUs: $CPUS, Memory: ${MEMORY}MB"

    local driver_arg=""
    if [ -n "$DRIVER" ]; then
        driver_arg="--driver=$DRIVER"
    fi

    if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
        log "Cluster $CLUSTER_NAME already exists"
        read -p "Delete and recreate? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting existing cluster..."
            minikube delete -p "$CLUSTER_NAME"
        else
            log "Using existing cluster"
            return
        fi
    fi

    minikube start \
        -p "$CLUSTER_NAME" \
        --kubernetes-version="$K8S_VERSION" \
        --cpus="$CPUS" \
        --memory="${MEMORY}mb" \
        $driver_arg \
        --addons=registry,metrics-server

    log "Cluster created successfully"

    # Ensure context name matches cluster name
    log "Setting kubectl context to $CLUSTER_NAME"
    kubectl config use-context "$CLUSTER_NAME"
}

install_tekton() {
    log "Installing Tekton Pipelines (required by Shipwright)"

    # Use latest stable Tekton release
    local TEKTON_VERSION="${TEKTON_VERSION:-latest}"

    kubectl apply -f "https://storage.googleapis.com/tekton-releases/pipeline/${TEKTON_VERSION}/release.yaml"

    log "Waiting for Tekton to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=tekton-pipelines-controller \
        -n tekton-pipelines \
        --timeout=300s

    log "Tekton Pipelines installed (version: $TEKTON_VERSION)"
}

install_shipwright() {
    log "Installing Shipwright Build $SHIPWRIGHT_VERSION"

    # Install Shipwright Build Controller
    # Use server-side apply to handle large CRD annotations (Kubernetes 1.31+ issue)
    kubectl apply --server-side -f "https://github.com/shipwright-io/build/releases/download/${SHIPWRIGHT_VERSION}/release.yaml"

    log "Waiting for Shipwright controller to be ready..."
    kubectl wait --for=condition=ready pod \
        -l control-plane=shipwright-build-controller \
        -n shipwright-build \
        --timeout=300s

    log "Shipwright Build $SHIPWRIGHT_VERSION installed"
}

install_build_strategies() {
    log "Installing default ClusterBuildStrategies"

    # Install common build strategies
    local STRATEGIES_VERSION="${SHIPWRIGHT_VERSION}"
    local STRATEGIES_BASE="https://github.com/shipwright-io/build/releases/download/${STRATEGIES_VERSION}/sample-strategies.yaml"

    # Use server-side apply for large CRDs
    kubectl apply --server-side -f "$STRATEGIES_BASE"

    log "Installed ClusterBuildStrategies:"
    kubectl get clusterbuildstrategy -o custom-columns=NAME:.metadata.name --no-headers | sed 's/^/  - /'
}

setup_local_registry() {
    log "Setting up local registry access"

    # Enable minikube registry addon if not already enabled
    minikube addons enable registry -p "$CLUSTER_NAME" 2>/dev/null || true

    # Get registry NodePort
    local REGISTRY_PORT=$(kubectl get svc registry -n kube-system -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

    if [ -n "$REGISTRY_PORT" ]; then
        local REGISTRY_IP=$(minikube ip -p "$CLUSTER_NAME")
        log "Local registry available at: $REGISTRY_IP:$REGISTRY_PORT"
        log "You can use this in Build output.image field"
    fi
}

verify_installation() {
    log "Verifying installation..."

    # Check Tekton
    if ! kubectl get deployment tekton-pipelines-controller -n tekton-pipelines &>/dev/null; then
        error "Tekton installation verification failed"
    fi

    # Check Shipwright
    if ! kubectl get deployment shipwright-build-controller -n shipwright-build &>/dev/null; then
        error "Shipwright installation verification failed"
    fi

    # Check strategies
    local strategy_count=$(kubectl get clusterbuildstrategy --no-headers 2>/dev/null | wc -l)
    if [ "$strategy_count" -eq 0 ]; then
        error "No ClusterBuildStrategies found"
    fi

    log "Verification successful"
    log ""
    log "Available ClusterBuildStrategies:"
    kubectl get clusterbuildstrategy -o custom-columns=NAME:.metadata.name --no-headers | sed 's/^/  - /'
}

print_summary() {
    log "Setup complete!"
    log ""
    log "Cluster: $CLUSTER_NAME"
    log "Context: $(kubectl config current-context)"
    log ""
    log "To use this cluster:"
    log "  kubectl config use-context $CLUSTER_NAME"
    log ""
    log "To test with crane-plugin-buildconfig-to-shipwright:"
    log "  1. Build the plugin: go build -o crane-plugin-buildconfig-to-shipwright ."
    log "  2. Run E2E test: ./tests/e2e-transform.sh"
    log "  3. Apply transformed resources to this cluster"
    log ""
    log "Example Build resource:"
    log "  kubectl apply -f - <<EOF"
    log "  apiVersion: shipwright.io/v1beta1"
    log "  kind: Build"
    log "  metadata:"
    log "    name: example-build"
    log "  spec:"
    log "    source:"
    log "      type: Git"
    log "      git:"
    log "        url: https://github.com/shipwright-io/sample-go"
    log "    strategy:"
    log "      name: buildah"
    log "      kind: ClusterBuildStrategy"
    log "    output:"
    log "      image: localhost:5000/example:latest"
    log "  EOF"
}

main() {
    parse_args "$@"
    check_prereqs
    create_cluster

    # Ensure kubectl context is set
    log "Using kubectl context: $CLUSTER_NAME"
    kubectl config use-context "$CLUSTER_NAME"

    install_tekton
    install_shipwright
    install_build_strategies
    setup_local_registry
    verify_installation
    print_summary
}

main "$@"
