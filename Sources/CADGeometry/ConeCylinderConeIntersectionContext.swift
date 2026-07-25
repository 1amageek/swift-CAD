import CADCore
import Foundation

struct ConeCylinderConeIntersectionContext:
    HeightQuadraticIntersectionContext
{
    let sourceConeSurface: Surface3D
    let cylinderSurface: Surface3D
    let targetConeSurface: Surface3D
    let cylinderOrigin: Point3D
    let cylinderAxis: Vector3D
    let cylinderRadialU: Vector3D
    let cylinderRadialV: Vector3D
    let sourceEquation: TrigonometricHeightQuadratic
    let targetEquation: TrigonometricHeightQuadratic
    let characteristicLength: Double

    var sourceSurface: Surface3D {
        sourceConeSurface
    }

    var targetSurface: Surface3D {
        targetConeSurface
    }

    init(
        sourceConeSurface: Surface3D,
        cylinderSurface: Surface3D,
        targetConeSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .cone(sourceCone) =
                CanonicalAnalyticSurface(sourceConeSurface),
              case let .cylinder(cylinder) =
                CanonicalAnalyticSurface(cylinderSurface),
              case let .cone(targetCone) =
                CanonicalAnalyticSurface(targetConeSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-cylinder cone elimination requires two exact cones and one exact cylinder."
            )
        }
        var cylinderAxis = try cylinder.axis.normalized(
            tolerance: tolerance.distance
        )
        if Self.isNegative(cylinderAxis) {
            cylinderAxis = -cylinderAxis
        }
        let originVector = cylinder.origin - .origin
        let canonicalCylinderOrigin = cylinder.origin
            + cylinderAxis * -originVector.dot(cylinderAxis)
        let basis = try analyticOrthonormalBasis(
            cylinderAxis,
            tolerance: tolerance
        )
        let radialU = basis.u * cylinder.radius
        let radialV = basis.v * cylinder.radius

        self.sourceConeSurface = sourceConeSurface
        self.cylinderSurface = cylinderSurface
        self.targetConeSurface = targetConeSurface
        cylinderOrigin = canonicalCylinderOrigin
        self.cylinderAxis = cylinderAxis
        cylinderRadialU = radialU
        cylinderRadialV = radialV
        sourceEquation = try Self.equation(
            cone: sourceCone,
            cylinderOrigin: canonicalCylinderOrigin,
            cylinderAxis: cylinderAxis,
            radialU: radialU,
            radialV: radialV,
            tolerance: tolerance
        )
        targetEquation = try Self.equation(
            cone: targetCone,
            cylinderOrigin: canonicalCylinderOrigin,
            cylinderAxis: cylinderAxis,
            radialU: radialU,
            radialV: radialV,
            tolerance: tolerance
        )
        characteristicLength = max(
            (canonicalCylinderOrigin - sourceCone.apex).length,
            (canonicalCylinderOrigin - targetCone.apex).length,
            cylinder.radius,
            1.0
        )
    }

    func candidatePoints(
        atAngle angle: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let sourceCoefficients = sourceEquation.coefficients(at: angle)
        let targetCoefficients = targetEquation.coefficients(at: angle)
        let sourceIsZero = isZero(sourceCoefficients)
        let targetIsZero = isZero(targetCoefficients)
        guard sourceIsZero == false || targetIsZero == false else {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "The two cones contain the same cylinder ruling at an elimination root."
            )
        }
        var heights: [Double] = []
        let rootSolver = StableHeightQuadraticRootSolver()
        if sourceIsZero == false {
            heights.append(contentsOf: rootSolver.roots(
                coefficients: sourceCoefficients,
                characteristicLength: characteristicLength,
                tolerance: tolerance
            ))
        }
        if targetIsZero == false {
            heights.append(contentsOf: rootSolver.roots(
                coefficients: targetCoefficients,
                characteristicLength: characteristicLength,
                tolerance: tolerance
            ))
        }
        let base = cylinderOrigin
            + cylinderRadialU * cos(angle)
            + cylinderRadialV * sin(angle)
        var points: [Point3D] = []
        for height in heights where height.isFinite {
            let point = base + cylinderAxis * height
            if points.contains(where: {
                ($0 - point).length <= tolerance.distance
            }) == false {
                points.append(point)
            }
        }
        return points
    }

    private func isZero(
        _ coefficients: (
            leading: Double,
            linear: Double,
            constant: Double
        )
    ) -> Bool {
        coefficients.leading == 0.0
            && coefficients.linear == 0.0
            && coefficients.constant == 0.0
    }

    private static func equation(
        cone: CanonicalAnalyticSurface.Cone,
        cylinderOrigin: Point3D,
        cylinderAxis: Vector3D,
        radialU: Vector3D,
        radialV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> TrigonometricHeightQuadratic {
        var coneAxis = try cone.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(coneAxis) {
            coneAxis = -coneAxis
        }
        let metricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)

        func metric(
            _ first: Vector3D,
            _ second: Vector3D
        ) -> Double {
            first.dot(second)
                - metricScale
                    * first.dot(coneAxis)
                    * second.dot(coneAxis)
        }

        let offset = cylinderOrigin - cone.apex
        return TrigonometricHeightQuadratic(
            leading: SecondOrderTrigonometricPolynomial(
                constant: metric(cylinderAxis, cylinderAxis)
            ),
            halfLinear: linear(
                constant: metric(offset, cylinderAxis),
                cosine: metric(radialU, cylinderAxis),
                sine: metric(radialV, cylinderAxis)
            ),
            constant: quadratic(
                offset: offset,
                radialU: radialU,
                radialV: radialV,
                product: metric
            )
        )
    }

    private static func linear(
        constant: Double,
        cosine: Double,
        sine: Double
    ) -> SecondOrderTrigonometricPolynomial {
        SecondOrderTrigonometricPolynomial(
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
        product: (Vector3D, Vector3D) -> Double
    ) -> SecondOrderTrigonometricPolynomial {
        let radialUU = product(radialU, radialU)
        let radialVV = product(radialV, radialV)
        return SecondOrderTrigonometricPolynomial(
            constant: product(offset, offset)
                + (radialUU + radialVV) * 0.5,
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
