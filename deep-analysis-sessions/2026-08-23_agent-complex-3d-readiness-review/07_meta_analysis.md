# Agentによる複雑な3Dプロダクト生成 — 達成度評価

## 結論

このプロジェクトは、外部Agentが構造化コマンドで操作できるexact CADカーネルの基盤としては大きく前進しています。一方、任意の複雑な3Dプロダクトを長いフィーチャ履歴として安定生成する目的は未達です。現時点の適切な位置づけは「制約を理解したAgent向けの高度なalpha」であり、一般的なCAD製品やproduction-readyな自律生成基盤ではありません。

単純な達成率は提示しません。39/67のcapabilityがsupportedでも、残る28のpartialにはBoolean、fillet、shell、sweep、pattern、direct edit、STEP/IGESなど依存度の高い機能が集中しており、各capabilityの範囲も同じ大きさではないためです。

| 評価対象 | 判定 | 根拠 |
|---|---|---|
| Agentから操作できる決定的API | 基盤は成立 | CADCommand、KernelQuery、CADPipeline、DocumentBuilder、native persistenceが存在 |
| 制約内の複雑形状 | alphaとして利用可能 | primitives、sketch、extrude、revolve、loft、選択されたBoolean、STL/GLB、subset STEP/IGES |
| 一般的な複雑プロダクト | 未達 | 合成に重要な機能がpartialで、supported出力が後続処理で拒否される経路も存在 |
| production/release readiness | 未達 | 最新の高コストBoolean回帰は個別成功したが、G0–G7は0/8で同一revisionのevidence manifestがない |

## End-to-end評価

~~~mermaid
flowchart LR
    A[External Agent intent] --> B[CADCommand / KernelQuery]
    B --> C[Document history and evaluation]
    C --> D[Exact geometry and BRep]
    D --> E{Feature composition}
    E -->|documented envelopes| F[Validated topology]
    E -->|general cases| X[Typed unsupported or invalid input]
    F --> G[Native persistence]
    F --> H[STL / GLB]
    F --> I[STEP / IGES subsets]
    I --> J{External proof}
    J -->|current| Y[No release evidence]
~~~

最も重要な観察は、API入口や単体アルゴリズムではなく、Feature compositionの合成閉包です。複雑な製品は、個々の演算が存在するだけでは作れません。前段が生成したsurface/topology表現を後段がexactに処理し、selection identityと失敗契約を保ったまま履歴を進める必要があります。

## 確認済みの現行事実

### 1. Agent向け基盤は実体がある

- 公開inventoryは75 route（44 feature operation、6 command、7 query、4 native persistence、14 exchange format）を登録済みです。
- CADCommandはCodable/Hashable/Sendableなmutation契約です。
- CADPipelineとDocumentBuilderはmutationをDocumentEditingへ集約しています。
- 評価エンジンはparameter、incremental invalidation、validated BRep、derived mesh、topology lineage、cacheを管理します。
- package dependencyはCADCore → CADGeometry → CADTopology → CADIR → CADModeling → CADKernel → CADExchange/SwiftCADの方向に整理され、境界テストも存在します。

これは「AgentがJSON-likeな構造化命令を生成できる」という前提では強い基盤です。ただし、自然言語から設計意図を分解し、制約を計画し、失敗から再計画するAgent runtimeはリポジトリ内にありません。現在の責務境界では外部clientに属します。

### 2. 幅広いcapabilityがあるが、重要領域がpartial

現在のledgerは67 capability中39 supported、28 partialです。geometryとtopologyの基盤は強い一方、次がpartialです。

- Boolean、Sketch、Sweep、PolySpline、curve offset/extend
- fillet、chamfer、G2 blend、shell、thicken、pattern群、direct edit群
- STEP、IGES、USD
- Agent/Builder API parity

