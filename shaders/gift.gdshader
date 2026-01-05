shader_type spatial;

uniform sampler2D base_tex;
uniform sampler2D top_tex;
uniform sampler2D mask_tex;

void fragment() {
    vec2 uv = UV;

    vec4 base = texture(base_tex, uv);
    vec4 top = texture(top_tex, uv);
    float mask = texture(mask_tex, uv).r;

    ALBEDO = mix(base.rgb, top.rgb, mask);
    ALPHA = 1.0;
}
