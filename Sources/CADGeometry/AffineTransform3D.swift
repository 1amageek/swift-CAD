import CADCore

/// A finite affine map represented by three linear-image columns and a translation.
public struct AffineTransform3D: Hashable, Sendable {
    public let basisX: Vector3D
    public let basisY: Vector3D
    public let basisZ: Vector3D
    public let translation: Vector3D

    public init(
        basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D
    ) throws {
        self.basisX = basisX
        self.basisY = basisY
        self.basisZ = basisZ
        self.translation = translation
        try validate()
    }

    public func validate() throws {
        try basisX.validate()
        try basisY.validate()
        try basisZ.validate()
        try translation.validate()
    }

    /// Exact orientation of the original stored linear columns.
    package func originalDeterminantSign<A: ExactScalarAdmission & ~Copyable>(
        using execution: inout A) throws -> RobustSign {
        try execution.consumeWork(1)
        try validate()
        func original(_ value: Vector3D, using execution: inout A) throws
            -> ExactExpansionArithmetic.Vector3 {
            try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
            return .init(x: [value.x], y: [value.y], z: [value.z])
        }
        let x = try original(basisX, using: &execution)
        let y = try original(basisY, using: &execution)
        let z = try original(basisZ, using: &execution)
        let determinant = try ExactExpansionArithmetic.tripleProduct(x, y, z, using: &execution)
        let sign = try ExactExpansionArithmetic.sign(determinant, using: &execution)
        try execution.checkpoint()
        switch sign {
        case .positive, .negative: return sign
        case .zero:
            throw GeometryConversionError.invalidInput("Original affine linear source is exactly singular.")
        default:
            throw GeometryConversionError.resourceLimitExceeded("Original affine determinant sign is not resolved by finite exact expansion arithmetic.")
        }
    }

    package func originalDeterminantBounds<A: ExactScalarAdmission & ~Copyable>(
        using execution: inout A) throws -> ScalarInterval {
        try OriginalAffineDeterminantBounds.bounds(of: self, using: &execution)
    }

    public func applying(to point: Point3D) -> Point3D {
        Point3D(
            x: translation.x,
            y: translation.y,
            z: translation.z
        ) + applying(to: Vector3D(x: point.x, y: point.y, z: point.z))
    }

    public func applying(to vector: Vector3D) -> Vector3D {
        basisX * vector.x + basisY * vector.y + basisZ * vector.z
    }

    /// A conservative Euclidean operator-norm bound for the linear part.
    package var linearMagnitudeUpperBound: Double {
        let values = [basisX.x, basisX.y, basisX.z, basisY.x, basisY.y,
                      basisY.z, basisZ.x, basisZ.y, basisZ.z]
        let scale = values.reduce(0.0) { max($0, abs($1)) }
        guard scale > 0 else { return 0 }
        var squared = OutwardScalarInterval.exact(0)
        for value in values {
            guard let fraction = OutwardScalarInterval.exact(value).divided(by: .exact(scale)) else {
                return .infinity
            }
            squared = squared + fraction * fraction
        }
        return (squared.upper.squareRoot().nextUp * scale).nextUp
    }

    public func composed(after source: AffineTransform3D) throws -> AffineTransform3D {
        try AffineTransform3D(
            basisX: applying(to: source.basisX),
            basisY: applying(to: source.basisY),
            basisZ: applying(to: source.basisZ),
            translation: applying(to: Point3D(
                x: source.translation.x,
                y: source.translation.y,
                z: source.translation.z
            )) - .origin
        )
    }

    package func applying(to curve: BSplineCurve3D,
        tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try applying(to: curve, tolerance: tolerance, using: &execution)
    }

    package func applying<A: ExactScalarAdmission & ~Copyable>(to curve: BSplineCurve3D,
        tolerance: ModelingTolerance, using execution: inout A) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: curve.controlPoints.count,
            of: Point3D.self, using: &execution)
        var points: [Point3D] = []
        points.reserveCapacity(curve.controlPoints.count)
        for point in curve.controlPoints {
            try execution.consumeWork(1)
            points.append(applying(to: point))
        }
        let transformed = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
            controlPoints: points, weights: curve.weights, isPeriodic: curve.isPeriodic,
            periodicOrigin: curve.periodicOrigin)
        try transformed.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return transformed
    }

}

#if !hasFeature(Embedded)
extension AffineTransform3D: Codable {}
#endif
