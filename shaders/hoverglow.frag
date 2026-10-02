#version 440
// Glow hover effect: a soft halo in the accent colour that follows the
// icon's own shape. `source` is the icon rendered with a margin around it,
// already reduced to a small texture; sampling it over a disc of taps
// blurs its alpha into the halo. Behind the icon, so only the parts outside
// it (and through its holes) show.
//
// A ripple leaves the icon once as `ring` runs 0 -> 1 when the pointer
// arrives: the outline of the blurred shape, scaled up from the centre.
// level fades the halo in and out with the hover.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o hoverglow.frag.qsb hoverglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 glow;
    vec2 spread;    // blur radius, texture coordinates per axis
    float ring;     // ripple progress 0..1
    float level;    // 0..1 hover fade
};

layout(binding = 1) uniform sampler2D source;

// Alpha averaged over a disc: the centre and three rings of eight taps.
float blurredAlpha(vec2 uv) {
    float sum = texture(source, uv).a;
    float weight = 1.0;
    for (int r = 1; r <= 3; r++) {
        vec2 rad = spread * float(r) / 3.0;
        float w = 1.0 - float(r) / 4.0;
        for (int i = 0; i < 8; i++) {
            float ang = 6.2831853 * (float(i) + 0.5 * float(r)) / 8.0;
            sum += texture(source, uv + vec2(cos(ang), sin(ang)) * rad).a * w;
            weight += w;
        }
    }
    return sum / weight;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float halo = clamp(blurredAlpha(uv) * 2.4, 0.0, 1.0) * level;

    float ringA = 0.0;
    if (ring > 0.0 && ring < 1.0) {
        vec2 scaled = (uv - 0.5) / (1.0 + ring * 0.45) + 0.5;
        float e = blurredAlpha(scaled);
        ringA = smoothstep(0.08, 0.3, e) * (1.0 - smoothstep(0.3, 0.6, e)) * (1.0 - ring) * 0.9;
    }

    float a = clamp(halo + ringA, 0.0, 1.0) * qt_Opacity;
    fragColor = vec4(glow.rgb * a, a);
}
