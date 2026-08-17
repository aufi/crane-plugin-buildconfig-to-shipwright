package buildconfig

import (
	"fmt"
	"sort"
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

		streamRef := name
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
	// Iterate in a deterministic order: longest prefix first (most specific
	// mapping wins), ties broken lexically. Plain map iteration order is
	// random in Go, which made the winner nondeterministic when multiple
	// keys matched (BUILD-2339).
	keys := make([]string, 0, len(registryMapping))
	for k := range registryMapping {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if len(keys[i]) != len(keys[j]) {
			return len(keys[i]) > len(keys[j])
		}
		return keys[i] < keys[j]
	})
	for _, oldRegistry := range keys {
		if oldRegistry == "" {
			// A malformed mapping entry (e.g. "=newvalue") yields an empty
			// key, which HasPrefix would match against every image ref.
			// Ignore it rather than silently remapping everything.
			continue
		}
		if strings.HasPrefix(imageRef, oldRegistry) {
			return registryMapping[oldRegistry] + imageRef[len(oldRegistry):]
		}
	}
	return imageRef
}
