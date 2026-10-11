# SSI-COONS-PLANE-01: assembly capability gap

通常 SSI の実行時停止は未観測。初回の Native compile/link は cached PlanePlane signature mismatch で失敗した。明示的に許可された因果的な追加 assembly は現行の実 PlanePlane body だけを加えたが、120 秒で timeout となった。bare/rich の実行前で終了しており、geometric contract の反例でも、static intake limit の runtime 再現でもない。

| 固定事項 | 内容 |
|---|---|
| Work item | `DIA.4.I.M7.SSI.COONSPLANE01`（進捗正本は root `PROGRESS.md`） |
| HEAD before / after | `310ed10bae1d842529e14fefe79954e858ee75d5` / 同一 |
| 入力 | original four-chart planar Coons `S(U,V)=(U,V,0)`, full closed `[0,1]^2` × whole plane `X=1/2`, stored normal `.unitX`, explicit uDirection なし |
| Compiler / target | Apple Swift 6.4 (`swift-6.4-RELEASE`), `arm64-apple-macos15.0` |
| SDK | `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk` |
| 制約 | process ごと CPU/wall 120 秒、timeout 時 descendant/process-group cleanup、fresh scratch/module cache、Native first |
| 実行数 | compile/link 2 回（初回＋因果的追加 1 回）、bare 0 回、rich 0 回 |
| 結果 | 初回 exit 1 / 75.425088 秒。追加 timeout / 120.352199 秒。実行可能製品なし |

```text
Original four-boundary input
  → fresh current DefaultSurfaceSurfaceIntersector + Result bodies
  → typecheck against admitted cached CADGeometry interface
  → first: compile error in unselected plane×plane branch
  → one causal assembly with current real PlanePlane body
  → second: 120-second timeout, no compiler diagnostic
  × no executable → no ordinary SSI runtime observation
```

## Input and independent oracle

Input fixture は [CoonsPlaneSSIStop.swift:13](../../CoonsPlaneSSIStop.swift:13)。既存 [OriginalPolylineAtlasLiftVerification/Proof.swift:18](../../../OriginalPolylineAtlasLiftVerification/Proof.swift:18) の `shape(multi:true)` と同じ degree-1、knot `[0,0,1/2,1,1]`、3×3 original control grid から、同じ既存 `OriginalSurfaceBoundarySourceIssuer` と `OriginalCoonsSurface3D` constructor で作る。未使用の boundary-corrected return value は構築しない。SSI の first argument は native tensor への置換ではなく `.procedural(.originalCoons(host))` のまま。

独立 oracle は source axis rule [OriginalStoredPlaneAxis.swift:3](../../../../Sources/CADGeometry/OriginalSourceIssuance/OriginalStoredPlaneAxis.swift:3) と [DefaultOriginalPlaneBasisIssuer.swift:32](../../../../Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalPlaneBasisIssuer.swift:32)、同 :42–45 から導出する。`N=X` では reference axis は `Y`、plane `u=Z`、`v=-Y`。従って `P(p,q)=(1/2,-q,p)`。

| 要求する全体関係 | 値 |
|---|---|
| Original parameter tuples | `(CoonsU,CoonsV;planeU,planeV)=(1/2,V;0,-V)`, `0≤V≤1` |
| XYZ | `(1/2,V,0)` |
| Dimensions | parameter/image dimension 1、fiber dimension 0 |
| Closed chart incidence | `U=1/2` の左右をすべて保持。`V<1/2` は下段左右、`V>1/2` は上段左右、`V=1/2` は 4 chart。端点 `V=0,1` は各 2 chart |
| 完全性 | 線分全体と対応する全 plane UV を保持し、sample/residual による equality・coverage の代替をしない |

## Admitted assembly and observed compiler failure

