# M3 scaled-normal repair verification

The public counterexample is a raw/analytic z=1 plane with stored normal
(0,0,1e-12) against a degree-one z=0 Native patch, in both operand orders.
Before repair the legacy boundary path reported coincidence. The shared
plane/B-spline dispatcher now checks the existing legacy unit-normal requirement
before any unit-distance computation. It does not normalize or alter the source.

The actual production M3 fixture checks unit-normal empty success, explicit
unsupportedCapability for tiny/large normals, and unchanged point/UV acceptance.
M2 complete Native family fixtures also pass with unchanged limits. The source
snapshot is unchanged throughout compilation and execution. receipt.json binds
all actual compiler inputs, products, commands and runtime hashes.

Swift 6.4.0 release, Native arm64, four compiler jobs, 120-second per-command
runner timeout. Builds took 16.83 and 2.76 seconds; M2/M3 runtime took 7.91 and
0.72 seconds. The unchanged independent source-domain Native/ASAN/WASM/Embedded
proof is retained; this record does not claim full Geometry portable execution.

Scoped review: the precondition dominates boundary coincidence, isoparametric
reduction and analytic conversion; both raw and analytic canonicalization reach
it in either order. The typed refusal is propagated unchanged. No unrelated
source, admission, ownership or tolerance contract changes.
