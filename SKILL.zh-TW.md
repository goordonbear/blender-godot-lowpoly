# Blender + Godot 4 Low-Poly 流程

在 Blender 裡程序化建模 → glTF → Godot 4，搭配三渲二視覺風格。
內容提煉自一個已完成的無限跑酷專案。

> English version: [SKILL.md](SKILL.md)

## 核心原則

**Blender 管幾何與基色，Godot 管風格。**

材質在執行期轉換，所以調整美術方向不需要重新匯出任何網格。
Blender 腳本裡不要做任何著色決定。

## 工作流程

```
1. Blender headless 建模        →  blender --background --factory-startup --python
2. 匯出 .glb（export_yup=True）  →  assets/models/*.glb
3. 每個 glb 包一層 .tscn         →  Node3D 根 + 腳本 + glb 子節點
4. 匯入 Godot                   →  --headless --editor --quit（順便註冊 class_name）
5. 執行期轉換材質                →  Toon.apply(root)
6. 錄影驗證畫面                  →  --write-movie out.avi（headless 無法渲染）
```

新增 `class_name` 之後**一定要做第 4 步**，否則會出現
`Identifier "X" not declared in the current scope`。

## 建模：斷面放樣

**不要**把基本體拼起來。要做成一條連續的網格：

```
環 1 → 環 2 → 環 3 → … → 環 N
```

每一環是一組 `Vector` 點，`loft()` 把相鄰兩環的同序號頂點連成四邊面。
形狀靠調整每一環的半徑、中心與輪廓來塑造。

好處：輪廓是雕塑出來的、四邊面拓撲乾淨、平面著色天生就有 Low-Poly 的切面感。

可重用的 `loft` / `tube` / `obj_from` 見 `templates/blender_loft.py`。
實際的斷面表範例見 `reference.zh-TW.md`。

## 座標轉換（零件錯位的第一號元凶）

| | Blender | Godot |
| --- | --- | --- |
| 前方 | +Y | **-Z** |
| 上方 | +Z | **+Y** |
| 右方 | +X | +X |

匯出時設 `export_yup=True`。Blender 裡 YZ 平面上的圓，到 Godot 會變成
ZY 平面（繞 X 軸旋轉）。

## 骨架規則：原點放在關節上

每個可動零件的原點都設在旋轉軸上，這樣 Godot 只要設 `rotation` 就好，
不需要任何軸心校正：

```
Rider
├── Bike
│   ├── WheelFront / WheelRear     原點在輪轂
│   └── Crank                      原點在大盤
└── ThighL → ShinL → FootL         髖 / 膝 / 踝
```

關節常數要**同時寫在兩邊的腳本裡**並視為契約
（`HIP_Y`、`L_THIGH`、`L_SHIN`、`WHEEL_R`）。

## 材質轉換

`Toon.apply()` 會走訪所有 `MeshInstance3D`，讀取匯入的基礎色，換上三階
cel 材質。程式碼見 `reference.zh-TW.md`，著色器見
`templates/toon3color.gdshader`。

兩條硬規則：

- **描邊寬度必須是螢幕像素，不是公尺。** 用固定的世界座標寬度，會讓同一個
  角色近看是粗黑邊、遠看完全消失 —— 那正是「描邊看起來不協調」的意思。
- **多塊體疊出來的物件要關掉描邊。** 每個塊體各自擴張外殼，小的會穿出大的，
  結果出現穿過物件**內部**的黑線。在包裝腳本上加一個 `outline` 開關。

## Godot 4 專案骨架

| 腳本 | 職責 |
| --- | --- |
| `GameConfig`（Resource） | 所有可調數值 + 難度公式 |
| `GameState`（Autoload） | 最高分持久化 |
| `GameManager` | 狀態機、分數、碰撞、時間凝滯 |
| `World` | 捲動、生成、背景 |
| `PlayerController` | 動畫（IK）、跳躍、擠壓拉伸 |
| `CameraRig` | 跟隨、FOV、抖動 |
| `HUD` | 面板、彈窗 |
| `Sfx` | 程序化音效 |

## 無限跑酷的關鍵決定

- **玩家固定在原點，世界往玩家移動。** 沒有浮點漂移，邏輯單純。
- **不用物理引擎做碰撞。** AABB 重疊更快、更確定、可單元測試。
- **相機用固定方位角 + 固定俯角，絕不用 `look_at`。** `look_at` 會把角色的
  畫面位置跟注視點距離綁在一起，每次調參都要重算。
- **難度用反應時間設計，不要用間距距離。** 空間間距必須永遠大於一次完整
  跳躍的前進距離，否則會出現無法通過的組合。
- **支援自訂碰撞盒。** 障礙物的實際判定範圍不一定是視覺邊界 —— 允許場景放一個
  名為 `HitBox` 的 `Area3D` + `BoxShape3D` 來覆寫合併網格的 AABB。

## 驗證迴圈

```
--headless --quit                     # 確認零腳本錯誤
--headless --script res://tests/...   # 斷言，exit code 0 才算通過
--write-movie out.avi --fixed-fps 30  # 看實際像素
```

headless 沒有渲染器 —— **不用 `--write-movie` 就看不到任何畫面**。
用 ffmpeg 抽格出來看。輪子陷進地面、邊緣鋸齒、天空污塊這些問題
在 log 裡完全看不到，但在畫面上很明顯。

## 其他資源

- 完整程式碼、常數與實例：[reference.zh-TW.md](reference.zh-TW.md)
- 可重用的網格輔助函式：[templates/blender_loft.py](templates/blender_loft.py)
- 三渲二著色器：[templates/toon3color.gdshader](templates/toon3color.gdshader)
- 描邊著色器：[templates/outline.gdshader](templates/outline.gdshader)
