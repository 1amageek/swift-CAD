# CS-POLY-01 prepared Native diagnostic

This is changed-path evidence for uncommitted implementation drafts based on
`de7dd2ba`. It does not complete CS-POLY-01, ordinary public dispatch, M7 or M8.
The executable uses the actual retained-lift/whole-plane public overload on
`DefaultCurveSurfaceIntersector`, with actual original Coons and Euclidean
polyline construction and source/domain receipts.

## Input and independent oracle

The input is the frozen four-cell planar Coons host and pcurve
`[(0,0),(0,0),(1/2,1/2),(1,1/2),(1/2,1/2)]`, intersected with the whole plane
through `(1/2,0,0)` with normal `unitX`. Independent authored roots are
`T=sqrt(2)-1` and `T=1`. Both have XYZ `(1/2,1/2,0)`, lift UV `(1/2,1/2)` and
plane UV `(0,-1/2)`. Eight closed-chart incidents belong to the first root and
four to the second; these are representatives of two authored roots, not twelve
new roots or one XYZ-merged root.

The [probe](../../PreparedPolylineCoonsPlaneProbe.swift) checks the exact positive
root equation `T*T+2*T-1=0`, the exact endpoint `T=1`, restored original TUV,
plane UV, XYZ and exact incident counts. Numerical residuals are not used as
equality evidence.

## Causal change

The retained polynomial lift witness reducer preserves the original graph and
complete forward `(T,U,V)` coordinates. The plane-incidence restriction retains
the exact necessary linear equation, original request, selected request and owner.
The existing graph compiler already proves identity-domain restriction. The
change reuses that restriction and substitutes a proved closed singleton into
every imported position and predicate law while retaining the parameter slot,
all guard instructions and the original binding.

Before this scoped specialization, the same prepared input failed in L5 scalar
work admission under the existing `8,388,608` work ceiling. The retained
`before-specialization-*` logs are diagnostic history; their overwritten old
product is not accepted as current evidence. The ordinary legacy red/trace
remains in [CS-POLY-01-trace](../CS-POLY-01-trace/receipt.json).

## Accepted diagnostic behavior

| Mode | Observed behavior |
|---|---|
| `public` | Two authored roots, exact 8/4 incidents and all TUV/XYZ checks pass. Preparation, query and oracle checks consume work `2,020,254` and storage `14,044,799` bytes. |
| `compiler` | All laws are constant on the retained singleton scope, the original parameter slot remains, a false guard selects no cell and a true guard selects one. |
| `selections` | Final root only gives four incidents; both endpoints open gives complete empty; the exact irrational singleton gives eight incidents; a request wholly outside support gives complete empty. |
| `resources` | A fresh prepared query succeeds at exactly work `1,901,288` and storage `13,372,000` bytes. One less work or storage, and point limit eleven, fail explicitly. Entry and final checkpoint cancellation remain cancellation. A later independent admission reads retained exact data. |
| `reduction` | Twelve charts, 72 tuple/guard comparisons and eighteen admitted tuples preserve position and guards, including exact 8/4 incidents. Exact/one-less work `8,700` and storage `33,049`, entry/final cancel and missing equality refusal pass. This is reducer evidence only. |

The independent Native assembly uses Swift `6.4.0-RELEASE`, target
`arm64-apple-macos15.0`, SDK `MacOSX27.0.sdk`, `-Onone`, `-enable-testing` and
compiler parallelism two. Independent compile is bounded by 240 seconds; port
compile, link and each runtime are bounded by 120 seconds. The final independent
compile took 107.854 seconds. Runtime duration is recorded per mode; no throughput
or wall-time speedup claim is made.

## Receipt and scope

[receipt.json](receipt.json) binds 307 compiled files, the changed premise delta,
all compiler/link commands, logs and thirteen retained products. The admitted
[Native parent receipt](../../../OriginalPolylineFieldFamilyVerification/Evidence/native/receipt.json)
has 2,969 premises matching before and after. Its unchanged cached CAD numerical,
constructor and DTO products supply original nominal types. Current independent
L2-L6 and changed graph/public-port sources are assembled against those types;
this is not a broad production CADCore/CADGeometry/Kernel rebuild. Retained
products live under `.build/cs-poly-01-prepared-accepted-20261011`; verify receipt
hashes before executing them again. Diagnostic driver copies describe this
assembly, not an accepted general-purpose runner.

`production-draft.patch` freezes the exact source/design draft against `de7dd2ba`
so later edits do not erase the Native diagnostic's implementation snapshot. Its
hash is in the receipt, and read-only `git apply --check` against that main base
passes. This patch is not a reviewed or delivered production change.

Ordinary `Curve3D` dispatch, numerical representative publication, ASAN, ordinary
WASM, Embedded, detached-source lifetime and existing GP regression remain
unverified. No aggregate review or production commit/main integration is claimed.
The next cell change is the actual ordinary public route consuming these retained
receipts under its existing caller allowance, rather than adding another source
producer or increasing resource ceilings. PROGRESS.md owns execution status.
