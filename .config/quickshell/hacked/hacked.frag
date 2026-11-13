#version 300 es
precision highp float;

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;

void main() {
    vec2 uv = v_texcoord;

    // Static tear pattern. The Quickshell overlay provides the motion;
    // animated shader uniforms force Hyprland to disable damage tracking,
    // which tanks the GPU.
    float tear = step(0.985, fract(sin(uv.y * 17.0) * 43758.5453));
    uv.x += tear * sin(uv.y * 120.0) * 0.012;
    uv.x += sin(uv.y * 12.0) * 0.0015;

    // slight RGB split
    float r = texture(tex, uv + vec2(0.0028, 0.0)).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - vec2(0.0028, 0.0)).b;

    // static scanlines
    float scan = 0.91 + 0.09 * sin(uv.y * 900.0);

    fragColor = vec4(vec3(r, g, b) * scan, 1.0);
}
