# PolarDrift

赤道儀の極軸合わせを支援する iOS アプリ。ドリフト法（Drift Alignment）をガイドし、星の Dec 軸方向のドリフトを自動計測・フィードバックする。

## 概要

望遠鏡カメラで星を撮影しながら、以下の流れで極軸合わせを行う。

1. **方位角フェーズ** — 南中付近の星で計測し、極軸の東西ズレを修正
2. **高度フェーズ** — 東・西の地平線付近の星で計測し、極軸の高度ズレを修正

各フェーズでキャリブレーション → ドリフト計測を繰り返し、ドリフト量が有意でなくなったらフェーズ完了。

## セッションフロー

```
phaseGuide(azimuth)
  ↓ 「スタート」
calibration.detectingCentroid   ← 星の重心を自動検出
  ↓ 重心確定
calibration.awaitingDecMove     ← Dec軸方向を特定するため星を手動移動
  ↓ 10% 以上の移動を検出
driftMeasure.reintroducing(1)   ← 星を元の位置に戻す（十字線追従）
  ↓ 「スタート」
driftMeasure.measuring(1)       ← 最大30秒間 Dec 方向ドリフトを計測
  ↓ 有意 or タイムアウト
driftMeasure.showingResult      ← 調整指示を表示（「スキップ」で次へ）
  ↓ 繰り返し
phaseComplete(azimuth)
  ↓
... altitude フェーズ ...
  ↓
sessionComplete
```

## ドリフト計測アルゴリズム

### キャリブレーション

カメラ画像の正規化座標（0–1）でセントロイドを検出し、ユーザーが Dec モーターで星を移動させた軌跡から Dec 軸方向ベクトルを算出する。移動量の閾値は画像幅の 10%（`decMoveThreshold = 0.10`）。

### ドリフト測定

各フレームの重心を `DecCalibration.decComponent(of:)` で Dec 軸に投影し、経過時間 t に対してオンライン線形回帰（O(1)/フレーム）を実行する。

```
y(t) = a + b·t
b = ドリフト速度 [Dec軸正規化単位/秒]
```

実ピクセル換算: `rate_px_per_min = b × 60 × imageHeight`

### 有意性検定

| 条件 | 値 |
|------|-----|
| 最低サンプル数 | 10 フレーム |
| t 統計量の閾値 | \|t\| > 2.0（95% 信頼区間） |
| 実ピクセル速度の下限 | 1 px/min |
| 早期終了条件 | 有意 かつ 経過 5 秒以上 |
| タイムアウト | 30 秒 |

### フィードバックロジック

```
isSignificant == false  → complete（調整完了）
current と previous が同符号 かつ |current| < |previous|  → sameDirection（同じ方向へ）
それ以外  → reverseDirection（逆方向へ）
```

## 音声コマンド

| コマンド | タイミング | 動作 |
|----------|-----------|------|
| 「スタート」 | phaseGuide / calibration / driftMeasure | 次ステップへ進む |
| 「スキップ」 | showingResult | 現在の測定をスキップして次のイテレーションへ |

## CSV 出力

セッション開始時に Documents ディレクトリへ 2 つの CSV を即時作成する。ファイルアプリの「PolarDrift」フォルダから参照できる。

### 概要 CSV: `polardrift_YYYYMMDD_HHmmss.csv`

1 行 = 1 測定イテレーション

| 列 | 単位 | 説明 |
|----|------|------|
| session_id | — | セッション UUID |
| session_start | ISO 8601 | セッション開始時刻 |
| phase | — | `azimuth` / `altitude` |
| cal_dec_axis_x/y | 正規化単位 | Dec 軸方向ベクトル |
| iteration | — | イテレーション番号 |
| duration_sec | 秒 | 計測時間 |
| sample_count | — | サンプル数（フレーム数） |
| drift_rate_px_per_min | px/min | ドリフト速度（実ピクセル） |
| drift_rate_se_2sigma | px/min | 標準誤差 × 2（95% CI 幅） |
| t_statistic | — | t 統計量 |
| is_significant | bool | 有意かどうか |
| feedback | — | `sameDirection` / `reverseDirection` / `complete` / `skipped` |

### 生データ CSV: `polardrift_raw_YYYYMMDD_HHmmss.csv`

1 行 = 1 フレーム（約 30 fps）

| 列 | 単位 | 説明 |
|----|------|------|
| session_id | — | セッション UUID |
| phase | — | `azimuth` / `altitude` |
| iteration | — | イテレーション番号 |
| elapsed_sec | 秒 | 計測開始からの経過時間 |
| x_norm / y_norm | 正規化 (0–1) | 重心座標 |
| dec_disp_norm | 正規化単位 | Dec 軸方向変位 |

### R での読み込み例

```r
df <- read.csv("polardrift_20260510_120000.csv")
raw <- read.csv("polardrift_raw_20260510_120000.csv")

# フェーズ別のドリフト速度推移
library(ggplot2)
ggplot(df, aes(x = iteration, y = drift_rate_px_per_min, color = phase)) +
  geom_line() + geom_point() +
  geom_errorbar(aes(ymin = drift_rate_px_per_min - drift_rate_se_2sigma / 2,
                    ymax = drift_rate_px_per_min + drift_rate_se_2sigma / 2)) +
  theme_minimal()
```

## アーキテクチャ

```
SessionView
  └── SessionViewModel          ← セッション全体の状態機械
        ├── CalibrationViewModel  ← キャリブレーション処理
        ├── DriftMeasureViewModel ← ドリフト計測処理
        │     └── DriftTracker   ← OnlineRegression + rawFrames
        ├── CameraManager        ← AVFoundation, AsyncStream<GrayImage>
        ├── SpeechRecognitionManager ← 音声コマンド認識
        └── SessionRecorder      ← CSV 書き込み
```

### 主要ファイル

| ファイル | 役割 |
|---------|------|
| `Models/SessionStep.swift` | セッション状態機械の定義 |
| `Models/DecCalibration.swift` | Dec 軸ベクトルと投影演算 |
| `Models/OnlineRegression.swift` | O(1) オンライン線形回帰 |
| `Models/DriftFeedback.swift` | フィードバック評価ロジック |
| `Camera/DriftTracker.swift` | 重心追跡・統計・ロギング |
| `Camera/FrameProcessor.swift` | セントロイド検出 |
| `Camera/CameraManager.swift` | カメラセットアップ・フレームストリーム |
| `Persistence/SessionRecorder.swift` | CSV 即時書き込み |

## 要件

- iOS 17 以上（`@Observable` マクロ使用）
- 実機必須（カメラ・音声認識）
- Xcode 15 以上
