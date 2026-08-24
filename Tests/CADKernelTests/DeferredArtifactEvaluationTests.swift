import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Deferred evaluation artifacts")
struct DeferredArtifactEvaluationTests {
    @Test
    func exactEvaluationDoesNotRequireDerivedMeshMaterialization() throws {
        let evaluated = try DocumentEvaluator(
            tessellator: RejectingTessellator(),
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(makeRectangleExtrudeDocument())

        #expect(evaluated.brep.bodies.isEmpty == false)
        #expect(evaluated.meshes.isEmpty)
    }

    @Test
    func exactEvaluationOverridesMaterializedEvaluatorPolicy() throws {
        let evaluated = try DocumentEvaluator(
            tessellator: RejectingTessellator(),
            tolerance: .standard,
            artifactPolicy: .materialized
        ).evaluateExact(makeRectangleExtrudeDocument())

        #expect(evaluated.brep.bodies.isEmpty == false)
        #expect(evaluated.meshes.isEmpty)
    }
}

private struct RejectingTessellator: Tessellating {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh] {
        throw KernelError(
            phase: .evaluation,
            code: .unsupportedCapability,
            tolerance: .standard,
            message: "Deferred evaluation must not invoke the tessellator."
        )
    }
}
