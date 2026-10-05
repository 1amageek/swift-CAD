# Original Affine Operation Word

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns a flat original
forward/inverse affine operation word and exact rational action derived from its
stored finite coefficient bits or authored normalized-direction laws. Curve/surface
source evaluation and BRep ownership remain outside this component. The normalized
frame algebra is supplied by Rational Bivariate Algebra; foreign STEP IDs/names
and units remain with CADIR.

## Responsibilities and Boundaries

`OriginalAffineOperationWord.factors` is the sole source authority. Factors are
applied in array order, first to last. Each retains the original affine columns
and operation direction. Normalized factors retain raw directions, presence,
length gain, scale, and adjustments; they use one shared original real-field
context, with exact positive square-root normalization and inverse operations.
The immutable exact rational/algebraic action is a derived cache,
never a rounded replacement source. Exact cofactor inversion rejects a zero
original determinant. Deep words do not create deep curve/surface source trees.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original image dispatch | Composes this action with an original child source | Child-source depth is separate from word length |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | originalDouble, exact arithmetic and RationalAlgebraAdmitting | Derives exact cofactor and composition authority | Same work/storage ledger for every limb and output |
| [Document Assembly](../../CADIR/DocumentAssembly/DESIGN.md) | used by | original ordered placement operations | Maps root-to-leaf source words into application order | No rounded inverse/composed matrix |
| [Assembly Evaluation](../../CADKernel/AssemblyEvaluation/DESIGN.md) | used by | prepared image action and orientation | Places all original body sources | BRep validation stays with its owner |

## Architecture

```text
original flat operation factors
 -> exact dyadic coefficient conversion -> cofactor inverse where requested
 -> exact rational 3x4 composition cache -> point/vector/whole-box action
 -> caller's original curve/surface image -> validated BRep publication
```

## Contracts and Invariants

- Source factors are nonempty, finite and nonsingular. Application order is
  explicit; callers retaining parent-to-child source order reverse it once.
- Matrix cache composition uses exact reduced rational arithmetic. No floating
  inverse or composed columns are promoted to source. Source equality/hashing
  and codecs use only original factors, excluding derived caches.
- Every factor, scalar/limb traversal and retained array is admitted through the
  composing caller's `RationalAlgebraAdmitting` before execution/allocation.
  No private/default allowance or counter reset is created. Factor count consumes
  work/storage; only actual original curve/surface nesting consumes source depth.
- Prepared action reuse retains the original word and exact immutable cache.
  Point/vector evaluation rounds the final exact rational/algebraic result to nearest even;
  it never rounds intermediate composition or an inverse into source.
- Whole-box action computes exact linear extrema from original interval endpoints
  and exact coefficient signs, then brackets the final rationals/algebraic values outward. Translation
  applies only to positions. Derivatives of every order use the same linear action.
  This avoids premature coefficient/term overflow when the final action is finite.
- Determinant orientation is the product of exact factor signs, including inverse
  factors. Singular input, nonfinite final output, resource exhaustion and
  cancellation fail without publishing a partial word/action.
- Common source/cache fields and Sendable contracts are identical on all targets.
  All state is immutable; the caller owns mutable admission and synchronization.

## Runtime Flows

```text
caller admission -> validate/prepare entire word -> immutable prepared action
 -> same-ledger point or interval action -> caller result publication
Native source decode -> same caller context -> common word preparation
```

## State, Ownership, and Lifecycle

The word owns immutable original factor storage and the exact derived action.
Prepared values share those immutable buffers through value semantics. They
retain their source for their whole lifetime. No mutable global or lazy registry,
unsafe pointer, callback under a lock, or platform-dependent state is introduced.

## Failure, Concurrency, and Constraints

All operations throw typed KernelError/Native codec failures. Rational arithmetic
checks finite source, overflowed storage counts and division by zero. The same
caller callback enforces cancellation/work/storage. Native decoding requires the
existing NativeRationalSourceDecodingContext; a missing context or unavailable
synchronization capability is a typed refusal, never a fresh allowance.

## Verification and Change Impact

After the source phase, CADGeometryTests own original forward/inverse cancellation,
nonuniform/sheared/reflected images, deep words, exact determinant/singular refusal,
subnormal and overflow-cancelling action, nearest-even ties, interval containment,
cumulative storage/work and cancellation. Assembly and original curve/surface
adapters own their public success/failure integration. Source authoring alone
provides no compile, runtime, complete assembly, or target capability evidence.

Normalized operations use the caller's explicit tolerance and maximum algebraic
depth. Their field context is extended in application order, never
restarted for each factor. Final binary rounding uses exact comparisons against
binary values and midpoint ties; a broad root interval is never substituted as a
point. Derived frame and root caches are omitted by source equality and codecs.

