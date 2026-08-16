# PolarDrift

赤道儀の極軸合わせを支援する iOS アプリ。ドリフト法（Drift Alignment）をガイドし、星の Dec 軸方向のドリフトを自動計測する。

## 概要

起動時にモードを選択する（`ModeSelectionView`）。

| モード | 内容 |
|--------|------|
| ドリフト確認 | 方位角フェーズ → 高度フェーズの2フェーズで極軸誤差を確認・追い込む |
| 周期確認 | キャリブレーション1回＋長時間連続計測（既定20分）で赤道儀の周期誤差を確認 |

### ドリフト確認モード

望遠鏡カメラで星を撮影しながら、以下の流れで極軸合わせを行う。

1. **方位角フェーズ** — 南中付近の星で計測し、極軸の東西ズレを確認
2. **高度フェーズ** — 東・西の地平線付近の星で計測し、極軸の高度ズレを確認

各フェーズでキャリブレーション → ドリフト計測を繰り返し、傾きが収束したらフェーズ完了。
アプリは調整方向の指示を出さない。直近の計測履歴を提示し、判断はユーザーが行う
（詳細は「計測結果の提示」を参照）。

## セッションフロー

```
ModeSelectionView
  ↓ モード選択
phaseGuide(azimuth)                          ← ドリフト確認モードのみ
  ↓ 「スタート」
calibration.detectingCentroid   ← 星の重心を自動検出
  ↓ 重心確定
calibration.awaitingDecMove     ← Dec軸方向を特定するため星を手動移動
  ↓ 画像幅の10%以上の移動を検出
driftMeasure.reintroducing(1)   ← 星を元の位置に戻す（十字線追従）
  ↓ 「スタート」
driftMeasure.measuring(1)       ← Dec方向ドリフトを計測（最小90秒、収束するまで最大300秒）
  ↓ 収束（isPrecise ∧ isStable）or 安全上限
driftMeasure.showingResult(1)   ← 計測結果を履歴表示（「スキップ」でフェーズ確定）
  ↓ 繰り返し
phaseComplete(azimuth)
  ↓
... altitude フェーズ ...
  ↓
sessionComplete
```

周期確認モードはフェーズを持たず、キャリブレーション後の1回の計測が
固定時間（既定1200秒）に達すると直接 `sessionComplete` へ遷移する。

## ドリフト計測アルゴリズム

### キャリブレーション

カメラ画像の px 座標でセントロイドを検出し、ユーザーが Dec モーターで星を移動させた軌跡から Dec 軸方向ベクトルを算出する。移動量の閾値は画像幅の 10%（`decMoveThreshold = 0.10`）。

### ドリフト測定

各フレームの重心を `DecCalibration.decComponent(of:)` で Dec 軸に投影し、経過時間 t に対してオンライン線形回帰（O(1)/フレーム）を実行する。RA 軸方向にも並行して回帰しており（`raRegression`）、診断表示に使う。

```
y(t) = a + b·t
b = ドリフト速度 [px/秒]
```

実ピクセル換算: `rate_px_per_min = b × 60`

### 計測終了条件

| 条件 | 値 |
|------|-----|
| 最低サンプル数 | 10 フレーム |
| t 統計量の閾値 | \|t\| > 2.0（95% 信頼区間） |
| 精度ゲート（isPrecise） | 3σ ≤ 1 px/分 |
| 安定性ゲート（isStable） | 直近60秒の傾き推定の幅が 1 px/分 以内 |
| 最小計測時間 | 90 秒 |
| 安全上限 | 300 秒（ウォーム周期1周を跨げる） |
| 星ロスト判定 | 3 秒間捉えられなければロスト確定（fps非依存） |
| 周期確認モード | 収束ゲートを無効化し、固定上限（既定1200秒）まで連続計測 |

計測は `elapsedTime ≥ 90秒 ∧ isPrecise ∧ isStable` で終了する。統計精度（isPrecise）に加えて傾きの収束（isStable）を必須化することで、早期終了による系統誤差の混入を防いでいる。

### 計測結果の提示

