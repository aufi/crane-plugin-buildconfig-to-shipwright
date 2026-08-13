package buildconfig

import (
	"encoding/json"
	"fmt"

	"github.com/konveyor/crane-lib/transform"
	buildv1 "github.com/openshift/api/build/v1"
	"github.com/sirupsen/logrus"
)

const PluginVersion = "v0.1.0"

const (
	RegistryMappingFlag      = "registry-mapping"
	ImageStreamMappingFlag   = "imagestream-mapping"
	DefaultBuildStrategyFlag = "default-build-strategy"
	SearchRegistriesFlag     = "search-registries"
	InsecureRegistriesFlag   = "insecure-registries"
	BlockRegistriesFlag      = "block-registries"
)

type BuildConfigTransformPlugin struct {
	Log logrus.FieldLogger
}

func (p *BuildConfigTransformPlugin) Metadata() transform.PluginMetadata {
	return transform.PluginMetadata{
		Name:    "BuildConfigPlugin",
		Version: PluginVersion,
		OptionalFields: []transform.OptionalFields{
			{
				FlagName: RegistryMappingFlag,
				Help:     "Map of image registry paths to replace, format: old-registry1=new-registry1,old-registry2=new-registry2",
				Example:  "image-registry.openshift-image-registry.svc:5000=quay.io/myorg",
			},
			{
				FlagName: ImageStreamMappingFlag,
				Help:     "Map of ImageStreamTag references to concrete image URLs, format: namespace/name:tag=registry/image:tag",
				Example:  "myns/mystream:latest=quay.io/myorg/myimage:latest",
			},
			{
				FlagName: DefaultBuildStrategyFlag,
				Help:     "Override default ClusterBuildStrategy names, format: docker=my-buildah,s2i=my-s2i",
				Example:  "docker=my-buildah,s2i=my-s2i",
			},
			{
				FlagName: SearchRegistriesFlag,
				Help:     "Comma-separated list of search registries for Buildah",
				Example:  "docker.io,quay.io",
			},
			{
				FlagName: InsecureRegistriesFlag,
				Help:     "Comma-separated list of insecure registries for Buildah",
				Example:  "my-registry.local:5000",
			},
			{
				FlagName: BlockRegistriesFlag,
				Help:     "Comma-separated list of blocked registries for Buildah",
				Example:  "docker.io",
			},
		},
		RequestVersion:  []transform.Version{transform.V1},
		ResponseVersion: []transform.Version{transform.V1},
	}
}

func (p *BuildConfigTransformPlugin) Run(request transform.PluginRequest) (transform.PluginResponse, error) {
	u := request.Unstructured
	gvk := u.GetObjectKind().GroupVersionKind()

	if gvk.Kind != "BuildConfig" || gvk.Group != "build.openshift.io" {
		return transform.PluginResponse{
			Version: string(transform.V1),
		}, nil
	}

	opts, err := ParseOptionalFields(request.Extras)
	if err != nil {
		return transform.PluginResponse{}, fmt.Errorf("error parsing optional fields: %w", err)
	}

	bc := &buildv1.BuildConfig{}

	jsonBytes, err := u.MarshalJSON()
	if err != nil {
		return transform.PluginResponse{}, fmt.Errorf("error marshaling BuildConfig to JSON: %w", err)
	}

	err = json.Unmarshal(jsonBytes, bc)
	if err != nil {
		return transform.PluginResponse{}, fmt.Errorf("error decoding BuildConfig: %w", err)
	}

	converter := &Converter{
		Log:  p.log(),
		Opts: opts,
	}

	newResources, err := converter.Convert(bc)
	if err != nil {
		return transform.PluginResponse{}, fmt.Errorf("error converting BuildConfig %s: %w", bc.Name, err)
	}

	if len(newResources) == 0 {
		p.log().Warnf("BuildConfig %s was not converted — passing through unchanged", bc.Name)
		return transform.PluginResponse{
			Version: string(transform.V1),
		}, nil
	}

	return transform.PluginResponse{
		Version:      string(transform.V1),
		IsWhiteOut:   true,
		NewResources: newResources,
	}, nil
}

func (p *BuildConfigTransformPlugin) log() logrus.FieldLogger {
	if p.Log != nil {
		return p.Log
	}
	return logrus.New()
}

type PluginOptionalFields struct {
	RegistryMapping    map[string]string
	ImageStreamMapping map[string]string
	StrategyMapping    map[string]string
	SearchRegistries   []string
	InsecureRegistries []string
	BlockRegistries    []string
}

func ParseOptionalFields(extras map[string]string) (PluginOptionalFields, error) {
	opts := PluginOptionalFields{}

	if v, ok := extras[RegistryMappingFlag]; ok && v != "" {
		opts.RegistryMapping = transform.ParseOptionalFieldMapVal(v)
	}
	if v, ok := extras[ImageStreamMappingFlag]; ok && v != "" {
		opts.ImageStreamMapping = transform.ParseOptionalFieldMapVal(v)
	}
	if v, ok := extras[DefaultBuildStrategyFlag]; ok && v != "" {
		opts.StrategyMapping = transform.ParseOptionalFieldMapVal(v)
	}
	if v, ok := extras[SearchRegistriesFlag]; ok && v != "" {
		opts.SearchRegistries = transform.ParseOptionalFieldSliceVal(v)
	}
	if v, ok := extras[InsecureRegistriesFlag]; ok && v != "" {
		opts.InsecureRegistries = transform.ParseOptionalFieldSliceVal(v)
	}
	if v, ok := extras[BlockRegistriesFlag]; ok && v != "" {
		opts.BlockRegistries = transform.ParseOptionalFieldSliceVal(v)
	}

	return opts, nil
}
