import CADCore
import CADIR

/// Source admission shared by modeling evaluators and their preflight consumers.
package enum ResolvedModelingSection: Sendable {
    case profile(Profile, ProfileReference)
    case curve(EvaluatedCurve)

    package static func resolveProfile(
        _ reference: ProfileReference,
        from profiles: [Profile]?
    ) throws -> Profile {
        guard let profiles, profiles.indices.contains(reference.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(reference.featureID, reference.profileIndex)
        }
        let profile = profiles[reference.profileIndex]
        guard profile.sourceFeatureID == reference.featureID else {
            throw FeatureEvaluationError.invalidGraph("Section profile belongs to a different source feature.")
        }
        return profile
    }

    package static func resolveCurve(
        _ reference: CurveSectionReference,
        from curves: [EvaluatedCurve]?,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves, curves.count == 1, let curve = curves.first else {
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "A curve section reference requires exactly one source curve."
            )
        }
        guard curve.sourceFeatureID == reference.featureID else {
            throw FeatureEvaluationError.invalidGraph("Section curve belongs to a different source feature.")
        }
        guard let domain = reference.parameterDomain else { return curve }
        try curve.validate(tolerance: tolerance)
        return try CurveTrimFeatureEvaluator().trimmedCurve(featureID: reference.featureID,
            source: curve, domain: domain, tolerance: tolerance)
    }

    package func plane() throws -> SketchPlane {
        switch self {
        case .profile(let profile, _):
            return profile.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                throw FeatureEvaluationError.invalidGraph("A planar section requires source plane metadata.")
            }
            return plane
        }
    }

    package func profileReference() throws -> ProfileReference {
        guard case .profile(_, let reference) = self else {
            throw FeatureEvaluationError.invalidGraph("A curve section cannot be used as a closed profile.")
        }
        return reference
    }
}
