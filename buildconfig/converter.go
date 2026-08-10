package buildconfig

import (
	buildv1 "github.com/openshift/api/build/v1"
	"github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

type Converter struct {
	Log  logrus.FieldLogger
	Opts PluginOptionalFields
}

func (c *Converter) Convert(bc *buildv1.BuildConfig) ([]unstructured.Unstructured, error) {
	return nil, nil
}
