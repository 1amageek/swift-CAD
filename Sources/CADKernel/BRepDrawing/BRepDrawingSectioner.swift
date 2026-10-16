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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try section(in: evaluated, on: frame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, using: &execution)
    }

    public func section(in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        try execution.checkpoint()
        return try section(bodyIDs: try OriginalParameterQueryStorage.ordered(evaluated.brep.bodies.keys, using: &execution, less: <), in: evaluated, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, using: &execution)
    }

    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try section(bodyIDs: bodyIDs, in: evaluated, on: frame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, using: &execution)
    }

    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        try execution.checkpoint()
        let operationWorkStart = execution.localWork
        let operationBytesStart = execution.localStorageBytes
        guard maximumSourceFaces > 0, maximumComponents > 0 else {
            throw failure(.invalidInput, "Section capacities must be positive.", evaluated.configuration.tolerance)
        }
        try evaluated.document.validate(tolerance: evaluated.configuration.tolerance, independentShapeLimits: .standard, using: &execution)
        try evaluated.brep.validate(tolerance: evaluated.configuration.tolerance, using: &execution)
        return try section(bodyIDs: bodyIDs, in: evaluated, workingBRep: evaluated.brep, placement: nil,
            operationWorkStart: operationWorkStart, operationBytesStart: operationBytesStart, retainedPreparationEntities: 0, on: frame, maximumSourceFaces: maximumSourceFaces,
            maximumComponents: maximumComponents, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Placed sections compose original affine source laws,
    // but the production Boolean SSI originalImage/world-plane route still requires the
    // bounded same-ledger lower producer before full placed section completion is claimed.
    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on frame: OrthographicProjectionFrame, maximumSourceFaces: Int, maximumComponents: Int,
                        maximumSourceEntities: Int, maximumPreparationWork: Int) throws -> BRepDrawingSection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try section(placement: placement, in: evaluated, on: frame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork, using: &execution)
    }

    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on frame: OrthographicProjectionFrame, maximumSourceFaces: Int, maximumComponents: Int,
                        maximumSourceEntities: Int, maximumPreparationWork: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        try execution.checkpoint()
        let operationWorkStart = execution.localWork
        let operationBytesStart = execution.localStorageBytes
        let tolerance = evaluated.configuration.tolerance
        try evaluated.document.validate(tolerance: tolerance, independentShapeLimits: .standard, using: &execution)
        try evaluated.brep.validate(tolerance: tolerance, using: &execution)
        guard maximumSourceFaces > 0, maximumComponents >= 0,
              evaluated.brep.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Section original-face capacity exhausted.", tolerance)
        }
        let image = try BRepDrawingBodyImage().make(placement, in: evaluated.brep,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork,
            tolerance: tolerance, using: &execution)
        return try section(bodyIDs: try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in [placement.bodyID] }, in: evaluated, workingBRep: image.model,
            placement: placement, operationWorkStart: operationWorkStart, operationBytesStart: operationBytesStart,
            retainedPreparationEntities: image.retainedEntities, on: frame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This additive public cut retains original
    // local plane/word/UV authority. Full source completion still requires general
    // original-word SSI and complete lower sewing/classification source proofs.
    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try section(bodyIDs: bodyIDs, in: evaluated, on: support, projectionFrame: projectionFrame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, maximumPreparationWork: maximumPreparationWork, maximumPreparationBytes: maximumPreparationBytes, maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    public func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        try execution.checkpoint()
        let operationWorkStart = execution.localWork
        let operationBytesStart = execution.localStorageBytes
        let tolerance = evaluated.configuration.tolerance
        guard maximumPreparationWork > 0, maximumPreparationBytes > 0 else {
            throw failure(.invalidInput, "Original cutting preparation capacities must be positive.", tolerance)
        }
        let policy = try OriginalQueryExecutionLimits(maximumValueDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumAlgebraicDepth, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth)
        let contribution = try execution.makeContributionHandle(workLimit: maximumPreparationWork,
            storageByteLimit: maximumPreparationBytes, executionLimits: policy)
        return try execution.withContributionScope(contribution) { execution in
        try evaluated.document.validate(tolerance: tolerance, independentShapeLimits: .standard, using: &execution)
        try evaluated.brep.validate(tolerance: tolerance, using: &execution)
        let preparation = try PreparedBRepDrawingCuttingSupport(support, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try section(bodyIDs: bodyIDs, in: evaluated, workingBRep: evaluated.brep, placement: nil,
            operationWorkStart: operationWorkStart, operationBytesStart: operationBytesStart, retainedPreparationEntities: 0, on: projectionFrame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents,
            cuttingPreparation: preparation, using: &execution)
            }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This source route composes original body and
    // original cutting-plane words. Full SSI and aggregate body/sewing byte admission
    // remain lower source dependencies; no rounded plane or matrix is substituted.
    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try section(placement: placement, in: evaluated, on: support, projectionFrame: projectionFrame, maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork, maximumPreparationBytes: maximumPreparationBytes, maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    public func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                        on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                        maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                        maximumPreparationWork: Int, maximumPreparationBytes: Int,
                        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        try execution.checkpoint()
        let operationWorkStart = execution.localWork
        let operationBytesStart = execution.localStorageBytes
        let tolerance = evaluated.configuration.tolerance
        guard maximumPreparationWork > 0, maximumPreparationBytes > 0 else {
            throw failure(.invalidInput, "Original placed cutting capacities must be positive.", tolerance)
        }
        let policy = try OriginalQueryExecutionLimits(maximumValueDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumAlgebraicDepth, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth)
        let contribution = try execution.makeContributionHandle(workLimit: maximumPreparationWork,
            storageByteLimit: maximumPreparationBytes, executionLimits: policy)
        return try execution.withContributionScope(contribution) { execution in
        try evaluated.document.validate(tolerance: tolerance, independentShapeLimits: .standard, using: &execution)
        try evaluated.brep.validate(tolerance: tolerance, using: &execution)
        let image = try BRepDrawingBodyImage().make(placement, in: evaluated.brep,
            maximumSourceEntities: maximumSourceEntities, maximumPreparationWork: maximumPreparationWork, tolerance: tolerance,
            remainingSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let preparation = try PreparedBRepDrawingCuttingSupport(support, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try section(bodyIDs: try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in [placement.bodyID] }, in: evaluated, workingBRep: image.model,
            placement: placement, operationWorkStart: operationWorkStart, operationBytesStart: operationBytesStart,
            retainedPreparationEntities: image.retainedEntities, on: projectionFrame,
            maximumSourceFaces: maximumSourceFaces, maximumComponents: maximumComponents, cuttingPreparation: preparation, using: &execution)
            }
    }

    private func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, workingBRep: BRepModel,
                         placement: BRepDrawingPlacement?, operationWorkStart: Int, operationBytesStart: Int,
                         retainedPreparationEntities: Int, on frame: OrthographicProjectionFrame, maximumSourceFaces: Int,
                         maximumComponents: Int,
                         cuttingPreparation originalPreparation: PreparedBRepDrawingCuttingSupport? = nil,
                         using execution: inout OriginalQueryExecution) throws -> BRepDrawingSection {
        let tolerance = evaluated.configuration.tolerance
        try execution.consumeWork(1)
        guard maximumSourceFaces > 0, maximumComponents >= 0 else {
            throw failure(.invalidInput, "Section capacities are invalid.", tolerance)
        }
        let cuttingPreparation = originalPreparation
        let source = workingBRep
        try source.validate(tolerance: tolerance, using: &execution)
        let selected = try OriginalParameterQueryStorage.set(bodyIDs, using: &execution)
        try execution.consumeWork(selected.count)
        guard selected.count == bodyIDs.count,
              selected.isSubset(of: try OriginalParameterQueryStorage.set(source.bodies.keys, using: &execution)),
              !selected.isEmpty || source.bodies.isEmpty else {
            throw failure(.invalidInput, "Section body selection is empty, duplicated or foreign.", tolerance)
        }
        guard source.faces.count <= maximumSourceFaces else {
            throw failure(.resourceLimitExceeded, "Section original-face capacity exhausted.", tolerance)
        }
        if source.bodies.isEmpty {
            return BRepDrawingSection(sourceDocument: evaluated.document, configuration: evaluated.configuration,
                                      frame: frame, horizontalRange: nil, verticalRange: nil, originalBRep: evaluated.brep, workingBRep: source, placement: placement,
                                      consumedPreparationWork: execution.localWork - operationWorkStart,
                                      retainedPreparationEntities: retainedPreparationEntities,
                                      cuttingModel: nil, cuttingFaceID: nil, splitGraph: nil, components: [],
                                      cuttingSupport: cuttingPreparation?.source,
                                      retainedPreparationBytes: execution.localStorageBytes - operationBytesStart)
        }
        var owners: [FaceID: BodyID] = [:]
        var xLower = Double.infinity, xUpper = -Double.infinity
        var yLower = Double.infinity, yUpper = -Double.infinity
        for body in source.bodies.values {
            try execution.consumeWork(1)
            for shellID in body.shellIDs {
                try execution.consumeWork(1)
                guard let shell = source.shells[shellID] else {
                    throw failure(.missingReference, "Section body shell is missing.", tolerance)
                }
                for faceID in shell.faceIDs {
                    try execution.consumeWork(1)
                    guard owners[faceID] == nil, let face = source.faces[faceID],
                          let surface = source.geometry.surfaces[face.surfaceID] else {
                        throw failure(.missingReference, "Section source face has missing or ambiguous ownership.", tolerance)
                    }
                    try OriginalParameterQueryStorage.set(body.id, for: faceID, in: &owners, using: &execution)
                    guard selected.contains(body.id) else { continue }
                    let parameters = try DefaultFaceParameterBoundsResolver().bounds(
                        for: faceID, in: source, tolerance: tolerance, using: &execution)
                    let position = try encloser.enclosure(of: surface, over: parameters, tolerance: tolerance, using: &execution).position
                    let x: ScalarInterval, y: ScalarInterval
                    if let preparation = cuttingPreparation {
                        let uv = try preparation.parameters(over: position, using: &execution)
                        x = uv.x; y = uv.y
                    } else {
                        x = try projectedRange(position, origin: frame.origin, direction: frame.horizontal, tolerance: tolerance, using: &execution)
                        y = try projectedRange(position, origin: frame.origin, direction: frame.vertical, tolerance: tolerance, using: &execution)
                    }
                    xLower = min(xLower, x.lower); xUpper = max(xUpper, x.upper)
                    yLower = min(yLower, y.lower); yUpper = max(yUpper, y.upper)
                }
            }
        }
        guard try OriginalParameterQueryStorage.set(owners.keys, using: &execution) == OriginalParameterQueryStorage.set(source.faces.keys, using: &execution) else {
            throw failure(.missingReference, "Section source contains faces without a body owner.", tolerance)
        }
        let magnitude = max(abs(xLower), abs(xUpper), abs(yLower), abs(yUpper),
                            abs(frame.origin.x), abs(frame.origin.y), abs(frame.origin.z))
        // The tool extends beyond the source envelope; this is representational
        // construction slack, never a relaxation of source intersection tolerance.
        let margin = max(tolerance.distance * 16, magnitude.ulp * 128).nextUp
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Double.self))
        let bounds = [ (xLower - margin).nextDown, (xUpper + margin).nextUp,
                       (yLower - margin).nextDown, (yUpper + margin).nextUp ]
        try execution.consumeWork(bounds.count)
        guard margin.isFinite, bounds.allSatisfy({ $0.isFinite }), bounds[1] > bounds[0], bounds[3] > bounds[2] else {
            throw failure(.invalidInput, "Section cutting extent cannot be represented finitely.", tolerance)
        }
        let surface: Surface3D
        var edges: [BRepSewingEdge] = []
        if let preparation = cuttingPreparation {
            surface = .procedural(.originalAffineWord(preparation.image))
            edges = try preparation.edges(u: .init(lower: bounds[0], upper: bounds[1]),
                v: .init(lower: bounds[2], upper: bounds[3]), tolerance: tolerance, using: &execution)
        } else {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: (Double, Double).self))
            let coordinates = [(bounds[0], bounds[2]), (bounds[1], bounds[2]),
                               (bounds[1], bounds[3]), (bounds[0], bounds[3])]
            let corners = try OriginalParameterQueryStorage.map(coordinates, using: &execution) { coordinate, execution in
                frame.origin + frame.horizontal * coordinate.0 + frame.vertical * coordinate.1
            }
            surface = Surface3D.plane(Plane3D(origin: frame.origin, normal: frame.normal))
            try OriginalParameterQueryStorage.reserve(4, in: &edges, using: &execution)
            for index in 0..<4 {
                try execution.consumeWork(1)
                let start = corners[index], end = corners[(index + 1) % 4], delta = end - start
                let curve = Curve3D.line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
                try OriginalParameterQueryStorage.append(BRepSewingEdge(stableID: "drawing:plane:edge:\(index)", curve: curve,
                    startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                    surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                        for: curve, startParameter: 0, endParameter: delta.length, on: surface, tolerance: tolerance, using: &execution)), to: &edges, using: &execution)
            }
        }
        try execution.retainStorage(bytes: MemoryLayout<BRepSewingLoop>.stride + MemoryLayout<BRepSewingFacePatch>.stride + MemoryLayout<BRepSewingShell>.stride)
        let patch = BRepSewingFacePatch(stableID: "drawing:plane:face", surface: surface, orientation: .forward,
            loops: [BRepSewingLoop(stableID: "drawing:plane:loop", role: .outer, edges: edges)])
        let tool = try sewer.sew(BRepSewingRequest(featureID: FeatureID(), bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "drawing:plane:shell", patches: [patch])]), tolerance: tolerance, using: &execution)
        guard tool.brep.faces.count == 1, let cuttingFaceID = tool.brep.faces.keys.first else {
            throw failure(.topologyFailure, "Section sewing did not produce one complete cutting face.", tolerance)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: BRepModel.self))
        let combined = try BRepModelCombiner().combined([source, tool.brep], using: &execution)
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let graph = try pipeline.completeIntersectionGraph(
            targetBodyIDs: try OriginalParameterQueryStorage.ordered(bodyIDs, using: &execution, less: <),
            toolBodyID: tool.bodyID, operation: .union, model: combined, tolerance: tolerance, using: &execution)
        let split = try pipeline.uvSplitGraph(intersectionGraph: graph, model: combined, tolerance: tolerance, using: &execution)
        var components: [BRepDrawingSectionComponent] = []
        for faceSplit in split.splits {
            guard let bodyID = owners[faceSplit.facePair.targetFaceID] else {
                throw failure(.missingReference, "Section split lost original-face provenance.", tolerance)
            }
            for component in faceSplit.components {
                try execution.consumeWork(1)
                guard components.count < maximumComponents else {
                    throw failure(.resourceLimitExceeded, "Section retained-component capacity exhausted.", tolerance)
                }
                try OriginalParameterQueryStorage.append(BRepDrawingSectionComponent(bodyID: bodyID, faceID: faceSplit.facePair.targetFaceID,
                    materialID: source.bodies[bodyID]?.material, ordinal: components.count, geometry: component.geometry), to: &components, using: &execution)
            }
        }
        try execution.consumeWork(1)
        return BRepDrawingSection(sourceDocument: evaluated.document, configuration: evaluated.configuration,
                                  frame: frame, horizontalRange: try ScalarInterval(lower: bounds[0], upper: bounds[1]),
                                  verticalRange: try ScalarInterval(lower: bounds[2], upper: bounds[3]), originalBRep: evaluated.brep, workingBRep: source, placement: placement,
                                      consumedPreparationWork: execution.localWork - operationWorkStart,
                                      retainedPreparationEntities: retainedPreparationEntities,
                                  cuttingModel: combined, cuttingFaceID: cuttingFaceID,
                                  splitGraph: split, components: components, cuttingSupport: cuttingPreparation?.source,
                                      retainedPreparationBytes: execution.localStorageBytes - operationBytesStart)
    }

    private func projectedRange(_ position: CoordinateEnclosure3D, origin: Point3D,
                                direction: Vector3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        var lower = 0.0, upper = 0.0
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: (ScalarInterval, Double, Double).self))
        for (range, offset, coefficient) in [(position.x, origin.x, direction.x),
                                             (position.y, origin.y, direction.y),
                                             (position.z, origin.z, direction.z)] {
            try execution.consumeWork(1)
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
