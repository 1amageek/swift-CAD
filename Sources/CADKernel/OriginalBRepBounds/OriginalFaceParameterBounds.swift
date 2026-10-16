import CADCore
import CADGeometry
import CADTopology

enum OriginalFaceParameterBounds {
    static func resolve(for faceID: FaceID, surface: Surface3D, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        execution.context = execution.context.at(stage: .domain)
        try execution.consumeWork(1)
        guard let face = model.faces[faceID], model.geometry.surfaces[face.surfaceID] == surface else {
            throw TopologyError.missingReference("Finite parameter bounds require the face's exact original support.")
        }
        let extent = try FaceParameterExtentResolver(
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth
        ).bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
        func contained(_ interval: ScalarInterval, within domain: ParameterDomain, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
            try execution.consumeWork(1)
            let lower: Double, upper: Double
            if case let .closed(a, b) = domain {
                lower = max(interval.lower, a)
                upper = min(interval.upper, b)
            } else {
                lower = interval.lower
                upper = interval.upper
            }
            guard lower.isFinite, upper.isFinite, upper > lower else {
                throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                    message: "Original finite face bounds require complete positive UV extents.")
            }
            return try ScalarInterval(lower: lower, upper: upper)
        }
        return try SurfaceParameterBox(u: contained(extent.u, within: surface.uDomain, using: &execution),
            v: contained(extent.v, within: surface.vDomain, using: &execution))
    }
}
