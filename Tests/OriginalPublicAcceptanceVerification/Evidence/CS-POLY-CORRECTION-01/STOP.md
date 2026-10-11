# CS-POLY-CORRECTION-01 Native Entry Stop

The current exact public entry producer was executed and returned `nil` for both `retainingRelations: false` and `true` on the actual original boundary-corrected lift. This is an observed producer decline, not a claimed public unsupported error, empty intersection, or complete fallback-dispatch result.

```text
Original corrected constructor
  -> existing polyline snapshot and retained atlas source/DI cover
    -> independent exact root/XYZ/UV oracle passes
      -> current OriginalRetainedLiftPlanePublicProducer.resolve
        -> nil in both bare and rich entry modes
```

| Input or expected behavior | Verified value |
|---|---|
| Host | `PolylineAtlasLiftProof.shape(multi: false).1` |
| Curve | `SurfaceLiftCurve3D` with existing `PolylineLiftProof.points()` |
| Plane | Origin `(0.5,0,0)`, normal `unitX` |
| Complete roots over the three authored polyline cells | Positive root of `t²+2t−1=0` and `t=1` |
| Distinct authored parameters | `sqrt(2)−1 < 1` |
| XYZ at both roots | `(0.5,0.5,1/16)` |
| Retained source UV | `(0.5,0.5)` |
| Exact original plane UV | `(1/16,-0.5)` |

Each pcurve cell's `u−1/2` polynomial divides exactly by its expected linear root with a nonzero constant quotient. Every retained host graph proves `X=U*W`. The source/DI incidents evaluate to the independently specified XYZ, and the original plane basis evaluates the expected plane UV to the same XYZ. No relation solver was rerun to establish the entry decline.

The selected compiled producer body exactly contains the current source body with SHA-256 `863b7989810a8f6cdccea0bcb9e3f3bd6c85bfb1c05cc00e503572b5cebfd6e5`. Its initial guard accepts `.originalCoons` only. The admitted `CS-POLY-COINC-01/native` port archive and module were reused. The receipt admits 3,403 source, product, compiler, log, and fixture paths and rechecks them before and after execution.

Command:

```sh
python3 Tests/OriginalPublicAcceptanceVerification/CorrectedPolylineLiftPlaneStop.py --output .build/cs-poly-correction-stop-native-20261011-v2
```

| Operation | Exit | Elapsed | Bounds |
|---|---:|---:|---|
| Native focused compile/link | 0 | 2.167 s | 120 s wall / CPU; process-group cleanup |
| Actual source/DI and selected producer runtime | 0 | 0.771 s | 120 s wall / CPU; process-group cleanup |

Runtime output:

```text
PASS actual corrected constructor/source/DI; complete three-segment roots sqrt2-1 and1 remain distinct; exact XYZ(.5,.5,1/16), sourceUV(.5,.5), planeUV(1/16,-.5)
OBSERVED selected exact public producer declined corrected host false result nil
OBSERVED selected exact public producer declined corrected host true result nil
```

Evidence directory: `.build/cs-poly-correction-stop-native-20261011-v2`.

| Evidence | SHA-256 |
|---|---|
| `receipt.json` | `e20ecf428d75dbe68f791f85dfcaf679e59c9cf57dd7134ea84852c9a0681945` |
| `admission.json` | `a4cbf0079e7ae871fef123f04e9ceefe92eb6a9d1fb8430b7be387cd0d4efa33` |
| `runs.json` | `a9a4770b005603059ae2245c070f21864910167a877257af2db1e8a5b513540c` |
| `runtime-selected-producer.log` | `a8e18036c129c23208979a94b5bb1d4ad0aef29e1d855fad506b0cd6cf4afa8c` |

The compiler is the receipt-identified Swift 6.4.0 release toolchain targeting `arm64-apple-macos15.0`. This stop establishes Native input and exact entry behavior only. No ordinary fallback dispatcher, ASan, WASM, or Embedded acceptance is claimed. The failed v1 attempt used an incorrect fixture denominator index and is excluded; v2 uses the actual `[u,v,0,1]` homogeneous representation.