sketch/profile経路は点・線・円・円弧・cubic Bézierに加えて、非交差のnested loopを穴としてExtrude、Revolve、translational Sweep、Loftへ渡せるところまで進みました。一方、交差・接触・自己交差を含む一般region arrangementは未完です。filletとshellも単一edge、直交planar topology、hexahedral solidなど狭いenvelopeに依存します。

### 3. supported capabilityの合成契約に実装上の穴がある

GEO-INTERSECTION-002はevery validated surface representation pairをaccepted inputとしてsupported宣言しています。しかし実装では、

1. surface offset evaluatorはexact simplificationできない場合にprocedural offset surfaceを生成する。
2. thickenのside faceはprocedural ruled surfaceを生成する。
3. canonical analytic conversionはruled surfaceとcone/general offsetをunsupportedと分類する（plane/cylinder/sphere/torusの単純offsetはcanonical化される）。
4. default surface-surface intersectorはcanonical analytic/BSplineへ落ちないpairをinvalidInputで拒否する。
5. Boolean pipelineはface pairごとにこのintersectorを呼ぶ。

したがって、supported operationの出力が後続の一般演算で閉じていません。catalog testはaccepted-input文字列とfailure-codeのmetadataを検証しますが、表現pairの実際の振る舞いを網羅していません。これは件数上の不足ではなく、capability promotionの根本契約の問題です。

### 4. Agent-facing queryの一部はcertified global resultではない

curve closest-point queryは有限sampleから上位6 seedを選び、局所Newton法で改善します。一般の高次数・振動的・multi-lobe curveではglobal minimumを保証できません。別のcertified projection foundationが存在していても、public Agent queryはそこへ統合されていません。

Agentはquery結果を次のselection/editへ利用するため、これは表示上の誤差ではなく、長い編集履歴の決定性と再現性に影響します。

### 5. 検証状態はrelease claimを許さない

| 検証 | 結果 | 解釈 |
|---|---|---|
| SwiftCAD product build | 成功 | production moduleはcompileする |
| Swift policy / zero-copy / tolerance checks | 成功 | 静的policy gateは通る |
| CADKernel full test | 602/602 tests pass（62 suites、357.867秒） | kernel behaviorの広い実体はある |
| CADGeometry validation test | 3/3 tests pass | validation certificateの成功・失敗・closed-domain契約を確認 |
| SwiftCAD facade test | 900秒で全体未完走 | joinは70.599秒、torus-torus intersectionは308.880秒で成功したが、その後のdifference実行中に全体timeout |
| CADExchange test | 237/237 tests pass（12 suites、84.405秒） | 現行subsetの内部round tripと失敗契約は実行検証済み |
| ROADMAP release gates | 0/8 | repository自身の完了条件は未達 |
| Evidence manifests | 0 | 同一revisionの再現可能な証拠がない |

旧評価時のfacade/exchange compile failureは解消しました。CADExchangeはgreenです。SwiftCAD facadeもcompileし難しい公開経路を実行できますが、surface-lift edgeを含むjoinは70.599秒、general torus-torus intersectionは308.880秒を要し、全体は900秒で完走しませんでした。したがって統合経路は存在するものの、複雑履歴を反復生成できる予測可能な性能契約は未達です。

## 維持すべき不変条件

- failureを空結果や近似成功へ丸めず、typed failureとして返す。
- validated BRepをauthoritative stateとし、meshはderived artifactに留める。
- Agent mutationは一つのcommand/editor経路へ集約し、cache・lineage・validationを迂回しない。
- lower packageはupper packageの具象に依存せず、CADModelingのprotocolをCADKernelが実装する現在の逆転境界を維持する。
- exactを名乗るcapabilityはrepresentation envelope全体をbehavioral testで証明する。
- performance pathはcopy/allocation予算を測定し、safe owner/view lifetimeを守る。

## 理想形

理想のpublic surfaceは、Agentが個々の特殊caseではなく、制約・操作・必要保証を宣言し、成功時にproductとevidence、未達時に再計画可能なdiagnosticsを受け取る形です。

この表面APIを成立させる内部条件は次です。

