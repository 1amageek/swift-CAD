# CS-POLY-CORRECTION-01 review

The following is the completed read-only reviewer report. Delivery is separate.

CS-POLY-CORRECTION-01 の検証・レビュー範囲を承認します。具体的な契約違反や未解決findingはありません。commit・main統合はDELIVERYの担当範囲として残ります。

| 固定した契約 | 確認結果 |
|---|---|
| 実装と公開接続 | 変更2bodyは指定SHAと一致。ordinary／callbackのbare／rich全4入口が同じproducerへ接続 |
| 原形状・完全対応 | 補正hostの原owner・field・transport・guardを既存経路で保持。同じledgerで準備からpublicationまで処理 |
| 独立oracle | 異なるT=`sqrt(2)-1`／`1`、source UV=(.5,.5)、XYZ=(.5,.5,.0625)、plane UV=(.0625,-.5)、全3incident（2/1）を確認 |
| 完全性・回帰 | singleton／root-free／support外／plane UV除外、既存Coons全12incident（8/4）が成功 |
| resource・失敗 | 有限work allowanceで成功。callback cap=1／1,000,000で正確に停止し、失敗後のfallbackなし |
| cancel・lifetime | entry／mid／最終storage callback後のcancel、原入力scope終了後・COW・独立readerが成功 |
| portability | Native・ASan・通常WASM・Embeddedで各10群成功。Embeddedのexistential操作はprotocol requirement、同期契約のtarget差なし |

4終端receiptの17,336参照・11,357ファイルを照合し、未説明のhash不一致はありません。

| 環境 | 最終証拠 | exact storage／1 byte不足 |
|---|---|---|
| Native | `.build/cs-poly-correction-native-20261011-v3/receipt.json` — `1b6a9435…` | 6,693,548 bytes成功／明示失敗 |
| ASan | `.build/cs-poly-correction-asan-20261011-v3/receipt.json` — `06527e83…` | 6,693,548 bytes成功／明示失敗 |
| WASM | `.build/cs-poly-correction-wasm-20261011-v3/receipt.json` — `38660e16…` | 4,065,192 bytes成功／明示失敗 |
| Embedded | `.build/cs-poly-correction-embedded-20261011-v6/receipt.json` — `da1ac3e1…` | 4,065,192 bytes成功／明示失敗 |

Native／ASan／WASMのroot fixture・driver旧hash計6件は、**現行rootとのbyte一致とは扱っていません**。各v3ディレクトリの`Proof.swift`から抽出したfixtureと`driver.py`をhistorical比較対象として採用しました。現行fixtureからEmbedded専用helper・2ログ分岐だけを除く独立再構成も、旧fixture SHA `6ab027c0…`へ完全一致しました。receiptの書換えはありません。

Embedded v6は成功済みv5 port receipt `469dc0f2…`を厳密に継承しています。実compile入力2bodyはimport-only prefix＋現行原文と一致しました。compile監視上限はwall 600秒／CPU 300秒、runtimeは各120秒です。これはcompiler運用値であり、CAD caller予算・assertionの緩和ではありません。whole-query workの非決定性を踏まえ、旧N／N−1診断を成功証拠に流用せず、変更していないper-unit admission証明と今回のpublic failure forwardingを組み合わせています。

レビューはread-onlyで完了しました。広域build・runtime再実行・下位再証明・追加review cycleは実施していません。一般補正family、全M4–M8、whole-seven／full87の完了は承認対象外です。
