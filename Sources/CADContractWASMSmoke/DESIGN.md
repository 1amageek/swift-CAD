# Portable Contract Verification

## Purpose and Scope

Child of [the package](../../DESIGN.md), without children. Executes the public
immutable capability and failure contracts under the matching normal WASM SDK.

## Responsibilities and Boundaries

Owns contract-runtime evidence for C3 and C4. CADWASMSmoke and the final integration
gate retain whole-kernel geometry and platform verification. This executable
cannot establish geometric coverage or Embedded compatibility.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Verification ownership | Separate contract runtime from geometry integration | No reduction in final coverage |
| [Capabilities](../CADCapabilities/DESIGN.md) | depends on | Current operation domains | Exercises source conditions and filters | Does not predict shape success |
| [Capability Contract](../CADCore/CapabilityContract/DESIGN.md) | depends on | Domain lookup and validation | Verifies transport and refusal | Empty filters do not imply universal support |
| [Failure Contract](../CADCore/FailureContract/DESIGN.md) | depends on | Cause-preserving errors | Checks resource and unsupported categories | No inference from diagnostic text |

## Architecture

```text
WASI host -> public catalog -> domain lookup/filter/transport/refusal
          -> public failure wrapping -> typed cause verification
```

## Contracts and Invariants

The executable throws on any lost domain record, transport mismatch, unknown
operation accepted, or lost failure cause. The success marker is emitted only
after these checks run. It uses immutable values with no platform-specific state.

## Verification and Change Impact

Build using Swift 6.4.0 and its matching normal WASM SDK, then run the produced
artifact through Scripts/run_wasi_smoke.mjs. Domain and failure contract changes
invalidate this local runtime evidence; full integration remains in PARI.
