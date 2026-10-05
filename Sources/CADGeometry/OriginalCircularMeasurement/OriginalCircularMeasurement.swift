import CADCore

/// Original circular-law receipt; representative display values are not source authority.
public struct OriginalCircularMeasurement: Sendable {
    public let source: Curve3D
    public let boundaryParameter: Double
    public let placement: OriginalAffineOperationWord?
    public let effectiveOperationWord: OriginalAffineOperationWord
    public let centerEnclosure: CoordinateEnclosure3D
    public let radiusEnclosure: ScalarInterval
    public let normalEnclosure: CoordinateEnclosure3D
    public let boundaryPointEnclosure: CoordinateEnclosure3D
    public let tolerance: ModelingTolerance
    public func projectedCenter(on frame: OrthographicProjectionFrame) throws -> CoordinateEnclosure2D {
        try project(centerEnclosure, on: frame)
    }
    public func projectedBoundary(on frame: OrthographicProjectionFrame) throws -> CoordinateEnclosure2D {
        try project(boundaryPointEnclosure, on: frame)
    }
    public func diameterEnclosure() throws -> ScalarInterval {
        let value = OutwardScalarInterval(lower: radiusEnclosure.lower, upper: radiusEnclosure.upper) * .exact(2)
        guard value.isFinite else { throw GeometryConversionError.invalidInput("Original circular diameter exceeds finite range.") }
        return try .init(lower: value.lower, upper: value.upper)
    }
    private func project(_ source: CoordinateEnclosure3D, on frame: OrthographicProjectionFrame) throws -> CoordinateEnclosure2D {
        let x = OutwardScalarInterval(lower: source.x.lower, upper: source.x.upper) - .exact(frame.origin.x)
        let y = OutwardScalarInterval(lower: source.y.lower, upper: source.y.upper) - .exact(frame.origin.y)
        let z = OutwardScalarInterval(lower: source.z.lower, upper: source.z.upper) - .exact(frame.origin.z)
        func component(_ axis: Vector3D) throws -> ScalarInterval {
            let value = x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
            guard value.isFinite else { throw GeometryConversionError.invalidInput("Original circular projection exceeds finite range.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        return try .init(x: component(frame.horizontal), y: component(frame.vertical))
    }
}