`isEquivalent(to:tolerance:maximumDepth:usage:)` compares all twelve exact action
coefficients. Normalized candidates are prepared in a descendant of the first
word's retained field, so root identity and positive direction rescaling can be
proved without comparing rounded columns. Both complete raw operand payloads are traversed under the same composing
admission before cached coefficient comparison. Each retained normalization premise
is revalidated with the explicit dimensionless-original direction policy and the
caller algebraic cap; exact nonzero and independent direction laws remain required.
Distinct foreign record IDs are outside geometry equality; CADIR still preserves them in its original source witness.
Native normalized-word decode takes tolerance only from
OriginalAffineWordDecodingContext.toleranceKey, set by the original package-store
caller. It shares NativeRationalSourceAllowance. Exact word construction takes
maximumAlgebraicDepthKey (0...32); curve image validation independently takes
maximumCurveSubdivisionDepthKey (0...32). Neither is inferred from source nesting.
Missing context refuses decoding, with no standard-tolerance or private-budget fallback.

Normalized source has separate exact lengthGain and linearGain. The first converts
original model-unit location; the second converts an authored primitive's local
coordinates before world adjustments. Occurrence mappings use linearGain.one.
Both gains stay complete original rational source, including normative SI prefix
and conversion factors; rounded LengthUnit.toInternal products are not authority.

The package validateOriginal entry traverses every original factor, nullable raw
direction, scale, exact gain limb, and adjustment through the composing ledger.
It relies on the immutable constructor's exact nonsingularity receipt instead of
replaying cofactor/root preparation. Normalized frames retain the minimum original
squared norm of all direction/projection normalization steps; validation proves
that receipt strictly positive under dimensionlessOriginalDirections. Raw foreign
direction ratios and their projected independence are scale-invariant, and SI
position tolerance never thresholds those ratios. Physical derivative/normal
normalization retains its separate lower physicalDistance policy; physical image
acceptance and angular output accuracy keep the original caller tolerance.
No hidden fresh preparation is created. The receipt stays derived
and is omitted from all source codecs/fingerprints.

Prepared applyingCofactor(to:usage:) transports cross-product normals using
Cof(A)=det(A) A^-T. Exact rational/algebraic minors are cached once during word
construction, with pre-admitted buffer/limb storage; every query uses exact linear
box extrema before final outward binary conversion. Translation is excluded. No
additional orientationSign multiplication is applied: Cof(A) already represents
geometric orientation. Material outward face orientation remains Topology's owner.
Cofactor caches are derived and omitted by source equality and codecs.

Prepared conditionBounds computes rigorous Frobenius upper bounds for A and
Cof(A) conditioning. It forms exact sums of squares and
(||Cof(A)||F² * ||A||F² / det(A)²) before comparing exact values against binary
candidate squares. Final upper square roots therefore avoid overflow caused by
separate huge/small norm factors, use no inferred matrix orthogonality, and charge
every comparison to the original caller ledger. A nonrepresentable final bound
fails explicitly; finite action on a particular point remains independently valid.

Word inverted(tolerance:maximumDepth:usage:) reverses factor application order and
toggles each original direction tag. It reuses the exact derived action for
cofactor inversion and retains every raw source field, with current caller
normalization admission. Prepared maps(_:exactlyTo:usage:) compares the exact
unrounded image with the complete authored binary target point; equality of
rounded numeric candidates is never acceptance authority. A false result does not
prove an imported real endpoint invalid: nonbinary exact endpoints require their
original endpoint carrier instead of substitution with an approximate Point3D.

Image composition can call validateOriginal(tolerance:usage:) to reuse the word's
retained constructor algebra-depth authority while rechecking the current
normalization premise under the composing invocation's ledger. It does not infer
algebra depth from curve subdivision or source-tree nesting and does not grant a
new allowance. The explicit maximumDepth overload remains for a caller imposing
a stricter independent algebra-depth policy. Prepared actions already retain and
use this constructor authority; composing callers must enforce their independent
resource caps in the same admission object.

Native source nesting is supplied independently through maximumSourceDepthKey
(the original positive package maximumNesting). validateSourceNesting checks the
actual decoder coding path before decoding source containers. Semantic Native
source visits are charged at exact-cell depth zero; algebra root visits retain
the caller maximumAlgebraicDepth. The source-depth key is never reconstructed
from the algebra allowance or curve subdivision setting.

Prepared physical metric admission can prove similarityScaledLengthIsGreaterThan
by checking the exact column Gram matrix (equal diagonal entries and zero cross
terms) and comparing squared original length times the exact scale square against
the authored physical threshold square. A nil result explicitly means the action
is not a similarity; callers must retain their general affine metric producer.
No rounded norm, source-unit tolerance, or Frobenius sufficient bound substitutes
for this exact physical primitive admission. inverseLinearNormUpper independently
bounds the exact inverse Frobenius norm without forming a rounded inverse matrix.
Both entries share the caller ledger and retained field authority.

Word.appending(_:tolerance:usage:) adds one original operation at the end of
application order, retaining the existing constructor algebra authority and
current normalization premise. The complete new source factor buffer is admitted
before its copy. Direct appends compose against the exact retained action cache;
normalized appends extend the retained original field. No rounded composed matrix
or guessed algebra ceiling is introduced. An operation exceeding the retained
cap fails under the same composing admission.

Word.mapsSameImage(of:as:of:tolerance:maximumDepth:usage:) compares two complete
raw binary points acted on by their retained original words. Rational images are
compared before binary rounding. Normalized images use a shared descendant field
and exact coordinate difference signs, preserving normative unit gains. This is
not a conic endpoint chart producer: an approximate local candidate cannot be
promoted to an authored raw point or a native parameter receipt.

