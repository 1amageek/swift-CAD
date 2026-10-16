import HashTreeCollections
#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing
    private let booleanApplicator: (any SweepBooleanApplying)?
    private let targetRelocator: (any ExactBodyPatternRebuilding)?
    private let generatedResultValidator: (any OffsetResultValidating)?

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: (any SweepBooleanApplying)? = nil,
        generatedResultValidator: (any OffsetResultValidating)? = nil
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = nil
        self.generatedResultValidator = generatedResultValidator
    }

    /// An evaluator that also moves placed Boolean targets into the extrusion's frame with
    /// `targetRelocator`, as a Boolean moves its placed operands.
    package init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: any SweepBooleanApplying,
        targetRelocator: any ExactBodyPatternRebuilding,
        generatedResultValidator: (any OffsetResultValidating)? = nil
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = targetRelocator
        self.generatedResultValidator = generatedResultValidator
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
        var execution = try CurvedSweepSourceBudget(tolerance: context.tolerance).execution()
        return try evaluateValidated(feature: feature, context: context, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The feature dispatcher uses this entry
    // for the selected original source construction. Existing request/expression
    // or staged feature branches still need their own direct contract; this
    // binding must not be counted as complete whole-feature U1 accounting.
    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> ValidatedFeatureEvaluation {
        try context.tolerance.validate()
        guard case let .extrude(extrude) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarExtrudeFeatureEvaluator only supports extrude."
            )
        }
        try extrude.validate()
        let range = try extrude.resolvedAxialRange(tolerance: context.tolerance) {
            try resolver.evaluate($0, parameters: context.parameters, variables: [:])
        }
        let span = range.upperBound - range.lowerBound
        var draftTangent = 0.0
        var sourceDraftAngle = 0.0
        if let draftAngle = extrude.draftAngle {
            let quantity = try resolver.evaluate(draftAngle, parameters: context.parameters, variables: [:])
            guard quantity.kind == .angle, quantity.value.isFinite, abs(quantity.value) < Double.pi / 2 - context.tolerance.angle else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                                  message: "An extrusion's draft is an angle under 90 degrees.")
            }
            sourceDraftAngle = quantity.value
            draftTangent = quantity.value == 0 ? 0 : tan(quantity.value)
        }
        var wallThickness = 0.0
        if let thickness = extrude.thickness {
            let quantity = try resolver.evaluate(thickness, parameters: context.parameters, variables: [:])
            guard quantity.kind == .length, quantity.value.isFinite, quantity.value > context.tolerance.distance else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                                  message: "An extrusion's wall thickness must be a positive length.")
            }
            wallThickness = quantity.value
        }
        // A placed Boolean target moves into the extrusion's frame first, as a staged body, the
        // way a Boolean moves its placed operands; the tool is built beside it.
        var stages = FeatureEvaluationStages(context)
        var targetBodyIDs: [BodyID] = []
        if extrude.operation != .newBody {
            targetBodyIDs = try PlacedBooleanTargetStager(relocator: targetRelocator).stage(
                extrude.targets, featureID: feature.id, stablePrefix: "extrude:placedTarget", stages: &stages, what: "an extrusion"
            )
        }
        // A face section is read where its face is before any target moves.
        var faceSection: ResolvedFaceSection?
        if case let .face(reference) = extrude.section {
            faceSection = try FaceSectionProfileResolver().resolve(for: reference,
                context: context, featureID: feature.id, using: &execution)
        }
        let context = stages.context
        var result: EvaluationResult
        switch extrude.section {
        case .profile, .face:
            if extrude.resultKind == .sheet, wallThickness == 0 {
                let section: ResolvedModelingSection
                let plane: SketchPlane
                if let faceSection {
                    section = .face(faceSection, extrude.section)
                    plane = faceSection.plane
                } else if case .profile(let reference) = extrude.section {
                    let profile = try ResolvedModelingSection.resolveProfile(reference,
                        from: context.profiles[reference.featureID])
                    section = .profile(profile, extrude.section)
                    plane = profile.plane
                } else {
                    throw FeatureEvaluationError.missingInput("An original sheet section was not read.")
                }
                let loops = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance,
                    using: &execution).loopSpans(from: section, using: &execution)
                result = try originalRegionSheet(loops: loops, plane: plane,
                    direction: extrude.direction,
                    lowerHeight: extrude.direction == .symmetric ? -0.5 * span : range.lowerBound,
                    distance: span, pull: extrude.draftDirection, angle: sourceDraftAngle,
                    featureID: feature.id, using: &execution, context: context)
                break
            }
            if let faceSection, draftTangent == 0, extrude.draftDirection == nil, wallThickness == 0 {
                let plane = try ExactSweepSectionPlane(faceSection.plane, tolerance: context.tolerance).plane
                let axis: Vector3D
                switch extrude.direction {
                case .normal, .symmetric: axis = plane.normal
                case .vector(let direction): axis = try direction.normalized(tolerance: context.tolerance.distance)
                }
                result = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id,
                    context: context, sewer: sewer)
                    .buildTranslatedFace(faceSection, axis: axis,
                        lowerHeight: extrude.direction == .symmetric ? -0.5 * span : range.lowerBound,
                        distance: span, resultKind: extrude.resultKind == .solid ? .solid : .sheet, using: &execution)
                break
            }
            let profile: Profile
            if case let .profile(reference) = extrude.section {
                profile = try ResolvedModelingSection.resolveProfile(reference, from: context.profiles[reference.featureID])
            } else if let faceSection {
                profile = faceSection.profile
            } else {
                throw FeatureEvaluationError.missingInput("An extrusion's face section was not read.")
            }
            result = try ExactProfileExtrudeBodyBuilder(
                featureID: feature.id,
                context: context,
                sewer: sewer
            ).build(
                from: profile,
                direction: extrude.direction,
                distance: span,
                startOffset: range.lowerBound,
                bodyKind: extrude.resultKind == .solid ? .solid : .sheet,
                includesCaps: extrude.resultKind == .solid,
                draftTangent: draftTangent,
                draftDirection: extrude.draftDirection,
                wallThickness: wallThickness,
                sourceDraftAngle: sourceDraftAngle,
                originalFaceSection: faceSection
            , using: &execution)
        case .curve(let reference):
            let curve = try ResolvedModelingSection.resolveCurve(
                reference, from: context.curves[reference.featureID], tolerance: context.tolerance,
                using: &execution
            )
            // A closed curve drafted or thin is its region's drafted wall or thin ring.
            if curve.isClosed, draftTangent != 0 || extrude.draftDirection != nil || wallThickness > 0 {
                let region = try closedCurveProfile(curve, featureID: feature.id,
                    tolerance: context.tolerance, using: &execution)
                if wallThickness == 0 {
                    result = try originalClosedCurveSheet(curve: curve, spans: region.originalSpans,
                        direction: extrude.direction, lowerHeight: extrude.direction == .symmetric ? -0.5 * span : range.lowerBound,
                        distance: span, pull: extrude.draftDirection, angle: sourceDraftAngle,
                        featureID: feature.id, using: &execution, context: context)
                    break
                }
                result = try ExactProfileExtrudeBodyBuilder(featureID: feature.id, context: context,
                    sewer: sewer).build(
                    from: region.profile, direction: extrude.direction,
                    distance: span, startOffset: range.lowerBound, bodyKind: wallThickness > 0 ? .solid : .sheet,
                    includesCaps: wallThickness > 0, draftTangent: draftTangent,
                    draftDirection: extrude.draftDirection, wallThickness: wallThickness,
                    sourceDraftAngle: sourceDraftAngle,
                    originalCurveSpans: region.originalSpans
                , using: &execution)
                break
            }
            if draftTangent != 0 || extrude.draftDirection != nil {
                result = try draftedCurveSheet(curve, feature: feature, direction: extrude.direction, distance: span,
                                               startOffset: range.lowerBound, tangent: draftTangent,
                                               draftDirection: extrude.draftDirection, sourceDraftAngle: sourceDraftAngle,
                                               using: &execution, context: context)
            } else {
                result = try evaluateCurveSheet(
                    curve, featureID: feature.id, direction: extrude.direction,
                    distance: span, startOffset: range.lowerBound, using: &execution, context: context
                )
            }
            if wallThickness > 0 {
                let axis = try curveAxis(curve, featureID: feature.id, direction: extrude.direction, context: context)
                result = try thickened(result, curve: curve, axis: axis, thickness: wallThickness, featureID: feature.id, context: context)
            }
        }
        if extrude.operation != .newBody {
            guard let booleanApplicator,
                  let operation = SweepBooleanOperation(rawValue: extrude.operation.rawValue) else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance,
                    message: "Extrusion Boolean evaluation requires a Boolean applicator.")
            }
            let toolReference = SubshapeID(featureID: feature.id,
                role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
            guard case let .body(toolID) = result.subshapes[toolReference] else {
                throw FeatureEvaluationError.missingInput("Extrusion tool body was not generated.")
            }
            result = try booleanApplicator.apply(operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolID, keepTools: extrude.keepTools, featureID: feature.id,
                toolResult: result, targetSubshapes: context.subshapes.entries,
                inputLineage: context.lineage, tolerance: context.tolerance)
            if stages.isEmpty == false {
                result = try stages.publish(result, featureID: feature.id)
            }
        }
        return try ValidatedFeatureEvaluation(
            planarExtrusion: result,
            tolerance: context.tolerance, using: &execution
        )
    }

    /// Keeps the closed curve's raw directed spans independently of its facade.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Thin material offsets still consume
    // this compatibility Profile. Non-thin authored draft uses originalSpans
    // directly; final wall source and thin original offset/joint publication
    // remain necessary before general closed-curve extrusion is complete.
    private func closedCurveProfile(_ curve: EvaluatedCurve, featureID: FeatureID,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
        -> (profile: Profile, originalSpans: [ExactBSplineCurveSpan]) {
        guard let plane = curve.plane else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID,
                tolerance: tolerance, message: "A closed drafted or thin curve requires its original section plane.")
        }
        let selected = try curve.validateOriginalGeometry(tolerance: tolerance, using: &execution)
        let lower = selected.startParameter, upper = selected.endParameter
        guard lower.isFinite, upper.isFinite, lower < upper,
            try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth)
                .kind(curve: selected.curve, from: lower, to: upper, tolerance: tolerance, using: &execution) == .closed else {
            throw KernelError(phase: .geometry, code: .topologyFailure, featureID: featureID,
                tolerance: tolerance, message: "A closed draft region requires original endpoint or periodic closure authority.")
        }
        let originalPlane = try ExactSweepSectionPlane(plane, tolerance: tolerance).plane
        let source = try OriginalCurveSpanSource(curve: selected.curve, tolerance: tolerance, using: &execution)
        let counterclockwise = try OriginalPlanarLoopOrientation().counterclockwise(source: source,
            startParameter: lower, endParameter: upper, origin: originalPlane.origin,
            normal: originalPlane.normal, tolerance: tolerance, using: &execution)
        let middle = lower * 0.5 + upper * 0.5
        guard middle > lower, middle < upper else {
            throw GeometryConversionError.resourceLimitExceeded("Original closed region has no representable interior split station.")
        }
        let builder = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, using: &execution)
        let first = try builder.sectionSpans(sourceOwner: source, lower: lower, upper: middle, using: &execution)
        let second = try builder.sectionSpans(sourceOwner: source, lower: middle, upper: upper, using: &execution)
        let count = first.count.addingReportingOverflow(second.count)
        let payload = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<ExactBSplineCurveSpan>.stride)
        guard !count.overflow, !payload.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original closed-region span payload overflows.")
        }
        try execution.retainStorage(bytes: payload.partialValue)
        var spans: [ExactBSplineCurveSpan] = []
        spans.reserveCapacity(count.partialValue)
        if counterclockwise {
            for span in first { try execution.consumeWork(1); spans.append(span) }
            for span in second { try execution.consumeWork(1); spans.append(span) }
        } else {
            for span in second.reversed() {
                try execution.consumeWork(1)
                spans.append(try builder.normalizedConstructionSpan(from: span.originalChart.reversed(), using: &execution))
            }
            for span in first.reversed() {
                try execution.consumeWork(1)
                spans.append(try builder.normalizedConstructionSpan(from: span.originalChart.reversed(), using: &execution))
            }
        }
        let display = try CurveTrimFeatureEvaluator().trimmedCurve(featureID: curve.sourceFeatureID,
            source: curve, domain: .closed(lower, upper), tolerance: tolerance, using: &execution)
        try execution.retainStorage(bytes: (display.points.count - 1) * MemoryLayout<Point3D>.stride)
        var vertices: [Point3D] = []
        vertices.reserveCapacity(display.points.count - 1)
        for index in 0..<(display.points.count - 1) {
            try execution.consumeWork(1)
            vertices.append(display.points[counterclockwise || index == 0 ? index
                : display.points.count - 1 - index])
        }
        let boundaries: [ProfileBoundarySegment]
        let circle: Circle3D?
        switch selected.curve {
        case .circle(let value): circle = value
        case .analytic(.circle(let center, let normal, let radius)):
            circle = Circle3D(center: center, normal: normal, radius: radius)
        default: circle = nil
        }
        if let circle, let start = display.points.first {
            // Preserve the ideal circular facade for the existing thin-circle
            // route. Non-thin draft still consumes the retained raw spans.
            try execution.retainStorage(bytes: 2 * MemoryLayout<ProfileBoundarySegment>.stride)
            try execution.consumeWork(2)
            let opposite = circle.center + (circle.center - start)
            boundaries = [.circularArc(.init(center: circle.center, normal: originalPlane.normal,
                radius: circle.radius, start: start, end: opposite, sweepAngle: Double.pi)),
                .circularArc(.init(center: circle.center, normal: originalPlane.normal,
                radius: circle.radius, start: opposite, end: start, sweepAngle: Double.pi))]
        } else {
            try execution.retainStorage(bytes: spans.count * MemoryLayout<ProfileBoundarySegment>.stride)
            boundaries = try spans.map { span -> ProfileBoundarySegment in
                try execution.consumeWork(1)
                return .spline(ProfileSplineSegment(curve: span.curve))
            }
        }
        let profile = Profile(sourceFeatureID: curve.sourceFeatureID, plane: plane,
            vertices: vertices, boundarySegments: boundaries)
        return (profile, spans)
    }

    /// An open curve's drafted sheet: the curve at each end height moved toward its left by the
    /// height times the draft's tangent (one taper through the sketch plane), and the surface
    /// ruled between them.
    private func draftedCurveSheet(_ curve: EvaluatedCurve, feature: FeatureNode, direction: ExtrudeDirection, distance: Double,
                                   startOffset: Double, tangent: Double, draftDirection: Vector3D?,
                                   sourceDraftAngle: Double, using execution: inout OriginalQueryExecution,
                                   context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard let plane = curve.plane else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "A drafted curve needs its sketch plane.")
        }
        let normal = try ExactSweepSectionPlane(plane, tolerance: tolerance).plane.normal
        let axis = try curveAxis(curve, featureID: feature.id, direction: direction, context: context)
        let originalDirections = OriginalDraftDirectionInputs(plane: plane, direction: direction, pull: draftDirection)
        let lower = direction == .symmetric ? -0.5 * distance : startOffset
        let usesOriginalGeneralRuling = sourceDraftAngle != 0
        if abs(abs(axis.dot(normal)) - 1) > tolerance.angle || draftDirection != nil
            || usesOriginalGeneralRuling {
            guard let exact = curve.exactCurve, case let .closed(a, b) = curve.parameterDomain else {
                throw KernelError(phase: .geometry, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                    message: "An oblique drafted sheet requires its original finite boundary curve.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original owning walls now reach
            // sewn-body contact admission. Sharp draft joins additionally require
            // retained original wall intersections and finite retrims; generic
            // shared-boundary and critical contact must not publish by sewing alone.
            let walls = try OriginalDraftedWallPartition().walls(curve: exact,
                parameters: ScalarInterval(lower: a, upper: b), normal: originalDirections.normal,
                axis: originalDirections.axis, pull: originalDirections.pull, lowerHeight: lower,
                upperHeight: lower + distance, angle: sourceDraftAngle,
                tolerance: tolerance, using: &execution)
            return try originalCurveSheet(walls: walls, featureID: feature.id,
                draftedRoles: true, using: &execution, context: context)
        }
        let reach = max(abs(lower * tangent), abs((lower + distance) * tangent))
        let builder = ExactDraftedProfileBoundaryBuilder(tolerance: tolerance, splineReach: reach)
        func joined(_ height: Double) throws -> BSplineCurve3D {
            let spans = try builder.openCurve(curve, planeNormal: axis, axis: axis, height: height, tangent: tangent)
            return spans.count == 1 ? spans[0] : try ExactCompositeBSplineCurveBuilder().build(spans: spans, tolerance: tolerance, using: &execution)
        }
        let (bottom, top) = (try joined(lower), try joined(lower + distance))
        guard bottom.degree == top.degree, bottom.knots == top.knots, bottom.weights == top.weights else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "A drafted curve's two heights lie on different bases.")
        }
        let surface = BSplineSurface3D(uDegree: bottom.degree, vDegree: 1, uKnots: bottom.knots, vKnots: [0, 0, 1, 1],
                                       controlPoints: [bottom.controlPoints, top.controlPoints], weights: [bottom.weights, top.weights])
        return try BSplineSurfaceFeatureEvaluator().evaluateValidated(
            feature: FeatureNode(id: feature.id, name: feature.name,
                                 operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface, material: nil)),
                                 outputs: feature.outputs, isSuppressed: feature.isSuppressed),
            context: context
        ).result
    }

    /// An open curve's extruded sheet thickened into a solid wall `thickness` wide toward the curve's
    /// left about the extrusion `axis`, as Thicken does.
    private func thickened(_ sheet: EvaluationResult, curve: EvaluatedCurve, axis: Vector3D, thickness: Double, featureID: FeatureID,
                           context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard case let .body(bodyID)? = sheet.subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              curve.points.count >= 2 else {
            throw KernelError(phase: .geometry, code: .missingReference, featureID: featureID, tolerance: tolerance,
                              message: "A thin curve extrusion lost its sheet.")
        }
        // The face at the curve's start and its outward normal there, against the curve's left
        // (the way the curve runs from its first sample to its second).
        let start = (position: curve.points[0], firstDerivative: curve.points[1] - curve.points[0])
        let left = axis.cross(start.firstDerivative)
        // A face with a vertex at the curve's start meets it there.
        let source = sheet.brep
        var normal: Vector3D?
        for case let .face(faceID) in try BodyTopologyScope(bodyID: bodyID, model: source).references {
            guard let face = source.faces[faceID], let surface = source.geometry.surfaces[face.surfaceID] else { continue }
            let touches = face.loops.contains { loopID in
                source.loops[loopID]?.coedges.contains { coedge in
                    guard let edge = source.edges[coedge.edgeID] else { return false }
                    return [edge.startVertexID, edge.endVertexID].contains {
                        source.vertices[$0].map { ($0.point - start.position).length <= tolerance.distance } ?? false
                    }
                } ?? false
            }
            guard touches else { continue }
            let projected = try surface.parameterProjection(of: start.position, tolerance: tolerance)
            normal = try surface.normal(u: projected.u, v: projected.v, tolerance: tolerance) * (face.orientation == .forward ? 1 : -1)
            break
        }
        guard let normal else {
            throw KernelError(phase: .geometry, code: .missingReference, featureID: featureID, tolerance: tolerance,
                              message: "A thin curve extrusion's sheet does not meet its curve.")
        }
        let offsets = normal.dot(left) >= 0 ? (lower: 0.0, upper: thickness) : (lower: -thickness, upper: 0.0)
        let request = try ExactThickenRequestBuilder().request(featureID: featureID, bodyID: bodyID, offsets: offsets, model: sheet.brep,
                                                               subshapes: SubshapeIndex(sheet.subshapes), tolerance: tolerance)
        let sewn = try sewer.sew(request, tolerance: tolerance)
        let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: sheet.brep)
        try model.validate(level: .volumetric, tolerance: tolerance)
        // The wall is generated from the curve: its sheet was this feature's own stage.
        let lineage = Dictionary(uniqueKeysWithValues: sewn.subshapes.keys.map { ($0, TopologyLineage(output: $0, relation: .generated)) })
        return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: lineage)
    }

    private func originalCurveSheet(walls: [OriginalDraftedRuledSurface3D], featureID: FeatureID,
        draftedRoles: Bool, using execution: inout OriginalQueryExecution,
        materialRegion: Bool = false, orientation: Orientation = .forward,
        loopWallCounts: [Int]? = nil, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let request = try OriginalDraftedSheetRequestBuilder().request(walls: walls,
            featureID: featureID, tolerance: tolerance, using: &execution,
            orientation: orientation, loopWallCounts: loopWallCounts)
        let sewn = try sewer.sew(request, tolerance: tolerance)
        if let generatedResultValidator {
            try generatedResultValidator.validate(bodyID: sewn.bodyID,
                validatedModel: sewn.validatedBRep, using: &execution)
        } else if let wall = walls.first, walls.count == 1 {
            let embedding = try DefaultOriginalSurfaceEmbeddingPreparer().prepare(
                surface: .procedural(.originalDrafted(wall)),
                over: .init(u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1)),
                options: .init(maximumSubdivisionDepth: min(14, execution.effectiveLimits.maximumSubdivisionDepth),
                    maximumSubdivisionCells: 65_536), tolerance: tolerance, using: &execution)
            try embedding.certify()
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone multi-wall sheet
            // publication needs the same original finite-pair validator.
            // Sewing alone cannot admit original between-wall contact freedom.
            throw KernelError(phase: .validation, code: .unsupportedCapability,
                featureID: featureID, tolerance: tolerance,
                message: "Original multi-wall publication requires its caller-admitted generated-body contact validator.")
        }
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep])
        var subshapes: [SubshapeID: TopologyReference] = [
            .init(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0): .body(sewn.bodyID)
        ]
        func retain(_ role: String, key: BRepSewingStableKey) throws {
            try execution.consumeWork(1)
            guard let reference = sewn.stableReferences[key] else {
                throw TopologyError.missingReference("Original drafted sheet lost its retained semantic boundary.")
            }
            subshapes[.init(featureID: featureID,
                role: SubshapeIdentityRole.compose(generatedRole: "bSplineSurface", subshapeRole: role),
                ordinal: 0)] = reference
        }
        if draftedRoles {
            for index in walls.indices {
                try execution.consumeWork(1)
                let prefix = "extrude:curve:patch:\(index)"
                try retain("patch:\(index):face", key: .face(prefix))
                for role in ["vMin", "uMax", "vMax", "uMin"] {
                    try retain("patch:\(index):edge:\(role)", key: .edge("\(prefix):edge:\(role)"))
                }
                let names = ["uMin:vMin", "uMax:vMin", "uMax:vMax", "uMin:vMax"]
                for (corner, role) in ["vMin", "uMax", "vMax", "uMin"].enumerated() {
                    try retain("patch:\(index):vertex:\(names[corner])", key: .startVertex(edge: "\(prefix):edge:\(role)"))
                }
            }
        } else {
            for index in walls.indices {
                try execution.consumeWork(1)
                guard let face = sewn.stableReferences[.face("extrude:curve:patch:\(index)")] else {
                    throw TopologyError.missingReference("Original translated sheet lost its side face.")
                }
                subshapes[.init(featureID: featureID, role: GeneratedSubshapeRole.sideFace.rawValue, ordinal: index)] = face
            }
            if materialRegion {
                try retainMaterialRegionTopology(wallCount: walls.count, sewn: sewn,
                    featureID: featureID, using: &execution,
                    loopWallCounts: loopWallCounts, subshapes: &subshapes)
            } else {
                try execution.retainStorage(bytes: sewn.brep.edges.count * MemoryLayout<EdgeID>.stride)
                let edges = try sewn.brep.edges.keys.sorted {
                    try execution.consumeWork(1); return $0.description < $1.description
                }
                for (ordinal, edge) in edges.enumerated() {
                    try execution.consumeWork(1)
                    subshapes[.init(featureID: featureID, role: GeneratedSubshapeRole.edge.rawValue, ordinal: ordinal)] = .edge(edge)
                }
                try execution.retainStorage(bytes: sewn.brep.vertices.count * MemoryLayout<VertexID>.stride)
                let vertices = try sewn.brep.vertices.keys.sorted {
                    try execution.consumeWork(1); return $0.description < $1.description
                }
                for (ordinal, vertex) in vertices.enumerated() {
                    try execution.consumeWork(1)
                    subshapes[.init(featureID: featureID, role: GeneratedSubshapeRole.vertex.rawValue, ordinal: ordinal)] = .vertex(vertex)
                }
            }
        }
        return EvaluationResult(brep: combined, subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(featureID: featureID, subshapes: subshapes, using: &execution))
    }

    private func retainMaterialRegionTopology(wallCount: Int, sewn: BRepSewingResult,
        featureID: FeatureID, using execution: inout OriginalQueryExecution,
        loopWallCounts: [Int]?,
        subshapes: inout [SubshapeID: TopologyReference]) throws {
        try execution.retainStorage(bytes: sewn.brep.edges.count * MemoryLayout<EdgeID>.stride
            + sewn.brep.vertices.count * MemoryLayout<VertexID>.stride)
        var edges: [EdgeID] = []; edges.reserveCapacity(sewn.brep.edges.count)
        var vertices: [VertexID] = []; vertices.reserveCapacity(sewn.brep.vertices.count)
        func append(_ wall: Int, _ role: String) throws {
                try execution.consumeWork(1)
                guard case .edge(let edge)? = sewn.stableReferences[.edge("extrude:curve:patch:\(wall):edge:\(role)")] else {
                    throw TopologyError.missingReference("Original closed sheet lost its retained material boundary edge.")
                }
                if try !edges.contains(where: { try execution.consumeWork(1); return $0 == edge }) { edges.append(edge) }
        }
        if let loopWallCounts {
            var first = 0
            for count in loopWallCounts {
                for role in ["vMin", "vMax"] {
                    for wall in first..<(first + count) { try append(wall, role) }
                }
                first += count
            }
            for wall in 0..<wallCount { try append(wall, "uMax") }
        } else {
            for role in ["vMin", "vMax", "uMax"] {
                for wall in 0..<wallCount { try append(wall, role) }
            }
        }
        guard edges.count == sewn.brep.edges.count else {
            throw TopologyError.missingReference("Original material ordering does not cover every sewn physical edge.")
        }
        for (ordinal, edgeID) in edges.enumerated() {
            try execution.consumeWork(1)
            subshapes[.init(featureID: featureID, role: GeneratedSubshapeRole.edge.rawValue, ordinal: ordinal)] = .edge(edgeID)
            guard let edge = sewn.brep.edges[edgeID] else { throw TopologyError.missingReference("Original material edge is absent.") }
            for vertex in [edge.startVertexID, edge.endVertexID] {
                if try !vertices.contains(where: { try execution.consumeWork(1); return $0 == vertex }) { vertices.append(vertex) }
            }
        }
        guard vertices.count == sewn.brep.vertices.count else {
            throw TopologyError.missingReference("Original material ordering does not cover every sewn vertex.")
        }
        for (ordinal, vertex) in vertices.enumerated() {
            try execution.consumeWork(1)
            subshapes[.init(featureID: featureID, role: GeneratedSubshapeRole.vertex.rawValue, ordinal: ordinal)] = .vertex(vertex)
        }
    }

    private func originalClosedCurveSheet(curve: EvaluatedCurve, spans: [ExactBSplineCurveSpan],
        direction: ExtrudeDirection, lowerHeight: Double, distance: Double, pull: Vector3D?,
        angle: Double, featureID: FeatureID, using execution: inout OriginalQueryExecution,
        context: EvaluationContext) throws -> EvaluationResult {
        guard let plane = curve.plane else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID,
                tolerance: context.tolerance, message: "A closed drafted region requires its original plane.")
        }
        try execution.retainStorage(bytes: MemoryLayout<[ExactBSplineCurveSpan]>.stride)
        return try originalRegionSheet(loops: [spans], plane: plane, direction: direction,
            lowerHeight: lowerHeight, distance: distance, pull: pull, angle: angle,
            featureID: featureID, using: &execution, context: context)
    }

    private func originalRegionSheet(loops: [[ExactBSplineCurveSpan]], plane: SketchPlane,
        direction: ExtrudeDirection, lowerHeight: Double, distance: Double, pull: Vector3D?,
        angle: Double, featureID: FeatureID, using execution: inout OriginalQueryExecution,
        context: EvaluationContext) throws -> EvaluationResult {
        guard !loops.isEmpty else {
            throw GeometryConversionError.invalidInput("An original material sheet requires retained boundary loops.")
        }
        let directions = OriginalDraftDirectionInputs(plane: plane, direction: direction, pull: pull)
        let sourcePlane: Plane3D
        switch plane {
        case .xy: sourcePlane = .init(origin: .origin, normal: .unitZ)
        case .yz: sourcePlane = .init(origin: .origin, normal: .unitX)
        case .zx: sourcePlane = .init(origin: .origin, normal: .unitY)
        case .plane(let original): sourcePlane = original
        }
        let originalNormal = try OriginalSupportingPlaneEquation.Vector.original(directions.normal, usage: &execution)
        let originalAxis = try OriginalSupportingPlaneEquation.Vector.original(directions.axis, usage: &execution)
        let signedNormalComponent = try originalNormal.dot(originalAxis, usage: &execution)
        guard !signedNormalComponent.isZero else { throw FeatureEvaluationError.invalidDirection(directions.axis) }
        let orientation: Orientation = signedNormalComponent.isPositive ? .forward : .reversed
        var wallCount = 0
        for loop in loops {
            try execution.consumeWork(1)
            let next = wallCount.addingReportingOverflow(loop.count)
            guard !loop.isEmpty, !next.overflow, next.partialValue <= execution.effectiveLimits.maximumSpans else {
                throw GeometryConversionError.resourceLimitExceeded("Original region walls exceed the retained source-span allowance.")
            }
            wallCount = next.partialValue
        }
        let bytes = wallCount.multipliedReportingOverflow(by: MemoryLayout<OriginalDraftedRuledSurface3D>.stride)
        guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original region wall storage overflows.") }
        try execution.retainStorage(bytes: bytes.partialValue)
        try execution.retainStorage(bytes: loops.count * MemoryLayout<Int>.stride)
        var walls: [OriginalDraftedRuledSurface3D] = []; walls.reserveCapacity(wallCount)
        var counts: [Int] = []; counts.reserveCapacity(loops.count)
        for (loopIndex, loop) in loops.enumerated() {
          counts.append(loop.count)
          try execution.retainStorage(bytes: loop.count * MemoryLayout<OriginalCurveSpanParameterChart>.stride)
          let charts = try loop.map { span in try execution.consumeWork(1); return span.originalChart }
          let ccw = try OriginalPlanarLoopOrientation().counterclockwise(charts: charts,
              origin: sourcePlane.origin, normal: directions.normal,
              tolerance: context.tolerance, using: &execution)
          let reverse = ccw != (loopIndex == 0)
          for offset in loop.indices {
            try execution.consumeWork(1)
            let index = reverse ? loop.count - 1 - offset : offset
            let chart = reverse ? loop[index].originalChart.reversed() : loop[index].originalChart
            let raw = try chart.persistentCurve(tolerance: context.tolerance, using: &execution)
            let retained = try OriginalDraftedWallPartition().walls(curve: raw,
                parameters: .init(lower: 0, upper: 1), normal: directions.normal,
                axis: directions.axis, pull: directions.pull, lowerHeight: lowerHeight,
                upperHeight: lowerHeight + distance, angle: angle,
                tolerance: context.tolerance, using: &execution)
            guard retained.count == 1, let wall = retained.first else {
                throw GeometryConversionError.invalidInput("An original closed-region span must retain its one complete construction chart.")
            }
            try OriginalDraftedBoundaryPlanarity().validate(wall.start.generator,
                on: sourcePlane, tolerance: context.tolerance, using: &execution)
            walls.append(wall)
          }
        }
        return try originalCurveSheet(walls: walls, featureID: featureID, draftedRoles: false,
            using: &execution, materialRegion: true, orientation: orientation,
            loopWallCounts: counts, context: context)
    }

    private func evaluateCurveSheet(
        _ curve: EvaluatedCurve,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        startOffset: Double,
        using execution: inout OriginalQueryExecution,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let rawAxis: Vector3D
        switch direction {
        case .normal, .symmetric:
            guard let plane = curve.plane else {
                throw KernelError(phase: .validation, code: .invalidInput, featureID: featureID,
                    tolerance: context.tolerance, message: "A spatial curve needs its explicit extrusion vector.")
            }
            rawAxis = OriginalDraftDirectionInputs.normal(of: plane)
        case .vector(let vector): rawAxis = vector
        }
        let selected = try curve.validateOriginalGeometry(tolerance: context.tolerance, using: &execution)
        let first = selected.startParameter, last = selected.endParameter
        guard first.isFinite, last.isFinite, first != last else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID,
                tolerance: context.tolerance, message: "An original curve extrusion requires a finite nonempty authored traversal.")
        }
        let lower = direction == .symmetric ? -0.5 * distance : startOffset
        let walls = try OriginalDraftedWallPartition().walls(curve: selected.curve,
            parameters: .init(lower: min(first,last), upper: max(first,last)), normal: rawAxis, axis: rawAxis, pull: rawAxis,
            lowerHeight: lower, upperHeight: lower + distance, angle: 0,
            tolerance: context.tolerance, using: &execution, reversedTraversal: first > last)
        return try originalCurveSheet(walls: walls, featureID: featureID,
            draftedRoles: false, using: &execution, context: context)
    }

    /// A curve extrusion's unit direction: its source plane's normal, or the explicit vector.
    private func curveAxis(_ curve: EvaluatedCurve, featureID: FeatureID, direction: ExtrudeDirection,
                           context: EvaluationContext) throws -> Vector3D {
        let axis: Vector3D
        switch direction {
        case .normal, .symmetric:
            guard let sourcePlane = curve.plane else {
                throw KernelError(phase: .validation, code: .invalidInput,
                    featureID: featureID, tolerance: context.tolerance,
                    message: "A spatial curve has no source-plane normal; specify an extrusion vector.")
            }
            axis = try OriginalDraftDirectionInputs.normalized(OriginalDraftDirectionInputs.normal(of: sourcePlane))
        case .vector(let vector):
            axis = try OriginalDraftDirectionInputs.normalized(vector)
        }
        return axis
    }

    package func evaluateSheet(from profile: Profile, featureID: FeatureID,
        direction: ExtrudeDirection, distance: Double, context: EvaluationContext) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try evaluateSheet(from: profile, featureID: featureID, direction: direction,
            distance: distance, context: context, using: &execution)
    }

    package func evaluateSheet(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try ExactProfileExtrudeBodyBuilder(
            featureID: featureID,
            context: context,
            sewer: sewer
        ).build(
            from: profile,
            direction: direction,
            distance: distance,
            bodyKind: .sheet,
            includesCaps: false
        , using: &execution)
    }

}
