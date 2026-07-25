import CADCore
import Foundation

struct DefaultCertifiedIntersectionParameterResolver:
    CertifiedIntersectionParameterResolving
{
    func normalizedParameters(
        of point: Point3D,
        on curve: CertifiedIntersectionCurve3D,
        restrictedTo range: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let candidates = try parameterCandidates(
            of: point,
            on: curve,
            tolerance: tolerance
        )
        var verified: [Double] = []
        for parameter in candidates.sorted() {
            guard range?.contains(parameter) ?? true,
                  verified.contains(where: {
                      abs($0 - parameter) <= tolerance.relative
                  }) == false else {
                continue
            }
            let curvePoint = try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            guard (curvePoint - point).length <= tolerance.distance else {
                continue
            }
            verified.append(parameter)
        }
        return verified
    }

    private func parameterCandidates(
        of point: Point3D,
        on curve: CertifiedIntersectionCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        var candidates = [0.0, 1.0]
        switch curve {
        case let .sphereCone(curve):
            if let angle = try sourceAngle(
                of: point,
                on: curve.coneSurface,
                curve: .sphereCone(curve),
                tolerance: tolerance
            ) {
                candidates.append(contentsOf: try curve.normalizedFractionCandidates(
                    forConeAngle: angle,
                    tolerance: tolerance
                ))
            }
        case let .coneCone(curve):
            if let angle = try sourceAngle(
                of: point,
                on: curve.parameterizedSurface,
                curve: .coneCone(curve),
                tolerance: tolerance
            ) {
                candidates.append(contentsOf: angleCandidates(
                    angle,
                    component: curve.componentKind,
                    lower: curve.lowerAngle,
                    upper: curve.upperAngle
                ))
            }
        case let .coneCylinder(curve):
            let projection = try curve.cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            candidates.append(contentsOf: angleCandidates(
                projection.u,
                component: curve.componentKind,
                lower: curve.lowerAngle,
                upper: curve.upperAngle
            ))
        case let .coneTorus(curve):
            if let reduction = curve.apexReduction {
                if let angle = try sourceAngle(
                    of: point,
                    on: reduction.coneSurface,
                    curve: .coneTorus(curve),
                    tolerance: tolerance
                ) {
                    candidates.append(contentsOf: angleCandidates(
                        angle,
                        component: reduction.componentKind,
                        lower: reduction.lowerAngle,
                        upper: reduction.upperAngle
                    ))
                }
            } else {
                if let angle = try sourceAngle(
                    of: point,
                    on: curve.coneSurface,
                    curve: .coneTorus(curve),
                    tolerance: tolerance
                ) {
                    candidates.append(contentsOf: fullPeriodCandidates(angle))
                }
            }
        case .parallelTorusTorus:
            break
        }
        return candidates
    }

    private func sourceAngle(
        of point: Point3D,
        on surface: Surface3D,
        curve: CertifiedIntersectionCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        do {
            return try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            ).u
        } catch let error as KernelError
            where error.code == .singularSystem
                || error.code == .intersectionFailure {
            let lower = try curve.point(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let upper = try curve.point(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            guard (lower - point).length <= tolerance.distance
                    || (upper - point).length <= tolerance.distance else {
                throw error
            }
            return nil
        }
    }

    private func angleCandidates(
        _ angle: Double,
        component: CertifiedConeConeIntersectionCurve.ComponentKind,
        lower: Double,
        upper: Double
    ) -> [Double] {
        switch component {
        case .negativeFullBranch, .positiveFullBranch:
            fullPeriodCandidates(angle)
        case .boundedAngularInterval:
            closedCosineCandidates(angle, lower: lower, upper: upper)
        case .apexReducedAngularInterval:
            linearCandidates(angle, lower: lower, upper: upper)
        }
    }

    private func angleCandidates(
        _ angle: Double,
        component: CertifiedConeCylinderIntersectionCurve.ComponentKind,
        lower: Double,
        upper: Double
    ) -> [Double] {
        switch component {
        case .negativeFullBranch, .positiveFullBranch, .tangentFullBranch,
             .rulingParallelLinear:
            fullPeriodCandidates(angle)
        case .boundedAngularInterval:
            closedCosineCandidates(angle, lower: lower, upper: upper)
        case .apexLowerNodeInterval:
            sineArchCandidates(
                angle,
                apex: lower,
                direction: 1.0,
                span: upper - lower
            )
        case .apexUpperNodeInterval:
            sineArchCandidates(
                angle,
                apex: upper,
                direction: -1.0,
                span: upper - lower
            )
        }
    }

    private func angleCandidates(
        _ angle: Double,
        component: CertifiedConeTorusApexIntersectionCurve.ComponentKind,
        lower: Double,
        upper: Double
    ) -> [Double] {
        switch component {
        case .apexNodeInterval:
            linearCandidates(angle, lower: lower, upper: upper)
        case .generatorTangencyInterval:
            closedCosineCandidates(angle, lower: lower, upper: upper)
        }
    }

    private func fullPeriodCandidates(_ angle: Double) -> [Double] {
        let period = 2.0 * Double.pi
        let normalized = normalizedAngle(angle)
        let fraction = normalized / period
        return normalized == 0.0 ? [0.0, 1.0] : [fraction]
    }

    private func linearCandidates(
        _ angle: Double,
        lower: Double,
        upper: Double
    ) -> [Double] {
        guard upper > lower,
              let lifted = liftedAngle(angle, lower: lower, upper: upper) else {
            return []
        }
        return [(lifted - lower) / (upper - lower)]
    }

    private func closedCosineCandidates(
        _ angle: Double,
        lower: Double,
        upper: Double
    ) -> [Double] {
        guard upper > lower,
              let lifted = liftedAngle(angle, lower: lower, upper: upper) else {
            return []
        }
        let normalized = min(max((lifted - lower) / (upper - lower), 0.0), 1.0)
        let phase = acos(1.0 - 2.0 * normalized)
        let fraction = phase / (2.0 * Double.pi)
        return [fraction, 1.0 - fraction]
    }

    private func sineArchCandidates(
        _ angle: Double,
        apex: Double,
        direction: Double,
        span: Double
    ) -> [Double] {
        guard span > 0.0,
              let lifted = liftedAngle(
                  angle,
                  lower: min(apex, apex + direction * span),
                  upper: max(apex, apex + direction * span)
              ) else {
            return []
        }
        let normalized = min(
            max(direction * (lifted - apex) / span, 0.0),
            1.0
        )
        let fraction = asin(normalized) / Double.pi
        return [fraction, 1.0 - fraction]
    }

    private func liftedAngle(
        _ angle: Double,
        lower: Double,
        upper: Double
    ) -> Double? {
        let period = 2.0 * Double.pi
        let normalized = normalizedAngle(angle)
        let firstIndex = ceil((lower - normalized) / period)
        let lifted = normalized + firstIndex * period
        guard lifted >= lower - Double.ulpOfOne * 256.0,
              lifted <= upper + Double.ulpOfOne * 256.0 else {
            return nil
        }
        return min(max(lifted, lower), upper)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }
}
