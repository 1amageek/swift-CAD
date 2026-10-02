import Foundation
import CADCore
import CADGeometry
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing
    private let booleanApplicator: (any SweepBooleanApplying)?
    private let targetRelocator: (any ExactBodyPatternRebuilding)?

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: (any SweepBooleanApplying)? = nil
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = nil
    }

    /// An evaluator that also moves placed Boolean targets into the extrusion's frame with
    /// `targetRelocator`, as a Boolean moves its placed operands.
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
        if let draftAngle = extrude.draftAngle {
            let quantity = try resolver.evaluate(draftAngle, parameters: context.parameters, variables: [:])
            guard quantity.kind == .angle, quantity.value.isFinite, abs(quantity.value) < Double.pi / 2 - context.tolerance.angle else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                                  message: "An extrusion's draft is an angle under 90 degrees.")
            }
            draftTangent = abs(quantity.value) > context.tolerance.angle ? tan(quantity.value) : 0
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
        var faceProfile: Profile?
        if case let .face(reference) = extrude.section {
            faceProfile = try FaceSectionProfileResolver().profile(for: reference, context: context, featureID: feature.id)
        }
        let context = stages.context
        var result: EvaluationResult
        switch extrude.section {
        case .profile, .face:
            let profile: Profile
            if case let .profile(reference) = extrude.section {
                profile = try ResolvedModelingSection.resolveProfile(reference, from: context.profiles[reference.featureID])
            } else if let faceProfile {
                profile = faceProfile
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
                wallThickness: wallThickness
            )
        case .curve(let reference):
            let curve = try ResolvedModelingSection.resolveCurve(
                reference, from: context.curves[reference.featureID], tolerance: context.tolerance
            )
            // A closed curve drafted or thin is its region's drafted wall or thin ring.
            if curve.isClosed, draftTangent != 0 || wallThickness > 0 {
                result = try ExactProfileExtrudeBodyBuilder(featureID: feature.id, context: context, sewer: sewer).build(
                    from: try closedCurveProfile(curve, featureID: feature.id, tolerance: context.tolerance), direction: extrude.direction,
                    distance: span, startOffset: range.lowerBound, bodyKind: wallThickness > 0 ? .solid : .sheet,
                    includesCaps: wallThickness > 0, draftTangent: draftTangent, wallThickness: wallThickness
                )
                break
            }
            if draftTangent != 0 {
                result = try draftedCurveSheet(curve, feature: feature, direction: extrude.direction, distance: span,
                                               startOffset: range.lowerBound, tangent: draftTangent, context: context)
            } else {
                result = try evaluateCurveSheet(
                    curve, featureID: feature.id, direction: extrude.direction,
                    distance: span, startOffset: range.lowerBound, context: context
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
            tolerance: context.tolerance
        )
    }

    /// A closed curve's region as a profile running counterclockwise about its sketch plane's
    /// normal: a circle as two half arcs, a closed spline as itself (turned when it runs clockwise).
    private func closedCurveProfile(_ curve: EvaluatedCurve, featureID: FeatureID, tolerance: ModelingTolerance) throws -> Profile {
        guard let plane = curve.plane, let start = curve.points.first else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A drafted or thin closed curve needs its sketch plane.")
        }
        let normal = try ExactSweepSectionPlane(plane, tolerance: tolerance).plane.normal
        let circle: Circle3D
        switch curve.exactCurve {
        case let .circle(value)?: circle = value
        case let .analytic(.circle(center, axis, radius))?: circle = Circle3D(center: center, normal: axis, radius: radius)
        case let .bSpline(spline)?:
            // Green's area about the normal from the curve's samples decides its sense.
            var area = 0.0
            for (a, b) in zip(curve.points, curve.points.dropFirst() + [curve.points[0]]) { area += (a - start).cross(b - start).dot(normal) }
            let running = area >= 0 ? spline : try spline.reversed(tolerance: tolerance)
            guard case let .closed(lower, upper) = running.domain else {
                throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: "A closed spline is unbounded.")
            }
            let vertices = try (0..<32).map { try Curve3D.bSpline(running).point(at: lower + (upper - lower) * Double($0) / 32, tolerance: tolerance) }
            // Two halves, so no span closes on itself.
            let middle = 0.5 * (lower + upper)
            let halves = [try running.trimmed(from: lower, to: middle, tolerance: tolerance), try running.trimmed(from: middle, to: upper, tolerance: tolerance)]
            return Profile(sourceFeatureID: curve.sourceFeatureID, plane: plane, vertices: vertices,
                           boundarySegments: halves.map { .spline(ProfileSplineSegment(curve: $0)) })
        default:
            throw KernelError(phase: .geometry, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "A drafted or thin closed curve is a circle or a closed spline.")
        }
        let opposite = circle.center + (circle.center - start)
        let arcs = [(start, opposite), (opposite, start)].map { from, to in
            ProfileBoundarySegment.circularArc(ProfileCircularArcSegment(center: circle.center, normal: normal, radius: circle.radius,
                                                                         start: from, end: to, sweepAngle: Double.pi))
        }
        let radial = try (start - circle.center).normalized(tolerance: tolerance.distance)
        let across = normal.cross(radial)
        let vertices = (0..<16).map { k -> Point3D in
            let angle = 2 * Double.pi * Double(k) / 16
            return circle.center + radial * (circle.radius * cos(angle)) + across * (circle.radius * sin(angle))
        }
        return Profile(sourceFeatureID: curve.sourceFeatureID, plane: plane, vertices: vertices, boundarySegments: arcs)
    }

    /// An open curve's drafted sheet: the curve at each end height moved toward its left by the
    /// height times the draft's tangent (one taper through the sketch plane), and the surface
    /// ruled between them.
    private func draftedCurveSheet(_ curve: EvaluatedCurve, feature: FeatureNode, direction: ExtrudeDirection, distance: Double,
                                   startOffset: Double, tangent: Double, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard let plane = curve.plane else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "A drafted curve needs its sketch plane.")
        }
        let normal = try ExactSweepSectionPlane(plane, tolerance: tolerance).plane.normal
        let axis = try curveAxis(curve, featureID: feature.id, direction: direction, context: context)
        guard abs(abs(axis.dot(normal)) - 1) <= tolerance.angle else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, featureID: feature.id, tolerance: tolerance,
                              message: "A drafted extrusion runs along its section's normal.")
        }
        let lower = direction == .symmetric ? -0.5 * distance : startOffset
        let reach = max(abs(lower * tangent), abs((lower + distance) * tangent))
        let builder = ExactDraftedProfileBoundaryBuilder(tolerance: tolerance, splineReach: reach)
        func joined(_ height: Double) throws -> BSplineCurve3D {
            let spans = try builder.openCurve(curve, planeNormal: axis, axis: axis, height: height, tangent: tangent)
            return spans.count == 1 ? spans[0] : try ExactCompositeBSplineCurveBuilder().build(spans: spans, tolerance: tolerance)
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

    private func evaluateCurveSheet(
        _ curve: EvaluatedCurve,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        startOffset: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let axis = try curveAxis(curve, featureID: featureID, direction: direction, context: context)
        let start = axis * (direction == .symmetric ? -0.5 * distance : startOffset)
        return try ExactLinearSectionSweepBodyBuilder(
            featureID: featureID, context: context, sewer: sewer
        ).buildTranslatedSheet(section: curve, startOffset: start, endOffset: start + axis * distance)
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
            axis = try ExactSweepSectionPlane(sourcePlane, tolerance: context.tolerance).plane.normal
        case .vector(let vector):
            do { axis = try vector.normalized(tolerance: context.tolerance.distance) }
            catch GeometryError.invalidVectorLength {
                throw FeatureEvaluationError.invalidDirection(vector)
            }
        }
        return axis
    }

    package func evaluateSheet(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
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
        )
    }

}
