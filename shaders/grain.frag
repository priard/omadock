#version 440
// Static film grain over the dock card. Every output pixel gets its own
// random value (a hash of its position, so it never changes and costs
// nothing once drawn); values away from the middle become light or dark
// specks. The card's rounded rectangle is cut out with a signed distance,
// so the grain never leaves the card's shape.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o grain.frag.qsb grain.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;   // 0..1
    float radius;     // card corner radius, logical px
    float cellScale;  // output pixels per logical px (grain = one output px)
    vec2 size;        // card size, logical px
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float roundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = roundedBox(p - size * 0.5, size * 0.5, min(radius, min(size.x, size.y) * 0.5));
    float inside = clamp(0.5 - d, 0.0, 1.0);

    float n = hash(floor(p * cellScale)) - 0.5;
    float a = abs(n) * 2.0 * strength * inside * qt_Opacity;
    vec3 speck = n > 0.0 ? vec3(1.0) : vec3(0.0);
    fragColor = vec4(speck * a, a);
}
