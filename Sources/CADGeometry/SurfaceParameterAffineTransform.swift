import CADCore
import Foundation

/// An exact affine change of coordinates between two surface parameter charts.
public struct SurfaceParameterAffineTransform: Codable, Hashable, Sendable {
    public let uu: Double
    public let uv: Double
    public let vu: Double
    public let vv: Double
    public let uOffset: Double
    public let vOffset: Double

    public init(
        uu: Double,
        uv: Double,
        vu: Double,
        vv: Double,
        uOffset: Double,
        vOffset: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.uu = uu
        self.uv = uv
        self.vu = vu
        self.vv = vv
        self.uOffset = uOffset
        self.vOffset = vOffset
        try validate(tolerance: tolerance)
    }

    package init(
        validatedUU uu: Double,
        uv: Double,
        vu: Double,
        vv: Double,
        uOffset: Double,
        vOffset: Double
    ) {
        self.uu = uu
        self.uv = uv
        self.vu = vu
        self.vv = vv
        self.uOffset = uOffset
        self.vOffset = vOffset
    }

    public static let identity = SurfaceParameterAffineTransform(
        validatedUU: 1.0,
        uv: 0.0,
        vu: 0.0,
        vv: 1.0,
        uOffset: 0.0,
        vOffset: 0.0
    )

    public var determinant: Double {
        uu * vv - uv * vu
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        let values = [uu, uv, vu, vv, uOffset, vOffset]
        guard values.allSatisfy(\.isFinite),
              abs(determinant) > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: determinant,
                tolerance: tolerance,
                message: "A surface-parameter affine transform requires finite coefficients and a nonsingular linear part."
            )
        }
    }

    public func applying(to point: Point2D) -> Point2D {
        Point2D(
            x: uu * point.x + uv * point.y + uOffset,
            y: vu * point.x + vv * point.y + vOffset
        )
    }

    public func applyingVector(to vector: Point2D) -> Point2D {
        Point2D(
            x: uu * vector.x + uv * vector.y,
            y: vu * vector.x + vv * vector.y
        )
    }

    public func applying(to parameter: SurfaceParameter) -> SurfaceParameter {
        let point = applying(to: Point2D(x: parameter.u, y: parameter.v))
        return SurfaceParameter(u: point.x, v: point.y)
    }

    package func applying(
        u: ScalarInterval,
        v: ScalarInterval
    ) throws -> (u: ScalarInterval, v: ScalarInterval) {
        (
            try affineInterval(
                first: u,
                firstScale: uu,
                second: v,
                secondScale: uv,
                offset: uOffset
            ),
            try affineInterval(
                first: u,
                firstScale: vu,
                second: v,
                secondScale: vv,
                offset: vOffset
            )
        )
    }

    private func affineInterval(
        first: ScalarInterval,
        firstScale: Double,
        second: ScalarInterval,
        secondScale: Double,
        offset: Double
    ) throws -> ScalarInterval {
        let values = [
            firstScale * first.lower + secondScale * second.lower + offset,
            firstScale * first.lower + secondScale * second.upper + offset,
            firstScale * first.upper + secondScale * second.lower + offset,
            firstScale * first.upper + secondScale * second.upper + offset,
        ]
        guard let lower = values.min(), let upper = values.max(),
              lower.isFinite, upper.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Surface-parameter interval transformation exceeded finite arithmetic."
            )
        }
        return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
    }
}

package extension RigidTransform3D {
    func parameterAffineTransform(
        from source: Surface3D,
        to target: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAffineTransform? {
        let expectedTarget = try applying(to: source, tolerance: tolerance)
        guard expectedTarget == target else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rigid surface parameter map requires the exact transformed target surface."
            )
        }
        switch (source, target) {
        case let (.plane(sourcePlane), .plane(targetPlane)):
            return try planarParameterTransform(
                sourceBasis: circleBasis(
                    sourcePlane.normal,
                    tolerance: tolerance
                ),
                targetBasis: circleBasis(
                    targetPlane.normal,
                    tolerance: tolerance
                )
            )
        case let (.cylinder(sourceCylinder), .cylinder(targetCylinder)):
            return try angularParameterTransform(
                sourceBasis: circleBasis(
                    sourceCylinder.axis,
                    tolerance: tolerance
                ),
                targetBasis: circleBasis(
                    targetCylinder.axis,
                    tolerance: tolerance
                )
            )
        case let (.analytic(sourceAnalytic), .analytic(targetAnalytic)):
            switch (sourceAnalytic, targetAnalytic) {
            case let (.plane(_, sourceNormal), .plane(_, targetNormal)):
                return try planarParameterTransform(
                    sourceBasis: analyticBasis(
                        sourceNormal,
                        tolerance: tolerance
                    ),
                    targetBasis: analyticBasis(
                        targetNormal,
                        tolerance: tolerance
                    )
                )
            case let (.cylinder(_, sourceAxis, _), .cylinder(_, targetAxis, _)),
                 let (.cone(_, sourceAxis, _), .cone(_, targetAxis, _)),
                 let (.torus(_, sourceAxis, _, _), .torus(_, targetAxis, _, _)):
                return try angularParameterTransform(
                    sourceBasis: analyticBasis(
                        sourceAxis,
                        tolerance: tolerance
                    ),
                    targetBasis: analyticBasis(
                        targetAxis,
                        tolerance: tolerance
                    )
                )
            case (.sphere, .sphere):
                return isTranslation ? .identity : nil
            default:
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A rigid parameter map cannot change the analytic surface family."
                )
            }
        case (.bSpline, .bSpline), (.procedural, .procedural):
            return .identity
        default:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rigid parameter map cannot change the surface representation family."
            )
        }
    }

    private func planarParameterTransform(
        sourceBasis: (u: Vector3D, v: Vector3D),
        targetBasis: (u: Vector3D, v: Vector3D)
    ) throws -> SurfaceParameterAffineTransform {
        let transformedU = applying(to: sourceBasis.u)
        let transformedV = applying(to: sourceBasis.v)
        return SurfaceParameterAffineTransform(
            validatedUU: transformedU.dot(targetBasis.u),
            uv: transformedV.dot(targetBasis.u),
            vu: transformedU.dot(targetBasis.v),
            vv: transformedV.dot(targetBasis.v),
            uOffset: 0.0,
            vOffset: 0.0
        )
    }

    private func angularParameterTransform(
        sourceBasis: (u: Vector3D, v: Vector3D),
        targetBasis: (u: Vector3D, v: Vector3D)
    ) throws -> SurfaceParameterAffineTransform {
        let transformedU = applying(to: sourceBasis.u)
        let phase = atan2(
            transformedU.dot(targetBasis.v),
            transformedU.dot(targetBasis.u)
        )
        return SurfaceParameterAffineTransform(
            validatedUU: reversesOrientation ? -1.0 : 1.0,
            uv: 0.0,
            vu: 0.0,
            vv: 1.0,
            uOffset: phase,
            vOffset: 0.0
        )
    }

}
