import CADCore
import CADGeometry

/// Atomic image of an authoritative imported source, retaining its original laws.
public protocol ImportedBRepSourceTransforming: Sendable {
    func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance) throws -> ImportedBRepFeature
}
