// ===========================================================================
//  卡通描邊 —— 反向外殼法（Inverted Hull）＋ 固定螢幕像素寬度
//
//  原理：把模型沿法線往外撐開一點，然後「只畫背面」（cull_front）。
//        模型本體蓋住撐開後殼的內部，只有比輪廓多出來的那一圈會露出來。
//
//  【為什麼要用像素寬度而不是公尺】
//  第一版是用固定的世界座標寬度（0.038 公尺）。結果：
//    近距離（3 公尺）→ 描邊佔畫面十幾像素，變成一圈粗黑輪廓
//    遠距離（30 公尺）→ 不到半個像素，完全消失
//  同一個角色在畫面上一下子粗一下子細，看起來就很「不協調」。
//
//  真實的手繪線稿，線寬是固定的（筆就是那個粗細）。所以這裡改成
//  依「頂點到相機的距離」反推世界座標的偏移量，讓描邊在畫面上
//  永遠維持約 outline_px 個像素。
//
//  換算：
//    某個世界長度 L 在距離 d 的畫面上佔的像素
//        px = L * (viewport_height / 2) / (d * tan(fov / 2))
//    反推要維持 px 需要多大的 L
//        L = px * d * tan(fov / 2) * 2 / viewport_height
// ===========================================================================

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.16, 0.11, 0.08, 1.0);

// 描邊在畫面上的目標寬度（像素）。1.5~2.5 是卡通線稿的舒適範圍。
uniform float outline_px : hint_range(0.0, 8.0) = 1.9;

// 由 GDScript 依實際視窗大小與相機 FOV 填入
uniform float viewport_height : hint_range(1.0, 4096.0) = 720.0;
uniform float fov_deg : hint_range(1.0, 179.0) = 68.0;

// 法線與「由原點往外的徑向」的混合。
// 平面著色的 low-poly 模型，同一個頂點在不同面上有不同法線，
// 純沿法線撐開時邊角會裂開；混一點徑向可以把裂縫收起來。
// 但徑向太重會讓描邊偏離輪廓，所以只留 0.18。
uniform float radial_blend : hint_range(0.0, 1.0) = 0.18;

// 超過這個距離就不再畫描邊（大氣透視：遠景不該有清楚的輪廓）
uniform float fade_start : hint_range(0.0, 400.0) = 70.0;
uniform float fade_end : hint_range(0.0, 800.0) = 150.0;

void vertex() {
	vec3 dir_normal = NORMAL;
	vec3 dir_radial = normalize(VERTEX + vec3(0.0001));
	vec3 dir = normalize(mix(dir_normal, dir_radial, radial_blend));

	// 頂點到相機的距離（視空間的 -z）
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(-view_pos.z, 0.01);

	// 由「想要的像素寬度」反推世界座標的偏移量
	float half_h = tan(radians(fov_deg) * 0.5);
	float world_w = outline_px * depth * half_h * 2.0 / viewport_height;

	// 遠景淡出：70 公尺內全寬、150 公尺外完全不畫
	float fade = 1.0 - smoothstep(fade_start, fade_end, depth);

	VERTEX += dir * world_w * fade;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
