import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Position and all parameter derivatives through total order three.
///
/// This value intentionally does not require a regular parameter frame. It is
/// the differential truth consumed by higher-order procedural surfaces; callers
/// that need normals or curvature must apply their own regularity contract.
public struct SurfaceParameterThirdOrderDerivatives: Hashable, Sendable {
    public let position: Point3D
    public let tangentU: Vector3D
    public let tangentV: Vector3D
    public let secondDerivativeUU: Vector3D
    public let secondDerivativeUV: Vector3D
    public let secondDerivativeVV: Vector3D
    public let thirdDerivativeUUU: Vector3D
    public let thirdDerivativeUUV: Vector3D
    public let thirdDerivativeUVV: Vector3D
    public let thirdDerivativeVVV: Vector3D

    var secondOrder: SurfaceParameterDerivatives {
        SurfaceParameterDerivatives(position: position, tangentU: tangentU, tangentV: tangentV,
            secondDerivativeUU: secondDerivativeUU, secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV)
    }

    public init(
        position: Point3D,
        tangentU: Vector3D,
        tangentV: Vector3D,
        secondDerivativeUU: Vector3D,
        secondDerivativeUV: Vector3D,
        secondDerivativeVV: Vector3D,
        thirdDerivativeUUU: Vector3D,
        thirdDerivativeUUV: Vector3D,
        thirdDerivativeUVV: Vector3D,
        thirdDerivativeVVV: Vector3D
    ) {
        self.position = position
        self.tangentU = tangentU
        self.tangentV = tangentV
        self.secondDerivativeUU = secondDerivativeUU
        self.secondDerivativeUV = secondDerivativeUV
        self.secondDerivativeVV = secondDerivativeVV
        self.thirdDerivativeUUU = thirdDerivativeUUU
        self.thirdDerivativeUUV = thirdDerivativeUUV
        self.thirdDerivativeUVV = thirdDerivativeUVV
        self.thirdDerivativeVVV = thirdDerivativeVVV
    }
}

