#!/bin/bash
#
# Setup OpenShift cluster with OpenShift Builds (Shipwright fork) for development and E2E testing
#
# Prerequisites:
#   - oc (OpenShift CLI)
#   - kubectl
#   - Access to an OpenShift cluster (4.12+)
#     For local development, you can install OpenShift Local via:
#     https://console.redhat.com/openshift/create/local
#
# Usage:
#   ./hack/setup-openshift-builds.sh [OPTIONS]
#
# Options:
#   --namespace NAMESPACE     Target namespace (default: my-app)
#   --operator-version VER    OpenShift Builds Operator version (default: latest)
#   --context-name NAME       Kubernetes context name (default: openshift)
#   --skip-namespace-create   Skip namespace creation
#   --skip-operator-install   Skip operator installation, only setup namespace
#   --skip-context-rename     Skip renaming kubectl context
#   --help                    Show this help
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-my-app}"
OPERATOR_VERSION="${OPERATOR_VERSION:-latest}"
CONTEXT_NAME="${CONTEXT_NAME:-openshift}"
SKIP_NAMESPACE_CREATE=false
SKIP_OPERATOR_INSTALL=false
SKIP_CONTEXT_RENAME=false

log() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

check_prereqs() {
    local missing=()
    command -v oc >/dev/null 2>&1 || missing+=("oc")
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
    fi

    # Check cluster connection
    if ! oc whoami &>/dev/null; then
        error "Not connected to an OpenShift cluster. Run 'oc login' first."
    fi

    log "Connected to OpenShift cluster: $(oc whoami --show-server)"
    log "Current user: $(oc whoami)"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --operator-version)
                OPERATOR_VERSION="$2"
                shift 2
                ;;
            --context-name)
                CONTEXT_NAME="$2"
                shift 2
                ;;
            --skip-namespace-create)
                SKIP_NAMESPACE_CREATE=true
                shift
                ;;
            --skip-operator-install)
                SKIP_OPERATOR_INSTALL=true
                shift
                ;;
            --skip-context-rename)
                SKIP_CONTEXT_RENAME=true
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

check_openshift_builds() {
    log "Checking if OpenShift Builds is available..."

    # Check if OpenShift Builds Operator is available in OperatorHub
    if oc get packagemanifests openshift-builds-operator -n openshift-marketplace &>/dev/null; then
        log "OpenShift Builds Operator found in OperatorHub"
        return 0
    fi

    # Check if Shipwright is already installed (alternative)
    if oc get deployment shipwright-build-controller -n openshift-builds &>/dev/null 2>&1; then
        log "Shipwright Build controller already installed"
        return 0
    fi

    log "WARNING: OpenShift Builds Operator not found in OperatorHub"
    log "This script will install Shipwright Build directly as fallback"
    return 1
}

create_namespace() {
    if [ "$SKIP_NAMESPACE_CREATE" = true ]; then
        log "Skipping namespace creation (--skip-namespace-create)"
        return
    fi

    if oc get namespace "$NAMESPACE" &>/dev/null; then
        log "Namespace $NAMESPACE already exists"
    else
        log "Creating namespace: $NAMESPACE"
        oc create namespace "$NAMESPACE"
    fi

    log "Setting current namespace to $NAMESPACE"
    oc project "$NAMESPACE"
}

install_openshift_builds_operator() {
    if [ "$SKIP_OPERATOR_INSTALL" = true ]; then
        log "Skipping operator installation (--skip-operator-install)"
        return
    fi

    log "Installing OpenShift Builds Operator"

    # Create OperatorGroup if not exists
    if ! oc get operatorgroup openshift-builds-operator -n openshift-operators &>/dev/null; then
        log "Creating OperatorGroup..."
        oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-builds-operator
  namespace: openshift-operators
spec: {}
EOF
    fi

    # Create Subscription
    log "Creating Subscription for OpenShift Builds Operator..."
    local channel="stable"
    if [ "$OPERATOR_VERSION" != "latest" ]; then
        channel="$OPERATOR_VERSION"
    fi

    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-builds-operator
  namespace: openshift-operators
spec:
  channel: $channel
  name: openshift-builds-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

    log "Waiting for OpenShift Builds Operator to install..."
    local timeout=300
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if oc get csv -n openshift-operators 2>/dev/null | grep -q openshift-builds-operator; then
            if oc get csv -n openshift-operators -o jsonpath='{.items[?(@.metadata.name~"openshift-builds-operator")].status.phase}' 2>/dev/null | grep -q Succeeded; then
                log "OpenShift Builds Operator installed successfully"
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    error "Timeout waiting for OpenShift Builds Operator installation"
}

install_shipwright_fallback() {
    log "Installing Shipwright Build as fallback..."

    local SHIPWRIGHT_VERSION="${SHIPWRIGHT_VERSION:-v0.20.11}"
    local TEKTON_VERSION="${TEKTON_VERSION:-v0.67.0}"

    # Install Tekton if not present
    if ! oc get namespace tekton-pipelines &>/dev/null; then
        log "Installing Tekton Pipelines $TEKTON_VERSION"
        oc apply -f "https://storage.googleapis.com/tekton-releases/pipeline/previous/${TEKTON_VERSION}/release.yaml"

        log "Waiting for Tekton to be ready..."
        oc wait --for=condition=ready pod \
            -l app=tekton-pipelines-controller \
            -n tekton-pipelines \
            --timeout=300s
    else
        log "Tekton Pipelines already installed"
    fi

    # Install Shipwright
    if ! oc get namespace shipwright-build &>/dev/null; then
        log "Installing Shipwright Build $SHIPWRIGHT_VERSION"
        oc apply -f "https://github.com/shipwright-io/build/releases/download/${SHIPWRIGHT_VERSION}/release.yaml"

        log "Waiting for Shipwright controller to be ready..."
        oc wait --for=condition=ready pod \
            -l control-plane=shipwright-build-controller \
            -n shipwright-build \
            --timeout=300s
    else
        log "Shipwright Build already installed"
    fi

    # Install build strategies
    log "Installing ClusterBuildStrategies..."
    oc apply -f "https://github.com/shipwright-io/build/releases/download/${SHIPWRIGHT_VERSION}/sample-strategies.yaml"
}