Command owner は [CoonsPlaneSSIStop.py](../../CoonsPlaneSSIStop.py)。`CS-POLY-01-ordinary/native/receipt.json` とその parent receipt を hash 検査し、記録された compiler source snapshots、logs、modules、archives の保全済み同一製品を使用した。最初の preflight は保存 command の archive path と receipt の保全先 path の違いで compiler 前に終了した。同一 SHA-256 の既存保全製品へ接続し直しただけで、新製品・追加 prerequisite は作っていない。

次の本観測では 3,380 file premises、unchanged cached CADCore/Geometry source 1,672 件を admission に記録。cached source と現行との差 43 件は一件ごとに「fresh facade/current admitted scalar wrapper」「unselected source branch」「cached DTO limitation」へ分類した。現在別 owner が変更している CS 専用 4 input は明示的に除外している。source producer の再実装、production 編集、広い CADCore/Geometry/Kernel/L2–L6 build は行っていない。

現行 [DefaultSurfaceSurfaceIntersector.swift:193](../../../../Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift:193) の plane×plane call は :198 で `options: options` を渡す。現行 [PlanePlaneSurfaceIntersector.swift:11](../../../../Sources/CADGeometry/PlanePlaneSurfaceIntersector.swift:11) はこの引数を宣言しているが、保全済み module の契約は受け付けなかった。生成 facade は import prefix 4 行を加えているので compiler log の :202 は原文 :198 に対応する。

```text
DefaultSurfaceSurfaceIntersector.swift:202:20:
error: extra argument 'options' in call
```

この入力の first canonical surface は [CanonicalAnalyticSurface.swift:76](../../../../Sources/CADGeometry/CanonicalAnalyticSurface.swift:76) の `.unsupported` であり、plane×plane branch は選択しない。しかし現行 facade 全体の typecheck にはその cached interface も必要だった。従って、現行 facade と今回の既存製品だけでは ordinary entry を実行できない、という assembly capability gap が初回の実測結果である。

## Causal resolution history

初回 receipt `1c972106…` とその 75 秒 command/log は変更せず保存した。親から、この具体的な signature mismatch に対し、既存 CURRENT PPFIX 製品の再利用または現行実 `PlanePlaneSurfaceIntersector.swift` 1 file の追加だけを行う bounded attempt が明示的に指示された。

| 調査・操作 | 結果 |
|---|---|
| PPFIX Native receipt | `Tests/OriginalPlanePlaneIntersectionVerification/Evidence/native/receipt.json`, SHA-256 `d5d85a1b6a6dcb3f1f08022bdb3033e0404c7a18a2741dc9648f6e45410e19e4` |
| PPFIX 製品の namespace | `Proof` executable。importable module を emit しておらず、今回リンクには使わない |
| 現行実 body | PlanePlane SHA-256 `eab03eda9648735ac5443af9856d8663f393e59110e1f166915246544c03e513`。PPFIX input と一致 |
| 推移的 field/source premises | PPFIX の 127 件は現行 source と M6 cache source hash の両方に全件一致。compiler/SDK/receipt/runtime evidence も既存 hash を照合 |
| 追加範囲 | 現行 facade 2 file と同じ assembly に実 PlanePlane 1 file を追加。stub/source producer/lower build なし、PPFIX 22 cases の再実行なし |
| 追加 compiler process | `timeout`, 120.352199 秒。diagnostic log は空。compile 成功も別の interface gap も未観測 |
| cleanup | runner の descendant/process-group SIGKILL。終了後、scratch path を引数に含む残存 process 0 件 |
| runtime | executable 未生成。bare/rich とも 0 回 |

追加 attempt の 3,394 file premises と fresh source 3 file は pre/post hash 一致、HEAD 同一。time cap を上げず、追加 body、再試行、recursive module adaptation は行わない。

## Runtime and receipt limitations

原文上、三つの Native SSI producer は originalCoons first argument を初期 `.bSpline` guard で拒否する。exact chart conversion は [ProceduralSurface3D.swift:334](../../../../Sources/CADGeometry/ProceduralSurface3D.swift:334) で `nil`、通常 fallback は [DefaultSurfaceSurfaceIntersector.swift:503](../../../../Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift:503) の `BoundedParametricSurfaceIntersector`。Coons interval path は retained original boundaries を使い、source/DI graph family の再発行をしない。これらは static route の確認であり実行観測ではない。

