import CADCore
import CADGeometry

public extension ImportedBRepFeature {
    /// Transform the retained source while preserving topology IDs, native trims and source units.
    func applying(_ transform: AffineTransform3D, tolerance: ModelingTolerance) throws -> ImportedBRepFeature {
        try DefaultImportedBRepSourceTransformer().applying(transform, to: self, tolerance: tolerance)
    }
}
