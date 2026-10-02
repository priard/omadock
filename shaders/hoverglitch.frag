#version 440
// Glitch hover effect: the icon split into RGB channels and cut into
// horizontal bands that jump sideways, with faint scanlines, strongest
// mid-burst as `t` runs 0 -> 1. Replaces the icon while it runs.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o hoverglitch.frag.qsb hoverglitch.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // burst progress 0..1
    float seed;     // varies the band pattern between bursts
};

layout(binding = 1) uniform sampler2D source;

float hash(float n) {
    return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

vec4 sampleIn(vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
    return texture(source, uv);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float amp = sin(3.14159265 * clamp(t, 0.0, 1.0));
    float tick = floor(t * 10.0);
    float band = floor(uv.y * 9.0);
    float shift = hash(band + tick * 17.0) > 0.55 ? (hash(band * 3.1 + tick) - 0.5) * 0.22 * amp : 0.0;
    float split = 0.045 * amp;
    vec2 base = uv + vec2(shift, 0.0);
    vec4 r = sampleIn(base + vec2(split, 0.0));
    vec4 g = sampleIn(base);
    vec4 b = sampleIn(base - vec2(split, 0.0));
    float a = max(max(r.a, g.a), b.a);
    float scan = 1.0 - 0.18 * amp * step(0.5, fract(uv.y * 24.0));
    fragColor = vec4(r.r, g.g, b.b, a) * scan * qt_Opacity;
}
