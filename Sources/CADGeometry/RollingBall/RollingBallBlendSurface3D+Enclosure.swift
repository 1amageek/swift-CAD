import CADCore
import Foundation

extension RollingBallBlendSurface3D {
    /// Bounds the blend formula on a regular parameter box. The caller owns
    /// subdivision and complete-domain feasibility; this is not a solid proof.
    func intervalJet(over parameters: SurfaceParameterBox) throws -> SurfaceIntervalVectorJet {
        try intervalJet(over: parameters,
            center: PreparedCurveDifferentialEncloser(curve: centerSpine, tolerance: tolerance),
            first: PreparedCurveDifferentialEncloser(curve: firstContact, tolerance: tolerance),
            second: PreparedCurveDifferentialEncloser(curve: secondContact, tolerance: tolerance))
    }

    func intervalJet(over parameters: SurfaceParameterBox,
                     center centerEncloser: PreparedCurveDifferentialEncloser,
                     first firstEncloser: PreparedCurveDifferentialEncloser,
                     second secondEncloser: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
        guard parameters.u.lower >= 0, parameters.u.upper <= 1, parameters.u.width > 0,
              parameters.v.lower >= 0, parameters.v.upper <= 1, parameters.v.width > 0 else {
            throw failure(.invalidInput, "Blend enclosures require a positive box inside the normalized domain.")
        }
        let center = try centerEncloser.thirdOrderIntervalJet(over: parameters.u, tolerance: tolerance)
        let firstRaw = try firstEncloser.thirdOrderIntervalJet(over: parameters.u,
                                                      tolerance: tolerance) + (-center)
        let secondRaw = try secondEncloser.thirdOrderIntervalJet(over: parameters.u,
                                                       tolerance: tolerance) + (-center)
        let midpoint = parameters.u.midpoint
        // Surface-lift bounds trim normalized pcurves, whose span must exceed
        // the modeling parameter tolerance. Keep that existing admission rule.
        let anchorRadius = max(tolerance.angle, tolerance.distance).nextUp
        let anchor = try ScalarInterval(lower: max(parameters.u.lower, (midpoint - anchorRadius).nextDown),
                                        upper: min(parameters.u.upper, (midpoint + anchorRadius).nextUp))
        let centerAnchor = try centerEncloser.thirdOrderIntervalJet(over: anchor, tolerance: tolerance)
        let displacement = OutwardScalarInterval(lower: parameters.u.lower, upper: parameters.u.upper)
            - OutwardScalarInterval(midpoint)
        func tightened(_ rail: PreparedCurveDifferentialEncloser, _ raw: SurfaceIntervalVectorJet) throws -> SurfaceIntervalVectorJet {
            let atCenter = try rail.thirdOrderIntervalJet(over: anchor,
                                                             tolerance: tolerance) + (-centerAnchor)
            func coordinate(_ value: SurfaceIntervalJet, _ origin: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
                func bound(_ original: OutwardScalarInterval, _ center: OutwardScalarInterval,
                           _ derivative: OutwardScalarInterval) throws -> OutwardScalarInterval {
                    let meanValue = center + derivative * displacement
                    let lower = max(original.lower, meanValue.lower)
                    let upper = min(original.upper, meanValue.upper)
                    guard lower <= upper else {
                        throw failure(.intersectionFailure, "Contact radial enclosures are inconsistent.")
                    }
                    return OutwardScalarInterval(lower: lower, upper: upper)
                }
                return try SurfaceIntervalJet(
                    value: bound(value.value, origin.value, value.derivativeU),
                    derivativeU: bound(value.derivativeU, origin.derivativeU, value.secondDerivativeUU),
                    derivativeV: value.derivativeV,
                    secondDerivativeUU: bound(value.secondDerivativeUU, origin.secondDerivativeUU, value.thirdDerivativeUUU),
                    secondDerivativeUV: value.secondDerivativeUV, secondDerivativeVV: value.secondDerivativeVV,
                    thirdDerivativeUUU: value.thirdDerivativeUUU, thirdDerivativeUUV: value.thirdDerivativeUUV,
                    thirdDerivativeUVV: value.thirdDerivativeUVV, thirdDerivativeVVV: value.thirdDerivativeVVV
                )
            }
            return try SurfaceIntervalVectorJet(x: coordinate(raw.x, atCenter.x),
                y: coordinate(raw.y, atCenter.y), z: coordinate(raw.z, atCenter.z))
        }
        let first = try tightened(firstEncloser, firstRaw)
        let second = try tightened(secondEncloser, secondRaw)
        guard let a = first.normalized(), let b = second.normalized() else {
            throw failure(.singularSystem, "The blend box cannot certify nonzero contact radials.")
        }
        let cross = a.cross(b)
        let threshold = max(sin(min(tolerance.angle, .pi * 0.5)), tolerance.relative)
        guard [cross.x.value, cross.y.value, cross.z.value].contains(where: {
            $0.lower > threshold || $0.upper < -threshold
        }) else {
            throw failure(.singularSystem, "The blend box cannot certify a regular minor arc.")
        }
        let one = SurfaceIntervalJet.constant(1)
        guard let weight = ((one + a.dot(b)) * .constant(0.5)).squareRoot(),
              let inverseWeight = weight.reciprocal() else {
            throw failure(.singularSystem, "The blend box cannot certify its circular weight.")
        }
        let t = SurfaceIntervalJet.parameterV(parameters.v)
        let s = one + (-t)
        let radial = a * (s * s) + (a + b) * (s * t * inverseWeight) + b * (t * t)
        let rawDenominator = s * s + .constant(2) * weight * s * t + t * t
        // Bernstein weights [1, w, 1] give a positive convex-hull bound.
        // Independent interval products otherwise allow both s and t to be zero.
        guard let denominatorValue = rawDenominator.value.intersection(with:
            OutwardScalarInterval(lower: min(1, weight.value.lower), upper: max(1, weight.value.upper))) else {
            throw failure(.intersectionFailure, "Blend denominator enclosures are inconsistent.")
        }
        let denominator = SurfaceIntervalJet(value: denominatorValue,
            derivativeU: rawDenominator.derivativeU, derivativeV: rawDenominator.derivativeV,
            secondDerivativeUU: rawDenominator.secondDerivativeUU,
            secondDerivativeUV: rawDenominator.secondDerivativeUV,
            secondDerivativeVV: rawDenominator.secondDerivativeVV,
            thirdDerivativeUUU: rawDenominator.thirdDerivativeUUU,
            thirdDerivativeUUV: rawDenominator.thirdDerivativeUUV,
            thirdDerivativeUVV: rawDenominator.thirdDerivativeUVV,
            thirdDerivativeVVV: rawDenominator.thirdDerivativeVVV)
        guard let inverseDenominator = denominator.reciprocal() else {
            throw failure(.singularSystem, "The blend box cannot certify a nonzero rational denominator.")
        }
        let result = center + radial * (.constant(radius) * inverseDenominator)
        for axis in [result.x, result.y, result.z] {
            for bound in [axis.value, axis.derivativeU, axis.derivativeV,
                          axis.secondDerivativeUU, axis.secondDerivativeUV, axis.secondDerivativeVV,
                          axis.thirdDerivativeUUU, axis.thirdDerivativeUUV,
                          axis.thirdDerivativeUVV, axis.thirdDerivativeVVV] {
                guard bound.lower.isFinite, bound.upper.isFinite else {
                    throw failure(.resourceLimitExceeded, "Blend derivative enclosures exceeded the finite numeric range.")
                }
            }
        }
        return result
    }
}
