{{flutter_js}}
{{flutter_build_config}}

// Limit overlay surfaces to 1 to reduce the chance of WebGL context exhaustion
// without falling back to the slow CPU-only path.
// See https://github.com/flutter/flutter/issues/184683
_flutter.loader.load({
  config: {
    canvasKitMaximumSurfaces: 1,
  },
});
