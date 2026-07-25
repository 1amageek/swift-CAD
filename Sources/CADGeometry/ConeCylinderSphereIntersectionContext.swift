import CADCore
import Foundation

struct ConeCylinderSphereIntersectionContext: Sendable {
    struct TrigonometricQuadratic: Sendable {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }
    }

    let coneSurface: Surface3D
    let cylinderSurface: Surface3D
    let sphereSurface: Surface3D
    let cylinderOrigin: Point3D
    let cylinderAxis: Vector3D
    let cylinderRadialU: Vector3D
    let cylinderRadialV: Vector3D
    let generatorQuadratic: Double
    let coneHalfLinear: TrigonometricQuadratic
    let coneBaseQuadratic: TrigonometricQuadratic
    let sphereHalfLinear: TrigonometricQuadratic
    let sphereBaseQuadratic: TrigonometricQuadratic
    let characteristicLength: Double

    init(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        sphereSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .cone(cone) = CanonicalAnalyticSurface(coneSurface),
              case let .cylinder(cylinder) =
                CanonicalAnalyticSurface(cylinderSurface),
              case let .sphere(sphere) =
                CanonicalAnalyticSurface(sphereSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-cylinder sphere elimination requires exact analytic source and target surfaces."
            )
        }
        var coneAxis = try cone.axis.normalized(
            tolerance: tolerance.distance
        )
        if Self.isNegative(coneAxis) {
            coneAxis = -coneAxis
        }
        var cylinderAxis = try cylinder.axis.normalized(
            tolerance: tolerance.distance
        )
        if Self.isNegative(cylinderAxis) {
            cylinderAxis = -cylinderAxis
        }
        let originVector = cylinder.origin - .origin
        let cylinderOrigin = cylinder.origin
            + cylinderAxis * -originVector.dot(cylinderAxis)
        let basis = try analyticOrthonormalBasis(
            cylinderAxis,
            tolerance: tolerance
        )
        let radialU = basis.u * cylinder.radius
        let radialV = basis.v * cylinder.radius
        let coneMetricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)

        func coneMetric(
            _ first: Vector3D,
            _ second: Vector3D
        ) -> Double {
            first.dot(second)
                - coneMetricScale
                    * first.dot(coneAxis)
                    * second.dot(coneAxis)
        }

        let coneOffset = cylinderOrigin - cone.apex
        let sphereOffset = cylinderOrigin - sphere.center
        let coneHalfLinear = Self.linear(
            constant: coneMetric(coneOffset, cylinderAxis),
            cosine: coneMetric(radialU, cylinderAxis),
            sine: coneMetric(radialV, cylinderAxis)
        )
        let coneBaseQuadratic = Self.quadratic(
            offset: coneOffset,
            radialU: radialU,
            radialV: radialV,
            product: coneMetric,
            constantAdjustment: 0.0
        )
        let sphereHalfLinear = Self.linear(
            constant: sphereOffset.dot(cylinderAxis),
            cosine: radialU.dot(cylinderAxis),
            sine: radialV.dot(cylinderAxis)
        )
        let sphereBaseQuadratic = Self.quadratic(
            offset: sphereOffset,
            radialU: radialU,
            radialV: radialV,
            product: { $0.dot($1) },
            constantAdjustment: -sphere.radius * sphere.radius
        )

        self.coneSurface = coneSurface
        self.cylinderSurface = cylinderSurface
        self.sphereSurface = sphereSurface
        self.cylinderOrigin = cylinderOrigin
        self.cylinderAxis = cylinderAxis
        cylinderRadialU = radialU
        cylinderRadialV = radialV
        generatorQuadratic = coneMetric(cylinderAxis, cylinderAxis)
        self.coneHalfLinear = coneHalfLinear
        self.coneBaseQuadratic = coneBaseQuadratic
        self.sphereHalfLinear = sphereHalfLinear
        self.sphereBaseQuadratic = sphereBaseQuadratic
        characteristicLength = max(
            (cylinderOrigin - cone.apex).length,
            (cylinderOrigin - sphere.center).length,
            cylinder.radius,
            sphere.radius,
            1.0
        )
    }

    func spherePoints(
        atCylinderAngle angle: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let halfLinear = sphereHalfLinear.value(at: angle)
        let baseQuadratic = sphereBaseQuadratic.value(at: angle)
        let discriminant = halfLinear * halfLinear - baseQuadratic
        let algebraicTolerance = max(
            Double.ulpOfOne * characteristicLength
                * characteristicLength * 4_096.0,
            tolerance.distance * characteristicLength * 1.0e-6
        )
        guard discriminant >= -algebraicTolerance else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let heights = root <= sqrt(algebraicTolerance)
            ? [-halfLinear]
            : [-halfLinear - root, -halfLinear + root]
        let base = cylinderOrigin
            + cylinderRadialU * cos(angle)
            + cylinderRadialV * sin(angle)
        return heights.map { base + cylinderAxis * $0 }
    }

    private static func linear(
        constant: Double,
        cosine: Double,
        sine: Double
    ) -> TrigonometricQuadratic {
        TrigonometricQuadratic(
            constant: constant,
            cosine: cosine,
            sine: sine,
            cosineDouble: 0.0,
            sineDouble: 0.0
        )
    }

    private static func quadratic(
        offset: Vector3D,
        radialU: Vector3D,
        radialV: Vector3D,
        product: (Vector3D, Vector3D) -> Double,
        constantAdjustment: Double
    ) -> TrigonometricQuadratic {
        let radialUU = product(radialU, radialU)
        let radialVV = product(radialV, radialV)
        return TrigonometricQuadratic(
            constant: product(offset, offset)
                + (radialUU + radialVV) * 0.5
                + constantAdjustment,
            cosine: 2.0 * product(offset, radialU),
            sine: 2.0 * product(offset, radialV),
            cosineDouble: (radialUU - radialVV) * 0.5,
            sineDouble: product(radialU, radialV)
        )
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0
                && direction.y == 0.0
                && direction.z < 0.0)
    }
}
