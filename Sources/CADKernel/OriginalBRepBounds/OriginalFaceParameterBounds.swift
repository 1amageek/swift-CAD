import CADCore
import CADGeometry
import CADTopology

enum OriginalFaceParameterBounds {
    static func resolve(for faceID: FaceID, surface: Surface3D, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) throws -> SurfaceParameterBox {
        try consumeWork?(0)
        guard let face = model.faces[faceID], model.geometry.surfaces[face.surfaceID] == surface else {
            throw TopologyError.missingReference("Finite parameter bounds require the face's exact original support.")
        }
        let extent = try FaceParameterExtentResolver(
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth
        ).bounds(for: faceID, in: model, tolerance: tolerance)
        func contained(_ interval: ScalarInterval, within domain: ParameterDomain) throws -> ScalarInterval {
            try consumeWork?(0)
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
        return try SurfaceParameterBox(u: contained(extent.u, within: surface.uDomain),
            v: contained(extent.v, within: surface.vDomain))
    }
}