public extension Surface3D {
    func parameterDerivativesThroughThirdOrder(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        switch self {
        case .plane:
            let lowerOrder = try parameterDerivatives(
                u: u,
                v: v,
                tolerance: tolerance
            )
            return lowerOrder.withZeroThirdDerivatives()
        case .cylinder:
            let lowerOrder = try parameterDerivatives(
                u: u,
                v: v,
                tolerance: tolerance
            )
            return SurfaceParameterThirdOrderDerivatives(
                lowerOrder: lowerOrder,
                thirdDerivativeUUU: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUUV: .zero,
                thirdDerivativeUVV: .zero,
                thirdDerivativeVVV: .zero
            )
        case let .analytic(surface):
            return try surface.parameterDerivativesThroughThirdOrder(
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .bSpline(surface):
            return try surface.parameterDerivativesThroughThirdOrder(
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .procedural(surface):
            return try surface.parameterDerivativesThroughThirdOrder(
                u: u,
                v: v,
                tolerance: tolerance
            )
        }
    }
}

public extension AnalyticSurface3D {
    func parameterDerivativesThroughThirdOrder(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        let lowerOrder = try parameterDerivatives(
            u: u,
            v: v,
            tolerance: tolerance
        )
        switch self {
        case .plane:
            return lowerOrder.withZeroThirdDerivatives()
        case .cylinder:
            return SurfaceParameterThirdOrderDerivatives(
                lowerOrder: lowerOrder,
                thirdDerivativeUUU: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUUV: .zero,
                thirdDerivativeUVV: .zero,
                thirdDerivativeVVV: .zero
            )
        case let .cone(_, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(
                axis,
                tolerance: tolerance
            )
            let radial = basis.u * CanonicalSphereAngularPhase.candidate(at: u, cosine: true) + basis.v * CanonicalSphereAngularPhase.candidate(at: u, cosine: false)
            return SurfaceParameterThirdOrderDerivatives(
                lowerOrder: lowerOrder,
                thirdDerivativeUUU: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUUV: -radial * (sin(halfAngle) * CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUVV: .zero,
                thirdDerivativeVVV: .zero
            )
        case let .sphere(_, radius):
            let basis = try analyticOrthonormalBasis(
                .unitZ,
                tolerance: tolerance
            )
            let radialU = basis.u * CanonicalSphereAngularPhase.candidate(at: u, cosine: true) + basis.v * CanonicalSphereAngularPhase.candidate(at: u, cosine: false)
            return SurfaceParameterThirdOrderDerivatives(
                lowerOrder: lowerOrder,
                thirdDerivativeUUU: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUUV: radialU * (radius * CanonicalSphereAngularPhase.candidate(at: v, cosine: false)) * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUVV: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeVVV: -lowerOrder.tangentV * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint)
            )
        case let .torus(_, axis, _, minorRadius):
            let basis = try analyticOrthonormalBasis(
                axis,
                tolerance: tolerance
            )
            let radial = basis.u * CanonicalSphereAngularPhase.candidate(at: u, cosine: true) + basis.v * CanonicalSphereAngularPhase.candidate(at: u, cosine: false)
            let tangent = -basis.u * CanonicalSphereAngularPhase.candidate(at: u, cosine: false) + basis.v * CanonicalSphereAngularPhase.candidate(at: u, cosine: true)
            return SurfaceParameterThirdOrderDerivatives(
                lowerOrder: lowerOrder,
                thirdDerivativeUUU: -lowerOrder.tangentU * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUUV: radial * (minorRadius * CanonicalSphereAngularPhase.candidate(at: v, cosine: false)) * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeUVV: tangent * (-minorRadius * CanonicalSphereAngularPhase.candidate(at: v, cosine: true)) * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint),
                thirdDerivativeVVV: -lowerOrder.tangentV * (CanonicalSphereAngularPhase.scaleBounds.midpoint * CanonicalSphereAngularPhase.scaleBounds.midpoint)
            )
        }
    }

}

public extension BSplineSurface3D {
    func parameterDerivativesThroughThirdOrder(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }

        let clampedU = try basisParameter(u, direction: .u, tolerance: tolerance)
        let clampedV = try basisParameter(v, direction: .v, tolerance: tolerance)
        let uBasis = (0...3).map { order in
            BSplineBasis.derivativeValues(
                parameter: clampedU,
                degree: uDegree,
                derivativeOrder: order,
                knots: uKnots,
                count: uControlPointCount
            )
        }
        let vBasis = (0...3).map { order in
            BSplineBasis.derivativeValues(
                parameter: clampedV,
                degree: vDegree,
                derivativeOrder: order,
                knots: vKnots,
                count: vControlPointCount
            )
        }

        var homogeneous: [Int: HomogeneousSurfaceDerivative] = [:]
        for totalOrder in 0...3 {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                homogeneous[derivativeKey(uOrder, vOrder)] = homogeneousDerivative(
                    uBasis: uBasis[uOrder],
                    vBasis: vBasis[vOrder]
                )
            }
        }
        guard let base = homogeneous[derivativeKey(0, 0)],
              base.weight.isFinite,
              base.weight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: homogeneous[derivativeKey(0, 0)]?.weight,
                tolerance: tolerance,
                message: "Rational B-spline third-order differentiation requires a positive finite weight."
            )
        }

        // A uniform original weight makes the denominator constant. Its higher
        // derivatives vanish exactly; numerical quotient residues are candidates only.
        let firstWeight = weights.first?.first
        let isPolynomial = weights.allSatisfy { row in row.allSatisfy { $0 == firstWeight } }
        var euclidean: [Int: Vector3D] = [:]
        for totalOrder in 0...3 {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                guard let source = homogeneous[derivativeKey(uOrder, vOrder)] else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "A required homogeneous surface derivative is missing."
                    )
                }
                var numerator = source.vector
                for weightUOrder in 0...uOrder {
                    for weightVOrder in 0...vOrder {
                        guard weightUOrder + weightVOrder > 0, !isPolynomial else {
                            continue
                        }
                        let remainingUOrder = uOrder - weightUOrder
                        let remainingVOrder = vOrder - weightVOrder
                        guard let weightDerivative = homogeneous[
                            derivativeKey(weightUOrder, weightVOrder)
                        ]?.weight,
                        let lowerDerivative = euclidean[
                            derivativeKey(remainingUOrder, remainingVOrder)
                        ] else {
                            throw KernelError(
                                phase: .geometry,
                                code: .invalidInput,
                                tolerance: tolerance,
                                message: "Rational surface derivative recurrence is incomplete."
                            )
                        }
                        let coefficient = Double(
                            binomial(uOrder, weightUOrder)
                                * binomial(vOrder, weightVOrder)
                        )
                        numerator = numerator
                            - lowerDerivative * (coefficient * weightDerivative)
                    }
                }
                let derivative = numerator / base.weight
                guard derivative.isFinite else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Rational B-spline third-order differentiation exceeded the finite numeric range."
                    )
                }
                euclidean[derivativeKey(uOrder, vOrder)] = derivative
            }
        }

        func derivative(_ uOrder: Int, _ vOrder: Int) throws -> Vector3D {
            guard let value = euclidean[derivativeKey(uOrder, vOrder)] else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A required rational surface derivative was not produced."
                )
            }
            return value
        }

        let position = try derivative(0, 0)
        return SurfaceParameterThirdOrderDerivatives(
            position: Point3D(x: position.x, y: position.y, z: position.z),
            tangentU: try derivative(1, 0),
            tangentV: try derivative(0, 1),
            secondDerivativeUU: try derivative(2, 0),
            secondDerivativeUV: try derivative(1, 1),
            secondDerivativeVV: try derivative(0, 2),
            thirdDerivativeUUU: try derivative(3, 0),
            thirdDerivativeUUV: try derivative(2, 1),
            thirdDerivativeUVV: try derivative(1, 2),
            thirdDerivativeVVV: try derivative(0, 3)
        )
    }

    private func homogeneousDerivative(
        uBasis: [Double],
        vBasis: [Double]
    ) -> HomogeneousSurfaceDerivative {
        var vector = Vector3D.zero
        var weight = 0.0
        for vIndex in 0..<vControlPointCount {
            for uIndex in 0..<uControlPointCount {
                let basisValue = uBasis[uIndex] * vBasis[vIndex]
                guard basisValue != 0.0 else {
                    continue
                }
                let controlWeight = weights[vIndex][uIndex]
                let coefficient = basisValue * controlWeight
                let point = controlPoints[vIndex][uIndex]
                vector = vector + Vector3D(
                    x: point.x,
                    y: point.y,
                    z: point.z
                ) * coefficient
                weight += coefficient
            }
        }
        return HomogeneousSurfaceDerivative(vector: vector, weight: weight)
    }
}