1. Representation closure: supported producerの全surface/curve/topology表現をgeneral consumerが処理できる。
2. Topology closure: intersection → pcurve → face arrangement → region selection → sewing → validationが一般caseで閉じる。
3. Stable semantic identity: edit後もAgentが意図したface/edge/featureをlineageで再特定できる。
4. Certified queries: closest/project/intersectionがglobal guaranteeとdeterministic tie-breakを持つ。
5. Capability truthfulness: catalog、implementation、behavioral matrix、failure contract、evidence manifestが一対一対応する。
6. Interchange proof: 外部CAD oracleとのround trip、schema subset、units、pcurves、periodic trims、assembly semanticsを証明する。
7. Agent boundary: plannerを外部に置くならversioned schemaとrecovery diagnosticsを公開し、内蔵するなら独立packageとしてkernelから分離する。

## 現行との差分と優先順位

| 優先度 | 根本修正 | 完了条件 |
|---|---|---|
| P0 | facade性能ゲートの回復 | SwiftCAD/CADExchangeを含む全public targetが同一commitで時間制限内にbuild/test可能 |
| P0 | surface intersection契約の是正 | validated representation pairのbehavioral matrixが全件pass、未対応ならcapabilityをpartialへdemote |
| P1 | general intersection/Boolean closure | procedural/rational surfaceを含む交線、pcurve、arrangement、partition、validationがend-to-endで成立 |
| P1 | certified queryとstable edit identity | adversarial curveと長期edit historyでglobal result、tie-break、lineage、cache invalidationを証明 |
| P2 | sketch/blend/shell/sweep/pattern/direct editの一般化 | topology fixture依存でなくcapability envelopeを満たす |
| P2 | external exchange proofとG0–G7 | external oracle/corpus/fuzz/performanceと全manifestがrelease commit上でgreen |

## 未解決事項

- 「Agent」が外部clientだけを指すか、自然言語planner/runtimeもこのrepositoryの責務か。前者なら現在の境界は妥当ですが、versioned schemaとdiagnostic contractを強化する必要があります。後者ならAgent orchestration packageが欠落しています。
- 製品カテゴリ、典型モデル、最大feature count、latency、memory、STEP schema/interoperability targetが未定義です。これらがないためproduction SLAは判定できません。
- current kernel 602-test run、CADExchange 237-test run、facade性能timeoutを修正後のclean commit evidenceへ再構成する必要があります。

## 最終判断

目的は「AgentがCADを操作する基盤」まで相当程度達成し、「複雑な3Dプロダクトを一般に完成させる能力」と「production proof」は未達です。現状で成功しやすいのは、利用するfeatureとtopologyをdocumented envelopeへ制限できる製品です。自由曲面、offset/thicken後のBoolean、一般fillet/shell、複雑sketch region、長いdirect-edit chain、任意STEP資産を組み合わせる用途では、Agentが途中でtyped failureへ到達する可能性が高く、目的達成とは言えません。

## Iteration 2 - 2026-08-23T09:52:00+09:00

### 更新された現行事実

- capability ledgerは38 supported / 29 partial、114 envelope、540 fixture bindingへ進展した。
- CADKernelは591/591、CADExchangeは237/237で成功した。
- SwiftCAD facadeはcompile不能ではなくなり、31件を実行して29件成功した。残る2件はいずれも高コストBoolean経路の60秒timeoutである。
- curve validationを一度だけ行う`ValidatedCurve3D`境界により、代表的なpoly-spline patch networkは104.326秒超から20.474秒、別経路は60秒超から24.564秒へ改善した。
- それでもformal gateは0/8で、同一clean revisionのevidence manifestは存在しない。

### ベイズ更新

