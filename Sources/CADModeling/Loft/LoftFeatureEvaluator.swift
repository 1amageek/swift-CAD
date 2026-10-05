import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct LoftFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    /// Sews a Loft to a vertex (`ApexLoftBuilder`); without one such a Loft is refused.
    private let sewer: (any BRepSewing)?
    private let capContactValidator: (any LoftFiniteCapContactValidating)?

    public init() {
        self.sewer = nil
        self.capContactValidator = nil
    }

    public init(sewer: any BRepSewing, capContactValidator: any LoftFiniteCapContactValidating) {
        self.sewer = sewer
        self.capContactValidator = capContactValidator
    }

    package init(sewer: any BRepSewing) {
        self.sewer = sewer
        self.capContactValidator = nil
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        var result = try evaluateUnvalidated(feature: feature, context: context)
        // Simplify: the loft's flat faces are trimmed planes.
        if case let .loft(loft) = feature.operation, loft.options.simplify {
            let bodyReference = result.subshapes[SubshapeID(featureID: feature.id, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)]
            guard case let .body(bodyID)? = bodyReference else {
                throw FeatureEvaluationError.missingInput("A simplified Loft publishes no body.")
            }
            result = try PlanarFaceSimplifier(tolerance: context.tolerance).simplified(result, bodyID: bodyID)
        }
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    /// A Loft from its one section to a vertex of a body, the section's one loop ruled to it.
    private func apexLoft(_ loft: LoftFeature, apex: LoftApex, featureID: FeatureID, context: EvaluationContext,
        allowance: inout LoftCorrespondenceAllowance) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard let sewer else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "This evaluator cannot sew a Loft to a vertex.")
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: try allowance.conversionAdmission())
        let section = loft.sections[0]
        let loop: (spans: [ExactBSplineCurveSpan], closed: Bool)
        switch section.section {
        case .face(let reference):
            let loops = try spanBuilder.faceLoopSpans(from: try FaceSectionProfileResolver().resolve(for: reference, context: context, featureID: featureID, admission: try allowance.conversionAdmission()))
            guard loops.count == 1 else {
                throw KernelError(phase: .topology, code: .ambiguousSelection, featureID: featureID, tolerance: tolerance,
                    message: "A Loft face with \(max(0, loops.count - 1)) holes and one terminal vertex has no declared hole birth or death correspondence.")
            }
            loop = (loops[0], true)
        case .profile(let reference):
            let loops = try spanBuilder.profileLoopSpans(from: try ResolvedModelingSection.resolveProfile(reference, from: context.profiles[reference.featureID]))
            guard loops.count == 1 else {
                throw KernelError(phase: .topology, code: .ambiguousSelection, featureID: featureID, tolerance: tolerance,
                    message: "A Loft profile with \(max(0, loops.count - 1)) holes and one terminal vertex has no declared hole birth or death correspondence.")
            }
            loop = (loops[0], true)
        case .curve(let reference):
            let original = try OriginalLoftCurveSection(reference: reference,
                curves: context.curves[reference.featureID], allowance: &allowance, tolerance: tolerance)
            loop = (original.imageSpans, original.isClosed)
        }
        guard case let .vertex(vertexID) = try StableSubshapeResolver().topologyReference(
                for: apex.vertex, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance),
              let point = context.brep.vertices[vertexID]?.point else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A Loft's apex is a vertex.")
        }
        let request = try ApexLoftBuilder(tolerance: tolerance).request(spans: loop.spans, isClosed: loop.closed, apex: point,
                                                                       resultKind: loft.options.resultKind, featureID: featureID)
        let sewn = try sewer.sew(request, tolerance: tolerance)
        return EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, sewn.brep]),
                                subshapes: sewn.subshapes, lineage: sewn.lineage)
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .loft(loft) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "LoftFeatureEvaluator requires a loft feature."
            )
        }
        try loft.validate()
        var correspondenceAllowance = LoftCorrespondenceAllowance(tolerance: context.tolerance)
        if let apex = loft.apex {
            return try apexLoft(loft, apex: apex, featureID: feature.id, context: context, allowance: &correspondenceAllowance)
        }
        if loft.sections.contains(where: { !$0.section.isClosedRegion }) {
            let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: try correspondenceAllowance.conversionAdmission())
            var seamPoints: [Point3D?] = []
            var originalContactLoops: [[[OriginalCurveContactSource]]?] = []
            let profileContacts = OriginalLoftProfileContactSources()
            let boundaries = try loft.sections.map { section -> (spans: [ExactBSplineCurveSpan], closed: Bool) in
                switch section.section {
                case .face(let reference):
                    let face = try FaceSectionProfileResolver().resolve(for: reference, context: context, featureID: feature.id, admission: try correspondenceAllowance.conversionAdmission())
                    let profile = face.profile
                    if let index = section.startSampleIndex {
                        guard profile.vertices.indices.contains(index) else {
                            throw FeatureEvaluationError.invalidGraph("Loft start index must reference an existing face sample.")
                        }
                        seamPoints.append(profile.vertices[index])
                    } else {
                        seamPoints.append(nil)
                    }
                    let loops = try spanBuilder.faceLoopSpans(from: face)
                    originalContactLoops.append(try profileContacts.loops(face: face,
                        consumeStorage: { try correspondenceAllowance.charge($0) }, tolerance: context.tolerance))
                    guard loops.count == 1, let spans = loops.first else {
                        throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: context.tolerance,
                            message: "A single curve and a Loft face with \(max(0, loops.count - 1)) holes have no declared boundary birth or death correspondence.")
                    }
                    return (try directedProfileSpans(spans, direction: section.profileDirection, tolerance: context.tolerance), true)
                case .curve(let reference):
                    if let index = section.startSampleIndex {
                        let source = try ResolvedModelingSection.resolveCurve(
                            CurveSectionReference(featureID: reference.featureID),
                            from: context.curves[reference.featureID], tolerance: context.tolerance)
                        guard source.points.indices.contains(index) else {
                            throw FeatureEvaluationError.invalidGraph("Loft start index must reference an existing source curve sample.")
                        }
                        seamPoints.append(source.points[index])
                    } else {
                        seamPoints.append(nil)
                    }
                    let original = try OriginalLoftCurveSection(reference: reference,
                        curves: context.curves[reference.featureID], allowance: &correspondenceAllowance,
                        tolerance: context.tolerance)
                    originalContactLoops.append([[original.source]])
                    return (original.imageSpans, original.isClosed)
                case .profile(let reference):
                    let profile = try ResolvedModelingSection.resolveProfile(reference,
                        from: context.profiles[reference.featureID])
                    if let index = section.startSampleIndex {
                        guard profile.vertices.indices.contains(index) else {
                            throw FeatureEvaluationError.invalidGraph("Loft start index must reference an existing source profile sample.")
                        }
                        seamPoints.append(profile.vertices[index])
                    } else {
                        seamPoints.append(nil)
                    }
                    let loops = try spanBuilder.profileLoopSpans(from: profile)
                    originalContactLoops.append(try profileContacts.loops(profile: profile,
                        consumeStorage: { try correspondenceAllowance.charge($0) }, tolerance: context.tolerance))
                    guard loops.count == 1, let spans = loops.first else {
                        throw KernelError(phase: .topology, code: .ambiguousSelection,
                            tolerance: context.tolerance,
                            message: "A single curve and a Loft profile with \(max(0, loops.count - 1)) holes have no declared boundary birth or death correspondence.")
                    }
                    return (try directedProfileSpans(spans, direction: section.profileDirection, tolerance: context.tolerance), true)
                }
            }
            guard let closed = boundaries.first?.closed, boundaries.allSatisfy({ $0.closed == closed }) else {
                throw FeatureEvaluationError.invalidGraph("Loft sections must have matching boundary closure.")
            }
            var boundarySpans = boundaries.map(\.spans)
            var lofted = loft
            if loft.sections.count == 1 {
                // Continuous lofting: the far section is the one section carried to the guides'
                // far ends, a section of its own (no continuity) for the builder.
                let guideSpans = try loft.guides.map { guide in
                    try spanBuilder.sectionSpans(from: ResolvedModelingSection.resolveCurve(
                        CurveSectionReference(featureID: guide.featureID), from: context.curves[guide.featureID], tolerance: context.tolerance))
                }
                boundarySpans.append(try ContinuousLoftEndSectionBuilder(tolerance: context.tolerance, admission: try correspondenceAllowance.conversionAdmission())
                    .endSection(of: boundarySpans[0], guides: guideSpans, featureID: feature.id))
                var end = loft.sections[0]
                end.section = .curve(CurveSectionReference(featureID: featureEvaluationStageID(featureID: feature.id, domain: .loftEndSection, ordinal: 0)))
                end.continuity = nil
                end.faceContinuity = nil
                end.startSampleIndex = nil
                lofted.sections.append(end)
                seamPoints.append(nil)
                originalContactLoops.append(nil)
            }
            guard boundarySpans.allSatisfy({ !$0.isEmpty }) else {
                throw FeatureEvaluationError.invalidGraph("Loft correspondence requires nonempty original boundary spans.")
            }
            if closed {
                let seamResolver = ExactLoftBodyBuilder(featureID: feature.id, context: context,
                    capContactValidator: capContactValidator, conversionAdmission: try correspondenceAllowance.conversionAdmission())
                for section in boundarySpans.indices {
                    if let seam = seamPoints[section] {
                        boundarySpans[section] = try seamResolver.boundarySpans(boundarySpans[section], startingAt: seam)
                    }
                }
            }
            if !closed, lofted.guides.isEmpty {
                let reversed = try LoftOpenCorrespondenceResolver().reversals(
                    endpoints: boundarySpans.map { ($0[0].startPoint, $0[$0.count - 1].endPoint) },
                    lockedSectionIndexes: Set(lofted.sections.indices.filter { index in
                        if case .curve = lofted.sections[index].section { return true }
                        return seamPoints[index] != nil || lofted.sections[index].profileDirection != .automatic
                    }),
                    closesSectionLoop: lofted.options.closesSectionLoop,
                    allowance: &correspondenceAllowance, tolerance: context.tolerance)
                for section in boundarySpans.indices where reversed[section] {
                    boundarySpans[section] = try boundarySpans[section].reversed().map {
                        try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: context.tolerance),
                            tolerance: context.tolerance, originalChart: $0.originalChart.reversed())
                    }
                }
            }
            if closed, lofted.guides.isEmpty {
                let targetCount = max(3, boundarySpans.map(\.count).max() ?? 0)
                let rings = try boundarySpans.map { spans in
                    try correspondenceAllowance.charge(targetCount)
                    return try exactMatchingRing(spans: spans, targetSampleCount: targetCount,
                        tolerance: context.tolerance)
                }
                let correspondence = try matchedEqualCountRings(rings,
                    lockedSectionIndexes: Set(seamPoints.indices.filter { seamPoints[$0] != nil }),
                    directions: lofted.sections.map(\.profileDirection),
                    lockedTraversalIndexes: Set(lofted.sections.indices.filter {
                        if case .curve = lofted.sections[$0].section { return true }
                        return false
                    }),
                    closesSectionLoop: lofted.options.closesSectionLoop,
                    tolerance: context.tolerance, allowance: &correspondenceAllowance)
                for section in boundarySpans.indices {
                    if correspondence.reversals[section] {
                        boundarySpans[section] = try boundarySpans[section].reversed().map {
                            try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: context.tolerance),
                                tolerance: context.tolerance, originalChart: $0.originalChart.reversed())
                        }
                    }
                    seamPoints[section] = correspondence.rings[section].first
                }
            }
            let guides = try ExactLoftGuideCurveResolver().resolve(guides: lofted.guides,
                sections: boundarySpans.indices.map {
                    ExactLoftGuideSection(loops: [boundarySpans[$0]],
                        originalContactLoops: originalContactLoops[$0])
                }, context: context, conversionAdmission: try correspondenceAllowance.conversionAdmission())
            return try ExactLoftBodyBuilder(featureID: feature.id, context: context, capContactValidator: capContactValidator, conversionAdmission: try correspondenceAllowance.conversionAdmission())
                .build(loft: lofted, boundarySpans: boundarySpans, isClosed: closed,
                    guideCurves: guides, seamPoints: seamPoints)
        }
        let originalRegions = try OriginalLoftRegionSections(loft: loft, featureID: feature.id,
            context: context, allowance: &correspondenceAllowance)
        let originalProfiles = originalRegions.profiles
        let guideCurves = try ExactLoftGuideCurveResolver().resolve(
            guides: loft.guides,
            sections: originalRegions.spans.indices.map {
                ExactLoftGuideSection(loops: originalRegions.spans[$0], originalContactLoops: originalRegions.contacts[$0])
            },
            context: context, conversionAdmission: try correspondenceAllowance.conversionAdmission()
        )
        let profiles = try resolvedCorrespondingProfiles(originalProfiles, guides: guideCurves,
            closesSectionLoop: loft.options.closesSectionLoop, tolerance: context.tolerance,
            allowance: &correspondenceAllowance, originalLoopSpans: originalRegions.spans)
        let orderedOriginalSpans = try originalRegions.reorderedSpans(for: profiles, allowance: &correspondenceAllowance)
        let matchedLoops = try resolvedMatchedLoops(
            from: profiles,
            originalLoopSpans: orderedOriginalSpans,
            sections: loft.sections,
            guides: guideCurves,
            smoothTangentScale: loft.options.smoothTangentScale,
            closesSectionLoop: loft.options.closesSectionLoop,
            tolerance: context.tolerance, allowance: &correspondenceAllowance
        )
        guard let outerMatched = matchedLoops.loops.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Loft requires at least one matched profile boundary loop."
            )
        }
        let rings = outerMatched.rings
        if loft.options.surfaceMode == .ruled, guideCurves.isEmpty {
            for loop in matchedLoops.loops {
                try validateParallelSectionTraversal(loop.rings,
                    closesSectionLoop: loft.options.closesSectionLoop,
                    tolerance: context.tolerance)
            }
        }
        let includesCaps = loft.options.resultKind == .solid
        let closesSectionLoop = loft.options.closesSectionLoop
        let faceOrientation = try sectionAdvanceFaceOrientation(
            rings: rings,
            includesCaps: includesCaps,
            closesSectionLoop: closesSectionLoop,
            tolerance: context.tolerance
        )

        return try ExactLoftBodyBuilder(
            featureID: feature.id,
            context: context, capContactValidator: capContactValidator,
            conversionAdmission: try correspondenceAllowance.conversionAdmission()
        ).build(
            loft: loft,
            profiles: profiles,
            originalLoopSpans: orderedOriginalSpans,
            matchedLoopRings: matchedLoops.loops.map(\.rings),
            sectionSeamPointsByLoop: matchedLoops.loops.map(\.exactSeamPoints),
            sectionTangentScales: outerMatched.smoothTangentScales,
            sectionTangentModes: outerMatched.smoothTangentModes,
            guideCurves: guideCurves,
            faceOrientation: faceOrientation
        )
    }

    private func resolvedMatchedLoops(
        from profiles: [Profile],
        originalLoopSpans: [[[ExactBSplineCurveSpan]]],
        sections: [LoftSectionReference],
        guides: [ExactLoftGuideCurve],
        smoothTangentScale: Double,
        closesSectionLoop: Bool,
        tolerance: ModelingTolerance, allowance: inout LoftCorrespondenceAllowance
    ) throws -> LoftMatchedLoopSet {
        guard let loopCount = profiles.first?.boundaryLoops.count,
              loopCount > 0,
              profiles.allSatisfy({ $0.boundaryLoops.count == loopCount }) else {
            throw KernelError(
                phase: .topology,
                code: .nonManifoldResult,
                tolerance: tolerance,
                message: "Every Loft section must preserve the same number of boundary loops."
            )
        }
        guard guides.allSatisfy({ $0.boundaryLoopIndex < loopCount }) else {
            throw FeatureEvaluationError.invalidGraph(
                "A Loft guide resolved to a boundary loop missing from another section."
            )
        }
        let matched = try (0..<loopCount).map { loopIndex in
            let loopProfiles = profiles.map { profile in
                Profile(
                    sourceFeatureID: profile.sourceFeatureID,
                    plane: profile.plane,
                    outerLoop: profile.boundaryLoops[loopIndex]
                )
            }
            let loopSections = sections.map { section in
                LoftSectionReference(
                    section: section.section,
                    profileDirection: section.profileDirection,
                    startSampleIndex: loopIndex == 0
                        ? section.startSampleIndex
                        : nil,
                    smoothTangentScale: section.smoothTangentScale,
                    smoothTangentMode: section.smoothTangentMode
                )
            }
            return try resolvedMatchedRings(
                from: loopProfiles,
                originalSpans: profiles.indices.map { originalLoopSpans[$0][loopIndex] },
                sections: loopSections,
                guides: guides.filter { $0.boundaryLoopIndex == loopIndex },
                smoothTangentScale: smoothTangentScale,
                closesSectionLoop: closesSectionLoop,
                tolerance: tolerance, allowance: &allowance
            )
        }
        return LoftMatchedLoopSet(loops: matched)
    }

    // Legacy facade-only resolver is unselected by the original region path.
    // Remove after deferred original face/region behavioral regression.
    @available(*, deprecated, message: "Use OriginalLoftRegionSections for original face laws.")
    private func resolvedProfiles(
        for loft: LoftFeature,
        context: EvaluationContext
    ) throws -> [Profile] {
        try loft.sections.map { section in
            switch section.section {
            case .profile(let reference):
                return try ResolvedModelingSection.resolveProfile(reference, from: context.profiles[reference.featureID])
            case .face(let reference):
                // A planar face lofts as the profile it bounds, read where its body is.
                return try FaceSectionProfileResolver().profile(for: reference, context: context, featureID: reference.featureID)
            case .curve:
                throw FeatureEvaluationError.invalidGraph("Profile Loft dispatch requires closed-region sections.")
            }
        }
    }

    private func resolvedCorrespondingProfiles(
        _ profiles: [Profile], guides: [ExactLoftGuideCurve], closesSectionLoop: Bool,
        tolerance: ModelingTolerance, allowance: inout LoftCorrespondenceAllowance,
        originalLoopSpans: [[[ExactBSplineCurveSpan]]]
    ) throws -> [Profile] {
        guard let holeCount = profiles.first?.innerLoops.count,
              profiles.allSatisfy({ $0.innerLoops.count == holeCount }) else {
            let counts = profiles.map { $0.innerLoops.count }
            throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                message: "Loft hole counts \(counts) differ; no original correspondence identifies a hole birth or death.")
        }
        try allowance.charge(profiles.count)
        var required = Array(repeating: [Int: Int](), count: profiles.count)
        for guide in guides where guide.boundaryLoopIndex > 0 {
            guard guide.sectionBoundaryLoopIndexes.count == profiles.count else {
                throw FeatureEvaluationError.invalidGraph("A Loft guide is missing its original section boundary identities.")
            }
            let canonical = guide.boundaryLoopIndex - 1
            for section in profiles.indices {
                try allowance.charge(1)
                let original = guide.sectionBoundaryLoopIndexes[section] - 1
                guard original >= 0, original < holeCount,
                      required[section][canonical] == nil || required[section][canonical] == original else {
                    throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                        message: "Original Loft guide contacts prescribe incompatible hole identities.")
                }
                required[section][canonical] = original
            }
        }
        guard holeCount > 1 else { return profiles }
        var spans: [[[ExactBSplineCurveSpan]]] = []
        for (section, profile) in profiles.enumerated() {
            // Source control and knot scans are charged before constructing exact
            // section partitions; display sample density is not the objective.
            for loop in profile.innerLoops {
                try allowance.charge(loop.vertices.count)
                for segment in loop.boundarySegments {
                    switch segment {
                    case .line: try allowance.charge(2)
                    case .circularArc: try allowance.charge(4)
                    case .spline(let spline):
                        try allowance.charge(spline.curve.controlPoints.count)
                        try allowance.charge(spline.curve.knots.count)
                    }
                }
            }
            spans.append(Array(originalLoopSpans[section].dropFirst()))
        }
        let targetCount = max(3, spans.flatMap { $0.map(\.count) }.max() ?? 0)
        var rings: [[[Point3D]]] = []
        for section in spans {
            try allowance.charge(section.count)
            var sectionRings: [[Point3D]] = []
            for hole in section {
                try allowance.charge(targetCount)
                for span in hole { try allowance.charge(span.curve.controlPoints.count) }
                sectionRings.append(try exactMatchingRing(spans: hole,
                    targetSampleCount: targetCount, tolerance: tolerance))
            }
            rings.append(sectionRings)
        }
        let mapping = try LoftHoleCorrespondenceResolver().resolve(ringsBySection: rings,
            requiredMappings: required, closesSectionLoop: closesSectionLoop,
            allowance: &allowance, tolerance: tolerance)
        try allowance.charge(profiles.count)
        return profiles.indices.map { section in
            var profile = profiles[section]
            profile.innerLoops = mapping[section].map { profiles[section].innerLoops[$0] }
            return profile
        }
    }

    private func resolvedMatchedRings(
        from profiles: [Profile],
        originalSpans: [[ExactBSplineCurveSpan]],
        sections: [LoftSectionReference],
        guides: [ExactLoftGuideCurve],
        smoothTangentScale: Double,
        closesSectionLoop: Bool,
        tolerance: ModelingTolerance, allowance: inout LoftCorrespondenceAllowance
    ) throws -> LoftMatchedRings {
        guard let first = profiles.first else {
            throw FeatureEvaluationError.invalidGraph("Loft requires at least one resolved profile.")
        }
        guard profiles.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft resolved profile count must match the section count.")
        }
        let vertexCount = first.vertices.count
        guard vertexCount >= 3 else {
            throw SketchError.openProfile
        }
        guard guides.allSatisfy({
            $0.sectionPoints.count == profiles.count
                && $0.sectionContacts.count == profiles.count
        }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Every exact Loft guide must provide one ordered contact per section."
            )
        }
        var exactSections: [[ExactBSplineCurveSpan]] = []
        exactSections.reserveCapacity(profiles.count)
        for (sectionIndex, values) in zip(sections, profiles).enumerated() {
            let (section, profile) = values
            if let startSampleIndex = section.startSampleIndex,
               profile.vertices.indices.contains(startSampleIndex) == false {
                throw FeatureEvaluationError.invalidGraph("Loft section start sample indexes must reference existing section samples.")
            }
            try validateClosedRing(profile.vertices, tolerance: tolerance)
            let guidePoints = guides.map { $0.sectionPoints[sectionIndex] }
            let seamPoint = section.startSampleIndex.map { profile.vertices[$0] }
                ?? guidePoints.first
            let spans = try exactMatchingSpans(
                profile: profile,
                originalSpans: originalSpans[sectionIndex],
                seamPoint: seamPoint,
                partitionPoints: guidePoints,
                tolerance: tolerance
            )
            exactSections.append(try directedProfileSpans(spans, direction: section.profileDirection, tolerance: tolerance))
        }
        let sectionTangentScales = sections.map { section in
            section.smoothTangentScale ?? smoothTangentScale
        }
        let sectionTangentModes = sections.map(\.smoothTangentMode)
        let guidePointsBySection = profiles.indices.map { sectionIndex in
            guides.map { $0.sectionPoints[sectionIndex] }
        }
        let rings = try exactCorrespondenceRings(
            sections: exactSections,
            guidePointsBySection: guidePointsBySection,
            tolerance: tolerance
        )
        let matched: [[Point3D]]
        if guides.isEmpty {
            let lockedSectionIndexes = Set(
                sections.indices.filter { sections[$0].startSampleIndex != nil }
            )
            matched = try matchedEqualCountRings(
                rings,
                lockedSectionIndexes: lockedSectionIndexes,
                directions: sections.map(\.profileDirection),
                closesSectionLoop: closesSectionLoop,
                tolerance: tolerance, allowance: &allowance
            ).rings
        } else {
            matched = rings
        }
        return LoftMatchedRings(
            rings: matched,
            smoothTangentScales: sectionTangentScales,
            smoothTangentModes: sectionTangentModes,
            exactSeamPoints: matched.map { $0.first }
        )
    }

    private func exactMatchingSpans(
        profile: Profile,
        originalSpans: [ExactBSplineCurveSpan],
        seamPoint: Point3D?,
        partitionPoints: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [ExactBSplineCurveSpan] {
        var spans = originalSpans
        for point in partitionPoints {
            spans = try spansSplit(
                spans,
                at: point,
                tolerance: tolerance
            )
        }
        guard let seamPoint else {
            return spans
        }
        for index in spans.indices {
            if spans[index].startPoint.isApproximatelyEqual(
                to: seamPoint,
                tolerance: tolerance.distance
            ) {
                return rotatedSpans(spans, offset: index)
            }
            if spans[index].endPoint.isApproximatelyEqual(
                to: seamPoint,
                tolerance: tolerance.distance
            ) {
                return rotatedSpans(spans, offset: (index + 1) % spans.count)
            }
        }

        for index in spans.indices {
            let projection: CurveParameterProjection
            do {
                projection = try Curve3D.bSpline(spans[index].curve)
                    .parameterProjection(of: seamPoint, tolerance: tolerance)
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
            guard projection.residual <= tolerance.distance,
                  case let .closed(lower, upper) = spans[index].curve.domain else {
                continue
            }
            let resolution = max(
                tolerance.relative * max(abs(lower), abs(upper), 1.0),
                Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 256.0
            )
            guard projection.parameter > lower + resolution,
                  projection.parameter < upper - resolution else {
                continue
            }
            let tail = try ExactBSplineCurveSpan(
                curve: spans[index].curve.trimmed(
                    from: projection.parameter,
                    to: upper,
                    tolerance: tolerance
                ),
                tolerance: tolerance,
                originalChart: try spans[index].originalChart.restricted(from: projection.parameter, to: upper,
                    in: spans[index].curve.domain, tolerance: tolerance)
            )
            let head = try ExactBSplineCurveSpan(
                curve: spans[index].curve.trimmed(
                    from: lower,
                    to: projection.parameter,
                    tolerance: tolerance
                ),
                tolerance: tolerance,
                originalChart: try spans[index].originalChart.restricted(from: lower, to: projection.parameter,
                    in: spans[index].curve.domain, tolerance: tolerance)
            )
            var result = [tail]
            if spans.count > 1 {
                var cursor = (index + 1) % spans.count
                while cursor != index {
                    result.append(spans[cursor])
                    cursor = (cursor + 1) % spans.count
                }
            }
            result.append(head)
            return result
        }
        throw KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message:
            "Loft section seam sample does not lie on its exact profile boundary.",
        )
    }

    private func spansSplit(
        _ spans: [ExactBSplineCurveSpan],
        at point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> [ExactBSplineCurveSpan] {
        if spans.contains(where: { span in
            span.startPoint.isApproximatelyEqual(
                to: point,
                tolerance: tolerance.distance
            ) || span.endPoint.isApproximatelyEqual(
                to: point,
                tolerance: tolerance.distance
            )
        }) {
            return spans
        }
        var best: (index: Int, projection: CurveParameterProjection)?
        for index in spans.indices {
            do {
                let projection = try Curve3D.bSpline(spans[index].curve)
                    .parameterProjection(of: point, tolerance: tolerance)
                if best.map({ projection.residual < $0.projection.residual }) ?? true {
                    best = (index, projection)
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        guard let best,
              best.projection.residual <= tolerance.distance,
              case let .closed(lower, upper) = spans[best.index].curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A Loft guide contact does not lie on its exact section boundary."
            )
        }
        let resolution = max(
            tolerance.relative * max(abs(lower), abs(upper), 1.0),
            Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 256.0
        )
        guard best.projection.parameter > lower + resolution,
              best.projection.parameter < upper - resolution else {
            return spans
        }
        let head = try ExactBSplineCurveSpan(
            curve: spans[best.index].curve.trimmed(
                from: lower,
                to: best.projection.parameter,
                tolerance: tolerance
            ),
            tolerance: tolerance,
                originalChart: try spans[best.index].originalChart.restricted(from: lower, to: best.projection.parameter,
                    in: spans[best.index].curve.domain, tolerance: tolerance)
        )
        let tail = try ExactBSplineCurveSpan(
            curve: spans[best.index].curve.trimmed(
                from: best.projection.parameter,
                to: upper,
                tolerance: tolerance
            ),
            tolerance: tolerance,
                originalChart: try spans[best.index].originalChart.restricted(from: best.projection.parameter, to: upper,
                    in: spans[best.index].curve.domain, tolerance: tolerance)
        )
        var result = Array(spans[..<best.index])
        result.append(head)
        result.append(tail)
        result.append(contentsOf: spans[(best.index + 1)...])
        return result
    }

    private func exactCorrespondenceRings(
        sections: [[ExactBSplineCurveSpan]],
        guidePointsBySection: [[Point3D]],
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        guard sections.count == guidePointsBySection.count,
              let firstSection = sections.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft correspondence requires one guide-contact set per section."
            )
        }
        guard guidePointsBySection.contains(where: { $0.isEmpty == false }) else {
            let targetCount = max(3, sections.map(\.count).max() ?? firstSection.count)
            return try sections.map { spans in
                let ring = try exactMatchingRing(
                    spans: spans,
                    targetSampleCount: targetCount,
                    tolerance: tolerance
                )
                try validateClosedRing(ring, tolerance: tolerance)
                return ring
            }
        }
        guard let guideCount = guidePointsBySection.first?.count,
              guidePointsBySection.allSatisfy({ $0.count == guideCount }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft sections require one contact for every guide."
            )
        }
        let guideIndexes = try sections.indices.map { sectionIndex in
            try guidePointsBySection[sectionIndex].map { point in
                guard let index = sections[sectionIndex].firstIndex(where: { span in
                    span.startPoint.isApproximatelyEqual(
                        to: point,
                        tolerance: tolerance.distance
                    )
                }) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A Loft guide contact is not an exact section partition vertex."
                    )
                }
                return index
            }
        }
        for indexes in guideIndexes where Set(indexes).count != indexes.count {
            throw FeatureEvaluationError.invalidGraph(
                "Loft guide curves must constrain distinct section boundary positions."
            )
        }
        let canonicalOrder = guideIndexes[0].indices.sorted {
            guideIndexes[0][$0] < guideIndexes[0][$1]
        }
        for indexes in guideIndexes.dropFirst() {
            let order = indexes.indices.sorted { indexes[$0] < indexes[$1] }
            guard order == canonicalOrder else {
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    tolerance: tolerance,
                    message: "Loft guide contacts must preserve their cyclic boundary order across sections."
                )
            }
        }
        let boundaries = sections.indices.map { sectionIndex in
            [0]
                + guideIndexes[sectionIndex]
                    .filter { $0 > 0 }
                    .sorted()
                + [sections[sectionIndex].count]
        }
        guard let intervalCount = boundaries.first.map({ $0.count - 1 }),
              boundaries.allSatisfy({ $0.count == intervalCount + 1 }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft guide partitions do not share one interval count."
            )
        }
        let targetCounts = (0..<intervalCount).map { intervalIndex in
            boundaries.indices.map { sectionIndex in
                boundaries[sectionIndex][intervalIndex + 1]
                    - boundaries[sectionIndex][intervalIndex]
            }.max() ?? 0
        }
        return try sections.indices.map { sectionIndex in
            var ring: [Point3D] = []
            for intervalIndex in 0..<intervalCount {
                let lower = boundaries[sectionIndex][intervalIndex]
                let upper = boundaries[sectionIndex][intervalIndex + 1]
                ring.append(contentsOf: try exactMatchingRing(
                    spans: Array(sections[sectionIndex][lower..<upper]),
                    targetSampleCount: targetCounts[intervalIndex],
                    tolerance: tolerance
                ))
            }
            try validateClosedRing(ring, tolerance: tolerance)
            return ring
        }
    }

    private func exactMatchingRing(
        spans: [ExactBSplineCurveSpan],
        targetSampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard spans.isEmpty == false,
              targetSampleCount >= spans.count else {
            throw SketchError.openProfile
        }
        let insertedCounts = apportionedCounts(
            weights: spans.map { span in
                zip(
                    span.curve.controlPoints,
                    span.curve.controlPoints.dropFirst()
                ).reduce(0.0) { partial, pair in
                    partial + (pair.1 - pair.0).length
                }
            },
            total: targetSampleCount - spans.count
        )
        var result: [Point3D] = []
        result.reserveCapacity(targetSampleCount)
        for index in spans.indices {
            let span = spans[index]
            result.append(span.startPoint)
            guard insertedCounts[index] > 0,
                  case let .closed(lower, upper) = span.curve.domain else {
                continue
            }
            for step in 1...insertedCounts[index] {
                let ratio = Double(step) / Double(insertedCounts[index] + 1)
                result.append(try span.curve.point(
                    at: lower + (upper - lower) * ratio,
                    tolerance: tolerance
                ))
            }
        }
        guard result.count == targetSampleCount else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft section matching did not produce its target correspondence count."
            )
        }
        return result
    }

    private func directedProfileSpans(_ spans: [ExactBSplineCurveSpan], direction: LoftProfileDirection,
        tolerance: ModelingTolerance) throws -> [ExactBSplineCurveSpan] {
        guard direction == .reversed else { return spans }
        return try spans.reversed().map {
            try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: tolerance), tolerance: tolerance,
                    originalChart: $0.originalChart.reversed())
        }
    }

    private func validateParallelSectionTraversal(_ rings: [[Point3D]],
        closesSectionLoop: Bool, tolerance: ModelingTolerance) throws {
        let normals = try rings.map { try ringWindingNormal($0, tolerance: tolerance) }
        let connectionCount = normals.count - (closesSectionLoop ? 0 : 1)
        for index in 0..<connectionCount {
            let next = normals[(index + 1) % normals.count]
            if normals[index].cross(next).length <= tolerance.angle,
               normals[index].dot(next) < 0 {
                throw KernelError(phase: .geometry, code: .singularGeometry,
                    tolerance: tolerance,
                    message: "Parallel ruled Loft sections have opposing traversal; their interpolation must collapse or self-intersect.")
            }
        }
    }

    private func matchedEqualCountRings(
        _ rings: [[Point3D]],
        lockedSectionIndexes: Set<Int>,
        directions: [LoftProfileDirection],
        lockedTraversalIndexes: Set<Int> = [],
        closesSectionLoop: Bool,
        tolerance: ModelingTolerance, allowance: inout LoftCorrespondenceAllowance
    ) throws -> LoftRingCorrespondence {
        guard let reference = rings.first, reference.count >= 3,
              directions.count == rings.count,
              rings.allSatisfy({ $0.count == reference.count }) else {
            throw FeatureEvaluationError.invalidGraph("Exact Loft correspondence requires equal nonempty rings and directions.")
        }
        let count = reference.count
        let centers = rings.map { ring in
            ring.reduce(Point3D.origin) { sum, point in
                sum + (point - Point3D.origin) / Double(count)
            }
        }
        let advances = try rings.indices.map { index -> Double in
            let previous = index == 0 ? (closesSectionLoop ? rings.count - 1 : 0) : index - 1
            let next = index == rings.count - 1 ? (closesSectionLoop ? 0 : index) : index + 1
            return try ringWindingNormal(rings[index], tolerance: tolerance)
                .dot(centers[next] - centers[previous])
        }
        var reversalsBySection = [[false]]
        for index in rings.indices.dropFirst() {
            if directions[index] != .automatic || lockedTraversalIndexes.contains(index) {
                reversalsBySection.append([false])
            } else if closesSectionLoop,
                      abs(advances[0]) > tolerance.distance, abs(advances[index]) > tolerance.distance {
                reversalsBySection.append([(advances[0] > 0) != (advances[index] > 0)])
            } else {
                reversalsBySection.append([false, true])
            }
        }
        return try LoftRingCorrespondenceResolver().correspondence(
            rings: rings, reversalsBySection: reversalsBySection,
            lockedSectionIndexes: lockedSectionIndexes,
            closesSectionLoop: closesSectionLoop, tolerance: tolerance, allowance: &allowance)
    }

    private func rotatedSpans<T>(_ spans: [T], offset: Int) -> [T] {
        spans.indices.map { index in
            spans[(index + offset) % spans.count]
        }
    }

    /// Loft rings are extracted counterclockwise about their sketch normal, so
    /// the generated loop windings (reversed start cap, forward end cap, and
    /// ring-tangent-by-advance side patches) face out of the material only when
    /// each section connection advances along its ring's winding normal. When
    /// every connection advances against it the shell is uniformly inside-out,
    /// so the faces are marked reversed for meshing and volume integration,
    /// mirroring the extrude evaluator's extrusionSign. A mixed-sign stack
    /// cannot be represented by one shell orientation and is rejected.
    private func sectionAdvanceFaceOrientation(
        rings: [[Point3D]],
        includesCaps: Bool,
        closesSectionLoop: Bool,
        tolerance: ModelingTolerance
    ) throws -> Orientation {
        guard includesCaps, closesSectionLoop == false, rings.count >= 2 else {
            return .forward
        }
        var hasForwardAdvance = false
        var hasReversedAdvance = false
        for sectionIndex in 0..<(rings.count - 1) {
            let windingNormal = try ringWindingNormal(
                rings[sectionIndex],
                tolerance: tolerance
            )
            let advance = averageRingOffset(
                from: rings[sectionIndex],
                to: rings[sectionIndex + 1]
            ).dot(windingNormal)
            if advance > tolerance.distance {
                hasForwardAdvance = true
            } else if advance < -tolerance.distance {
                hasReversedAdvance = true
            }
        }
        if hasForwardAdvance, hasReversedAdvance {
            throw KernelError(
                phase: .topology,
                code: .nonManifoldResult,
                tolerance: tolerance,
                message: "A mixed-direction solid Loft section stack folds back through one shell and cannot produce a consistently oriented manifold boundary."
            )
        }
        return hasReversedAdvance ? .reversed : .forward
    }

    private func ringWindingNormal(
        _ ring: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        // Newell's method: follows the ring winding regardless of concave corners.
        let origin = ring[0]
        var areaVector = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        for index in ring.indices {
            let current = ring[index] - origin
            let next = ring[(index + 1) % ring.count] - origin
            areaVector = areaVector + current.cross(next)
        }
        // Cross products measure area, so compare them with a squared length.
        return try areaVector.normalized(tolerance: tolerance.distance * tolerance.distance)
    }

    private func averageRingOffset(
        from first: [Point3D],
        to second: [Point3D]
    ) -> Vector3D {
        guard first.count == second.count, first.isEmpty == false else {
            return Vector3D(x: 0.0, y: 0.0, z: 0.0)
        }
        var sum = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        for pair in zip(first, second) {
            sum = sum + (pair.1 - pair.0)
        }
        return sum * (1.0 / Double(first.count))
    }

    private func apportionedCounts(weights: [Double], total: Int) -> [Int] {
        let weightSum = weights.reduce(0.0, +)
        guard total > 0, weightSum > 0.0 else {
            return Array(repeating: 0, count: weights.count)
        }
        var counts = Array(repeating: 0, count: weights.count)
        var remainders: [(index: Int, remainder: Double)] = []
        var assigned = 0
        for index in weights.indices {
            let exact = Double(total) * weights[index] / weightSum
            let wholePart = Int(exact.rounded(.down))
            counts[index] = wholePart
            assigned += wholePart
            remainders.append((index, exact - Double(wholePart)))
        }
        remainders.sort { lhs, rhs in
            if lhs.remainder != rhs.remainder {
                return lhs.remainder > rhs.remainder
            }
            return lhs.index < rhs.index
        }
        for entry in remainders.prefix(total - assigned) {
            counts[entry.index] += 1
        }
        return counts
    }

    private func validateClosedRing(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) throws {
        guard points.count >= 3 else {
            throw SketchError.openProfile
        }
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            guard points[index].isApproximatelyEqual(to: points[nextIndex], tolerance: tolerance.distance) == false else {
                throw SketchError.degenerateProfile
            }
        }
    }

}

private struct LoftMatchedRings: Sendable, Hashable {
    var rings: [[Point3D]]
    var smoothTangentScales: [Double]
    var smoothTangentModes: [LoftSectionSmoothTangentMode]
    var exactSeamPoints: [Point3D?]
}

private struct LoftMatchedLoopSet: Sendable, Hashable {
    var loops: [LoftMatchedRings]
}
