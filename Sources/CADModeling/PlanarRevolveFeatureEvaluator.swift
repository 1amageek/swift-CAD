import CADCore
import CADIR

public struct PlanarRevolveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing
    private let booleanApplicator: (any SweepBooleanApplying)?
    private let targetRelocator: (any ExactBodyPatternRebuilding)?

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = nil
        self.targetRelocator = nil
    }

    /// An evaluator that also combines a Boolean revolve with its targets, moving placed ones
    /// into the revolve's frame with `targetRelocator` first.
    package init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: any SweepBooleanApplying,
        targetRelocator: any ExactBodyPatternRebuilding
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = targetRelocator
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .revolve(revolve) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: context.tolerance,
                message: "PlanarRevolveFeatureEvaluator only supports revolve."
            )
        }
        try revolve.validate(tolerance: context.tolerance)
        let resolvedAngle = try resolver.evaluate(
            revolve.angle,
            parameters: context.parameters,
            variables: [:]
        )
        guard resolvedAngle.kind == .angle else {
            throw UnitError.expectedQuantity(
                operation: "revolve.angle",
                expected: .angle,
                actual: resolvedAngle.kind
            )
        }
        let angle = resolvedAngle.value
        guard angle.isFinite, abs(angle) > context.tolerance.angle else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                residual: angle.isFinite ? abs(angle) : nil,
                tolerance: context.tolerance,
                message: "Revolve requires a finite nonzero angle."
            )
        }
        guard abs(angle) <= Double.pi * 2.0 + context.tolerance.angle else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                residual: abs(angle) - 2.0 * Double.pi,
                tolerance: context.tolerance,
                message: "Revolve angle must not exceed one full turn."
            )
        }

        var wallThickness: Double?
        if let thickness = revolve.thickness {
            let quantity = try resolver.evaluate(thickness, parameters: context.parameters, variables: [:])
            guard quantity.kind == .length, quantity.value.isFinite, quantity.value > context.tolerance.distance else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                                  message: "A revolve's wall thickness must be a positive length.")
            }
            wallThickness = quantity.value
        }
        // A face section is read where its face is before any target moves; placed targets then
        // move into the revolve's frame as staged bodies.
        var faceProfile: Profile?
        if case let .face(reference) = revolve.section {
            faceProfile = try FaceSectionProfileResolver().profile(for: reference, context: context, featureID: feature.id)
        }
        var stages = FeatureEvaluationStages(context)
        var targetBodyIDs: [BodyID] = []
        if revolve.operation != .newBody {
            targetBodyIDs = try PlacedBooleanTargetStager(relocator: targetRelocator).stage(
                revolve.targets, featureID: feature.id, stablePrefix: "revolve:placedTarget", stages: &stages, what: "a revolve"
            )
        }
        var result = try tool(
            revolve, angle: angle, faceProfile: faceProfile, wallThickness: wallThickness,
            featureID: feature.id, context: stages.context
        )
        if revolve.operation != .newBody {
            guard let booleanApplicator,
                  let operation = SweepBooleanOperation(rawValue: revolve.operation.rawValue) else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance,
                    message: "Revolve Boolean evaluation requires a Boolean applicator.")
            }
            let toolReference = SubshapeID(featureID: feature.id, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
            guard case let .body(toolID) = result.subshapes[toolReference] else {
                throw FeatureEvaluationError.missingInput("Revolve tool body was not generated.")
            }
            // The analytic fast path leaves its faces without pcurves, which the Boolean's face
            // arrangement reads.
            try ExactFacePcurveBuilder().populateMissingPcurves(in: &result.brep, tolerance: context.tolerance)
            let staged = stages.context
            result = try booleanApplicator.apply(operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolID, keepTools: revolve.keepTools, featureID: feature.id,
                toolResult: result, targetSubshapes: staged.subshapes.entries,
                inputLineage: staged.lineage, tolerance: staged.tolerance)
            if stages.isEmpty == false {
                result = try stages.publish(result, featureID: feature.id)
            }
        }
        return result
    }

    /// The revolved body itself, before any Boolean.
    private func tool(
        _ revolve: RevolveFeature,
        angle: Double,
        faceProfile: Profile?,
        wallThickness: Double?,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var profile: Profile
        switch revolve.section {
        case .face:
            guard let faceProfile else {
                throw FeatureEvaluationError.missingInput("A revolve's face section was not read.")
            }
            profile = faceProfile
        case .curve(let reference):
            let section = try ResolvedModelingSection.resolveCurve(reference,
                from: context.curves[reference.featureID], tolerance: context.tolerance)
            guard revolve.resultKind == .solid else {
                return try CurvedRevolveBodyBuilder.buildSheet(axis: revolve.axis, angle: angle,
                    section: section, featureID: featureID, context: context, sewer: sewer)
            }
            let region = try solidProfile(of: section, axis: revolve.axis, featureID: featureID, context: context)
            return try CurvedRevolveBodyBuilder(
                axis: revolve.axis, angle: angle, profile: region, featureID: featureID, context: context, sewer: sewer
            ).build(from: region, resultKind: .solid)
        case .profile(let reference):
            profile = try ResolvedModelingSection.resolveProfile(reference,
                from: context.profiles[reference.featureID])
        }
        if let wallThickness {
            let rings = try ExactDraftedProfileBoundaryBuilder(tolerance: context.tolerance).wallProfiles(
                from: profile, planeNormal: try normal(of: profile.plane, tolerance: context.tolerance), thickness: wallThickness
            )
            // A section with holes walls each loop into a ring of its own: the rings revolve into one
            // body, a solid for each.
            guard let first = rings.first else {
                throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID, tolerance: context.tolerance,
                                  message: "A thin revolve's wall leaves no ring.")
            }
            if rings.count > 1 {
                return try CurvedRevolveBodyBuilder(
                    axis: revolve.axis, angle: angle, profile: first, featureID: featureID, context: context, sewer: sewer
                ).build(fromRings: rings, resultKind: .solid)
            }
            profile = first
        }

        // Multi-loop regions require one topology authority for cap holes,
        // detached void shells, pcurves, and volume ownership. The general
        // exact sewing path provides that contract even when every boundary is
        // linear; the analytic fast path remains specialized for one loop.
        let requiresGeneralTopology = revolve.resultKind == .sheet || profile.innerLoops.isEmpty == false
            || profile.boundaryLoops.flatMap(\.boundarySegments).contains(where: { segment in
            switch segment {
            case .line:
                return false
            case .circularArc, .spline:
                return true
            }
        })
        if requiresGeneralTopology {
            return try CurvedRevolveBodyBuilder(
                axis: revolve.axis,
                angle: angle,
                profile: profile,
                featureID: featureID,
                context: context,
                sewer: sewer
            ).build(from: profile, resultKind: revolve.resultKind)
        }
        return try RevolveBodyBuilder(
            axis: revolve.axis,
            angle: angle,
            profile: profile,
            featureID: featureID,
            context: context
        ).build(from: profile)
    }

    /// A curve read as the region it bounds with the axis: a closed planar curve on its own, an
    /// open one closed along the axis between its ends, which must both lie on it.
    private func solidProfile(of curve: EvaluatedCurve, axis: RevolveAxis, featureID: FeatureID, context: EvaluationContext) throws -> Profile {
        let tolerance = context.tolerance
        guard let plane = curve.plane else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A curve revolves into a solid only when it is planar.")
        }
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: curve)
        guard let first = spans.first, let last = spans.last else { throw SketchError.openProfile }
        var segments = spans.map { ProfileBoundarySegment.spline(ProfileSplineSegment(curve: $0.curve)) }
        var vertices: [Point3D] = []
        for span in spans {
            guard case let .closed(lower, upper) = span.curve.domain else { throw SketchError.degenerateProfile }
            vertices.append(span.startPoint)
            vertices.append(try span.curve.point(at: 0.5 * (lower + upper), tolerance: tolerance))
        }
        if curve.isClosed == false {
            let direction = try axis.normalizedDirection(tolerance: tolerance)
            func offAxis(_ point: Point3D) -> Double {
                let relative = point - axis.origin
                return (relative - direction * relative.dot(direction)).length
            }
            guard offAxis(first.startPoint) <= tolerance.distance, offAxis(last.endPoint) <= tolerance.distance else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "An open curve revolves into a solid only when both its ends lie on the axis; make a sheet instead.")
            }
            segments.append(.line(ProfileLineSegment(start: last.endPoint, end: first.startPoint)))
            vertices.append(last.endPoint)
        }
        return Profile(sourceFeatureID: curve.sourceFeatureID, plane: plane,
                       outerLoop: ProfileLoop(vertices: vertices, boundarySegments: segments), innerLoops: [])
    }

    private func normal(of plane: SketchPlane, tolerance: ModelingTolerance) throws -> Vector3D {
        switch plane {
        case .xy: return .unitZ
        case .yz: return .unitX
        case .zx: return .unitY
        case let .plane(value): return try value.normal.normalized(tolerance: tolerance.distance)
        }
    }
}