| Claim | Prior | Posterior | 理由 |
|---|---:|---:|---|
| Agent-facing substrate is substantial | 0.91 | 0.96 | facadeがcompile・実行し、exchange 237件とkernel 591件が通過 |
| Constrained alpha workflows are usable | 0.86 | 0.91 | 公開経路と交換subsetのbehavioral proofが増加 |
| General complex-product generation is achieved | 0.03 | 0.04 | supported増加はあるが、29 partialとBoolean critical pathが残存 |
| Production/release readiness is achieved | 0.01 | 0.01 | facade性能failure、0/8 gates、dirty worktree、manifest不在 |

## Iteration 3 - 2026-08-23T11:50:00+09:00

### 現行作業ツリーによる再評価

全テスト用ビルドは成功し、CADKernelは602/602件（62 suites、357.867秒）、CADExchangeは237/237件（12 suites、84.405秒）に成功した。穴付きprofileがExtrude、Revolve、translational Sweep、Loftを通してvoid topology、exact curve/surface、体積、lineageを維持する実動証拠も増えた。

一方、SwiftCAD公開経路の全体実行は900秒で完走しなかった。certified surface-lift edgeを含むjoinは70.599秒、general torus-torus intersectionは308.880秒を要し、その後のdifference実行中に全体timeoutへ到達した。複雑な解析曲面Booleanを正しく構成できる範囲は拡大したが、Agentが長い履歴を反復生成するための予測可能なlatency契約は未達である。

| 判断軸 | 更新後の判定 | 現行証拠 |
|---|---|---|
| Agent操作基盤 | 相当程度達成 | 75 public routes、build成功、shared command/query/evaluation path |
| 制約付き複雑形状 | advanced alphaとして利用可能 | Kernel 602/602、穴付きexact feature、一般解析曲面Booleanの成功例 |
| 一般的な複雑プロダクト | 未達 | 29 partial、general feature compositionの未閉包、予測不能な高latency |
| production readiness | 未達 | G0-G7 0/8、manifest 0、dirty entries 465、facade全体timeout |

capabilityは67件中38 supported、29 partialのままである。29 partialはBoolean、Sketch、Sweep、PolySpline、blend、shell、thicken、direct edit、pattern、STEP/IGES/USD、Agent API parityに集中するため、38/67を目的達成率へ換算してはならない。現在の適切な位置づけは、解析曲面主体の機械部品や制約されたfeature履歴を生成できる高度なexact-CAD alphaであり、任意の複雑製品を自律的・対話的に完成させるproduction systemではない。

### 中心性と次のアクション

最も中心性が高いのはgeneral Boolean materializationです。pattern、mirror、join、direct edit、blend、shell、thickenの多くがこの経路へ収束します。次の介入順は、(1) surface/curve表現の閉包、(2) planar arrangementとhole-aware region、(3) coincident/periodic partitionを含むgeneral Boolean、(4)それを利用する編集・pattern、(5)exchange/API parity、(6)同一revisionのG0–G7証拠です。

## Iteration 5 - 2026-08-23T14:18:00+09:00

### 周期面Booleanの更新と目的達成度への影響

non-contractible periodic pcurveをbounded planar containmentへ送っていた責務誤りは修正された。production dispatcherはessential periodic closed componentを明示seam付きopen arrangementへ送り、shifted seamを持つfull-period cylinder faceを有限stripへ分割する。focused testはarrangementだけでなく`DefaultBRepSewer`と`ValidatedBRepModel(.exact)`まで通過した。周期pcurve trimのupper-period lift、正規periodic seamの受理、偽seamの拒否も独立に成功した。

これはgeneral Booleanのcritical pathを実質的に前進させるため、制約付きexact生成の確度を0.91から0.93へ更新する。一方、67 capability中38 supported / 29 partial、75 public routes、0/8 gatesは不変である。二重周期torus、より複雑なsource chart、coincident arrangement、procedural surface pair、Boolean依存featureの一般化、およびfull-suite再実行は未証明であり、一般的な複雑製品の完成判定は変えない。

