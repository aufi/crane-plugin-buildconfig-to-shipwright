#!/bin/bash
#
# Install FAKE OpenShift BuildConfig CRD on Minikube (or any non-OpenShift Kubernetes cluster)
#
# WARNING: This only installs the CRD schema - it does NOT provide actual BuildConfig
# functionality. BuildConfigs created with this CRD will not trigger any builds.
#
# This is purely for testing crane-plugin-buildconfig-to-shipwright transformation
# on clusters that don't have the native OpenShift BuildConfig resource type.
#
# Usage:
#   ./hack/fake-minikube-buildconfig.sh [OPTIONS]
#
# Options:
#   --uninstall    Remove the BuildConfig CRD
#   --verify       Verify CRD installation
#   --help         Show this help
#
set -euo pipefail

UNINSTALL=false
VERIFY_ONLY=false

log() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

check_prereqs() {
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found. Please install kubectl first."
    fi

    if ! kubectl cluster-info &>/dev/null; then
        error "Not connected to a Kubernetes cluster. Run 'kubectl config use-context <context>' first."
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            --verify)
                VERIFY_ONLY=true
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

verify_crd() {
    log "Verifying BuildConfig CRD installation..."

    if kubectl get crd buildconfigs.build.openshift.io &>/dev/null; then
        log "BuildConfig CRD is installed"

        # Show CRD details
        echo ""
        kubectl get crd buildconfigs.build.openshift.io -o custom-columns=\
NAME:.metadata.name,\
GROUP:.spec.group,\
VERSION:.spec.versions[0].name,\
SCOPE:.spec.scope

        echo ""
        log "You can now create BuildConfig resources:"
        log "  kubectl get buildconfigs"
        log "  kubectl get bc"
        return 0
    else
        log "BuildConfig CRD is NOT installed"
        return 1
    fi
}

install_crd() {
    log "Installing FAKE OpenShift BuildConfig CRD..."
    log "WARNING: This CRD has no controller - BuildConfigs will not actually build anything!"

    # Check if already installed
    if kubectl get crd buildconfigs.build.openshift.io &>/dev/null; then
        log "BuildConfig CRD already exists. Updating..."
    else
        log "Creating BuildConfig CRD..."
    fi

    # Apply CRD inline
    kubectl apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: buildconfigs.build.openshift.io
  annotations:
    description: "FAKE OpenShift BuildConfig CRD for testing transformation only - no build functionality"
    warning: "This CRD has no controller. BuildConfigs created with this will not trigger any builds."
spec:
  group: build.openshift.io
  names:
    kind: BuildConfig
    listKind: BuildConfigList
    plural: buildconfigs
    singular: buildconfig
    shortNames:
    - bc
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
    subresources:
      status: {}
EOF

    log "Waiting for CRD to be established..."
    kubectl wait --for=condition=established crd/buildconfigs.build.openshift.io --timeout=60s

    log "Fake BuildConfig CRD installed successfully (CRD only, no build functionality)"
}

uninstall_crd() {
    log "Uninstalling OpenShift BuildConfig CRD..."

    if ! kubectl get crd buildconfigs.build.openshift.io &>/dev/null; then
        log "BuildConfig CRD not found, nothing to uninstall"
        return 0
    fi

    # Warn about existing BuildConfig resources
    local bc_count=$(kubectl get buildconfigs --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$bc_count" -gt 0 ]; then
        log "WARNING: Found $bc_count BuildConfig resources in the cluster"
        read -p "Delete CRD and all BuildConfig resources? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Uninstall cancelled"
            return 0
        fi
    fi

    kubectl delete crd buildconfigs.build.openshift.io

    log "BuildConfig CRD uninstalled"
}

print_usage_example() {
    log ""
    log "Example BuildConfig resource:"
    cat <<'EOF'

  kubectl apply -f - <<YAML
  apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: example-build
    namespace: default
  spec:
    source:
      type: Git
      git:
        uri: https://github.com/example/myapp.git
        ref: main
    strategy:
      type: Docker
      dockerStrategy:
        dockerfilePath: Dockerfile
    output:
      to:
        kind: DockerImage
        name: quay.io/example/myapp:latest
  YAML

EOF
    log "Then transform with crane-plugin-buildconfig-to-shipwright"
}

main() {
    parse_args "$@"
    check_prereqs

    if [ "$VERIFY_ONLY" = true ]; then
        verify_crd
        exit $?
    fi

    if [ "$UNINSTALL" = true ]; then
        uninstall_crd
        exit 0
    fi

    install_crd
    verify_crd
    print_usage_example
}

main "$@"
