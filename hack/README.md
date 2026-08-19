# Development and Testing Scripts

This directory contains scripts for setting up development and E2E testing environments.

## Prerequisites

### Common Prerequisites

- **[crane CLI](https://github.com/konveyor/crane)** - Required for transform and apply operations
  
  **Installation:**
  
  ```bash
  # Build from source
  git clone https://github.com/konveyor/crane.git
  cd crane
  make build
  sudo mv bin/crane /usr/local/bin/
  
  # Verify installation
  crane version
  ```

- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### For Minikube with Shipwright

- [minikube](https://minikube.sigs.k8s.io/docs/start/)

### For OpenShift with OpenShift Builds

- [oc (OpenShift CLI)](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- Access to an OpenShift cluster (4.12+)
  - For local development: [OpenShift Local](https://console.redhat.com/openshift/create/local)

## Quick Start

### Option 1: Minikube with Shipwright

```bash
# Setup a local Minikube cluster with Shipwright Build
./hack/setup-minikube-shipwright.sh

# This creates:
# - Cluster named "minikube-shipwright"
# - Kubectl context "minikube-shipwright"
# - Tekton Pipelines (required by Shipwright)
# - Shipwright Build v0.20.11
# - Default ClusterBuildStrategies (buildah, source-to-image, etc.)
# - Local registry addon
```

### Option 2: OpenShift with OpenShift Builds

```bash
# First, install OpenShift Local if you don't have a cluster:
# https://console.redhat.com/openshift/create/local

# Login to your OpenShift cluster
oc login --server=https://api.your-cluster.com:6443

# Setup namespace and install OpenShift Builds
./hack/setup-openshift-builds.sh

# This creates:
# - Namespace "my-app"
# - Kubectl context "openshift"
# - OpenShift Builds Operator (or Shipwright as fallback)
# - ClusterBuildStrategies
# - ServiceAccount with necessary permissions
```

## Script Reference

### `setup-minikube-shipwright.sh`

Creates a Minikube cluster with Shipwright Build for testing.

**Usage:**
```bash
./hack/setup-minikube-shipwright.sh [OPTIONS]
```

**Common Options:**
- `--cluster-name NAME` - Minikube profile name (default: `minikube-shipwright`)
- `--k8s-version VERSION` - Kubernetes version (default: `v1.31.0`)
- `--cpus N` - CPU count (default: `4`)
- `--memory MB` - Memory in MB (default: `8192`)
- `--shipwright-version VER` - Shipwright version (default: `v0.20.11`)
- `--skip-cluster-create` - Only install Shipwright, don't create cluster

**Examples:**
```bash
# Default setup
./hack/setup-minikube-shipwright.sh

# Custom configuration
./hack/setup-minikube-shipwright.sh \
  --cluster-name my-cluster \
  --cpus 6 \
  --memory 16384 \
  --k8s-version v1.30.0

# Only install Shipwright on existing cluster
./hack/setup-minikube-shipwright.sh --skip-cluster-create
```

### `setup-openshift-builds.sh`

Sets up OpenShift Builds (or Shipwright) on an OpenShift cluster.

**Usage:**
```bash
./hack/setup-openshift-builds.sh [OPTIONS]
```

**Common Options:**
- `--namespace NAME` - Target namespace (default: `my-app`)
- `--context-name NAME` - Kubectl context name (default: `openshift`)
- `--operator-version VER` - OpenShift Builds Operator version (default: `latest`)
- `--skip-namespace-create` - Skip namespace creation
- `--skip-operator-install` - Only setup namespace, skip operator
- `--skip-context-rename` - Skip renaming kubectl context

**Examples:**
```bash
# Default setup
./hack/setup-openshift-builds.sh

# Custom namespace and context
./hack/setup-openshift-builds.sh --namespace my-custom-app --context-name my-openshift

# Only create and configure namespace, keep original context name
./hack/setup-openshift-builds.sh --skip-operator-install --skip-context-rename
```

### `cleanup-env.sh`

Cleans up development/test environments.

**Usage:**
```bash
./hack/cleanup-env.sh [OPTIONS]
```

**Options:**
- `--minikube` - Delete minikube cluster
- `--openshift` - Delete OpenShift namespace
- `--all` - Cleanup both environments
- `--cluster-name NAME` - Minikube cluster name (default: `minikube-shipwright`)
- `--namespace NAME` - OpenShift namespace (default: `my-app`)

**Examples:**
```bash
# Cleanup minikube cluster
./hack/cleanup-env.sh --minikube

# Cleanup OpenShift namespace
./hack/cleanup-env.sh --openshift

# Cleanup everything
./hack/cleanup-env.sh --all

# Cleanup custom named resources
./hack/cleanup-env.sh --minikube --cluster-name my-cluster
./hack/cleanup-env.sh --openshift --namespace my-custom-app
```

## Testing the Plugin

After setting up your environment, test the crane plugin.

**Note:** Make sure you have the `crane` CLI installed (see Prerequisites above).

### 1. Build the Plugin

```bash
cd /path/to/crane-plugin-buildconfig-to-shipwright
go build -o crane-plugin-buildconfig-to-shipwright .
```

### 2. Run E2E Transform Test

```bash
# This tests the transform pipeline without applying to a cluster
./tests/e2e-transform.sh
```

### 3. Test on Real Cluster

#### Minikube
```bash
# Set kubectl context (context name: minikube-shipwright)
kubectl config use-context minikube-shipwright

# Build plugin
go build -o /tmp/plugins/crane-plugin-buildconfig-to-shipwright .

# Transform test data
crane transform \
  --export-dir ./tests/testdata/export \
  --transform-dir /tmp/transform \
  --plugin-dir /tmp/plugins

# Apply to cluster
kubectl apply -f /tmp/transform/resources/
```

#### OpenShift
```bash
# Set context (context name: openshift)
kubectl config use-context openshift
oc project my-app

# Build plugin
go build -o /tmp/plugins/crane-plugin-buildconfig-to-shipwright .

# Transform test data
crane transform \
  --export-dir ./tests/testdata/export \
  --transform-dir /tmp/transform \
  --plugin-dir /tmp/plugins \
  --optional-flags "registry-mapping=image-registry.openshift-image-registry.svc:5000=image-registry.openshift-image-registry.svc:5000"

# Apply to cluster
oc apply -f /tmp/transform/resources/
```

### 4. Verify Build Resources

```bash
# List Build resources
kubectl get builds

# Describe a Build
kubectl describe build <build-name>

# Trigger a BuildRun (manual)
kubectl create -f - <<EOF
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  name: <build-name>-run-1
spec:
  build:
    name: <build-name>
EOF

# Watch BuildRun progress
kubectl get buildrun -w
```

## Troubleshooting

### Minikube Issues

**Cluster won't start:**
```bash
# Delete and recreate
minikube delete -p minikube-shipwright
./hack/setup-minikube-shipwright.sh
```

**Registry not accessible:**
```bash
# Check registry addon
minikube addons list -p minikube-shipwright

# Enable if disabled
minikube addons enable registry -p minikube-shipwright
```

### OpenShift Issues

**Operator installation fails:**
```bash
# Check if you have cluster-admin permissions
oc auth can-i '*' '*'

# View operator logs
oc logs -n openshift-operators deployment/openshift-builds-operator
```

**Build fails with permission errors:**
```bash
# Grant privileged SCC to builder SA
oc adm policy add-scc-to-user privileged -z builder -n my-app
```

**Cannot push to internal registry:**
```bash
# Verify registry route exists
oc get route default-route -n openshift-image-registry

# Create if missing
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge -p '{"spec":{"defaultRoute":true}}'
```

## Kubectl Contexts

The setup scripts create and configure kubectl contexts for easy switching:

```bash
# List all contexts
kubectl config get-contexts

# Switch to minikube
kubectl config use-context minikube-shipwright

# Switch to OpenShift
kubectl config use-context openshift

# View current context
kubectl config current-context
```

## Environment Variables

All scripts support environment variables as an alternative to CLI flags:

```bash
# Minikube
export CLUSTER_NAME=my-cluster
export K8S_VERSION=v1.30.0
export CPUS=6
export MEMORY=16384
export SHIPWRIGHT_VERSION=v0.20.11
./hack/setup-minikube-shipwright.sh

# OpenShift
export NAMESPACE=my-namespace
export CONTEXT_NAME=openshift
export OPERATOR_VERSION=latest
./hack/setup-openshift-builds.sh
```

## Related Documentation

- [Shipwright Build Documentation](https://shipwright.io/docs/)
- [Tekton Documentation](https://tekton.dev/docs/)
- [OpenShift Builds](https://docs.openshift.com/container-platform/latest/cicd/builds/understanding-builds.html)
- [crane CLI](https://github.com/konveyor/crane)
