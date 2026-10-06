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
        return try intervalJet(over: parameters, center: center, firstRadial: first, secondRadial: second)
    }

    /// The caller supplies native, owning-span jets at closed intervals. This
    /// overload does not rebuild or sample a contact curve to authorize bounds.
    func intervalJet(over parameters: SurfaceParameterBox,
                     centerJet: SurfaceIntervalVectorJet,
                     firstContactJet: SurfaceIntervalVectorJet,
                     secondContactJet: SurfaceIntervalVectorJet,
                     consumeWork: () throws -> Void = {},
                     consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
        guard parameters.u.lower >= 0, parameters.u.upper <= 1, parameters.u.width >= 0,
              parameters.v.lower >= 0, parameters.v.upper <= 1, parameters.v.width >= 0 else {
            throw failure(.invalidInput, "Blend native jets require a closed box inside the normalized domain.")
        }
        return try intervalJet(over: parameters, center: centerJet,
            firstRadial: firstContactJet + (-centerJet), secondRadial: secondContactJet + (-centerJet),
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func intervalJet(over parameters: SurfaceParameterBox, center: SurfaceIntervalVectorJet,
                             firstRadial first: SurfaceIntervalVectorJet,
                             secondRadial second: SurfaceIntervalVectorJet,
                             consumeWork: () throws -> Void = {},
                             consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
        // All composition scratch is fixed-value jet storage; there is no
        // dynamic coefficient buffer to replace by a nominal byte reservation.
        try consumeWork()
        guard let a = first.normalized(), let b = second.normalized() else {
            throw failure(.singularSystem, "The blend box cannot certify nonzero contact radials.")
        }
        try consumeWork()
        let cross = a.cross(b)
        let threshold = max(sin(min(tolerance.angle, .pi * 0.5)), tolerance.relative)
        func separated(_ bound: OutwardScalarInterval) throws -> Bool {
            try consumeWork()
            return bound.lower > threshold || bound.upper < -threshold
        }
        guard try separated(cross.x.value) || separated(cross.y.value) || separated(cross.z.value) else {
            throw failure(.singularSystem, "The blend box cannot certify a regular minor arc.")
        }
        try consumeWork()
        let one = SurfaceIntervalJet.constant(1)
        guard let weight = ((one + a.dot(b)) * .constant(0.5)).squareRoot(),
              let inverseWeight = weight.reciprocal() else {
            throw failure(.singularSystem, "The blend box cannot certify its circular weight.")
        }
        try consumeWork()
        let t = SurfaceIntervalJet.parameterV(parameters.v)
        let s = one + (-t)
        try consumeWork()
        let radial = a * (s * s) + (a + b) * (s * t * inverseWeight) + b * (t * t)
        try consumeWork()
        let rawDenominator = s * s + .constant(2) * weight * s * t + t * t
        // Bernstein weights [1, w, 1] give a positive convex-hull bound.
        // Independent interval products otherwise allow both s and t to be zero.
        guard let denominatorValue = rawDenominator.value.intersection(with:
            OutwardScalarInterval(lower: min(1, weight.value.lower), upper: max(1, weight.value.upper))) else {
            throw failure(.intersectionFailure, "Blend denominator enclosures are inconsistent.")
        }
        try consumeWork()
        let denominator = SurfaceIntervalJet(value: denominatorValue,
            derivativeU: rawDenominator.derivativeU, derivativeV: rawDenominator.derivativeV,
            secondDerivativeUU: rawDenominator.secondDerivativeUU,
            secondDerivativeUV: rawDenominator.secondDerivativeUV,
            secondDerivativeVV: rawDenominator.secondDerivativeVV,
            thirdDerivativeUUU: rawDenominator.thirdDerivativeUUU,
            thirdDerivativeUUV: rawDenominator.thirdDerivativeUUV,
            thirdDerivativeUVV: rawDenominator.thirdDerivativeUVV,
            thirdDerivativeVVV: rawDenominator.thirdDerivativeVVV)
        try consumeWork()
        guard let inverseDenominator = denominator.reciprocal() else {
            throw failure(.singularSystem, "The blend box cannot certify a nonzero rational denominator.")
        }
        try consumeWork()
        let result = center + radial * (.constant(radius) * inverseDenominator)
        func finite(_ bound: OutwardScalarInterval) throws {
            try consumeWork()
            guard bound.lower.isFinite, bound.upper.isFinite else {
                throw failure(.resourceLimitExceeded, "Blend derivative enclosures exceeded the finite numeric range.")
            }
        }
        func finite(_ axis: SurfaceIntervalJet) throws {
            try finite(axis.value); try finite(axis.derivativeU); try finite(axis.derivativeV)
            try finite(axis.secondDerivativeUU); try finite(axis.secondDerivativeUV); try finite(axis.secondDerivativeVV)
            try finite(axis.thirdDerivativeUUU); try finite(axis.thirdDerivativeUUV)
            try finite(axis.thirdDerivativeUVV); try finite(axis.thirdDerivativeVVV)
        }
        try finite(result.x); try finite(result.y); try finite(result.z)
        return result
    }
}
