import CADCore
import CADGeometry

extension OriginalSTEPPlacementSource {
    /// Produces a numeric view only after evaluating the complete original normalized law.
    public func derivedAffineTransform<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> AffineTransform3D {
        let law = try originalNormalizedAffineSource(usage: &usage, maximumSourceDepth: maximumSourceDepth)
        let word = try OriginalAffineOperationWord(operation: .normalizedForward(law),
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        let prepared = try word.prepared(usage: &usage)
        let x = try prepared.applying(to: Vector3D.unitX, usage: &usage)
        let y = try prepared.applying(to: Vector3D.unitY, usage: &usage)
        let z = try prepared.applying(to: Vector3D.unitZ, usage: &usage)
        let origin = try prepared.applying(to: Point3D.origin, usage: &usage)
        return try AffineTransform3D(basisX: x, basisY: y, basisZ: z,
            translation: Vector3D(x: origin.x, y: origin.y, z: origin.z))
    }
}
