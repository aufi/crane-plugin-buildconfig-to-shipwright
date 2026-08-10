package buildconfig

import (
	"testing"

	"github.com/konveyor/crane-lib/transform"
	"github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func TestRunSkipsNonBuildConfig(t *testing.T) {
	tests := []struct {
		name       string
		resource   map[string]interface{}
		wantWhiteOut bool
	}{
		{
			name: "Deployment is skipped",
			resource: map[string]interface{}{
				"apiVersion": "apps/v1",
				"kind":       "Deployment",
				"metadata": map[string]interface{}{
					"name":      "myapp",
					"namespace": "default",
				},
			},
			wantWhiteOut: false,
		},
		{
			name: "BuildConfig with wrong API group is skipped",
			resource: map[string]interface{}{
				"apiVersion": "wrong.group/v1",
				"kind":       "BuildConfig",
				"metadata": map[string]interface{}{
					"name":      "myapp",
					"namespace": "default",
				},
			},
			wantWhiteOut: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			plugin := &BuildConfigTransformPlugin{Log: logrus.New()}
			request := transform.PluginRequest{
				Unstructured: unstructured.Unstructured{Object: tt.resource},
			}
			resp, err := plugin.Run(request)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if resp.IsWhiteOut != tt.wantWhiteOut {
				t.Errorf("IsWhiteOut = %v, want %v", resp.IsWhiteOut, tt.wantWhiteOut)
			}
			if resp.Patches != nil {
				t.Errorf("Patches should be nil for non-BuildConfig, got %d patches", len(resp.Patches))
			}
		})
	}
}

func TestParseOptionalFields(t *testing.T) {
	tests := []struct {
		name   string
		extras map[string]string
		check  func(t *testing.T, opts PluginOptionalFields)
	}{
		{
			name:   "empty extras",
			extras: map[string]string{},
			check: func(t *testing.T, opts PluginOptionalFields) {
				if opts.RegistryMapping != nil {
					t.Error("RegistryMapping should be nil")
				}
				if opts.ImageStreamMapping != nil {
					t.Error("ImageStreamMapping should be nil")
				}
				if opts.SearchRegistries != nil {
					t.Error("SearchRegistries should be nil")
				}
			},
		},
		{
			name: "registry mapping parsed",
			extras: map[string]string{
				"registry-mapping": "old.io=new.io,old2.io=new2.io",
			},
			check: func(t *testing.T, opts PluginOptionalFields) {
				if len(opts.RegistryMapping) != 2 {
					t.Fatalf("expected 2 registry mappings, got %d", len(opts.RegistryMapping))
				}
				if opts.RegistryMapping["old.io"] != "new.io" {
					t.Errorf("expected old.io=new.io, got %s", opts.RegistryMapping["old.io"])
				}
			},
		},
		{
			name: "imagestream mapping parsed",
			extras: map[string]string{
				"imagestream-mapping": "myns/mystream:latest=quay.io/org/img:latest",
			},
			check: func(t *testing.T, opts PluginOptionalFields) {
				if len(opts.ImageStreamMapping) != 1 {
					t.Fatalf("expected 1 imagestream mapping, got %d", len(opts.ImageStreamMapping))
				}
				if opts.ImageStreamMapping["myns/mystream:latest"] != "quay.io/org/img:latest" {
					t.Errorf("unexpected mapping: %v", opts.ImageStreamMapping)
				}
			},
		},
		{
			name: "search registries parsed",
			extras: map[string]string{
				"search-registries": "docker.io,quay.io",
			},
			check: func(t *testing.T, opts PluginOptionalFields) {
				if len(opts.SearchRegistries) != 2 {
					t.Fatalf("expected 2 search registries, got %d", len(opts.SearchRegistries))
				}
			},
		},
		{
			name: "strategy mapping parsed",
			extras: map[string]string{
				"default-build-strategy": "docker=my-buildah,s2i=my-s2i",
			},
			check: func(t *testing.T, opts PluginOptionalFields) {
				if opts.StrategyMapping["docker"] != "my-buildah" {
					t.Errorf("expected docker=my-buildah, got %s", opts.StrategyMapping["docker"])
				}
				if opts.StrategyMapping["s2i"] != "my-s2i" {
					t.Errorf("expected s2i=my-s2i, got %s", opts.StrategyMapping["s2i"])
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			opts, err := ParseOptionalFields(tt.extras)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			tt.check(t, opts)
		})
	}
}

func TestResolveImageRef(t *testing.T) {
	tests := []struct {
		name        string
		kind        string
		refName     string
		namespace   string
		opts        PluginOptionalFields
		wantRef     string
		wantWarning bool
		wantErr     bool
	}{
		{
			name:    "DockerImage returns name directly",
			kind:    "DockerImage",
			refName: "golang:1.21-alpine",
			wantRef: "golang:1.21-alpine",
		},
		{
			name:      "ImageStreamTag resolved via mapping",
			kind:      "ImageStreamTag",
			refName:   "mystream:latest",
			namespace: "myns",
			opts: PluginOptionalFields{
				ImageStreamMapping: map[string]string{
					"myns/mystream:latest": "quay.io/org/img:latest",
				},
			},
			wantRef: "quay.io/org/img:latest",
		},
		{
			name:        "ImageStreamTag falls back to internal registry URL",
			kind:        "ImageStreamTag",
			refName:     "mystream:v1",
			namespace:   "myns",
			wantRef:     "image-registry.openshift-image-registry.svc:5000/myns/mystream:v1",
			wantWarning: true,
		},
		{
			name:        "ImageStreamImage falls back to internal registry URL",
			kind:        "ImageStreamImage",
			refName:     "mystream@sha256:abc123",
			namespace:   "myns",
			wantRef:     "image-registry.openshift-image-registry.svc:5000/myns/mystream@sha256:abc123",
			wantWarning: true,
		},
		{
			name:      "Registry mapping applied after resolution",
			kind:      "ImageStreamTag",
			refName:   "mystream:latest",
			namespace: "myns",
			opts: PluginOptionalFields{
				ImageStreamMapping: map[string]string{
					"myns/mystream:latest": "old-registry.io/org/img:latest",
				},
				RegistryMapping: map[string]string{
					"old-registry.io": "new-registry.io",
				},
			},
			wantRef: "new-registry.io/org/img:latest",
		},
		{
			name:      "Registry mapping applied on fallback URL",
			kind:      "ImageStreamTag",
			refName:   "mystream:v1",
			namespace: "myns",
			opts: PluginOptionalFields{
				RegistryMapping: map[string]string{
					"image-registry.openshift-image-registry.svc:5000": "quay.io",
				},
			},
			wantRef: "quay.io/myns/mystream:v1",
		},
		{
			name:    "unknown kind returns error",
			kind:    "UnknownKind",
			refName: "something",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ref, warning, err := resolveImageRef(tt.kind, tt.refName, tt.namespace, tt.opts)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if ref != tt.wantRef {
				t.Errorf("ref = %q, want %q", ref, tt.wantRef)
			}
			if tt.wantWarning && warning == "" {
				t.Error("expected warning, got empty string")
			}
			if !tt.wantWarning && warning != "" {
				t.Errorf("unexpected warning: %s", warning)
			}
		})
	}
}