The similarity scaled-difference entry retains both original finite length values
and subtracts their exact dyadic coefficients before squaring. It shares the same
Gram/physical-threshold proof as single-length admission. A rounded torus major
minus minor radius is never substituted for this original source gap.

The package prepared.originalNormalizedFrame(usage:) accessor retains the immutable
exact frame and its constructor algebra-depth authority together. A nil result
means a rational-only source, whose exact coefficient accessors remain available.
The returned value is pre-admitted and shares the original field buffers/context;
no normalization replay, rounded matrix, or unrelated authority is introduced.

For general affine primitive admission, minimumImageLengthIsGreaterThan retains
raw original directions and separate raw lengths. It forms exact transformed
columns and their Gram matrix, then proves the shifted matrix strictly positive
by two- or three-dimensional Sylvester minors. This proves the complete minimum
over all unit coefficient directions, including shear/nonuniform/reflected laws,
without sampled eigenvectors. The difference overload subtracts original lengths
exactly before applying the same matrix proof. Raw and temporary buffers are
admitted before allocation; caller-owned input arrays require caller admission.

The projected minimum-difference entry measures distance perpendicular to the
exact transformed original axis. It retains two original radial directions, one
original axial direction and the exact original upper-minus-lower gap. The
complete three-column Gram matrix yields its two-dimensional Schur complement;
strict Sylvester positivity is proved after multiplying by the positive exact
axial norm square. No rounded projection, inverse, eigenvector or full radial
image norm replaces this axis-distance law. Original buffers and all field
arithmetic share the caller's existing ledger.

An explicit constructor algebra-depth capability is retained even when its
current factors are entirely rational. Exact direct append and inversion carry
that same explicit capability forward; a later original normalized factor may
use it without inventing a new cap. The rational-only constructor without a
cap retains zero. Native reconstruction reads the caller's explicit algebra
cap for both rational and normalized source, independently from factor contents.
The capability remains derived and is excluded from persistent source fields.

### Original Scaled Vector Action
Prepared `enclosure(ofOriginalVector:originalScale:usage:)` interprets each raw
finite vector component and scale as separate exact original binary rationals,
multiplies in that source field before any floating conversion, and applies the
retained exact linear action. Rational and normalized ordered-field paths sum
all three original products before their final outward component enclosure.
Translation is excluded. No intermediate binary direction-times-radius can
underflow, and coefficient cancellation is retained. Same caller work/storage
and retained algebra depth govern all arithmetic. No temporary row/vector arrays
are created. Physical positive-radius/metric admission stays with the primitive
owner. Deferred evidence includes least-subnormal radii expanded by large exact
scale, cancellation, normalized factors, overflow refusal and budget exhaustion.

## Original Direct Rational Coefficient Source

`OriginalRationalAffineSource` retains twelve exact original coefficients in
row-major 3x4 order. `OriginalAffineOperation.rationalForward` and `.rationalInverse`
apply that direct coefficient law or its exact inverse. This is distinct from
binary authored transforms and foreign normalized directions: IGES matrix decimal
coefficients never acquire an axis-normalization law or rounded binary authority.
Translation and original unit interpretation are prepared by the foreign-source
owner before creating these coefficients; the word does not infer units.

The input coefficient buffer is immutable COW source. Its allocator must admit
incoming construction before allocating it. Source acceptance traverses all
canonical numerator/denominator words on the same composing ledger; no copy of
those buffers is made at acceptance. Derived composition, inversion, determinant,
cofactor and mixed-field embedding use the existing exact matrix contracts and
pre-admit each owned cache before allocation. Factor-count work is distinct from
child source depth. A zero exact determinant rejects the factor. Mixed normalized
and direct rational factors share one original field context and independent
algebra capability, never a rounded representative matrix.

Native wire adds `rationalForward`/`rationalInverse` operation tags with a `source`
object containing only `coefficients`, each using the strict canonical rational
codec. Existing four tags remain unchanged. Portable source stores only raw
coefficients and direction tags, never derived action/caches/orientation. Deferred
behavioral evidence: exact decimal rotations, reflection, shear, scale/translation
order, inverse and mixed normalized words; singularity and selected lower work,
word bytes and independent source/algebra admission failures.


### Exact Rational Publication View

`PreparedOriginalAffineOperationWord.exactRationalCoefficients(usage:)` returns
all twelve final exact action coefficients in row-major 3x4 order only when the
retained action is rational. The composing publication ledger admits twelve
coefficient slots and traverses their complete canonical limbs before the
immutable COW result escapes. It reuses the prepared exact cache without matrix
rounding or original normalization replay. Algebraic actions fail explicitly;
interval coefficient brackets cannot be serialized as original exact rationals.
The foreign writer owns finite-decimal representability and legal format tokens.
Native and Portable source continue to retain factors rather than this derived
publication view. Deferred evidence includes decimal matrix round trips, exact
inverse/composition cancellation, algebraic refusal and lowered publication
work/storage failures.