計測が終わるたびに、直近3回のドリフト速度を履歴カードとして表示する
（`|rate| < 1.0 px/分` のとき緑表示）。かつては前回との比較から調整方向を
指示する仕組み（`sameDirection`/`reverseDirection`）があったが、
アプリが「ユーザーが実際にノブを調整したか」を知り得ないため廃止した
（同一設定での再測定時に誤った指示になり得るため）。
どちらへ調整するか・調整するかどうかはユーザーが履歴から判断する。

## 音声コマンド

| コマンド | タイミング | 動作 |
|----------|-----------|------|
| 「スタート」 | phaseGuide / calibration(waitingForVoice) / driftMeasure.reintroducing | 次ステップへ進む |
| 「スキップ」 | driftMeasure.showingResult | 現在の測定をスキップして次のイテレーションへ（最後の測定であればフェーズ確定） |

## CSV 出力

セッション開始時に Documents ディレクトリへ 2 つの CSV を即時作成する。ファイル名にモードが埋め込まれる（`drift` / `period`）。ファイルアプリの「PolarDrift」フォルダから参照できる。

### 概要 CSV: `polardrift_drift_YYYYMMDD_HHmmss.csv` / `polardrift_period_YYYYMMDD_HHmmss.csv`

1 行 = 1 測定イテレーション

| 列 | 単位 | 説明 |
|----|------|------|
| session_id | — | セッション UUID |
| session_start | ISO 8601 | セッション開始時刻 |
| phase | — | `azimuth` / `altitude` / `period_check` |
| cal_dec_axis_x/y | px空間の単位ベクトル | Dec 軸方向ベクトル |
| iteration | — | イテレーション番号 |
| duration_sec | 秒 | 計測時間 |
| sample_count | — | サンプル数（フレーム数） |
| drift_rate_px_per_min | px/min | Dec軸方向のドリフト速度 |
| drift_rate_se_2sigma | px/min | 標準誤差 × 2（95% CI 幅） |
| ra_drift_rate_px_per_min | px/min | RA軸方向のドリフト速度（診断用） |
| t_statistic | — | t 統計量 |
| is_significant | bool | 有意かどうか |

### 生データ CSV: `polardrift_raw_drift_YYYYMMDD_HHmmss.csv` / `polardrift_raw_period_YYYYMMDD_HHmmss.csv`

1 行 = 1 フレーム（約 30 fps）

| 列 | 単位 | 説明 |
|----|------|------|
| session_id | — | セッション UUID |
| phase | — | `azimuth` / `altitude` / `period_check` |
| cal_dec_axis_x/y | px空間の単位ベクトル | Dec 軸方向ベクトル |
| iteration | — | イテレーション番号 |
| elapsed_sec | 秒 | 計測開始からの経過時間 |
| x_px / y_px | px | 重心座標 |
| dec_disp_px | px | Dec 軸方向変位 |
| ra_disp_px | px | RA 軸方向変位 |
| image_width / image_height | px | フレームサイズ |

### R での読み込み例

```r
df  <- read.csv("polardrift_drift_20260815_204101.csv")
raw <- read.csv("polardrift_raw_drift_20260815_204101.csv")

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
RootView
  └── ModeSelectionView         ← モード選択（ドリフト確認 / 周期確認）
  └── SessionView
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
| `Views/RootView.swift` | モード選択とセッション画面のナビゲーション |
| `Models/SessionMode.swift` | モード定義（ドリフト確認 / 周期確認） |
| `Models/SessionStep.swift` | セッション状態機械の定義 |
| `Models/DecCalibration.swift` | Dec 軸ベクトルと投影演算 |
| `Models/OnlineRegression.swift` | O(1) オンライン線形回帰 |
| `Camera/DriftTracker.swift` | 重心追跡・統計・計測終了判定 |
| `Camera/FrameProcessor.swift` | セントロイド検出 |
| `Camera/CameraManager.swift` | カメラセットアップ・フレームストリーム |
| `Camera/CameraActor.swift` | `@globalActor` によるカメラ制御の直列化 |
| `Camera/GrayImage.swift` | vImage による BGRA→グレースケール変換 |
| `Persistence/SessionRecorder.swift` | CSV 即時書き込み |

## 要件

- iOS 26.2 以上（`@Observable` マクロ使用、`IPHONEOS_DEPLOYMENT_TARGET = 26.2`）
- 実機必須（カメラ・音声認識）
- Xcode 26 系
