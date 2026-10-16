import CADCore
import CADGeometry

/// Atomic image of an authoritative imported source, retaining its original laws.
public protocol ImportedBRepSourceTransforming: Sendable {
    func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance) throws -> ImportedBRepFeature
    func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ImportedBRepFeature
}

public extension ImportedBRepSourceTransforming {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected providers without an original
    // execution core cannot participate in composed source transformation. The
    // production direct caller must fail until the provider forwards its actual
    // source, determinant, image and final model validation through that execution.
    func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ImportedBRepFeature {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Imported source transformer does not provide caller-admitted original transformation.")
    }
}
