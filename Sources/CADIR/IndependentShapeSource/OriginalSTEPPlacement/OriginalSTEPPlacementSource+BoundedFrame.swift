import CADCore
import CADGeometry

extension OriginalSTEPPlacementSource {
    /// Produces a numeric view only after evaluating the complete original normalized law.
    public func derivedAffineTransform(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D {
        let law = try originalNormalizedAffineSource(using: &execution, maximumSourceDepth: maximumSourceDepth)
        let word = try OriginalAffineOperationWord(operation: .normalizedForward(law),
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &execution)
        let prepared = try word.prepared(usage: &execution)
        let x = try prepared.applying(to: Vector3D.unitX, usage: &execution)
        let y = try prepared.applying(to: Vector3D.unitY, usage: &execution)
        let z = try prepared.applying(to: Vector3D.unitZ, usage: &execution)
        let origin = try prepared.applying(to: Point3D.origin, usage: &execution)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z,
            translation: Vector3D(x: origin.x, y: origin.y, z: origin.z))
    }
}
