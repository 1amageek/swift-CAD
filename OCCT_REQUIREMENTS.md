# OCCT Functional Parity Requirements

## Authority and Scope

The user-authorized objective is to implement every requirement below, verify its actual public execution path, and merge the implementation branch into main. Backward compatibility is not required. OCCT 8.0.1 supplies functional requirements only; its implementation must not be transplanted. Commercial add-ons and C++ implementation mechanisms are outside the referenced requirement set.

Baseline: `beb51bfe5b5962185e29b1eb85f4720d64de61f2`. The referenced user attachment has SHA-256 `84d8da428399e0cfe3d0f938f3fcd95b6f0a4d7be3ae7fbc830a9a0680fdbd8e`. Requirement IDs and scope survive partial implementation and continuation. Existing application responsibilities are included through their established owners, not duplicated inside the kernel.

## Requirement Register

The Japanese requirement text is retained from the user-provided specification. Status descriptions from the investigation are not completion evidence.

| ID | Required behavior |
|---|---|
| C1 | 全公開操作を一つの正本で追跡する。操作、対応入力、制約、失敗、評価器、検証証拠を対応付ける |
| C2 | 機械判定する capability と公開入口を一致させる。現在の共通 import 入口では、IGES 分岐に到達する前に拒否される |
| C3 | 「フィレット対応」などの一語ではなく、支持面、境界曲線、接続形態、退化条件ごとの対応領域を公開する |
| C4 | 正常入力での成功、対応外入力での明示的拒否、数値的に判定できない場合の失敗を区別する |
| G1 | **周期 B-spline 曲線**。現在の `BSplineCurve3D.domain` は閉区間。周期的なノット・制御点、周期正規化、継ぎ目をまたぐ評価、周期原点の変更が必要 |
| G2 | **周期 B-spline 曲面**。U／V 独立の周期性、片方向・両方向周期、継ぎ目をまたぐトリム、周期原点変更の公開契約 |
| G3 | **ノット除去・多重度低減**。削減後の形状偏差を制限し、許容誤差内で削減できない場合は変更を拒否する |
| G4 | **曲線と曲面の連続的な重なりの返却**。現在の曲線―曲面交差は離散イベントを中心とし、非離散交差を失敗として扱う。面上に乗る曲線の区間、端点、対応パラメータを返す契約が必要 |
| G5 | **幾何表現と下流演算の対応の一致**。表現できる楕円、暗黙交線、面上の曲線などが、断面抽出・押し出し・編集・交換でも利用できる範囲を明確にする |
| G6 | **近似・補間・変換の共通保証**。解析形状、NURBS、手続き的曲面間の変換で、位置誤差、接線、曲率、次数、制御点数の条件を明示する |
| T1 | **汎用 Shape の公開抽象**。単独頂点、単独辺、ワイヤ、面、シェル、ソリッド、および異種形状の集合を共通操作の入力にする |
| T2 | **Compound／CompSolid 相当の意味**。単なる配列と、面を共有するソリッド集合を区別する。材料成分・所有権の既存契約を維持する |
| T3 | **3D 曲線と pcurve の再構築・整合修復**。片方が欠ける、同じパラメータで位置が一致しない、向きが逆、範囲が異なる場合を修復する |
| T4 | **ワイヤ修復**。隙間、小さな辺、重複辺、交差する境界、接続順序、接続点の不一致を処理する |
| T5 | **周期継ぎ目・極の修復**。円筒やトーラスの seam、球の極、円錐頂点で、必要な pcurve と退化辺を維持・復元する |
| T6 | **シェル／ソリッド修復**。面の向き、閉鎖性、外殻と空洞の関係、重複面、許容差内の接合を修復する |
| T7 | **修復による変更量の契約**。どの幾何・トポロジーが変わったか、最大変位、許容差増加、削除・生成要素、残る不具合を報告する |
| T8 | **非多様体形状の明示的な扱い**。診断・保持できる範囲と、モデリング入力として許可する範囲を分離する |
| B1 | **同一支持面上で重なる面の統合**。共通面を共有する領域片へ分割し、材料の所属・向きを決める |
| B2 | **接触・接線・一致の網羅的な分類**。点接触、辺接触、接する曲面、局所的な一致、極小の交差領域を区別する |
| B3 | **混在する次元への操作契約**。ソリッド、シート、ワイヤ、辺を入力にしたとき、許可する組合せ、生成する次元、失われる要素を規定する |
| B4 | **汎用 Splitter／Section の公開機能**。対象と工具を分けた分割、交線・交点・一致領域の抽出、元形状との対応を返す |
| B5 | **交差計算の再利用**。同じ入力集合に対する union／cut／intersection／領域選択で、準備済み交差情報を安全に共有する |
| B6 | **演算ポリシー**。追加許容差、接合の前提、入力非破壊、並列化、キャンセル、診断を明示する |
| B7 | **履歴の完全性**。辺・面の分割、統合、削除、生成と、結果の材料成分・空洞の対応を返す |
| F1 | **Rolling-ball の通常フィーチャー経路への統合**。幾何構築があっても、通常のフィレット操作から利用できなければ公開機能として完了しない |
| F2 | **凹側の交差するブレンド網**。複数の凹フィレットが合流する頂点で、ブレンド面、切り詰め境界、接続を構築する |
| F3 | **4本以上の辺が集まるコーナー**。高い頂点次数、丸める辺と鋭い辺の混在、複数半径を扱う |
| F4 | **異なる面角度を持つ曲面ブレンドの合流**。接続曲線が平面内に収まらないケースを処理する |
| F5 | **特殊な端部・リム**。斜めの終端面、円周 seam、角度分割が異なるリム、凹凸が混在する壁、鋭い端部の接合 |
| F6 | **一般的なフルラウンド**。隣接面が曲面で、単純な同軸チューブ構成に限定されないケース |
| F7 | **G1／G2 を要求できる面ブリッジ**。現在の Bridge Surface は G0 境界接続を中心とする。接線・曲率条件、張力、幅、壁面との切り詰めを完成させる |
| F8 | **限界形状の失敗契約**。半径が局所厚さを超える、ブレンドが自己交差する、隣接面が消える条件を検出・報告する |
| S1 | **一般曲線を含む面境界の断面化**。面から断面を作る経路で、楕円、暗黙交線、面上曲線などを利用できるようにする |
| S2 | **斜め方向のドラフト付き押し出し**。押し出し方向、断面法線、ドラフト方向が一致しないケース |
| S3 | **曲線境界を持つドラフト断面**。B-spline の鋭いコーナーにおけるオフセット交差、円形コーナーが作る円錐曲線の軌跡 |
| S4 | **複数ガイドによる一般的な曲線スイープ**。現在の回転・尺度変形だけでは表せない断面変形 |
| S5 | **角を持つ経路と変形則の組合せ**。折れ点で twist／scale／guide を同時に適用する |
| S6 | **非平面の閉じた経路**。一周後の断面フレームのずれを扱い、閉鎖条件を満たす |
| S7 | **スイープの極・縮退**。境界が軸へ到達する、小円へ縮退する、断面が消失する位置を正しいトポロジーへ変換する |
| S8 | **ロフトの退化ガイド条件**。接線接触、一致、ガイドの対応パラメータが停留する条件で対応関係を解く |
| S9 | **ロフトの端面と側面の一般的な切り詰め**。接触、共面境界の交差、有限な面どうしの clipping を処理する |
| S10 | **断面対応と自己交差の共通契約**。頂点数・穴数・向き・周期原点が異なる断面間で、対応の曖昧さを報告する |
| E1 | **複数面シートの一体的な Surface Offset**。現在の公開経路は単一面シートを対象とする。複数面の接合、交差、切り詰め、再接合が必要 |
| E2 | **一般的なオフセット／厚み付けの成立判定**。局所曲率、厚さ、自己交差、薄肉部の消失、複数成分への分裂を分類する |
| E3 | **共有境界を伴う Face Rebuild**。編集面だけでなく、隣接辺・共有頂点・隣接面の境界を同時に解く |
| E4 | **一般的な Face Draft**。曲がった中立要素、複数面、Grow 時の衝突、曲面に対する延長・切り詰め |
| E5 | **一般的な Face Match**。単純な平行平面を超え、移動側・固定側・遭遇する壁を整合させる |
| E6 | **一般的な Sheet Extend**。曲線境界、解析・手続き的曲面、物体までの延長、負方向のトリム、複数面の同時編集 |
| E7 | **極・頂点を含む Untrim**。球の極、円錐頂点に必要な退化境界を生成する |
| E8 | **自然延長を使う曲線オフセット**。曲線どうしの延長・交差を解き、端部の接続を構築する |
| E9 | **Imprint の一致・部分遮蔽**。同じ面上にある工具の輪郭、部分的に隠れる投影曲線の分割 |
| E10 | **インポート形状を含む変換の一貫性**。幾何変換だけでなく、取り込んだ B-rep の source、pcurve、参照、履歴まで更新する |
| Q1 | **任意形状どうしの最短距離**。辺―辺、辺―面、面―面、Body―Body。距離に加えて最近点の組、支持要素、曲線・面パラメータを返す |
| Q2 | **複数の最短解・包含の扱い**。複数解、接触、交差、片方が他方の内部にある場合を区別する |
| Q3 | **一般自由曲面の面積・面積重心**。B-spline、offset、ruled、rolling-ball 面は現在の面積評価で拒否される |
| Q4 | **一般ソリッドの体積重心・一次モーメント**。空洞、複数成分、曲面境界を含む |
| Q5 | **慣性テンソル・慣性主軸・主慣性モーメント**。基準点・座標系の変更、合成、平行軸の関係を扱う |
| Q6 | **密度付きの合成質量特性**。材料密度、異なる部品、配置変換、単位系を反映する |
| Q7 | **計測の誤差と適用範囲**。値の単位、絶対／相対精度、積分誤差、達成不能時の失敗を返す |
| M1 | **矩形 B-spline 面の適応細分化**。固定ステップ中心の経路から、位置偏差・法線角度・曲率に応じた細分化へ拡張する |
| M2 | **トリム面内部の誤差制御**。境界の細分化だけでなく、三角形内部の曲面との偏差・法線変化・辺長を制御する |
| M3 | **隣接面間の一致**。共有辺の分割点を一致させ、亀裂・T-junction・重複 seam を防ぐ |
| M4 | **周期・極・細長い領域への品質保証**。seam、球の極、円錐頂点、小穴、狭い領域を扱う |
| M5 | **面単位の設定**。現在は非空の face override が拒否される経路がある。局所設定と共有境界の整合が必要 |
| M6 | **キャッシュ・増分更新・並列化の成立範囲**。形状、精度、許容差の変更に対する無効化と、結果の再現性を保証する |
| X1 | **IGES の公開経路の完成**。対応フラグ、共通入口、直接 reader/writer を統一する |
| X2 | **STEP アセンブリ**。部品定義と配置された実体、共有部品、入れ子、ローカル座標系を保持する |
| X3 | **名前・色・レイヤー・材料の対応付け**。Body／Face／部品／配置ごとの属性、密度、属性の優先順位を交換する |
| X4 | **PMI／GD&T**。寸法、公差、データム、参照形状、意味を持つ注記と描画用注記を保持する |
| X5 | **保存ビュー・クリッピング・検証属性**。ビュー、注記配置、面積・体積・重心などの検証値を保持する |
| X6 | **手続き的ブレンドの交換**。rolling-ball 面は現在の exact STEP／IGES 表現解決で拒否される。対応する厳密表現か、明示的な誤差付き変換が必要 |
| X7 | **独立した曲線・面、グループ、変換の交換範囲**。Body 以外の交換対象も含め、entity ごとに対応を公開する |
| X8 | **追加の標準メッシュ形式**。GLB は export があるが共通 import は未対応。glTF JSON、PLY、VRML は今回の公開形式一覧で確認できない |
| X9 | **双方向の意味保存**。単位、向き、穴、空洞、周期性、配置、属性を外部ツールとの往復で検証する |
| X10 | **部分読込・情報損失の方針**。未対応 entity を含むファイルの拒否、明示的な部分読込、失われる情報の報告を規定する |
| D1 | **B-rep に基づく隠線処理**。可視線、隠線、輪郭線、接線境界、seam の分類を行う |
| D2 | **幾何曲線としての投影図**。投影結果を辺・曲線として返し、三角形の輪郭だけに依存しない |
| D3 | **断面図の構成**。断面輪郭、材料領域、穴、複数成分、元形状への参照を保持する |
| D4 | **図面の表現**。線種、尺度、寸法配置、ハッチング、ページ構成は図面層が所有する |
| A1 | **OCAF 相当の文書基盤**。型付き属性、永続参照、文書間参照、永続化と変更の整合 |
| A2 | **トランザクション**。複数変更の原子的確定、rollback、undo／redo、参照・依存関係の復元 |
| A3 | **永続的なトポロジー参照**。既存 lineage と stable reference を、長い編集列、split／merge／delete、再読込へ拡張して検証する |
| A4 | **依存関係の評価制御**。変更伝播、再評価、循環検出、失敗したフィーチャーの後続処理 |
| A5 | **可視化**。表示モード、カメラ、クリッピング、材質、透明度、注記、表示更新 |
| A6 | **対話的選択**。頂点・辺・面・部品の選択、フィルタ、ハイライト、操作ハンドル、配置された部品の識別 |
| A7 | **カーネルと表示の対応**。表示 Mesh の選択が、正しい評価 snapshot の B-rep 要素へ戻ること |

## Completion Contract

Every requirement needs an inspected implementation and successful behavioral evidence at its owning scope. Supported domains, geometric validity, numerical error, topology ownership, explicit failure, resource admission, cancellation, concurrency and interoperability are verified where applicable. API presence, catalog registration, marker removal and passing superficial tests cannot close an item.

Native pure logic uses bounded SwiftPM tests. Metal execution uses Apple-platform xcodebuild tests. WASM and Embedded use Swift 6.4.0 release with matching SDKs and target runtime tests; unexecuted targets remain unverified. Application changes additionally require preserving unsaved edits, restarting the rebuilt Rupa executable and verifying the active document.

Each coding sprint is designed before source edits, reviewed, behaviorally verified and committed on `codex/occt-functional-parity`. PROGRESS.md is the sole task progress record. Full integration and requirement-by-requirement audit precede merging to main. No partial phase establishes completion of the objective.