private struct HomogeneousSurfaceDerivative {
    let vector: Vector3D
    let weight: Double
}

private extension SurfaceParameterDerivatives {
    func withZeroThirdDerivatives() -> SurfaceParameterThirdOrderDerivatives {
        SurfaceParameterThirdOrderDerivatives(
            lowerOrder: self,
            thirdDerivativeUUU: .zero,
            thirdDerivativeUUV: .zero,
            thirdDerivativeUVV: .zero,
            thirdDerivativeVVV: .zero
        )
    }
}

private extension SurfaceParameterThirdOrderDerivatives {
    init(
        lowerOrder: SurfaceParameterDerivatives,
        thirdDerivativeUUU: Vector3D,
        thirdDerivativeUUV: Vector3D,
        thirdDerivativeUVV: Vector3D,
        thirdDerivativeVVV: Vector3D
    ) {
        self.init(
            position: lowerOrder.position,
            tangentU: lowerOrder.tangentU,
            tangentV: lowerOrder.tangentV,
            secondDerivativeUU: lowerOrder.secondDerivativeUU,
            secondDerivativeUV: lowerOrder.secondDerivativeUV,
            secondDerivativeVV: lowerOrder.secondDerivativeVV,
            thirdDerivativeUUU: thirdDerivativeUUU,
            thirdDerivativeUUV: thirdDerivativeUUV,
            thirdDerivativeUVV: thirdDerivativeUVV,
            thirdDerivativeVVV: thirdDerivativeVVV
        )
    }
}

private func derivativeKey(_ uOrder: Int, _ vOrder: Int) -> Int {
    uOrder * 4 + vOrder
}

private func binomial(_ n: Int, _ k: Int) -> Int {
    guard k >= 0, k <= n else {
        return 0
    }
    if k == 0 || k == n {
        return 1
    }
    if n == 2, k == 1 {
        return 2
    }
    if n == 3, k == 1 || k == 2 {
        return 3
    }
    return 1
}

#if !hasFeature(Embedded)
extension SurfaceParameterThirdOrderDerivatives: Codable {}
#endif
