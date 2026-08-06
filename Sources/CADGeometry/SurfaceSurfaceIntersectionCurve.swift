import Foundation
import CADCore

public struct SurfaceSurfaceIntersectionCurve: Codable, Hashable, Sendable {
    public let truth: SurfaceSurfaceIntersectionCurveTruth
    public let derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation
    public let kind: CurveSurfaceIntersectionKind
    public let firstSurfaceAnchor: SurfaceParameterProjection
    public let secondSurfaceAnchor: SurfaceParameterProjection
    public let certificationTolerance: ModelingTolerance

    public var curve: Curve3D { truth.curve }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        switch truth {
        case .parametric:
            derivedRepresentation.firstSurfaceParameterCurve
        case let .implicit(curve):
            .certifiedImplicit(CertifiedImplicitSurfaceParameterCurve(
                validatedIntersection: curve,
                role: .first
            ))
        case let .analyticBSpline(curve):
            curve.firstSurfaceParameterCurve
        case let .analyticBSplineTangency(curve):
            curve.firstSurfaceParameterCurve
        case let .analyticAnalytic(curve):
            curve.usesDerivedSurfaceParameterCurves
                ? derivedRepresentation.firstSurfaceParameterCurve
                : curve.firstSurfaceParameterCurve
        case let .quadraticTangency(curve):
            curve.firstSurfaceParameterCurve
        }
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        switch truth {
        case .parametric:
            derivedRepresentation.secondSurfaceParameterCurve
        case let .implicit(curve):
            .certifiedImplicit(CertifiedImplicitSurfaceParameterCurve(
                validatedIntersection: curve,
                role: .second
            ))
        case let .analyticBSpline(curve):
            curve.secondSurfaceParameterCurve
        case let .analyticBSplineTangency(curve):
            curve.secondSurfaceParameterCurve
        case let .analyticAnalytic(curve):
            curve.usesDerivedSurfaceParameterCurves
                ? derivedRepresentation.secondSurfaceParameterCurve
                : curve.secondSurfaceParameterCurve
        case let .quadraticTangency(curve):
            curve.secondSurfaceParameterCurve
        }
    }

    public var maximumResidual: Double {
        derivedRepresentation.maximumResidualUpperBound
    }

    public var sourceIdentity: SurfaceSurfaceIntersectionSourceIdentity {
        SurfaceSurfaceIntersectionSourceIdentity(
            kind: kind,
            firstSurfaceAnchor: firstSurfaceAnchor,
            secondSurfaceAnchor: secondSurfaceAnchor,
            certificationTolerance: certificationTolerance
        )
    }

    public func surfaceParameter(
        on role: SurfaceIntersectionSurfaceRole,
        atCurveParameter parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        switch truth {
        case .parametric, .quadraticTangency, .analyticBSpline,
             .analyticBSplineTangency, .analyticAnalytic:
            let parameterCurve = role == .first
                ? firstSurfaceParameterCurve
                : secondSurfaceParameterCurve
            return try parameterCurve.parameter(
                atCurveParameter: parameter,
                curveDomain: curve.parameterDomain,
                tolerance: tolerance
            )
        case let .implicit(implicitCurve):
            guard parameter.isFinite else {
                throw GeometryError.invalidDistance(parameter)
            }
            // A closed implicit curve accepts any periodic representative of
            // its normalized fraction.
            let canonical: Double
            if case .periodic = curve.parameterDomain {
                let remainder = parameter.truncatingRemainder(dividingBy: 1.0)
                canonical = remainder >= 0.0 ? remainder : remainder + 1.0
            } else {
                guard parameter >= -tolerance.relative,
                      parameter <= 1.0 + tolerance.relative else {
                    throw GeometryError.invalidDistance(parameter)
                }
                canonical = min(max(parameter, 0.0), 1.0)
            }
            let pair = try implicitCurve.parameterPair(
                atNormalizedFraction: canonical,
                tolerance: tolerance
            )
            return role == .first ? pair.first : pair.second
        }
    }

    public func surfaceParameter(
        on role: SurfaceIntersectionSurfaceRole,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        switch truth {
        case .parametric, .quadraticTangency, .analyticBSpline,
             .analyticBSplineTangency, .analyticAnalytic:
            let parameterCurve = role == .first
                ? firstSurfaceParameterCurve
                : secondSurfaceParameterCurve
            return try parameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .implicit(implicitCurve):
            let pair = try implicitCurve.parameterPair(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return role == .first ? pair.first : pair.second
        }
    }

    public init(
        truth: SurfaceSurfaceIntersectionCurveTruth,
        derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation,
        kind: CurveSurfaceIntersectionKind,
        firstSurfaceAnchor: SurfaceParameterProjection,
        secondSurfaceAnchor: SurfaceParameterProjection,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try truth.validate(tolerance: tolerance)
        try derivedRepresentation.validate(tolerance: tolerance)
        switch truth {
        case let .quadraticTangency(curve):
            guard kind == curve.kind,
                  derivedRepresentation.curve == curve.curve,
                  derivedRepresentation.firstSurfaceParameterCurve
                    == curve.firstSurfaceParameterCurve,
                  derivedRepresentation.secondSurfaceParameterCurve
                    == curve.secondSurfaceParameterCurve,
                  derivedRepresentation.maximumResidualUpperBound
                    >= curve.maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A quadratic tangency derived representation changed its certified truth."
                )
            }
        case let .analyticBSplineTangency(curve):
            guard kind == curve.tangencyCurve.kind,
                  derivedRepresentation.curve == curve.curve,
                  derivedRepresentation.firstSurfaceParameterCurve
                    == curve.firstSurfaceParameterCurve,
                  derivedRepresentation.secondSurfaceParameterCurve
                    == curve.secondSurfaceParameterCurve,
                  derivedRepresentation.maximumResidualUpperBound
                    >= curve.maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An analytic B-spline tangency cache changed its certified truth."
                )
            }
        case .parametric, .implicit, .analyticBSpline, .analyticAnalytic:
            break
        }
        guard firstSurfaceAnchor.residual.isFinite,
              secondSurfaceAnchor.residual.isFinite,
              derivedRepresentation.maximumResidualUpperBound <= tolerance.distance,
              firstSurfaceAnchor.residual <= tolerance.distance,
              secondSurfaceAnchor.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: derivedRepresentation.maximumResidualUpperBound,
                tolerance: tolerance,
                message: "Surface-surface intersection curve failed residual verification."
            )
        }
        self.truth = truth
        self.derivedRepresentation = derivedRepresentation
        self.kind = kind
        self.firstSurfaceAnchor = firstSurfaceAnchor
        self.secondSurfaceAnchor = secondSurfaceAnchor
        certificationTolerance = tolerance
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface intersection curve cannot satisfy a stricter tolerance than its stored certification tolerance."
            )
        }
        _ = try SurfaceSurfaceIntersectionCurve(
            truth: truth,
            derivedRepresentation: derivedRepresentation,
            kind: kind,
            firstSurfaceAnchor: firstSurfaceAnchor,
            secondSurfaceAnchor: secondSurfaceAnchor,
            tolerance: tolerance
        )
    }

    private enum CodingKeys: String, CodingKey {
        case truth
        case derivedRepresentation
        case kind
        case firstSurfaceAnchor
        case secondSurfaceAnchor
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .truth,
                .derivedRepresentation,
                .kind,
                .firstSurfaceAnchor,
                .secondSurfaceAnchor,
                .certificationTolerance,
            ],
            in: decoder
        )
        try self.init(
            truth: container.decode(SurfaceSurfaceIntersectionCurveTruth.self, forKey: .truth),
            derivedRepresentation: container.decode(
                SurfaceSurfaceIntersectionDerivedRepresentation.self,
                forKey: .derivedRepresentation
            ),
            kind: container.decode(CurveSurfaceIntersectionKind.self, forKey: .kind),
            firstSurfaceAnchor: container.decode(
                SurfaceParameterProjection.self,
                forKey: .firstSurfaceAnchor
            ),
            secondSurfaceAnchor: container.decode(
                SurfaceParameterProjection.self,
                forKey: .secondSurfaceAnchor
            ),
            tolerance: container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(truth, forKey: .truth)
        try container.encode(derivedRepresentation, forKey: .derivedRepresentation)
        try container.encode(kind, forKey: .kind)
        try container.encode(firstSurfaceAnchor, forKey: .firstSurfaceAnchor)
        try container.encode(secondSurfaceAnchor, forKey: .secondSurfaceAnchor)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}