cached `SurfaceSurfaceIntersectionResult` は現行 issued-receipt field と一致していない。この DTO は本観測の premise limitation として admission に記録した。仮に bare が成功しても numerical cached-DTO scope を超えた rich receipt の成功証拠にはならない。本回は executable 自体がないため、old DTO の construction/use より前の compile failure であり、ordinary runtime failure の前後関係は主張しない。

`OriginalIssuedGraphFamily × OriginalIssuedPlaneGraph` の prepared intake が既存 generic resolver に直接適合しないという前回の static finding も、この compile failure とは別である。GP.PUB の既存準備済 relation port を使った runtime failure/coverage acceptance は今回観測していない。

## Artifacts and post-premise check

保全した raw text と元 bytes/hash の対応は [evidence-manifest.json](evidence-manifest.json) を参照。compiler commands は各 `runs.json` の `command` field に原文のまま保存した。親 receipt は参照だけを保持し、binary/archive/親 evidence は複製していない。

初回 durable artifacts: [native-admitted/receipt.json](native-admitted/receipt.json)、[admission.json](native-admitted/admission.json)、[runs.json](native-admitted/runs.json)。元 scratch: `.build/ssi-coons-plane-01-observation-20261011-native-admitted/`。

| Artifact | SHA-256 |
|---|---|
| `receipt.json` | `1c972106bd6ff7ee96e72bf4ebdffe56582a1a8609a026690a1035f5b03c877f` |
| `admission.json` | `3df1658ec0dad5758595cb425bd9315aad161633297174e25fc9bf5c5a8f0b93` |
| `compile-link.log` | `b9836612000b990e44bfc7900ad1d5e78e527fa93609d3bb61c6850df3f5682e` |
| `compiler-version.log` | `0b8a89a2a509c22d7708e5de961c937d99829285dfedf796a988cc5275f1986c` |
| `runs.json` | `3edbb7c78190018db1ef5df637b4df1c1b7ed97ce9641ecb7c3317729d4c1e58` |

追加 durable artifacts: [native-plane-contract/receipt.json](native-plane-contract/receipt.json)、[admission.json](native-plane-contract/admission.json)、[runs.json](native-plane-contract/runs.json)、[cleanup-observation.json](native-plane-contract/cleanup-observation.json)。元 scratch: `.build/ssi-coons-plane-01-observation-20261011-native-plane-contract/`。

| Artifact | SHA-256 |
|---|---|
| `receipt.json` | `9e191adfeba86e1d2af200a3903a77e9c52cf8f6a8284f44bd60f8f7596ed1c7` |
| `admission.json` | `53f9ca8aa28d6ea1787209abafa49c5f07bc3aa66fdbc8ea1a361e647a1c63b4` |
| `compile-link.log`（空） | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `runs.json` | `98ee4136dd8674bf2eb19de4950f70709bb16896a4f5b2ee55fa374fbdeba69b` |
| `cleanup-observation.json` | `9c3ced38b6e6699ae1eeff1e4d97f810a50d47a69a92cb54b7db23ed18ff7242` |

両 `receipt.json` の `postHashesMatch=true`、`freshProductionPostHashesMatch=true`。各実行時の fresh production、fixture/runner、admitted cache/module/archive/compiler/SDK premises は pre/post 同一で、HEAD も同一。新しい counter/shared mutable task state は追加していない。既存 fixture admission は local noncopyable value のまま。cancellation/storage/depth/lifetime の runtime verification は未実施であり、source contract を変更していない。

残る gap はこの入力の ordinary bare/rich 実動証拠。具体的な geometric/public broken contract はまだ得られていないので production implementation を選ばない。既存 8 cells の完成、全 87 cells、whole seven families の完成判定には使用しない。
