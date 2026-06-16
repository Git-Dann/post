// Core Image Metal kernel for film grain.
//
// Compiled with -fcikernel (compiler) / -cikernel (linker) so it can be loaded as a CIColorKernel.
// Lives in each target that runs the pipeline (app + extensions); FilterPipeline loads it from the
// host bundle's default.metallib. Because it's part of the shared FilterPipeline, it applies to the
// live preview, the full-resolution export, and any style that sets a grain amount.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

namespace {
    // Cheap 2D hash → [0,1).
    inline float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // Smooth value noise (interpolated hash) → soft, organic grain rather than sharp digital speckle.
    inline float valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float a = hash(i);
        float b = hash(i + float2(1.0, 0.0));
        float c = hash(i + float2(0.0, 1.0));
        float d = hash(i + float2(1.0, 1.0));
        float2 u = f * f * (3.0 - 2.0 * f);     // smoothstep
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
}

// amount: grain strength (already capped by the caller).
// grainSize: noise cell size in pixels (scaled so preview/export density match).
extern "C" float4 postGrain(coreimage::sample_t s, float amount, float grainSize, coreimage::destination dest) {
    float2 coord = dest.coord();
    float n = valueNoise(coord / max(grainSize, 0.5)) - 0.5;        // centered ±0.5

    // Real film grain lives in the midtones — fade it out of deep shadows and bright highlights.
    float lum = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
    float weight = clamp(1.0 - abs(lum - 0.5) * 1.6, 0.0, 1.0);

    float g = n * amount * weight;             // monochromatic, additive
    return float4(s.rgb + g, s.a);
}
