import CADCore
import Foundation

struct ConeHostedQuadricIntersectionContext:
    HeightQuadraticIntersectionContext
{
    let hostConeSurface: Surface3D
    let sourceSurface: Surface3D
    let targetSurface: Surface3D
    let hostApex: Point3D
    let hostAxis: Vector3D
    let hostRadialU: Vector3D
    let hostRadialV: Vector3D
    let sourceEquation: TrigonometricHeightQuadratic
    let targetEquation: TrigonometricHeightQuadratic
    let characteristicLength: Double

    init(
        hostConeSurface: Surface3D,
        sourceSurface: Surface3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .cone(hostCone) =
                CanonicalAnalyticSurface(hostConeSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-hosted quadric elimination requires an exact host cone."
            )
        }
        var hostAxis = try hostCone.axis.normalized(
            tolerance: tolerance.distance
        )
        if Self.isNegative(hostAxis) {
            hostAxis = -hostAxis
        }
        let basis = try analyticOrthonormalBasis(
            hostAxis,
            tolerance: tolerance
        )
        let radialScale = tan(hostCone.halfAngle)
        let radialU = basis.u * radialScale
        let radialV = basis.v * radialScale

        self.hostConeSurface = hostConeSurface
        self.sourceSurface = sourceSurface
        self.targetSurface = targetSurface
        hostApex = hostCone.apex
        self.hostAxis = hostAxis
        hostRadialU = radialU
        hostRadialV = radialV
        sourceEquation = try Self.equation(
            surface: sourceSurface,
            hostApex: hostCone.apex,
            hostAxis: hostAxis,
            radialU: radialU,
            radialV: radialV,
            tolerance: tolerance
        )
        targetEquation = try Self.equation(
            surface: targetSurface,
            hostApex: hostCone.apex,
            hostAxis: hostAxis,
            radialU: radialU,
            radialV: radialV,
            tolerance: tolerance
        )
        characteristicLength = max(
            try Self.characteristicLength(
                surface: sourceSurface,
                from: hostCone.apex,
                tolerance: tolerance
            ),
            try Self.characteristicLength(
                surface: targetSurface,
                from: hostCone.apex,
                tolerance: tolerance
            ),
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
                message: "The source and target quadrics contain the same host-cone ruling at an elimination root."
            )
        }
        let rootSolver = StableHeightQuadraticRootSolver()
        var heights: [Double] = []
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
        let direction = hostAxis
            + hostRadialU * cos(angle)
            + hostRadialV * sin(angle)
        var points: [Point3D] = []
        for height in heights where height.isFinite {
            let point = hostApex + direction * height
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
        surface: Surface3D,
        hostApex: Point3D,
        hostAxis: Vector3D,
        radialU: Vector3D,
        radialV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> TrigonometricHeightQuadratic {
        let origin: Point3D
        let constantOffset: Double
        let product: (Vector3D, Vector3D) -> Double
        switch CanonicalAnalyticSurface(surface) {
        case let .sphere(sphere):
            origin = sphere.center
            constantOffset = -sphere.radius * sphere.radius
            product = { $0.dot($1) }
        case let .cylinder(cylinder):
            let axis = try cylinder.axis.normalized(
                tolerance: tolerance.distance
            )
            origin = cylinder.origin
            constantOffset = -cylinder.radius * cylinder.radius
            product = {
                $0.dot($1) - $0.dot(axis) * $1.dot(axis)
            }
        case let .cone(cone):
            let axis = try cone.axis.normalized(
                tolerance: tolerance.distance
            )
            let metricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)
            origin = cone.apex
            constantOffset = 0.0
            product = {
                $0.dot($1)
                    - metricScale * $0.dot(axis) * $1.dot(axis)
            }
        case .plane, .torus, .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-hosted elimination requires a sphere, cylinder, or cone quadric."
            )
        }

        let offset = hostApex - origin
        return TrigonometricHeightQuadratic(
            leading: quadratic(
                offset: hostAxis,
                radialU: radialU,
                radialV: radialV,
                product: product
            ),
            halfLinear: linear(
                constant: product(offset, hostAxis),
                cosine: product(offset, radialU),
                sine: product(offset, radialV)
            ),
            constant: SecondOrderTrigonometricPolynomial(
                constant: product(offset, offset) + constantOffset
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
            sine: sine
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

    private static func characteristicLength(
        surface: Surface3D,
        from point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch CanonicalAnalyticSurface(surface) {
        case let .sphere(sphere):
            return max((point - sphere.center).length, sphere.radius)
        case let .cylinder(cylinder):
            return max((point - cylinder.origin).length, cylinder.radius)
        case let .cone(cone):
            return (point - cone.apex).length
        case .plane, .torus, .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-hosted elimination requires a finite quadric characteristic length."
            )
        }
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0
                && direction.y == 0.0
                && direction.z < 0.0)
    }
}
