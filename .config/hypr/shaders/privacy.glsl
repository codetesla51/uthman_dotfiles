#version 300 es
precision highp float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 px = 1.0 / size;

    // Quantise to chunky blocks, then soften them. Text becomes unreadable
    // while the layout stays recognisable enough to keep your bearings.
    float block = 22.0;
    vec2 uv = (floor(v_texcoord * size / block) + 0.5) * block * px;
    uv = clamp(uv, px * 0.5, 1.0 - px * 0.5);

    vec2 o = px * 3.0;
    vec3 c = texture(tex, uv).rgb * 0.40;
    c += texture(tex, uv + vec2( o.x, 0.0)).rgb * 0.15;
    c += texture(tex, uv + vec2(-o.x, 0.0)).rgb * 0.15;
    c += texture(tex, uv + vec2(0.0,  o.y)).rgb * 0.15;
    c += texture(tex, uv + vec2(0.0, -o.y)).rgb * 0.15;

    float g = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(g), c, 0.18);
    c *= 0.32;

    // Subtle vignette makes the privacy state obvious at a glance.
    vec2 q = v_texcoord - 0.5;
    c *= 1.0 - dot(q, q) * 0.35;

    fragColor = vec4(c, 1.0);
}
