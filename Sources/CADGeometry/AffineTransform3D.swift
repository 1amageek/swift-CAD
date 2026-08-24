import CADCore
import Foundation

/// A finite affine map represented by three linear-image columns and a translation.
public struct AffineTransform3D: Codable, Hashable, Sendable {
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
        hypot(hypot(basisX.length, basisY.length), basisZ.length).nextUp
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

    package func applying(
        to curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let transformed = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map(applying(to:)),
            weights: curve.weights
        )
        try transformed.validate(tolerance: tolerance)
        return transformed
    }
}