| 判断軸 | 最新判定 | 更新理由 |
|---|---|---|
| Agent操作基盤 | 相当程度達成 | 共有Command/Query focused testが再度成功 |
| 制約付き複雑形状 | 高度なalpha | essential periodic cylinder stripがexact B-repまで成立 |
| 一般的な複雑製品 | 未達 | 29 partialとrepresentation closure未成立 |
| production readiness | 未達 | full regression未再実行、0/8 gates、manifest 0、dirty worktree |

### 最新の実行証拠

- capability ledger: 67 total / 38 supported / 29 partial / 115 envelopes / 546 bindings
- public inventory: 75 routes
- formal gates: 0/8
- focused current tests: 6/6 pass
- `FIXME(INCOMPLETE_IMPLEMENTATION)` in `Sources`: 0
- `git diff --check`: pass
- worktree: 480 porcelain entries at `10d3416159e4`

`FIXME`が0であることは完成証拠ではない。callable partial capabilityはcatalogのtyped unsupported contractで管理されているため、目的達成判定はcapability status、具象分岐、behavioral matrix、gate evidenceを優先する。

## Iteration 6 - 2026-08-23T14:49:00+09:00

### Representation closure と query correctness の更新

ruled surfaceをunsupportedなprocedural表現のまま交差器へ渡していた経路は、同一parameter chartを保つexact rational B-splineへ解決してからdispatchする構造へ修正された。公開結果は元のsurface identityを保持し、certified implicit pcurveの所属検証もexact same-parameter equivalenceを認識する。ruled×plane、ruled×ruled、JSON往復、pcurveからのtrim-loop sewing、exact BRep validationがすべて成功した。

B-spline surfaceのclosest-point queryも、有限samplingと6 seedの局所Newtonから、区間包囲と分枝限定で大域距離下界を閉じる共通CADGeometry責務へ移った。証明予算不足は成功値へ丸めず`resourceLimitExceeded`になる。これにより制約付きexact生成の確度を0.93から0.94へ更新する。

一方、一般の非還元procedural offsetはexact rational representationを持たず、certified procedural intersectionが必要である。curve closest-pointとgeneral directional projectionにもsampling/local refinementが残る。capability inventoryは38 supported / 29 partial、formal gateは0/8のままであり、一般的な複雑製品とproduction readinessの判定は変えない。

| 判断軸 | 最新判定 | 更新理由 |
|---|---|---|
| Agent操作基盤 | 相当程度達成 | B-spline queryが大域証明契約へ移行 |
| 制約付き複雑形状 | 高度なalpha | ruled交差が元UVを保ったままexact BRepまで成立 |
| 一般的な複雑製品 | 未達 | general offset、query残差、29 partialが残存 |
| production readiness | 未達 | 0/8 gates、manifest 0、dirty revision |

## Iteration 4 - 2026-08-23T13:35:00+09:00

### 最新inventoryとAgent入口の確認

正式checkersは75 public routes、67 capabilities、38 supported、29 partial、115 development envelopes、546 fixture bindings、0/8 gatesを報告した。現行ソースを再buildしたSwiftCAD facadeでは、共有capability/query入口とserializable KernelQuery round-tripがそれぞれ成功した。XcodeのSwift Testing filterが指定外のsuiteも起動したため全体は手動停止し、今回の観測をfacade全体成功とは扱わない。

`SurfaceParameterTopology`と`SurfaceParameterLoopLift`により、periodic surfaceのchart topologyとloop homologyはCADGeometryへ責務移管され、torus generator、sphere pole closure、seam-crossing contractible loopのbehavioral testsが成功した。一方、non-contractible periodic loopをBoolean strip cellsへmaterializeする本番経路には明示的な`FIXME(INCOMPLETE_IMPLEMENTATION)`が残る。この改善は根本構造を前進させたが、general Booleanの完成を意味しない。

