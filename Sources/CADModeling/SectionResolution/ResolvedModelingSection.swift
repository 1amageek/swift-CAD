import CADCore
import CADGeometry
import CADIR

/// Source admission shared by modeling evaluators and their preflight consumers.
package enum ResolvedModelingSection: Sendable {
    /// A closed region and the section naming it: a sketch profile or a planar face of a body.
    case profile(Profile, SectionReference)
    case curve(EvaluatedCurve)

    /// `section` read from `context`: a sketch region, a planar face where its body is, or a curve.
    package static func resolve(
        _ section: SectionReference,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> ResolvedModelingSection {
        switch section {
        case .face(let reference):
            return .profile(
                try FaceSectionProfileResolver().profile(for: reference, context: context, featureID: featureID),
                section
            )
        case .profile(let profileReference):
            return .profile(try resolveProfile(profileReference, from: context.profiles[profileReference.featureID]), section)
        case .curve(let curveReference):
            return .curve(try resolveCurve(
                curveReference, from: context.curves[curveReference.featureID], tolerance: context.tolerance
            ))
        }
    }

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
        guard reference.parameterDomain != nil || reference.isReversed else { return curve }
        try curve.validate(tolerance: tolerance)
        var selected = curve
        if let domain = reference.parameterDomain {
            selected = try CurveTrimFeatureEvaluator().trimmedCurve(featureID: reference.featureID,
                source: curve, domain: domain, tolerance: tolerance)
        }
        guard reference.isReversed else { return selected }
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: selected)
        let composite = try spans.count == 1 ? spans[0].curve
            : ExactCompositeBSplineCurveBuilder().build(spans: spans.map(\.curve), tolerance: tolerance)
        let reversed = try composite.reversed(tolerance: tolerance)
        guard case .closed(let lower, let upper) = reversed.domain else {
            throw FeatureEvaluationError.invalidGraph("Reversed curve sections require a bounded exact curve.")
        }
        let parameters = (0...32).map { index in
            index == 32 ? upper : lower + (upper - lower) * Double(index) / 32
        }
        selected.source = curve.source
        selected.exactCurve = .bSpline(reversed)
        selected.exactParameterDomain = reversed.domain
        selected.exactPointParameters = parameters
        selected.points = try parameters.map { try reversed.point(at: $0, tolerance: tolerance) }
        try selected.validate(tolerance: tolerance)
        return selected
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

    /// The section naming a closed region, for a feature that reads the region itself.
    package func regionSection() throws -> SectionReference {
        guard case .profile(_, let section) = self else {
            throw FeatureEvaluationError.invalidGraph("A curve section cannot be used as a closed profile.")
        }
        return section
    }
}
