package buildconfig

import (
	"fmt"
	"strings"
)

const internalRegistryURL = "image-registry.openshift-image-registry.svc:5000"

func resolveImageRef(kind, name, namespace string, opts PluginOptionalFields) (string, string, error) {
	switch kind {
	case "DockerImage":
		return applyRegistryMapping(name, opts.RegistryMapping), "", nil

	case "ImageStreamTag", "ImageStreamImage":
		key := namespace + "/" + name
		if mapped, ok := opts.ImageStreamMapping[key]; ok {
			return applyRegistryMapping(mapped, opts.RegistryMapping), "", nil
		}

		var streamRef string
		if kind == "ImageStreamTag" {
			streamRef = name
		} else {
			streamRef = name
		}
		fallback := internalRegistryURL + "/" + namespace + "/" + streamRef
		originalFallback := fallback
		fallback = applyRegistryMapping(fallback, opts.RegistryMapping)

		// Only warn if the fallback wasn't transformed by registry mapping
		var warning string
		if fallback == originalFallback {
			warning = fmt.Sprintf("ImageStream reference %q in namespace %q could not be resolved — no --imagestream-mapping provided. Using fallback: %s. Provide --imagestream-mapping to set the correct image reference.", name, namespace, fallback)
		}
		return fallback, warning, nil

	default:
		return "", "", fmt.Errorf("unknown image reference kind %q for %q", kind, name)
	}
}

func applyRegistryMapping(imageRef string, registryMapping map[string]string) string {
	for oldRegistry, newRegistry := range registryMapping {
		if strings.HasPrefix(imageRef, oldRegistry) {
			imageRef = newRegistry + imageRef[len(oldRegistry):]
			break
		}
	}
	return imageRef
}
