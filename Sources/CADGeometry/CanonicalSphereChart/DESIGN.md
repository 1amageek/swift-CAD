# Canonical Sphere Chart

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md). Owns the continuous symbolic angular chart
of the ideal analytic sphere, original circle/ellipse/circular arc, intrinsic
cylinder/cone/torus periodic coordinates and the intrinsic original revolution orbit. There are no children.

## Responsibilities and Boundaries

Stored center/radius define the sphere. Stored conventional angle labels identify
mathematical quarter/full turns. Native rational angular laws remain independent.
Numerical representatives never replace certified phase intervals.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | canonical sphere authority | Defines source meaning. | All ideal angular primitive adapters must agree. |
| [Surface pole geometry](../SurfacePoleGeometry/DESIGN.md) | used by | closed normal/position receipts | Exact quarter turns collapse. | No proximity snapping. |
| [Original revolution](../OriginalRevolution/DESIGN.md) | used by | coherent full-turn Rodrigues harmonics | Shares intrinsic symbolic orbit phase. | Preserve mixed derivative scale. |
| [Surface silhouette](../SurfaceSilhouette/DESIGN.md) | used by | requested-order harmonics | Uses original chain scale. | Mixed partials remain original. |

## Architecture

```text
original angle label -> normalized symbolic phase -> sine/cosine source ranges
                     -> original chain scale -> closed D0-D3 / higher Taylor
```

## Contracts and Invariants

Physical angle equals mathematical pi times label divided by the conventional
binary64 pi label. The exact mathematical pi lies strictly between
`0x1.921fb54442d18p+1` and `0x1.921fb54442d19p+1`. This fixed constant enclosure
follows from Machin's identity `pi=16 atan(1/5)-4 atan(1/239)` and the alternating
rational series remainder: the sum through degree 49 and the next signed term
bound each arctangent; exact rational comparisons place the resulting pi bounds
inside the two binary endpoints. The stored constants are the resulting theorem
bounds, not model data. Every harmonic derivative includes the original scale
pi/conventionalPi. Canonical quarter-turn singleton values are exact sine/cosine
identities of this same continuous law. Whole intervals retain outward phase
and trigonometric ranges; exact singleton values do not alter nearby values.

## Failure, Concurrency, and Constraints

All fields are immutable. The composing admission accounts for phase composition;
there is no private traversal budget. Nonfinite phase/derivative arithmetic fails
through the consuming original provider. Source-normalization roles apply to
the analytic sphere, original ideal closed conics, their authored circular arcs,
cylinder/cone U, torus U/V and retained original revolution orbit. The cone's
nonperiodic halfAngle slope retains its authored scalar law. Original rational
angular sources and unrelated analytic scalars retain their authored laws. Circle and analytic
circle frame conventions remain distinct. Rational conic images require an
original nonlinear angular station receipt; candidate controls and atan values
do not establish that correspondence.

## Verification and Change Impact

After source implementation, check pole positions and all mixed derivatives,
continuous endpoint approach, longitude seam, inverse pcurves, reflection images,
whole-box normal bounds, projection and Native round trips through public paths.
For curves, verify full-turn closure, partial authored arc labels, all derivative
orders, circle/ellipse inverse projection and retained frame conventions.
Directional roots and rational conic/pcurve station maps remain incomplete
until their original phase authority is connected.


The symbolic longitude period is exactly twice the conventional binary pi label.
Finite labels reduce by that binary period before numerical trigonometric
representatives are formed, avoiding unbounded phase error at large longitude.
Whole harmonic queries retain branch crossings and use the complete [-1,1]
cycle when their original label width covers a turn. Derivative fields keep the
original continuous phase scale; reducing a value never sets a derivative to
zero or treats a seam as a derivative discontinuity.

Label reduction is exact dyadic arithmetic. The original binary64 significand is reduced modulo the original binary period significand with UInt64 full-width products; powers of two are applied by bounded repeated squaring. The resulting remainder has at most the period's 53-bit significand and is exactly representable before rescaling. This preserves the symbolic turn even for large finite labels and does not infer a canonical angle from a rounded floating remainder. Interval width is enclosed outward before full-cycle admission.


Point candidates, D0-Dn jets, interval harmonics, original UV inverse candidates
and silhouette scalar fields share this phase for each intrinsic angular axis.
The phase derivative gain applies once per angular differentiation. Source
normalization/basis authority is unchanged by the phase contract; an exact
normalized STEP word keeps its separate original frame authority.

Bounded harmonic evaluation charges each actual dyadic modular-reduction iteration and trigonometric endpoint/extremum visit through the composing admission. Fixed scalar range accumulation creates no temporary arrays. Standalone numerical entries root one independent execution and use the same direct body; harmonic source enclosure semantics and phase gain remain unchanged.

## Authored Physical-Radian Transport

