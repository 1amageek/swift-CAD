import CADCore
import CADIR
import CADKernel
import CADTopology

@main
struct CADWASMSmoke {
    static func main() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-6,
            angle: 1.0e-9,
            relative: 1.0e-9
        )
        let featureID = FeatureID()
        var document = CADDocument(units: .meters)
        let operation = FeatureOperation.primitive(PrimitiveFeature(
            definition: .box(BoxPrimitive(
                width: .constant(.length(0.04, unit: .meter)),
                depth: .constant(.length(0.02, unit: .meter)),
                height: .constant(.length(0.01, unit: .meter))
            ))
        ))
        document.designGraph.nodes[featureID] = try FeatureNodeFactory.make(
            operation: operation,
            id: featureID,
            in: document,
            tolerance: tolerance
        )
        document.designGraph.order.append(featureID)
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(
            tolerance: tolerance,
            artifactPolicy: .deferred
        ).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: tolerance)

        guard evaluated.brep.bodies.count == 1,
              evaluated.brep.shells.count == 1,
              evaluated.brep.faces.count == 6,
              evaluated.brep.edges.count == 12,
              evaluated.brep.vertices.count == 8 else {
            throw KernelError(
                phase: .validation,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "WASM smoke evaluation produced an unexpected box topology."
            )
        }
        let expectedVolume = 0.04 * 0.02 * 0.01
        let actualVolume = try evaluated.brep.volume(tolerance: tolerance)
        guard abs(actualVolume - expectedVolume) <= 1.0e-12 else {
            throw KernelError(
                phase: .validation,
                code: .topologyFailure,
                residual: abs(actualVolume - expectedVolume),
                tolerance: tolerance,
                message: "WASM smoke evaluation produced an incorrect exact volume."
            )
        }

        print("CADWASMSmoke passed")
    }
}