// The synthesized equality copies every large member pair into one frame,
// which overflows 512 KB worker stacks in unoptimized builds, so each member
// comparison runs in its own bounded frame.
extension SurfaceSurfaceIntersectionCurve {
    public static func == (
        lhs: SurfaceSurfaceIntersectionCurve,
        rhs: SurfaceSurfaceIntersectionCurve
    ) -> Bool {
        equalsTruth(lhs, rhs)
            && equalsDerivedRepresentation(lhs, rhs)
            && lhs.kind == rhs.kind
            && equalsAnchors(lhs, rhs)
            && lhs.certificationTolerance == rhs.certificationTolerance
    }

    @inline(never)
    private static func equalsTruth(
        _ lhs: SurfaceSurfaceIntersectionCurve,
        _ rhs: SurfaceSurfaceIntersectionCurve
    ) -> Bool {
        lhs.truth == rhs.truth
    }

    @inline(never)
    private static func equalsDerivedRepresentation(
        _ lhs: SurfaceSurfaceIntersectionCurve,
        _ rhs: SurfaceSurfaceIntersectionCurve
    ) -> Bool {
        lhs.derivedRepresentation == rhs.derivedRepresentation
    }

    @inline(never)
    private static func equalsAnchors(
        _ lhs: SurfaceSurfaceIntersectionCurve,
        _ rhs: SurfaceSurfaceIntersectionCurve
    ) -> Bool {
        lhs.firstSurfaceAnchor == rhs.firstSurfaceAnchor
            && lhs.secondSurfaceAnchor == rhs.secondSurfaceAnchor
    }
}