`OriginalAngularParameterTransport` retains either intrinsic native labels or an
exact rational physical-radian gain and offset. The physical branch denotes
`nativeLabel = conventionalPi / mathematicalPi * (gain * t + offset)` symbolically.
Harmonic evaluation cancels the intrinsic phase ratio and evaluates the original
physical radians directly; no enclosure of pi becomes an exact source coefficient.
The derivative gain is the original rational gain at every order. Untrimmed
periodic primitives keep their intrinsic chart. Authored physical-angle trims
and pcurves may use the distinct persistent curve/surface transport families.
A physical-radian coordinate has no binary period witness; a binary endpoint
`2 * Double.pi` is never declared an exact mathematical full turn.

The curve source fields are `source` and `transport`; the surface fields are
`source`, `uTransport`, and `vTransport`. Immutable prepared harmonic coefficient
receipts are derived caches excluded from identity and serialization. Direct
ideal conics and cylinder/sphere/torus angular axes use the same coefficient
producer before spatial word action. Raw radius positivity is structural;
physical metric validation occurs under the complete spatial action. Cone
semi-angle is a separate nonperiodic physical slope and is not silently remapped.
Unsupported primitive/image/inverse domains fail explicitly until their actual
original law producer is connected.

An angular support with intrinsic sphere latitude retains the canonical collapsed
XYZ pole for every finite physical or intrinsic longitude interval. World images
consume already-transformed center/axial coefficients, so raw local radius
underflow or SI validation does not replace the physical pole authority.

`physicalRadianArc(start:end:additionalTurns:)` retains a normalized authored
physical trim. Its phase is start plus `(end-start+2*pi*additionalTurns)*t`, with
mathematical pi retained symbolically. The original rational endpoints and
integer turns are serialized; neither a rounded period nor a rounded width is
source authority. Singleton endpoint harmonics cancel integral full turns
structurally while all derivatives retain the same whole symbolic phase gain.
The directed gain must have a strict certified sign; failure to isolate it is
explicit. Equal rational endpoints plus a nonzero integral turn count retain
exact closed traversal. This chart is distinct from the untrimmed intrinsic
primitive basis and does not grant a binary physical-radian period witness.

Numerical canonical harmonic candidates are the midpoint of the original symbolic-phase harmonic enclosure. Exact quarter-turn values are identities of that continuous phase law. Reduced-label libm evaluation alone is not the public candidate producer. The valueBounds port retains the actual outward error for caller proof; legacy numerical facades use the same law with no new private allowance.

Physical sphere latitude uses the inverse image of mathematical `[-pi/2,pi/2]`.
The exact source support and collapsed fibers are owned by
[OriginalSourceIssuance](../OriginalSourceIssuance/DESIGN.md). Numerical point and
jet requests admit their complete phase interval against certified pi bounds;
outside support or an unresolved boundary propagates failure. Normalized arcs
include all retained integral turns when checking whole latitude support. Cone
longitude transports retain scalar V and the separately authored physical slope;
the shared harmonic coefficient producer owns their evaluation.

## Direct Original Query Calling

The [module direct execution contract](../DESIGN.md#u1-direct-execution-ownership)
governs caller composition. Scalar source construction consumes the original
`inout A: ExactScalarAdmission & ~Copyable`, with explicit work units, checked
allocation bytes, independent value/coefficient scope observations and unchanged
source laws. Geometry query composition uses the same original execution;
ordinary conveniences create one cumulative owner only at their real entry.
Callback-to-admission reconstruction, copied budget writeback and cancellation-
only legacy allowances are removed. Actual structural and parameter guards,
original source ownership and scoped identities remain required.

### Direct Source Execution

Pure original word/coefficient operations receive the original generic
`inout A: ExactScalarAdmission & ~Copyable`. General geometry construction,
validation and retained queries receive the original `inout OriginalQueryExecution`.
Actual lower calculations keep that same object; no legacy, validation or borrowed
admission is reconstructed from resource callbacks. Configured capabilities
remain independent of attained proof metadata. Actual payload bytes are checked
and admitted before materialization; failures and cancellation publish no partial
source or complete query. Ordinary numerical entry points may create one explicit
independent execution and delegate to the direct operation. Source-only generic
branches consume their genuine Native/word law without acquiring a general
geometry capability.

```text
Original caller execution -> source validation/query -> original lower operation
generic caller A -> pure Native/word coefficient law -> retained source proof
```

Owning behavioral success, guard rejection, independent budgets/depth, terminal
cancellation and retained lifetime must execute through the actual direct path.
Syntax or signature checks alone are not completion evidence.

Angular coefficient preparation observes the attained local scalar proof depth
on the composing admission. The immutable source retains that depth alongside
its cached coefficients, and cached interval/derivative queries re-admit it before
use. Source equality and hashes exclude this operational metadata. No mutable
shared refinement state is introduced.