| 判定軸 | 最新判定 | 根拠 |
|---|---|---|
| 構造化Agent入口 | 成立 | CADCommand/KernelQueryの共有経路と直接テスト |
| 制約付きexact生成 | 高度なalpha | 直近full runの602 kernel tests、237 exchange tests、後続変更のfocused regressions、exact B-rep/lineage |
| 一般的な複雑製品 | 未達 | 29 partialとnon-contractible periodic Boolean materialization |
| 正式完成 | 未達 | 0/8 gates、0 manifests、dirty worktree |

## Iteration 7 - 2026-08-24T08:55:00+09:00

### 周期 chart の所有権と誤差伝播の是正

general torus–torus Boolean の体積誤差は、根探索の近似精度ではなく、周期 chart の所有権重複が原因だった。Geometry が一曲線内の universal-cover lift を構成した後、Topology の volume path が曲線中央を基準に同じ巻き数を再正規化していたため、Green primitive の非周期項へ整数周期が二重加算されていた。Topology 側の再正規化を除去し、coedge 全体の整数周期 translation だけを担当させた。

同時に、固定 16 標本による chart lift は明示曲線の多周回を別の短い曲線へ alias できるため廃止した。affine、constant、harmonic、polyline、positive-weight rational B-spline、および certified implicit 系は Geometry が導関数上界を所有し、その上界から周期の 1/4 以下となる偶数分割数を導く。分割予算超過と非有限値は typed failure となり、奇数分割で `middle` が `t = 0.5` からずれる経路も閉じた。adaptive integral cell は逐次加算でなく balanced outward-rounded reduction により合成する。

facade 全件の初回再実行では general cone–torus intersection だけが失敗し、期待体積 `11.489854194529729` に対して `12.03122938816642` を返した。これは Topology 補正の除去が誤りだったのではなく、Geometry の certified full lift が general torus–torus にだけ限定され、cone–torus の torus-role pcurve が旧固定標本へ落ちていたためである。責務を pair 名ではなく chart capability で定義し直し、特異 parameter を持たない周期 elementary chart の全 certified analytic-pair pcurve に同じ導関数証明付き lift を要求した。追加した cone–torus 回帰は、各積分 cell の start/middle/end を整数周期だけ整列した点が、canonical pcurve と同じ 3D 点へ写ることを検証する。

~~~mermaid
flowchart LR
    G[Geometry: one-curve continuous lift] --> T[Topology: integer-period coedge alignment]
    T --> I[Green / divergence integration]
    D[Certified derivative bound] --> G
    I --> B[Balanced outward-rounded composition]
~~~

| 現行証拠 | 結果 |
|---|---|
| capability/public inventory | 67 total / 39 supported / 28 partial / 115 envelopes / 556 bindings / 75 routes |
| formal goal contract | 0/8、未達のまま |
| macOS Debug focused regression | chart lift 6/6、general torus–torus differential 3/3、cone–torus periodic lift 1/1、trimmed analytic volume 18/18、analytic-pair area/flux 18/18（46/46） |
| macOS Release public Boolean | intersection 41.976秒、difference 46.624秒、union 41.254秒、すべて exact validated solid |
| macOS Release facade | 69 suites / 181 tests / 181 pass / 0 failure、244.344秒 |
| platform compile/link | iOS Debug成功、visionOS Debug成功 |
| WASM | pinned 2026-08-14 Swift 6.4 snapshotでRelease buildとWASI runtime smoke成功 |
| Embedded WASM | `Foundation` / `Codable` 依存境界で明示的非対応。通常sourceの同期契約を弱める条件分岐はない |

修正前の代表 intersection 体積は期待値 `8.8103` に対して約 `11.0477` だった。修正後の certified shell enclosure は `[8.810306546319577, 8.810308127360555]` となり、許容値を広げず期待値を包含した。general cone–torus の既存期待値と tolerance も変更せず、公開三演算 3/3 と facade 全 181/181 が成功した。以前の308.880秒 intersectionと900秒 facade timeoutの中心的ボトルネック、および pair 固有 lift という設計漏れは解消した。ただし external CAD oracle、G0–G7 evidence manifest、28 partial capability は未完であり、production-ready 判定は変更しない。
