import CADCore
import CADGeometry

/// Original silhouette traversal whose trim endpoints retain exact source expressions.
public struct BRepDrawingExactSilhouetteSpan: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let componentOrdinal: Int
    public let curveOrdinal: Int
    public let curve: OriginalSurfaceSilhouetteTrimmedCurve
    public let isCoincidentWithTrim: Bool
    /// Whole original zero-derivative proof; nil does not assert curve regularity.
    public let constantSpatialEnclosure: CoordinateEnclosure3D?
    public var isSpatiallyCollapsed: Bool { constantSpatialEnclosure != nil }
    public let frame: OrthographicProjectionFrame

    public func projectedEnclosure(overNormalized range: ScalarInterval,
        maximumParameterWidth: ExactRationalCoefficient, usage: inout SurfaceSilhouetteUsage) throws -> CoordinateEnclosure2D {
        let source = try curve.enclosure(overNormalized: range, maximumParameterWidth: maximumParameterWidth, usage: &usage)
        guard let position = source.spatialDerivatives.first else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: nil,
                message: "Exact trimmed silhouette source has no spatial position enclosure.")
        }
        func interval(_ value: ScalarInterval) -> OutwardScalarInterval { .init(lower: value.lower, upper: value.upper) }
        let x = interval(position.x) - .exact(frame.origin.x)
        let y = interval(position.y) - .exact(frame.origin.y)
        let z = interval(position.z) - .exact(frame.origin.z)
        func project(_ axis: Vector3D) throws -> ScalarInterval {
            let value = x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
            guard value.isFinite else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: nil,
                    message: "Exact trimmed silhouette projection is nonfinite.")
            }
            return try .init(lower: value.lower, upper: value.upper)
        }
        return try .init(x: project(frame.horizontal), y: project(frame.vertical))
    }
}
