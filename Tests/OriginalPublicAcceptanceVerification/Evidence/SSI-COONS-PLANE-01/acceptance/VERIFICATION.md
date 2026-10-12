# SSI-COONS-PLANE-01 verification

## Accepted input and public behavior

The actual original four-boundary Coons surface is F(U,V)=(U,V,0), with
four closed half-square charts; it is never replaced by a Native tensor surface.
The whole original plane is P(p,q)=(1/2,-q,p). Both public source orders retain
exactly (U,V;p,q)=(1/2,V;0,-V), V in[0,1], XYZ=(1/2,V,0), image1/fiber0.
At V=1/2 all four chart owners remain; endpoints retain their two incidents.
The fixture compares every final partition leaf against this independent
polynomial/closed-domain oracle, including omitted-root exclusion.

The ordinary standard, caller-accounted and boxed rich SSI APIs retain the mixed
source/DI/L5 owner and L6 strata through the public reading protocol. Quarter-box
requests retain all charts and restricted UV; singleton(.5,.5;0,-.5) retains all
four exact incidents and XYZ points. PlaneX2 has complete empty selections in
both source orders. Bare continuous entries explicitly throw nonDiscreteIntersection;
bare empty returns empty only after complete exact exclusion.

There is one existing L5 solve and one L6 resolution per chart pair. No numerical
fallback retry, finite plane window, source formula recreation, inverse, UV/root
merge or lower solver redesign is introduced. The shared point publisher's first
transport may now be absent, preserving primitive plane UV in plane-first order.
Existing nonoptional first transports and absent second transports keep their
previous algorithm. Five unchanged Native callers were recompiled for this
internal signature; the other target lanes compile all current production inputs.

## Execution receipts

Fixed Swift6.4.0 release; matching ordinary/Embedded WASM SDK, wasm32-unknown-wasip1;
Native/ASAN arm64 macOS27 SDK. Actual compile, link and runtime passed.
Native/ASAN use the initial fixture; WASM/Embedded use its logging-only portable
revision. Assertion bodies are unchanged. The subsequent COW addition is separately
checked on all four targets without replaying the fourteen accepted groups.

| Lane | Accepted groups | Sum of runtime groups | Summary SHA prefix |
|---|---|---|---|
| native | 14/14 | 114.257s | a7059a29015d |
| asan | 14/14 | 286.099s | 904d1f50ffdd |
| wasm | 14/14 | 45.766s | 924fbaffce61 |
| embedded | 14/14 | 29.272s | 23d754b4bab3 |

Groups cover success, clipped/singleton request, complete empty, six bare entry/order
combinations, bare empty, resources, depth, cancel and detached-source lifetime.
Every group has a120s wall bound and owned-process cleanup. Resource controls use
the measured exact N and N-1 work/bytes, charts4/3, component ceiling4/3,
actual retained source depth and one-less. Algebra depth2 succeeds; depth1 returns
an explicit KernelError (resourceLimitExceeded or intersectionFailure), never
empty/partial success. The fixture does not infer minimum depth from result metadata.
Cancellation checks actual Task cancellation at first/middle/last caller callback
for both nonempty and empty publication. Lifetime checks source release followed
by two independent Task readers with independent admissions. This establishes
immutable reader behavior; WASI's execution does not prove OS-thread parallelism.

The user-authorized dependency generations are under dependency-builds:
Native baseline381.402s/2,136,375,296 bytes peak; ASAN316.354s/2,006,761,472;
ordinary WASM236.977s/1,991,704,576; Embedded324.272s/6,902,415,360.
Each lane had1200s/8GiB bounds and excludes wholeKernel generation.
Native current module and changed8 objects plus5 ABI callers replace only those
baseline object bodies; unchanged objects are receipt-admitted, not appended to
a duplicate merged Geometry object. The module's first partial-module attempt
was stopped after339.668s and is diagnostic only. Corrected single WMO module
production took36.832s; the recorded combined elapsed includes the failed attempt.
Do not interpret the fast object sampler's missed RSS peak as actual peak memory.

[audit.json](audit.json) binds all2090 current production inputs for each new lane,
actual Native replaced products, all accepted runtime logs, and13,127 external
product/toolchain/SDK/runtime files. Link dependencies omitted by SwiftPM product
lists are hash-bound separately; their mtimes predate fixture compilation.
Native/ASAN proof fixtures and portable fixtures are retained exactly as compiled.
Compiler-only success is not counted as runtime acceptance.

## Diagnostics and remaining scope

The old ordinary numerical route timed out at120.014s. It was not replayed.
Current dispatch now bypasses that route using the already established source/DI
capability. Historic compiler failures, incorrect fixture expectations and portable
link failures stay under diagnostics and are not accepted receipts.
The initial WASM link omitted SDK clang resources; Embedded first needed portable
C logging and then the matching SDK Unicode library. These were runner/fixture
changes; the production snapshot and dependency objects remained fixed.

A broader box Coons[0,1]^2/plane[-1,1]^2 is diagnostic, separate from the accepted
quarter request. Rich Coons-first returned a relation owner; no whole-set oracle
was applied in that diagnostic, so it is not additional accepted coverage.
Bare Coons-first returns nonDiscreteIntersection after3,101,409 work/78,298,760 bytes.
Bare plane-first explicitly exhausts resources after6,374,154 work/163,913,196 bytes.
The exact exhausted subresource was not retained; it must not be guessed as caller
work or used to justify raising limits. Neither path returns empty success or
falls back. This replaces the earlier v6 fixture's uninformative invalidEvidence
with an observed public cause. Its bounded reverse success remains unaccepted.

This cell does not complete general Coons boundaries, general plane bases,
numerical bare isolated-point publication, all M7 or all M4–M8. The applicable
INCOMPLETE_IMPLEMENTATION markers remain. Whole-seven completion stays1/7
(requirement5 decomposition); full87 remains incomplete.

## Review and delivery

The stable production snapshot is production-snapshot.json. One comprehensive
review and finding-only mapping confirmation are recorded in [REVIEW.md](REVIEW.md).
Latest-main composition and protected-work checks are recorded by the subsequent
integration receipt; this document alone does not assert main delivery.
