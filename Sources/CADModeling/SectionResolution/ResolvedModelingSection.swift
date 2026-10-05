import CADCore
import CADGeometry
import CADIR

/// Source admission shared by modeling evaluators and their preflight consumers.
package enum ResolvedModelingSection: Sendable {
    /// A closed region and the section naming it: a sketch profile or a planar face of a body.
    case profile(Profile, SectionReference)
    case face(ResolvedFaceSection, SectionReference)
    case constructedRegion(ResolvedBoundaryRegion)
    case curve(EvaluatedCurve)

    /// `section` read from `context`: a sketch region, a planar face where its body is, or a curve.
    package static func resolve(
        _ section: SectionReference,
        context: EvaluationContext,
        featureID: FeatureID,
        sourceBudget: CurvedSweepSourceBudget? = nil,
        admission: GeometryConversionAdmission? = nil
    ) throws -> ResolvedModelingSection {
        switch section {
        case .face(let reference):
            return .face(
                try FaceSectionProfileResolver().resolve(for: reference, context: context, featureID: featureID, sourceBudget: sourceBudget, admission: admission),
                section
            )
        case .profile(let profileReference):
            return .profile(try resolveProfile(profileReference, from: context.profiles[profileReference.featureID]), section)
        case .curve(let curveReference):
            return .curve(try resolveCurve(
                curveReference, from: context.curves[curveReference.featureID], tolerance: context.tolerance,
                admission: admission
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
        tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil
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
        if let admission {
            _ = try curve.validateOriginalGeometry(tolerance: tolerance,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: { try admission.visit(depth: $0) },
                consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
        }
        guard reference.parameterDomain != nil || reference.isReversed else { return curve }
        if admission == nil { try curve.validate(tolerance: tolerance) }
        var selected = curve
        if let domain = reference.parameterDomain {
            selected = try CurveTrimFeatureEvaluator().trimmedCurve(featureID: reference.featureID,
                source: curve, domain: domain, tolerance: tolerance, admission: admission)
        }
        guard reference.isReversed else { return selected }
        guard let original = selected.exactCurve else {
            throw FeatureEvaluationError.invalidGraph("Reversed curve sections require an original curve law.")
        }
        let originalBounds: (lower: Double, upper: Double)
        switch selected.parameterDomain {
        case let .closed(lower, upper):
            originalBounds = (lower, upper)
        case let .periodic(period) where selected.isClosed:
            originalBounds = (0, period)
        default:
            throw FeatureEvaluationError.invalidGraph("Reversed curve sections require a bounded exact curve.")
        }
        let lower = -originalBounds.upper
        let upper = -originalBounds.lower
        let span = upper - lower
        guard span.isFinite, span > 0 else {
            throw GeometryError.invalidDistance(span)
        }
        let reversed: Curve3D
        if let admission {
            // Original input admission above and the fixed exact -1 gain are
            // the constructor's premise; validation pays the new image level.
            reversed = .parameterImage(ParameterImageCurve3D(validatedSource: original,
                parameterGain: .binary(-1), offset: 0))
            try reversed.validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { try admission.visit(depth: $0) },
                consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
            selected.exactCurve = reversed
            selected.exactParameterDomain = .closed(lower, upper)
            selected = try CurveTrimFeatureEvaluator().trimmedCurve(featureID: reference.featureID,
                source: selected, domain: .closed(lower, upper), tolerance: tolerance, admission: admission)
            selected.source = curve.source
            return selected
        }
        reversed = .parameterImage(try ParameterImageCurve3D(
            source: original, gain: -1, offset: 0, tolerance: tolerance))
        let parameters = (0...32).map { index in
            index == 0 ? lower : (index == 32 ? upper : lower + span * Double(index) / 32)
        }
        selected.source = curve.source
        selected.exactCurve = reversed
        selected.exactParameterDomain = .closed(lower, upper)
        selected.exactPointParameters = parameters
        selected.points = try parameters.map { try reversed.point(at: $0, tolerance: tolerance) }
        try selected.validate(tolerance: tolerance)
        return selected
    }

    package var retainsOriginalRegionBoundary: Bool {
        switch self {
        case .face, .constructedRegion: true
        case .profile, .curve: false
        }
    }

    package func plane() throws -> SketchPlane {
        switch self {
        case .profile(let profile, _):
            return profile.plane
        case .face(let face, _):
            return face.plane
        case .constructedRegion(let region):
            return region.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                throw FeatureEvaluationError.invalidGraph("A planar section requires source plane metadata.")
            }
            return plane
        }
    }

    package func profileFacade() throws -> Profile {
        switch self {
        case .profile(let profile, _): return profile
        case .face(let face, _): return face.profile
        case .constructedRegion(let region): return region.profile
        case .curve: throw FeatureEvaluationError.invalidGraph("A curve section has no region profile facade.")
        }
    }

    /// The section naming a closed region, for a feature that reads the region itself.
    package func regionSection() throws -> SectionReference {
        switch self {
        case .profile(_, let section), .face(_, let section): return section
        case .constructedRegion(let region): return region.sectionReference
        case .curve: throw FeatureEvaluationError.invalidGraph("A curve section cannot be used as a closed profile.")
        }
    }
}
