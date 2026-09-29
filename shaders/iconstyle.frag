#version 440
// Theme-tinted icon styles, drawn in one colour:
//
//   dots = 0  monochrome: every pixel keeps the icon's alpha, and its ink
//             follows the icon's tone, so shapes and shading survive.
//   dots = 1  dot matrix: the icon is read once per grid cell, its tone is
//             ordered-dithered against a 4x4 Bayer matrix, and each cell in
//             the silhouette draws one round dot; unlit cells stay faintly
//             visible so the shape reads even where the icon is dark.
//
// "Tone" is the icon's brightness for a light tint and its darkness for a
// dark one (invert = 1), so the ink always lands on the parts that contrast
// with the dock behind it.
//
// contrast (0..1) stretches the tone around the icon's own average (a 4x4
// grid of samples weighted by coverage), so the symbol separates from
// its backdrop whether the icon is light or dark overall, and fades the
// faint parts out; near 1 an icon reduces to a flat, poster-like shape.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o iconstyle.frag.qsb iconstyle.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;      // straight (non-premultiplied) RGBA of the ink
    float grid;     // cells across (and down) the icon, dots mode
    float dotFill;  // dot diameter as a fraction of the cell
    float dimLevel; // ink of the icon's faintest parts
    float invert;   // 1 when the tint is dark
    float dots;     // 1 for the dot matrix, 0 for monochrome
    float alphaCut; // cell coverage below which a cell is outside the shape
    float contrast; // 0..1, adaptive contrast (see above)
};

layout(binding = 1) uniform sampler2D source;

// 4x4 Bayer threshold, 0..1, centred in its step. Built from the 2x2 matrix
// instead of a lookup table: some GLSL targets (e.g. NVIDIA's GL 1.x
// profiles) reject constant arrays.
float bayer2(vec2 a) {
    a = floor(a);
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 cell) {
    return bayer2(0.5 * cell) * 0.25 + bayer2(cell) + 0.5 / 16.0;
}

float toneOf(vec4 c) {
    vec3 rgb = c.rgb / max(c.a, 0.001);
    float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float t = mix(lum, 1.0 - lum, invert);
    return clamp(pow(t, 0.8) * 1.15, 0.0, 1.0);
}

// The tone after contrast: stretched around the icon's average tone.
float contrasted(float tone, float meanTone) {
    float gain = mix(1.0, 5.0, contrast);
    float stretched = clamp((tone - meanTone) * gain + 0.5, 0.0, 1.0);
    return mix(tone, stretched, contrast);
}

// The icon's average colour: 16 samples across it, weighted by coverage
// (the texture is premultiplied, so summing and dividing by alpha works).
vec4 iconAverage() {
    vec4 sum = vec4(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            sum += texture(source, (vec2(float(x), float(y)) + 0.5) / 4.0);
        }
    }
    return sum / 16.0;
}

void main() {
    vec4 avg = iconAverage();
    float meanTone = avg.a > 0.01 ? toneOf(avg) : 0.5;
    float dim = mix(dimLevel, dots < 0.5 ? 0.06 : 0.0, contrast);

    if (dots < 0.5) {
        vec4 c = texture(source, qt_TexCoord0);
        float ink = c.a * mix(dim, 1.0, contrasted(toneOf(c), meanTone)) * tint.a * qt_Opacity;
        fragColor = vec4(tint.rgb * ink, ink);
        return;
    }

    vec2 cellPos = qt_TexCoord0 * grid;
    vec2 cell = floor(cellPos);
    vec4 c = texture(source, (cell + 0.5) / grid);

    if (c.a < alphaCut) {
        fragColor = vec4(0.0);
        return;
    }

    // Extra contrast before dithering: mid-tones would otherwise dither into
    // noise at this resolution, where a poster-like split reads as a shape.
    float tone = contrasted(smoothstep(0.2, 0.8, toneOf(c)), smoothstep(0.2, 0.8, meanTone));
    float level = tone > bayer4(cell) ? 1.0 : dim;

    float r = length(fract(cellPos) - 0.5);
    float radius = dotFill * 0.5;
    float aa = max(fwidth(r), 0.0001);
    float dotMask = 1.0 - smoothstep(radius - aa, radius + aa, r);

    float alpha = dotMask * level * tint.a * qt_Opacity;
    fragColor = vec4(tint.rgb * alpha, alpha);
}
