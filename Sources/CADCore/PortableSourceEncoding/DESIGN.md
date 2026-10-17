# Portable Source Encoding

## Purpose and Scope

Parent: [CADCore](../DESIGN.md). This component owns the target-common canonical
source-byte encoding contract used by [CADIR](../../CADIR/PortableSourceEncoding/DESIGN.md).
It has no children. It is independent of Native Codable transport.

## Responsibilities and Boundaries

Explicit protocol requirements encode original values without reflection, runtime
metadata, random Hashable seeds, Foundation, Codable, sampling or fallback. CADIR
owns the fingerprint payload and semantics of ordered versus unordered source
collections. This component owns unambiguous byte framing, cumulative admission,
canonical sorting and primitive values. It does not parse Native packages.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Common values and typed failures | Supplies module boundary | SchemaVersion stays with root owner |
| [Numeric Work Admission](../NumericWorkAdmission/DESIGN.md) | depends on | Exclusive caller work, storage and checkpoint requirements | The existing ordinary adapter is package-visible for full fingerprint delegation | Direct writers always forward their incoming admission |
| [Portable Identity](../PortableIdentity/DESIGN.md) | depends on | Original high/low words | Encodes identity without UUID metadata | No source identity regeneration |
| [CADIR Portable Source Encoding](../../CADIR/PortableSourceEncoding/DESIGN.md) | used by | Explicit original source writers | Owns payload and SHA-256 publication | Wire transport is a separate capability |

## Architecture

```text
original typed value -> explicit encodeSource requirement
 -> type/case/field/length framing -> cumulative source encoding admission
 -> original canonical bytes -> CADIR SHA-256
```

## Contracts and Invariants

The byte stream uses distinct scalar, optional, array, map, record and enum tags.
Integers and binary64 bit patterns use fixed big-endian bytes. Strings retain exact
UTF-8 including empty, null-distinct and non-normalized text. Identity retains
both original 64-bit words. Records carry stable type names, field counts and
field names; enums carry stable type/case names and associated-value counts.
Ordered arrays retain order. Canonical maps sort complete encoded keys and reject
encoding collisions; unordered source collections sort complete original element
encodings with multiplicity preserved. Generic encoder operations invoke the
writer requirement on a statically bound generic `T`. Production has no
`any PortableSourceEncodable` or `some PortableSourceEncodable` call sites.
The generic requirement is not invoked through an Embedded existential and
requires no runtime metadata dispatch.

Limits are caller-owned, explicit values. Every append and scratch key/element
encoding consumes one invocation's remaining byte/work allowance before growth.
Sorting comparisons charge actual visited bytes and retained entries. A child
encoder inherits remaining allowances; its consumed counts are adopted by the
parent and are never refunded or reset. Depth and checked counter arithmetic are
part of admission. Cancellation propagates during encoding and comparisons.
No exhausted, invalid or ambiguous encoding publishes a successful prefix.

### Caller Admission

The sole `PortableSourceEncodable` requirement takes a generic, potentially
noncopyable `NumericWorkAdmission` by exclusive inout access. Each writer and
encoder operation forwards that same admission through original fields, child
encoders and sorting comparisons. The encoder retains only its invocation-local
encoding limits, counters and byte buffers; it stores no admission, pointer,
callback, remaining query allowance or independent budget. Core has no Geometry
dependency and adds no requirement to numeric admission.

Ordinary writer and encoder entry points select the existing stateless
`UnboundedAuthoringAdmission` once and delegate to the same admitted body.
There is no ordinary fallback in a direct call. Original local byte/work/depth
checks and task-cancellation ordering remain before caller admission. Every
existing charged byte and work unit is admitted before the corresponding
allocation or operation. The caller's storage policy remains authoritative.
A scratch child uses the same admission while computing its actual key. On
success, the parent adopts only the child's local counters: this preserves the
existing cumulative encoding limits without charging the caller twice. Failed
work is never refunded. Measurement still suppresses only final output storage;
real canonical keys and their existing output/scratch charges remain necessary.

The byte schema, source field order, key comparisons, collision refusal and
original errors remain unchanged. Completed value traversal checkpoints before
returning. The encoder and its buffers remain invocation-local under exclusive
access on all targets; no new shared state or synchronization is introduced.

## State, Ownership, and Lifecycle

The encoder is an invocation-local, non-Sendable value used through exclusive
inout access. Its arrays own their bytes and do not escape until complete success.
There is no shared registry, lock-free Embedded storage or target-specific state.
Temporary sorting buffers are retained only for their current canonicalization.

## Failure, Concurrency, and Constraints

Typed errors distinguish invalid limits/scalars, exhausted bytes/work/depth and
canonical key collisions. The same algorithms, counters and ownership apply to
Native, normal WASM and Embedded. Consumers choose default limits from their
existing source admission contracts; this component introduces no hidden default
or independent unlimited allowance.

## Verification and Change Impact

Deferred verification must prove fixed byte vectors, exact signed/binary64/UTF-8
identity values, map insertion independence, unchanged array ordering, resource
boundaries, cancellation and complete Native/WASM/Embedded source fingerprints.
Source-only implementation is not portable runtime completion.

### Shared Caller Admission Checks

The [Core shared checks](../../../Tests/CADCoreTests/PortableSourceEncodingAdmissionChecks.swift)
are the sole oracle bodies for the [Native wrapper](../../../Tests/CADCoreTests/PortableSourceEncodingAdmissionTests.swift)
and [portable entry](../../../Tests/OriginalQueryExecutionVerification/PortableSourceEncodingAdmissionPortable.swift).
The same fixed bytes, canonical order, local counters, exact work/storage N/N-1,
original guards/collision and entry/interior/terminal cancellation checks execute
on every selected target. The checks use one invocation-local noncopyable numeric
admission; they introduce no shared mutable state or target-specific oracle.
Actual OriginalQueryExecution and complete Section validation remain their
upper callers' verification responsibility.

### Measurement Without Output Publication

`PortableSourceEncoder.measure` returns immutable cumulative byte/work counts
using the same explicit writer traversal, depth, cancellation and canonical-key
checks. Its private encoder suppresses final output storage; it never exposes
a counting encoder or an empty encoded artifact as the result. Canonical scratch
keys remain real bytes because ordering and collision work depend on their
contents. Byte counts therefore include existing output and scratch admission,
not only final serialized length. Writers describe their original input and
must not branch on an in-progress output buffer. Ordinary construction always
retains bytes and preserves its existing framing and publication contract.
The measurement mode adds no shared state or target-specific implementation.
Deferred verification compares counts and typed failures to retained encoding
for exactly the same source, limits and canonical ordering.
