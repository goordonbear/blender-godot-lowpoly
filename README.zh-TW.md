# blender-godot-lowpoly

一個 Agent Skill：用 **Blender headless 程序化建模** 搭配 **Godot 4** 製作 Low-Poly 3D 遊戲。

內容提煉自一個已完成的無限跑酷專案：一隻鵜鶘騎著單車沿著海岸公路前進，
全部模型由 Blender 腳本程序化生成、三渲二著色、卡通描邊、程序化音效，
並附帶 51 項自動化測試。

> English version: [README.md](README.md)

---

## 這個 Skill 教什麼

| 主題 | 內容 |
| --- | --- |
| **建模** | 斷面放樣（Cross-section Lofting）—— 雕塑出輪廓，而不是把基本體拼起來 |
| **座標** | Blender `+Y/+Z` → glTF `export_yup` → Godot `-Z/+Y`，以及隨之而來的所有陷阱 |
| **骨架** | 原點放在關節上，Godot 直接 `rotation` 就能動，不需要校正軸心 |
| **材質** | 執行期把 PBR 轉成三階 cel 材質；基礎色驅動整組配色 |
| **描邊** | 反向外殼法 ＋ **固定螢幕像素寬度**，以及什麼時候該關掉描邊 |
| **架構** | 無限跑酷的分層：Config 資源、狀態機、AABB 碰撞 |
| **難度** | 用「反應時間」設計難度，再換算成距離 —— 不是反過來 |
| **驗證** | Headless 測試 + `--write-movie` 逐格檢查實際畫面 |
| **工具** | `.bat` 編碼、BOM 陷阱、JavaScript `replace()` 的坑 |

---

## 安裝

把資料夾複製到你的 skills 目錄：

```bash
# 個人用（所有專案都能用）
cp -r blender-godot-lowpoly ~/.agents/skills/

# 專案專用
cp -r blender-godot-lowpoly <your-repo>/.cursor/skills/
```

然後明確指定，例如：「用 blender-godot-lowpoly 這個 skill」。

---

## 檔案結構

```
SKILL.md                         ← 進入點：工作流程、規則、陷阱
SKILL.zh-TW.md                   ← 同上的繁體中文版
reference.md                     ← 完整程式碼：輔助函式、著色器、常數、公式
reference.zh-TW.md               ← 同上的繁體中文版
README.md / README.zh-TW.md      ← 你在看的這份
templates/blender_loft.py        ← 可直接執行的建模骨架
templates/toon3color.gdshader    ← 三階 cel 著色器
templates/outline.gdshader       ← 反向外殼描邊（像素寬度）
```

兩個著色器與 Python 輔助檔**不是節錄** —— 它們是實際出貨、在引擎裡驗證過的檔案原封不動搬過來的。

---

## 幾段核心程式碼

### 用一圈一圈的斷面疊出一個連續網格

```python
rings = [ring_pts(y, cz, rx, rz, SIDES, flat_bottom=fb)
         for (y, cz, rx, rz, fb) in BODY_PROFILE]
verts, faces = loft(rings)
```

每一圈都刻意調整半徑與中心高度，輪廓才會是「雕塑」出來的而不是拉長的球體。

### 描邊寬度必須用像素，不是公尺

```glsl
// 由「想要的像素寬度」反推世界座標的偏移量
float world_w = outline_px * depth * tan(radians(fov_deg) * 0.5)
              * 2.0 / viewport_height;
VERTEX += dir * world_w * fade;
```

用固定的公尺數會讓同一個角色近看是粗黑邊、遠看完全消失 —— 那正是
「描邊看起來很不協調」的真正原因。

### 難度用時間設計，再換算成距離

```gdscript
func gap_for_speed(speed: float) -> float:
    var v := clampf(speed, base_speed, max_speed)   # 夾制一次，全程用同一個值
    var t := inverse_lerp(base_speed, max_speed, v)
    var interval := lerpf(gap_time_start, gap_time_end, t)
    return maxf(v * interval, min_gap)
```

空間間距永遠要大於一次完整跳躍的前進距離，否則會出現物理上無法通過的組合。

---

## 這份 Skill 解決過的真實問題

以下每一個都是「程式跑得動、看起來好像正常」的類型：

1. `get_node_or_null("Player")` 找的是子節點，但 Player 是**兄弟節點** → 全部回傳 null
2. AABB 掃描只走直接子節點 → 障礙物碰撞盒永遠是空的 → **完全沒有碰撞判定**
3. 用固定座標當生成指標 → 障礙物生成 3 個之後永久停止
4. 夾制後的速度只用在插值，乘的時候仍用原始值 → 算出 221 公尺的荒謬間距
5. 反向外殼法在凹面會往模型內部擠 → 多塊體物件（雲）出現內部黑線
6. `fog_sky_affect` 預設 1.0 → 整個天空盒被染成單一霧色
7. `sky_curve` 方向搞反 → 把橘色推滿整個天空
8. `.bat` 用 UTF-8 存中文 → `cmd.exe` 用 CP950 讀，拆成碎片變成不存在的指令

---

## 授權

MIT —— 見 [LICENSE](LICENSE)。
