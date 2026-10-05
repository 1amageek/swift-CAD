# Native Codec Capability

## Purpose and Scope

This component owns the capability boundary between common CADCore values and
their Native/normal-WASM Codable adapters. Parent: [CADCore](../DESIGN.md).
It has no children. The verification unit is the actual complete CADCore module
and its registered HashTreeCollections dependency, not an extracted primitive
source subset. This is an A2 prerequisite; it does not complete A2, CADIR
portability, document persistence, or the Embedded full facade.

## Responsibilities and Boundaries

Common value fields, constructors, validation, equality, hashing, Sendable,
typed failures, expressions, lineage, capability records and numeric algorithms
retain their existing meaning on all three targets. Only Codable, its coding
helpers and Foundation-specific error presentation are capability adapters.
Adapters stay in the original type's file because Swift synthesizes a value's
Codable witnesses there; these are explicit platform adapters, not additional
storage owners. Original paths and Native public APIs remain intact.

SchemaVersion, ModelingTolerance and FailureContract changes remain owned by
the module/root task. PortableIdentity, TaggedID's existing adapter boundary,
CurrentTaskCancellation and PersistentMap's TreeDictionary owner are unchanged.
CADIR owns document records, including X7 source. Foundation Date/Data and
portable document/source-envelope decisions are outside this component.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Public Core values and module dependencies | Supplies the complete production module | A small primitive extraction cannot prove the module |
| [Failure Contract](../FailureContract/DESIGN.md) | coordinates with | Typed classification and diagnostic context | Owns shared failure fields and source error mapping | Keep common descriptions; isolate only unavailable codec/LocalizedError adapters |
| [Capability Contract](../CapabilityContract/DESIGN.md) | coordinates with | Immutable capability records | Uses common values and Native transport adapters | Codec availability does not change declared geometry support |
| [Portable Identity](../PortableIdentity/DESIGN.md) | depends on | Tagged identity words and Native wire adapter | Preserves identity fields in common records | Do not change identity storage or generation |
| [Current Task Cancellation](../CurrentTaskCancellation/DESIGN.md) | depends on | Current-task typed cancellation | Retains the existing checker and witness | No weaker Embedded cancellation or Sendable contract |
| [CADIR](../../CADIR/DESIGN.md) | used by | Values, expressions and persistent references | Composes these values into complete source documents | Its remaining Codable/Date/Data graph is not proved here |
| [Core Portability Smoke](../../CADCorePortabilitySmoke/DESIGN.md) | used by | Public complete-Core value operations | Verifies fixed-target compile/link/runtime | A codec-unavailable marker is not serialization success |

## Architecture

```text
HashTreeCollections 1.5.1 -> PersistentMap (same COW owner)
                                      |
Common CADCore values/errors/algorithms
        |                             |
Native / normal WASM                  Embedded WASM
same Codable witnesses                same values, no Codable adapter
Foundation presentation adapter       common descriptions and typed failures
        \                             /
         actual CADCore public smoke
```

## Contracts and Invariants

- The Native and normal-WASM Codable API and wire formats are preserved.
  Point2D, Point3D and Vector3D keep their coordinate keys; Transform3D keeps
  its matrix field; Matrix4x4 remains a single array of exactly 16 finite
  values, with its existing typed decode-time validation. Quantity, units,
  revision, references, lineage and capability records retain their original
  synthesized/RawRepresentable witnesses, fields and enum spellings.
- CADExpression keeps its explicit kind/operand keys and strict unexpected-key
  rejection. BezierExtensionShape keeps its kind/spanCount/degree/coversCurve
  contract. No new private JSON format, default record, migration or extra
  validation rule is introduced.
- Embedded Swift 6.4.0 does not supply Codable as a usable capability. The
  unavailable adapter is absent; no empty substitute protocol, placeholder
  encoder, successful empty bytes, or pipeline/source-family exclusion is used.
- Every common stored field, mutation, COW owner, validation and Sendable
  conformance remains the same. Conditional compilation may isolate only the
  genuinely unavailable codec/presentation interface or the C math import.
- Common validation reads operation and identity-validity properties through
  explicit closures rather than runtime key paths, which Embedded Swift 6.4.0
  cannot compile. The same map/allSatisfy traversal, property getter, order,
  short-circuit behavior and result apply on every target; validation and
  resource semantics are unchanged.
- The existing `hypot`, `atan2`, `sin` and `cos` calls retain real target C math.
  Darwin and the matching WASI SDK provide their native declarations. No
  squared-norm replacement, sampled result, altered tolerance or numeric
  fallback is introduced. NaturalBezierContinuation's unused Foundation import
  is removed without changing its existing speed algorithm.
- HashTreeCollections stays at the registered 1.5.1 dependency. Its existing
  Embedded codec guards are reused; its value/storage implementation is not
  replaced with a different map or raw mutable state.

## Runtime Flows

```text
original public value -> original validation/algorithm -> value or typed failure
Native/normal value -> existing Codable adapter -> original wire or codec failure
Embedded caller -> common value operations (no Codable operation is exposed)
```

## State, Ownership, and Lifecycle

| State | Native / normal WASM / Embedded storage | Isolation | Read / mutation | Release |
|---|---|---|---|---|
| Numeric and record values | Same struct/enum fields | Caller-owned Sendable values | Existing public operations | Value lifetime |
| Arrays and PersistentMap | Same Array/TreeDictionary COW backing | Existing value ownership | Same constructors/mutations | Existing backing lifetime |
| Identity and cancellation | Existing common lower owners | Existing lower contracts | Unchanged witnesses | Existing lower lifecycle |

No actor, mutex, shared mutable storage, callback, stream or shutdown resource
is added. Codec objects are local Native/normal adapters. Target capability
differences never remove isolation or weaken Sendable.

## Failure, Concurrency, and Constraints

Common domain failures preserve their existing typed values and KernelError
classification. Native decoding/encoding errors keep their existing invalidInput
mapping. Embedded cannot produce those unavailable codec error types, so only
their type references are omitted. Cancellation and unknown source-error mapping
retain the FailureContract owner. No retry or success fallback is introduced.
The [Failure Contract](../FailureContract/DESIGN.md#target-diagnostic-capability)
owns the Native/normal reflective and Embedded structural diagnostic boundary.
The public smoke verifies known associated payloads, the unknown foreign-error
capability limitation and complete existing KernelError context on each target.
Existing numeric and allocation limits are unchanged; this sprint adds no
unbounded traversal or hidden codec work to common operations.

## Verification and Change Impact

| Environment | Success evidence | Failure evidence |
|---|---|---|
| Native 6.4.0 | Actual complete CADCore, literal wire formats and common math/record/COW smoke | Malformed custom wire, invalid matrix, coordinate/vector/record failures |
| normal WASM 6.4.0 matching SDK | Same public smoke plus actual Native codec branch on Node WASI | Same typed/common and codec refusals |
| Embedded WASM 6.4.0 matching SDK | Actual complete CADCore and dependency compile/link; common smoke on WASI | Same typed common failures, unavailable codec declared without fake output |

[NativeCodecCapabilityTests](../../../Tests/CADCoreTests/NativeCodecCapabilityTests.swift)
owns Native literal codec checks. The public smoke owns target behavior and
uses the complete registered CADCore module. Fixed-source/PIF/product/runtime
receipts must distinguish targets. Existing A2 Native/normal receipts remain
bound to their immutable source; they are not extended to changed Core bytes.
Root owns review, build lanes, integration, commits and parent indices. Full
Embedded A2 remains open until CADIR/Geometry/Topology/Kernel/SwiftCAD and the
same public transaction proof are separately composed and verified.
