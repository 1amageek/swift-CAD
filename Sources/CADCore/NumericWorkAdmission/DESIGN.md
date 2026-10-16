# Numeric Work Admission

## Purpose and Scope

This Core component owns resource admission for the existing Natural, Arc,
Soft and Reflective numeric authoring algorithms. Parent:
[CADCore](../DESIGN.md). It owns the three-operation abstraction and the
explicit adapter for existing ordinary authoring calls, not a budget or solver.

## Responsibilities and Boundaries

`NumericWorkAdmission` requires checkpoint, work and typed storage admission.
CADGeometry's original execution supplies the actual cumulative owner, limits,
contributions and cancellation. Core cannot depend on CADGeometry. The three
Core producers retain their existing numerical algorithms and local iteration
ceilings; the abstraction has no parameter, coefficient, source or root depth.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Numeric producer and unit contracts | Owns the three existing algorithms | Ordinary and admitted calls share each algorithm body |
| [Original Query Execution](../../CADGeometry/OriginalQueryExecution/DESIGN.md) | used by | Existing cumulative admission owner | Supplies the concrete three-operation witness | A direct call never creates another execution or budget |
| [CADModeling](../../CADModeling/DESIGN.md) | used by | Direct expression evaluation | Passes its existing execution into coordinate evaluation | Expression-tree depth remains the interpreter's responsibility |

## Architecture

```text
ordinary Core API -> UnboundedAuthoringAdmission --+
                                                 +-> one generic numeric body
direct Core API -> caller NumericWorkAdmission ---+
                    (OriginalQueryExecution)
```

## Contracts and Invariants

- All three operations are protocol requirements and work on noncopyable
  callers. Failures propagate unchanged; no catch retries an ordinary path.
- Every visited input, numerical loop iteration and copied or emitted array
  element consumes work before its operation. Fixed numerical scratch and
  newly materialized arrays admit their typed storage before allocation.
  Immutable aliases do not invent a new allocation. Counts and byte products
  are checked before allocation, and results checkpoint before publication.
- Quadrature nodes, weights, summation order, Newton and fitting iteration
  bounds, convergence tolerances, units and existing numerical errors retain
  their source meanings. Resource counters do not stand in for root depth.
- Existing ordinary Core calls deliberately use internal, stateless
  `UnboundedAuthoringAdmission`: no resource ceiling and no cancellation
  observation, preserving their existing synchronous authoring policy. It
  validates count arithmetic. Only ordinary wrappers instantiate this adapter;
  every `using:` call forwards its incoming admission through all lower calls.

## State, Ownership, and Lifecycle

The protocol owns no state. The ordinary adapter has no stored state, budget,
callback, pointer or lifecycle. Producer values are immutable. Intermediate and
output arrays retain ordinary Swift ownership; direct allocation admission is
performed on the incoming execution before their creation or COW mutation.

| Target | Storage | Isolation | Read and mutation | Release |
|---|---|---|---|---|
| Native | Same immutable producer and local arrays | Exclusive incoming admission | Same three requirements | Swift array ownership |
| WASM | Same immutable producer and local arrays | Exclusive incoming admission | Same three requirements | Swift array ownership |
| Embedded | Same immutable producer and local arrays | Exclusive incoming admission | Same three requirements | Swift array ownership |

No target condition changes admission, sendability or shared-state isolation.
The existing C math import and Native Codable adapter remain separate target
capabilities.

## Failure, Concurrency, and Constraints

Admission may reject work, storage or cancellation before output. Core does not
reinterpret the caller's failure. The adapter rejects invalid or overflowing
counts explicitly. Existing numerical invalid-input and convergence failures
remain explicit. There is no shared mutable producer state or callback under a
Core lock.

## Verification and Change Impact

The [query verification owner](../../../Tests/OriginalQueryExecutionVerification/DESIGN.md)
links the actual numerical producer, protocol caller and target-specific fixtures.

The focused Core/portable tests exercise genuine Natural, Arc, Soft and
Reflective results, ordinary/direct equivalence, cumulative reuse, measured
work and storage N/N-1, entry and inner-iteration cancellation, and existing
unit/numeric failures. The actual OriginalQueryExecution witness and modeling
expression callers require their corresponding behavioral gates. A change to
this protocol or a charged numerical operation invalidates that caller's cost
boundary; unchanged unrelated scalar/root contracts are not re-proved here.
