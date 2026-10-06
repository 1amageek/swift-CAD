import CADCore
import CADGeometry

/// Translates the authoritative source through the same original affine image service.
struct ImportedBRepSourceTranslator {
    func translated(_ source: ImportedBRepFeature, by vector: Vector3D,
        tolerance: ModelingTolerance) throws -> ImportedBRepFeature {
        let transform = try AffineTransform3D(basisX: .unitX, basisY: .unitY,
            basisZ: .unitZ, translation: vector)
        return try DefaultImportedBRepSourceTransformer().applying(transform, to: source, tolerance: tolerance)
    }
}
