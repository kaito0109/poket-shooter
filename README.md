# Pocket TPS

Godot 4.6.3 / GDScript で作った、横持ちの簡単な3D TPS（サードパーソン・シューティング）試作です。
ボット8体を全て倒せば勝ち。ブラウザでそのまま遊べます。

## 遊ぶ

https://kaito0109.github.io/poket-shooter/

## 操作

- 移動: WASD / 矢印キー / 左スティック（タッチ）
- 視点: マウス（クリックでキャプチャ）/ 右ドラッグ / 画面右側をドラッグ（タッチ）
- 射撃: 左クリック長押し / FIREボタン（タッチ）
- ジャンプ: Space / JUMPボタン、リロード: R / RELOADボタン、ダッシュ: Shift

## 実装メモ

- プレイヤーと敵ボットは CharacterBody3D + コード生成のマップ（建物・木・箱）
- 敵AIは「接近→距離を保ってバースト射撃」のシンプルなステアリング方式
- 射撃はカメラ中心のレイキャスト（ヒットスキャン）、トレーサーとヒットスパーク付き
- スマホ向けタッチUI（左スティック、FIRE/JUMP/RELOADボタン、右側ドラッグで視点）はタッチ端末で自動表示

## モデルとライセンス

- プレイヤー／敵モデル: **CesiumMan**（KhronosGroup glTF Sample Models、CC-BY 4.0）
  https://github.com/KhronosGroup/glTF-Sample-Models/tree/main/2.0/CesiumMan
  敵は同じモデルを赤く着色して使用しています（歩行アニメーションがループ再生しやすい形式だったため）。
- モデルの GLB はこのリポジトリには含めていません。GitHub Actions がビルド時に上記リポジトリから
  `assets/player.glb` をダウンロードしてから Godot で書き出します（ワークフローの
  "Download free character model" ステップ）。手元で開発する場合は同じ場所に GLB を置いてください。

## ファイル構成

- `main.gd` - マップ生成、スポーン、勝敗管理、エフェクト
- `player.gd` - TPS操作、カメラ、射撃
- `enemy.gd` - 敵ボットのAI
- `hud.gd` / `joystick.gd` - HUDとタッチ操作
- `model_util.gd` - GLBモデルの取り付け・アニメーション制御
- `tracer.gd` - トレーサー／ヒットスパーク
- `.github/workflows/web-deploy.yml` - main への push で Web 版を自動ビルドして GitHub Pages に公開
