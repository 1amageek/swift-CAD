# Native JSON Encoding

## Purpose and Scope
Owns bounded Native Codable JSON output and original drawing source descriptors. Parent: [CADExchange](../DESIGN.md). No children.

## Responsibilities and Boundaries
The serializer owns actual JSON token, container, work, source-depth and cancellation admission. Semantic source validation and Native codecs remain owned by their value components. The byte ceiling bounds serialized payload, not Foundation allocator capacity.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADExchange](../DESIGN.md) | parent | caller resource limits | Native package composition | Original deadline is retained |
| [Exchange Resource Accounting](../ExchangeResourceAccounting/DESIGN.md) | depends on | same shared counters | Token admission and cancellation | No child counter reset |
| [B-rep Drawing Exchange](../BRepDrawingExchange/DESIGN.md) | used by | exact original descriptor | Algebraic endpoint provenance | Numeric samples do not replace source |

## Architecture
```text
Original Codable -> bounded token tree -> canonical ordering -> bounded compact JSON
                 -> same work/byte/depth owner -------------------------^
```

## Contracts and Invariants
Native Codable fields, strict discriminators, decimal numeric tokens, explicit nulls and reference-date seconds retain their existing semantic wire grammar. Objects use sorted keys. Document parameter, feature and sketch-entity dynamic dictionaries become canonically ordered key/value pair arrays, matching the Native package grammar. Whitespace is not source identity. Every string token's escaped byte size is admitted before materialization; scalar, container and separator bytes are admitted before retention. Every node/container visit and ordering comparison consumes original work, checks cancellation and respects maximumNesting. One owner covers manifest and document payloads. Data retains JSONEncoder's base64 string grammar. Serializer-private nodes are invocation-owned synchronized values; external Codable calls execute outside their locks.

## State, Ownership, and Lifecycle
A synchronous encode invocation owns its token tree; node mutation uses Mutex and retained children have no back-reference. The immutable context holds the shared counter owner. Deferred failures from nonthrowing Encoder container creation are checked before any successful output. No encoder or node crosses the public result boundary.

## Failure, Concurrency, and Constraints
Unknown conflicting container use, duplicate object keys, nonfinite numeric values, invalid dynamic keys and exhausted byte/work/node/depth limits fail explicitly. Buffered output is returned only after complete serialization. This component does not advertise allocator-wide accounting or make Foundation input-shape scratch a source proof.

## Verification and Change Impact
After source implementation, compare original Native roundtrips, canonical dynamic dictionary order, Data/date tokens, exact source descriptors, boundary byte limits, malformed encoders, cancellation, and atomic publication. Recheck Native package and drawing writer callers. Source authoring alone is not verification.

The encoder consumes a non-generic internal accounting contract. Native packages
use their existing shared resource owner. Original silhouette source descriptors
use an adapter to the live SurfaceSilhouetteUsage, forwarding work and retained
bytes to its admission and drawing owner exactly once. JSON structural depth is
checked separately from semantic surface source, subdivision and algebra depth.
The adapter never creates an allowance or transfers counters.
