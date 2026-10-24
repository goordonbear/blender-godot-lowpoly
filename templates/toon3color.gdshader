// 三渲二（cel）著色器 —— 3 色 2 階
// =====================================================================
// 用途：所有遊戲物件共用的 toon 材質。把連續的光照切成三個色階，
//       讓 low-poly 的平面切面更有漫畫／動畫的塊面感。
//
// 原理：
//   ndl = 法線與光源的夾角餘弦
//   用兩個門檻把 ndl 分成「陰影 / 中間 / 亮面」三段，
//   每段輸出一個固定顏色（不是乘上明暗，而是直接換色）。
//   這樣才會出現硬邊色塊，而不是漸層。
//
// 另外加一圈邊緣光（rim），讓輪廓從背景裡跳出來 —— 對低多邊形模型
// 特別有效，因為它強調了切面的轉折。
// =====================================================================
shader_type spatial;
render_mode specular_disabled, cull_back;

// ---- 三個色階（三渲二的核心：三色兩階） ----
uniform vec3 color_shadow : source_color = vec3(0.42, 0.47, 0.62);
uniform vec3 color_mid    : source_color = vec3(0.72, 0.75, 0.80);
uniform vec3 color_light  : source_color = vec3(1.00, 0.98, 0.94);

// ---- 門檻：ndl 低於 low 全暗、low~high 中間、高於 high 全亮 ----
uniform float threshold_low  : hint_range(0.0, 1.0) = 0.32;
uniform float threshold_high : hint_range(0.0, 1.0) = 0.68;
// 邊界柔化，0 = 完全硬邊
uniform float band_softness : hint_range(0.0, 0.30) = 0.035;

// ---- 邊緣光 ----
uniform vec3  rim_color : source_color = vec3(1.0, 0.96, 0.85);
uniform float rim_power : hint_range(0.5, 12.0) = 3.2;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.30;

// ---- 整體色偏，讓每個物件可以微調而不必另開材質 ----
uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness : hint_range(0.0, 2.0) = 0.50;

void fragment() {
	ALBEDO = color_mid * tint;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	// 不需要高光：三渲二通常把高光畫成色塊，而不是用 BRDF
	SPECULAR = 0.0;
}

void light() {
	// 主要光源方向：把 LIGHT 正規化後與 NORMAL 求餘弦
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);
	float ndl = dot(n, l);

	// 兩段 smoothstep 就是「2 階」—— 產生 3 個顏色區間
	float t1 = smoothstep(threshold_low - band_softness,
	                      threshold_low + band_softness, ndl);
	float t2 = smoothstep(threshold_high - band_softness,
	                      threshold_high + band_softness, ndl);

	vec3 band = mix(color_shadow, color_mid, t1);
	band = mix(band, color_light, t2);

	// 邊緣光：視線與法線越垂直越亮
	vec3 v = normalize(VIEW);
	float facing = clamp(dot(n, v), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power) * rim_strength;

	vec3 lit = band * brightness + rim_color * rim;

	// 陰影不參與計算（三渲二的色階本身就是陰影）
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR;
}
