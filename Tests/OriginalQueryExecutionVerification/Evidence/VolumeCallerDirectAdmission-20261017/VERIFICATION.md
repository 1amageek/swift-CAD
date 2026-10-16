# Public volume caller admission — 2026-10-17

This package accepts one finite change: the existing line-only shell reference
and exact support-plane calls now receive the caller's `OriginalQueryExecution`.
The two inverse argument removals restore the entire pre-change production file
byte for byte. Source equations, source authority, topology order, tolerance
checks, fallback selection and local ceilings are unchanged. Ordinary public
entries still create their established root once and delegate to the same body.

```text
BRepModel volume / signedVolume / volumetric validation
  -> existing base validation (P, including first lower traversal)
  -> existing shell integration
       -> original reference + six exact planes (second traversal L)
       -> original ordered points (O) + fixed cube incidence visits
  -> original result / explicit typed failure on the same caller A
```

## Accepted implementation and behavior

The shared fixture retains the original six-plane, twelve-line, eight-vertex unit
cube with six four-coedge loops and authored two-point UV polylines. Whole-model,
body and signed-shell volume remain one; ordinary and direct entries run the real
producers. Public volumetric validation completes over the same original source.
No validated receipt, membership result, geometric producer or budget is faked.

| Evidence | Native | ASAN | WASM | Embedded WASM |
|---|---:|---:|---:|---:|
| Actual focused groups | 4 PASS | 4 PASS | 4 PASS | 4 PASS |
| Fresh Topology142 compiler seconds | 11.185 | 14.234 | 13.456 | 15.074 |
| Fresh client build/link seconds | 12.058 | 3.034 | 1.629 | 54.077 |
| Runtime process seconds | 1.635 | 7.249 | 3.724 | 1.162 |
| Source/product/log drift | 0 | 0 | 0 | 0 |

Each target uses the fixed Swift 6.4.0 release toolchain and its pinned SDK/target
flags. Native and ASAN target macOS 27; WASM targets `wasm32-unknown-wasip1` with
the matching ordinary or Embedded SDK and WMO. Existing, byte-identical Core67
and Geometry2171 products were strictly reused from their actual successful
compiler origins. Only Topology142 and these real clients were compiled. The
raw receipts preserve complete commands, tool/SDK fingerprints, whole-source
inventories, original product hashes, snapshots, logs and dependency bindings.
No product binary, object or module is copied into this package.

The compile/link bound was 1200 seconds, process-tree memory 10 GiB, runtime 120
seconds, and SwiftPM jobs one. Native Testing cases retain their one-minute time
limit. The largest observed phase was Embedded client linking at 6,104,678,400
bytes; no bound or source was changed between targets and no failed lane was
replayed.

## Independent lower-owner cost composition

For the retained cube, signed-shell work is exactly:

| Separate actual producer/query | Work |
|---|---:|
| P: public base `validate(tolerance:using:)` | 87,116 |
| L: original shell reference plus six exact support planes | 78 |
| O: public ordered-point queries for the six loops | 48 |
| Fixed topology visits: 6 faces + 6 loops + 24 edges + 12 triangles | 48 |
| Actual signed-shell query, excluding prior caller work | **87,290** |

P already contains the first reference/plane traversal. L measures the mandatory
second traversal after base validation, not the same work twice. Public
orderedPoints only constructs an immutable invocation before the same internal
body; it has no extra paid entry, validation or sorting prefix. Public base
validation likewise adds no paid prefix before the internal body used by volume.
All four targets independently observed this exact composition.

The reference portion of L is 36 work and the plane portion is 42. Restoring
one of the two independent-root calls would remove its second traversal from
the caller, while remeasuring P absorbs only its first traversal. The exact
composition oracle therefore detects either omission independently of the
self-measured N/N−1 boundary. This mutation sensitivity is a source-derived
argument; no mutant was compiled or executed. The raw source inverse is not
represented as a mutant runtime result.

