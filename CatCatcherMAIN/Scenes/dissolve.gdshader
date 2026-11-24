shader_type canvas_item;

// 撕纸式消散：噪声阈值以下的像素直接消失，消失边缘留一圈"烧焦"色。
// 每只猫被撞飞时，在它原来的格子上留一个残影，用这个 shader 在 0.35 秒里烧掉。
//
// 全靠 UV + progress 驱动，**不需要任何贴图** —— M4 里少数完全不需要美术的效果之一。
// 撕纸感靠 grain 调：数值越大，边缘越碎。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 burn_color : source_color = vec4(0.96, 0.56, 0.22, 1.0);
uniform float grain : hint_range(1.0, 40.0) = 13.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		float n = value_noise(UV * grain);
		float edge = progress * 1.15;
		float alive = step(edge, n);
		float burn = smoothstep(edge, edge + 0.10, n);
		vec3 rgb = mix(burn_color.rgb, base.rgb, burn);
		COLOR = vec4(rgb, base.a * alive);
	}
}
