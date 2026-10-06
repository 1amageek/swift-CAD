import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Clips original surface-plane intersections through the existing complete Boolean pipeline.
public struct BRepDrawingSectioner: BRepDrawingSectioning {
    private let encloser: any SurfaceDifferentialEnclosing
    private let sewer: any BRepSewing

    public init(encloser: any SurfaceDifferentialEnclosing = DefaultSurfaceDifferentialEncloser(),
                sewer: any BRepSewing = DefaultBRepSewer()) {
        self.encloser = encloser
        self.sewer = sewer
    }

    public func section(in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection {
        try section(bodyIDs: evaluated.brep.bodies.keys.sorted(), in: evaluated, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents)
    }

    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection {
        guard maximumSourceFaces > 0, maximumComponents > 0 else {
            throw failure(.invalidInput, "Section capacities must be positive.", evaluated.configuration.tolerance)
        }
        try evaluated.document.validate(tolerance: evaluated.configuration.tolerance)
        try evaluated.brep.validate(tolerance: evaluated.configuration.tolerance)
        return try section(bodyIDs: bodyIDs, in: evaluated, workingBRep: evaluated.brep, placement: nil,
            consumedPreparationWork: 0, retainedPreparationEntities: 0, on: frame, maximumSourceFaces: maximumSourceFaces,
            maximumComponents: maximumComponents)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Placed sections compose original affine source laws,
    // but the production Boolean SSI originalImage/world-plane route still requires the
    // bounded same-ledger lower producer before full placed section completion is claimed.
    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on frame: OrthographicProjectionFrame, maximumSourceFaces: Int, maximumComponents: Int,
                        maximumSourceEntities: Int, maximumPreparationWork: Int) throws -> BRepDrawingSection {
        let tolerance = evaluated.configuration.tolerance
        try evaluated.document.validate(tolerance: tolerance)
        try evaluated.brep.validate(tolerance: tolerance)
        guard maximumSourceFaces > 0, maximumComponents >= 0,
              evaluated.brep.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Section original-face capacity exhausted.", tolerance)
        }
        let image = try BRepDrawingBodyImage().make(placement, in: evaluated.brep,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork,
            tolerance: tolerance)
        return try section(bodyIDs: [placement.bodyID], in: evaluated, workingBRep: image.model,
            placement: placement, consumedPreparationWork: image.consumedWork,
            retainedPreparationEntities: image.retainedEntities, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This additive public cut retains original
    // local plane/word/UV authority. Full source completion still requires general
    // original-word SSI and lower sewing/classification allocation callbacks.
    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        let tolerance = evaluated.configuration.tolerance
        guard maximumPreparationWork > 0, maximumPreparationBytes > 0 else {
            throw failure(.invalidInput, "Original cutting preparation capacities must be positive.", tolerance)
        }
        try evaluated.document.validate(tolerance: tolerance)
        try evaluated.brep.validate(tolerance: tolerance)
        let admission = BRepDrawingCuttingAdmission(owner: .init(maximumWork: maximumPreparationWork,
            maximumBytes: maximumPreparationBytes, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth))
        let preparation = try PreparedBRepDrawingCuttingSupport(support, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: admission)
        return try section(bodyIDs: bodyIDs, in: evaluated, workingBRep: evaluated.brep, placement: nil,
            consumedPreparationWork: 0, retainedPreparationEntities: 0, on: projectionFrame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents,
            cuttingPreparation: preparation)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This source route composes original body and
    // original cutting-plane words. Full SSI and aggregate body/sewing byte admission
    // remain lower source dependencies; no rounded plane or matrix is substituted.
    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        let tolerance = evaluated.configuration.tolerance
        guard maximumPreparationWork > 0, maximumPreparationBytes > 0 else {
            throw failure(.invalidInput, "Original placed cutting capacities must be positive.", tolerance)
        }
        try evaluated.document.validate(tolerance: tolerance)
        try evaluated.brep.validate(tolerance: tolerance)
        let image = try BRepDrawingBodyImage().make(placement, in: evaluated.brep,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork, tolerance: tolerance,
            remainingSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        guard image.consumedWork < maximumPreparationWork else {
            throw failure(.resourceLimitExceeded, "Original placed cutting preparation work is exhausted.", tolerance)
        }
        let admission = BRepDrawingCuttingAdmission(owner: .init(
            maximumWork: maximumPreparationWork - image.consumedWork,
            maximumBytes: maximumPreparationBytes, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth))
        let preparation = try PreparedBRepDrawingCuttingSupport(support, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: admission)
        return try section(bodyIDs: [placement.bodyID], in: evaluated, workingBRep: image.model,
            placement: placement, consumedPreparationWork: image.consumedWork,
            retainedPreparationEntities: image.retainedEntities, on: projectionFrame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, cuttingPreparation: preparation)
    }

    private func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, workingBRep: BRepModel,
                         placement: BRepDrawingPlacement?, consumedPreparationWork: Int,
                         retainedPreparationEntities: Int, on frame: OrthographicProjectionFrame, maximumSourceFaces: Int,
                         maximumComponents: Int,
                         cuttingPreparation originalPreparation: PreparedBRepDrawingCuttingSupport? = nil) throws -> BRepDrawingSection {
        let tolerance = evaluated.configuration.tolerance
        try CurrentTaskCancellationChecker().checkCancellation()
        guard maximumSourceFaces > 0, maximumComponents >= 0 else {
            throw failure(.invalidInput, "Section capacities are invalid.", tolerance)
        }
        var cuttingPreparation = originalPreparation
        let source = workingBRep
        try source.validate(tolerance: tolerance)
        let selected = Set(bodyIDs)
        guard selected.count == bodyIDs.count,
              selected.isSubset(of: Set(source.bodies.keys)),
              !selected.isEmpty || source.bodies.isEmpty else {
            throw failure(.invalidInput, "Section body selection is empty, duplicated or foreign.", tolerance)
        }
        guard source.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Section original-face capacity exhausted.", tolerance)
        }
        if source.bodies.isEmpty {
            return BRepDrawingSection(sourceDocument: evaluated.document, configuration: evaluated.configuration,
                                      frame: frame, horizontalRange: nil, verticalRange: nil, originalBRep: evaluated.brep, workingBRep: source, placement: placement,
                                      consumedPreparationWork: consumedPreparationWork + (cuttingPreparation?.usage.consumedWork ?? 0),
                                      retainedPreparationEntities: retainedPreparationEntities,
                                      cuttingModel: nil, cuttingFaceID: nil, splitGraph: nil, components: [],
                                      cuttingSupport: cuttingPreparation?.source,
                                      retainedPreparationBytes: cuttingPreparation?.usage.retainedBytes ?? 0)
        }
        var owners: [FaceID: BodyID] = [:]
        var xLower = Double.infinity, xUpper = -Double.infinity
        var yLower = Double.infinity, yUpper = -Double.infinity
        for body in source.bodies.values {
            for shellID in body.shellIDs {
                guard let shell = source.shells[shellID] else {
                    throw failure(.missingReference, "Section body shell is missing.", tolerance)
                }
                for faceID in shell.faceIDs {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    guard owners[faceID] == nil, let face = source.faces[faceID],
                          let surface = source.geometry.surfaces[face.surfaceID] else {
                        throw failure(.missingReference, "Section source face has missing or ambiguous ownership.", tolerance)
                    }
                    owners[faceID] = body.id
                    guard selected.contains(body.id) else { continue }
                    let parameters = try DefaultFaceParameterBoundsResolver().bounds(
                        for: faceID, in: source, tolerance: tolerance)
                    let position = try encloser.enclosure(of: surface, over: parameters, tolerance: tolerance).position
                    let x: ScalarInterval, y: ScalarInterval
                    if var preparation = cuttingPreparation {
                        let uv = try preparation.parameters(over: position)
                        x = uv.x; y = uv.y; cuttingPreparation = preparation
                    } else {
                        x = try projectedRange(position, origin: frame.origin, direction: frame.horizontal, tolerance: tolerance)
                        y = try projectedRange(position, origin: frame.origin, direction: frame.vertical, tolerance: tolerance)
                    }
                    xLower = min(xLower, x.lower); xUpper = max(xUpper, x.upper)
                    yLower = min(yLower, y.lower); yUpper = max(yUpper, y.upper)
                }
            }
        }
        guard Set(owners.keys) == Set(source.faces.keys) else {
            throw failure(.missingReference, "Section source contains faces without a body owner.", tolerance)
        }
        let magnitude = max(abs(xLower), abs(xUpper), abs(yLower), abs(yUpper),
                            abs(frame.origin.x), abs(frame.origin.y), abs(frame.origin.z))
        // The tool extends beyond the source envelope; this is representational
        // construction slack, never a relaxation of source intersection tolerance.
        let margin = max(tolerance.distance * 16, magnitude.ulp * 128).nextUp
        let bounds = [ (xLower - margin).nextDown, (xUpper + margin).nextUp,
                       (yLower - margin).nextDown, (yUpper + margin).nextUp ]
        guard margin.isFinite, bounds.allSatisfy({ $0.isFinite }), bounds[1] > bounds[0], bounds[3] > bounds[2] else {
            throw failure(.invalidInput, "Section cutting extent cannot be represented finitely.", tolerance)
        }
        let surface: Surface3D
        var edges: [BRepSewingEdge] = []
        if var preparation = cuttingPreparation {
            surface = .procedural(.originalAffineWord(preparation.image))
            edges = try preparation.edges(u: .init(lower: bounds[0], upper: bounds[1]),
                v: .init(lower: bounds[2], upper: bounds[3]), tolerance: tolerance)
            cuttingPreparation = preparation
        } else {
            let coordinates = [(bounds[0], bounds[2]), (bounds[1], bounds[2]),
                               (bounds[1], bounds[3]), (bounds[0], bounds[3])]
            let corners = coordinates.map { frame.origin + frame.horizontal * $0.0 + frame.vertical * $0.1 }
            surface = Surface3D.plane(Plane3D(origin: frame.origin, normal: frame.normal))
            edges.reserveCapacity(4)
            for index in 0..<4 {
                let start = corners[index], end = corners[(index + 1) % 4], delta = end - start
                let curve = Curve3D.line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
                edges.append(BRepSewingEdge(stableID: "drawing:plane:edge:\(index)", curve: curve,
                    startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                    surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                        for: curve, startParameter: 0, endParameter: delta.length, on: surface, tolerance: tolerance)))
            }
        }
        let patch = BRepSewingFacePatch(stableID: "drawing:plane:face", surface: surface, orientation: .forward,
            loops: [BRepSewingLoop(stableID: "drawing:plane:loop", role: .outer, edges: edges)])
        let tool = try sewer.sew(BRepSewingRequest(featureID: FeatureID(), bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "drawing:plane:shell", patches: [patch])]), tolerance: tolerance)
        guard tool.brep.faces.count == 1, let cuttingFaceID = tool.brep.faces.keys.first else {
            throw failure(.topologyFailure, "Section sewing did not produce one complete cutting face.", tolerance)
        }
        let combined = try BRepModelCombiner().combined([source, tool.brep])
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let graph = try pipeline.completeIntersectionGraph(
            targetBodyIDs: bodyIDs.sorted(),
            toolBodyID: tool.bodyID, operation: .union, model: combined, tolerance: tolerance)
        let split = try pipeline.uvSplitGraph(intersectionGraph: graph, model: combined, tolerance: tolerance)
        var components: [BRepDrawingSectionComponent] = []
        for faceSplit in split.splits {
            guard let bodyID = owners[faceSplit.facePair.targetFaceID] else {
                throw failure(.missingReference, "Section split lost original-face provenance.", tolerance)
            }
            for component in faceSplit.components {
                try CurrentTaskCancellationChecker().checkCancellation()
                guard components.count < maximumComponents else {
                    throw failure(.resourceLimitExceeded, "Section retained-component capacity exhausted.", tolerance)
                }
                components.append(BRepDrawingSectionComponent(bodyID: bodyID, faceID: faceSplit.facePair.targetFaceID,
                    materialID: source.bodies[bodyID]?.material, ordinal: components.count, geometry: component.geometry))
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return BRepDrawingSection(sourceDocument: evaluated.document, configuration: evaluated.configuration,
                                  frame: frame, horizontalRange: try ScalarInterval(lower: bounds[0], upper: bounds[1]),
                                  verticalRange: try ScalarInterval(lower: bounds[2], upper: bounds[3]), originalBRep: evaluated.brep, workingBRep: source, placement: placement,
                                      consumedPreparationWork: consumedPreparationWork + (cuttingPreparation?.usage.consumedWork ?? 0),
                                      retainedPreparationEntities: retainedPreparationEntities,
                                  cuttingModel: combined, cuttingFaceID: cuttingFaceID,
                                  splitGraph: split, components: components, cuttingSupport: cuttingPreparation?.source,
                                      retainedPreparationBytes: cuttingPreparation?.usage.retainedBytes ?? 0)
    }

    private func projectedRange(_ position: CoordinateEnclosure3D, origin: Point3D,
                                direction: Vector3D, tolerance: ModelingTolerance) throws -> ScalarInterval {
        var lower = 0.0, upper = 0.0
        for (range, offset, coefficient) in [(position.x, origin.x, direction.x),
                                             (position.y, origin.y, direction.y),
                                             (position.z, origin.z, direction.z)] {
            let a = (range.lower - offset).nextDown, b = (range.upper - offset).nextUp
            let p = a * coefficient, q = b * coefficient
            lower = (lower + min(p, q).nextDown).nextDown
            upper = (upper + max(p, q).nextUp).nextUp
            guard a.isFinite, b.isFinite, p.isFinite, q.isFinite, lower.isFinite, upper.isFinite else {
                throw failure(.invalidInput, "Section projected enclosure arithmetic is nonfinite.", tolerance)
            }
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
