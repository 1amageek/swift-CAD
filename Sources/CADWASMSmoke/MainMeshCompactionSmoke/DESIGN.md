# MainMeshCompactionSmoke

## Purpose and Scope

This component belongs to [CADWASMSmoke](../DESIGN.md). It verifies the public mesh publication path for the composition root's original identity-placed 0.04 by 0.02 by 0.01 meter box. It has no children. Native and normal WebAssembly execute identical witness source; this bounded witness does not establish Embedded or other surface-family support.

## Responsibilities and Boundaries

The witness consumes the actual evaluated B-rep and calls public `MeshTessellator` with unchanged standard options and limits. It independently verifies literal box positions, outward normals, triangle winding, checked indices, complete vertex references and six generating face runs. A second invocation lowers only the vertex storage ceiling to one and requires the existing typed resource refusal. It owns no production index conversion, topology construction, resource policy or platform adapter.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADWASMSmoke](../DESIGN.md) | parent | evaluated original box | Supplies the original B-rep and tolerance. | Existing topology and volume assertions precede this witness. |
| [CADKernel](../../CADKernel/DESIGN.md) | depends on | public tessellation and target-width-safe compaction | Publishes actual mesh attributes and provenance or typed failure. | Caller options and cumulative limits remain unchanged. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | mesh and tessellation limits | Supplies published arrays and contiguous FaceRuns. | Source IDs must cover the actual model faces. |

## Architecture

```text
Evaluated original box -> public MeshTessellator -> literal mesh assertions
                      -> public MeshTessellator(vertex limit 1) -> typed refusal
                      -> unchanged-source assertion -> completion markers
```

## Contracts and Invariants

`run(model:tolerance:)` throws unless the one published body mesh has twelve triangles, six two-triangle FaceRuns covering the original face IDs, representable in-range indices and no unreferenced positions. Every triangle lies on a literal box plane, has its plane's outward normals and positive outward winding. All coordinates match the literal box corner coordinates within 1e-12. The refusal invocation must report `resourceExhausted(.vertexCount, requested: >1, limit: 1)`. Both invocations leave the input model unchanged.

## State, Ownership, and Lifecycle

All witness state is local to one synchronous invocation. The immutable model value remains caller-owned. No shared mutable state, pointer lifetime or conditional synchronization is introduced.

## Failure, Concurrency, and Constraints

Producer errors propagate. Assertion failures are typed validation errors; a missing or different storage refusal is a failure. There is no retry, generated proxy mesh or fallback. The external proof runner imposes bounded build and runtime deadlines with a fixed Swift toolchain and matching SDK.

## Verification and Change Impact

The permanent executable invokes this witness after its existing box evaluation assertions. The existing private full-SwiftCAD `MainNormalWASISmoke` product may compile identical helper bytes and call the same function while retaining its previous source-roundtrip and ZIP assertions. Actual Native and normal WebAssembly runs must reach both child markers and the caller's final marker. Preserve source, full production graph, PIF, raw artifact and terminal evidence. Changes to the production compaction or witness assertions require this bounded public verification; other families and Embedded remain separate.