## Resources, cancellation, errors and ownership

Each resource check retains one immutable authored cube throughout its measured
and boundary requests, includes prior caller work 13, and requires exact work N
and byte N success plus typed work N−1 and byte N−1 refusal. Zero storage also
refuses before allocation. Work N is 87,306 for body volume and 87,416 for public
volumetric validation on all four targets. Typed byte costs are target-specific:

| Target | Body byte N | Volumetric byte N |
|---|---:|---:|
| Native | 932,416 | 932,432 |
| ASAN | 934,224 | 934,240 |
| WASM | 709,224 | 709,240 |
| Embedded WASM | 709,296 | 709,312 |

These byte values are observations, not cross-target constants in the fixture.
Rejected debit counters stay within the supplied boundary, and local work equals
the original caller's cumulative budget. No incoming ceiling is raised, no child
budget is created, and no phase resets the caller's prior work.

The four public paths each expose entry, in-progress and last-observed checkpoint
cancellation on the same retained trace. All twelve cancellations propagate the
original typed cancellation; entry cancellation admits no work/bytes and later
cancellation retains admitted work. The last observed checkpoint precedes the
original return; this is not a newly introduced post-result/publication hook or
a claim about cancellation after an API has already returned. Checkpoint counts
are measured per target on the retained input, not transferred across targets.

Missing body and missing shell preserve their exact original
`TopologyError.missingReference` cases/messages. A copied persistent source remains
valid after authored vertices change and authored surface/loop tables are removed;
all three returned measurements remain one after their source/query owners leave
scope. The only new mutable fixture owner is `Checkpoints`: Native, WASM and
Embedded all store the same `let Mutex<Int>`, read/increment through `withLock`,
and throw outside the lock. Its stop ordinal is immutable and the budget closure
retains the Sendable owner. There is no target-specific raw state, weakened
Sendable contract, unsafe concurrency, I/O under lock, or new production state.

## Unaccepted earlier probe

`unaccepted-native-probe/` preserves the earlier 33-by-2 same-law Native-plane cost
probe. It hit the existing 60-second test time limit before P completed; this is
not an accepted RED cost assertion. One subsequent, bounded retained-binary LLDB
observation (9.208 seconds total, one inferior, compiler zero) captured fixture
line 59 in base validation's original pcurve correspondence/Taylor enclosure,
then killed the inferior. The plain cube volume-one check had already returned;
L and V were not reached. The A.work numeric value was not captured and is not
inferred from elapsed time. No timeout, cap increase, geometry replacement or
proximity-to-equality conversion is used as successful volume evidence.

## Review, provenance and delivery boundary

One comprehensive review completed with no findings/blocker in this scope. Its
raw SHA-256 is
`292c8132276f160ee70abb6b063aa930ee0a99364d368e6f4d8efbab0509add9`.
The index maps each compressed raw member to its original path, uncompressed
SHA-256, compressed SHA-256 and evidence role. Every member was decompressed and
hash-verified, and source/fixture freeze hashes were checked again after packing.
The manifest records the source inverse and the shared-state ownership matrix.

This package does not accept whole U1, NUMERIC, Topology, general Native/curved
volume families, nonlinear correspondence completion, or historical raw Mass
work. The two established producers and their failure/source contracts remain
authoritative. The slow Native correspondence probe remains outside this unit's
positive coverage.

Main integration is pending. The separately prepared private `bind.py` is not yet
executed. It must check all 2,380 Main production source hashes, Package.swift,
original snapshots, compiler/SDK/flags, real fresh phase origins and all retained
products before and after Main client execution. Its metadata must say
`status: reuse-bound`, `compiledHere: false`, retain originalSourceRoot and
nativeAuthority, and normalize each reusedFrom to the actual fresh compiler
receipt without changing commands/products/elapsed data. It does not claim a
fresh Main compilation or permit source-equivalence by ABI assumption. Root owns
that integration, canonical progress, commit and push.