grant_permissions() {
    log "Granting permissions to default ServiceAccount in $NAMESPACE"

    # Grant permissions for builds to run
    oc adm policy add-scc-to-user privileged -z default -n "$NAMESPACE" || \
        log "WARNING: Could not add privileged SCC (may require cluster-admin)"

    # Create a basic builder ServiceAccount with pull/push secrets template
    if ! oc get sa builder -n "$NAMESPACE" &>/dev/null; then
        log "Creating builder ServiceAccount..."
        oc create sa builder -n "$NAMESPACE"
    fi
}

setup_internal_registry() {
    log "Setting up access to OpenShift internal registry..."

    # Get internal registry route
    local REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [ -z "$REGISTRY_HOST" ]; then
        log "Creating route to internal registry..."
        oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}' || \
            log "WARNING: Could not create registry route (may require cluster-admin)"

        # Wait for route
        sleep 5
        REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    fi

    if [ -n "$REGISTRY_HOST" ]; then
        log "Internal registry available at: $REGISTRY_HOST"
        log "Example Build output.image: $REGISTRY_HOST/$NAMESPACE/myapp:latest"
    else
        log "WARNING: Could not determine internal registry host"
    fi
}

setup_kubectl_context() {
    if [ "$SKIP_CONTEXT_RENAME" = true ]; then
        log "Skipping kubectl context rename (--skip-context-rename)"
        return
    fi

    log "Setting up kubectl context: $CONTEXT_NAME"

    local current_context=$(kubectl config current-context)

    # Check if desired context name already exists
    if kubectl config get-contexts "$CONTEXT_NAME" &>/dev/null; then
        if [ "$current_context" != "$CONTEXT_NAME" ]; then
            log "Context '$CONTEXT_NAME' already exists, switching to it"
            kubectl config use-context "$CONTEXT_NAME"
        else
            log "Already using context '$CONTEXT_NAME'"
        fi
    else
        # Rename current context to desired name
        log "Renaming context '$current_context' to '$CONTEXT_NAME'"
        kubectl config rename-context "$current_context" "$CONTEXT_NAME"
        kubectl config use-context "$CONTEXT_NAME"
    fi

    log "Kubectl context set to: $CONTEXT_NAME"
}

verify_installation() {
    log "Verifying installation..."

    # Check for Shipwright or OpenShift Builds
    if oc get deployment shipwright-build-controller -n shipwright-build &>/dev/null; then
        log "Shipwright Build controller found"
    elif oc get deployment -n openshift-builds &>/dev/null 2>&1; then
        log "OpenShift Builds found"
    else
        error "Neither Shipwright nor OpenShift Builds installation found"
    fi

    # Check strategies
    local strategy_count=$(oc get clusterbuildstrategy --no-headers 2>/dev/null | wc -l)
    if [ "$strategy_count" -eq 0 ]; then
        log "WARNING: No ClusterBuildStrategies found"
    else
        log "Found $strategy_count ClusterBuildStrategies"
    fi

    log "Verification complete"
}

print_summary() {
    log "Setup complete!"
    log ""
    log "Namespace: $NAMESPACE"
    log "Current context: $(oc config current-context)"
    log ""
    log "Available ClusterBuildStrategies:"
    oc get clusterbuildstrategy -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | sed 's/^/  - /' || echo "  (none found)"
    log ""
    log "To test with crane-plugin-buildconfig-to-shipwright:"
    log "  1. Export BuildConfigs from source cluster:"
    log "     crane export -n <source-namespace> --export-dir ./migration"
    log "  2. Transform with plugin:"
    log "     crane transform --export-dir ./migration --transform-dir ./migration/transform --plugin-dir ./plugins"
    log "  3. Apply to this namespace:"
    log "     kubectl apply -f ./migration/transform/resources/ -n $NAMESPACE"
    log ""
    log "Example Build resource:"
    log "  oc apply -f - <<EOF"
    log "  apiVersion: shipwright.io/v1beta1"
    log "  kind: Build"
    log "  metadata:"
    log "    name: example-build"
    log "    namespace: $NAMESPACE"
    log "  spec:"
    log "    source:"
    log "      type: Git"
    log "      git:"
    log "        url: https://github.com/shipwright-io/sample-go"
    log "    strategy:"
    log "      name: buildah"
    log "      kind: ClusterBuildStrategy"
    log "    output:"
    log "      image: image-registry.openshift-image-registry.svc:5000/$NAMESPACE/example:latest"
    log "  EOF"
}

main() {
    parse_args "$@"
    check_prereqs

    if check_openshift_builds; then
        install_openshift_builds_operator || install_shipwright_fallback
    else
        install_shipwright_fallback
    fi

    create_namespace
    grant_permissions
    setup_internal_registry
    setup_kubectl_context
    verify_installation
    print_summary
}

main "$@"
