import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Carries the faces no intersection splits, each kept, turned or dropped whole by the region
/// rule from where it lies against the other operand's material.
struct ClosedIntersectionUnsplitFaceMaterializer {
    private let pointSampler: BRepFaceInteriorPointSampler

    init(pointSampler: BRepFaceInteriorPointSampler = BRepFaceInteriorPointSampler()) {
        self.pointSampler = pointSampler
    }

    func patches(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        splitFaceIDs: Set<FaceID>,
        forcedActions: [FaceID: BooleanRegionSelectionAction] = [:],
        splitPatches: [BRepSewingFacePatch] = [],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        try execution.consumeWork(1)
        try tolerance.validate()
        // An intersection curve may only touch a face's boundary edge (two equal cylinders
        // meeting in a tee touch along the line where the upright's halves meet) and not enter
        // the neighbouring face, which is then carried whole while the split face's copy of the
        // shared edge is cut at the touching point. The carried edge is cut there too.
        var junctionPoints: [Point3D] = []
        for patch in splitPatches {
            try execution.consumeWork(1)
            for loop in patch.loops {
            try execution.consumeWork(1)
                for edge in loop.edges {
            try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(edge.startPoint, to: &junctionPoints, using: &execution)
                    try OriginalParameterQueryStorage.append(edge.endPoint, to: &junctionPoints, using: &execution)
                }
            }
        }
        guard targetBodyIDs.isEmpty == false,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              targetBodyIDs.contains(toolBodyID) == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed-intersection materialization requires distinct Boolean operands."
            )
        }
        var targetFaceIDs: [FaceID] = []
        for bodyID in targetBodyIDs {
            try execution.consumeWork(1)
            let faces = try faceIDs(in: bodyID, model: model, tolerance: tolerance, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: faces, to: &targetFaceIDs, using: &execution)
        }
        let toolFaceIDs = try faceIDs(
            in: toolBodyID,
            model: model,
            tolerance: tolerance
        , using: &execution)
        guard splitFaceIDs.isSubset(of: Set(targetFaceIDs + toolFaceIDs)) else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Closed face split does not belong to a declared Boolean operand."
            )
        }
        var classificationBodyIDs: [BodyID] = []
        if targetFaceIDs.contains(where: {
            splitFaceIDs.contains($0) == false && forcedActions[$0] == nil
        }) {
            try OriginalParameterQueryStorage.append(toolBodyID, to: &classificationBodyIDs, using: &execution)
        }
        if toolFaceIDs.contains(where: {
            splitFaceIDs.contains($0) == false && forcedActions[$0] == nil
        }) {
            try OriginalParameterQueryStorage.append(contentsOf: targetBodyIDs, to: &classificationBodyIDs, using: &execution)
        }
        let classificationSessions: SolidPointClassificationSessionSet?
        if classificationBodyIDs.isEmpty {
            classificationSessions = nil
        } else {
            classificationSessions = try SolidPointClassificationSessionSet(
                bodyIDs: classificationBodyIDs,
                pointClassifier: operands.pointClassifier,
                model: model,
                tolerance: tolerance
            , using: &execution)
        }
        let targetPatches = try carriedPatches(
            faceIDs: targetFaceIDs,
            excluding: splitFaceIDs,
            oppositeBodyIDs: [toolBodyID],
            isToolFace: false,
            operation: operation,
            stablePrefix: "closed-intersection:carried:target",
            forcedActions: forcedActions,
            junctionPoints: junctionPoints,
            model: model,
            sourceSubshapes: sourceSubshapes,
            classificationSessions: classificationSessions,
            operands: operands,
            tolerance: tolerance
        , using: &execution)
        let toolPatches = try carriedPatches(
            faceIDs: toolFaceIDs,
            excluding: splitFaceIDs,
            oppositeBodyIDs: targetBodyIDs,
            isToolFace: true,
            operation: operation,
            stablePrefix: "closed-intersection:carried:tool",
            forcedActions: forcedActions,
            junctionPoints: junctionPoints,
            model: model,
            sourceSubshapes: sourceSubshapes,
            classificationSessions: classificationSessions,
            operands: operands,
            tolerance: tolerance
        , using: &execution)
        var result = targetPatches
        try execution.retainKernelValues(count: result.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
        try OriginalParameterQueryStorage.append(contentsOf: toolPatches, to: &result, using: &execution)
        return result
    }

    private func carriedPatches(
        faceIDs: [FaceID],
        excluding splitFaceIDs: Set<FaceID>,
        oppositeBodyIDs: [BodyID],
        isToolFace: Bool,
        operation: BooleanOperation,
        stablePrefix: String,
        forcedActions: [FaceID: BooleanRegionSelectionAction],
        junctionPoints: [Point3D],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        classificationSessions: SolidPointClassificationSessionSet?,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        try execution.consumeWork(1)
        var patches: [BRepSewingFacePatch] = []
        for (faceIndex, faceID) in faceIDs.sorted().enumerated()
            where splitFaceIDs.contains(faceID) == false {
            try execution.consumeWork(1)
            let action: BooleanRegionSelectionAction
            if let forcedAction = forcedActions[faceID] {
                action = forcedAction
            } else {
                guard let classificationSessions else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "Unsplit Boolean face classification preparation is missing."
                    )
                }
                let point = try pointSampler.point(
                    on: faceID,
                    in: model,
                    tolerance: tolerance
                , using: &execution)
                let classification = try classification(
                    of: point,
                    in: oppositeBodyIDs,
                    classificationSessions: classificationSessions
                , using: &execution)
                guard classification != .boundary else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "An unsplit Boolean face resolved to the opposite operand boundary without explicit coincident ownership."
                    )
                }
                action = operands.rule.action(
                    operation: operation,
                    classification: classification,
                    isToolFace: isToolFace
                )
            }
            switch action {
            case .discard:
                continue
            case .partitionBoundary:
                throw KernelError(
                    phase: .topology,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Closed-intersection slice materialization requires explicit partition shells."
                )
            case .keep, .keepReversed:
                break
            }
            guard let face = model.faces[faceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Unsplit Boolean face disappeared during materialization."
                )
            }
            let stableID = "\(stablePrefix):face:\(faceIndex)"
            let source = try cutAtJunctions(
                SourceBRepFacePatchBuilder().build(
                    faceID: faceID,
                    stableID: stableID,
                    from: model,
                    sourceSubshapes: sourceSubshapes,
                    tolerance: tolerance
                , using: &execution).patch,
                junctionPoints: junctionPoints,
                tolerance: tolerance
            , using: &execution)
            let orientation = action == .keepReversed
                ? reversed(face.orientation)
                : face.orientation
            try OriginalParameterQueryStorage.append(try BRepSewingPatchOrientationAdapter().reorient(
                source,
                to: orientation,
                tolerance: tolerance
            , using: &execution), to: &patches, using: &execution)
        }
        return patches
    }

    private func cutAtJunctions(
        _ patch: BRepSewingFacePatch,
        junctionPoints: [Point3D],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        guard junctionPoints.isEmpty == false else { return patch }
        let subdivider = BRepSewingEdgeSubdivider()
        var changed = false
        var loops: [BRepSewingLoop] = []
        for loop in patch.loops {
            try execution.consumeWork(1)
            var edges: [BRepSewingEdge] = []
            for edge in loop.edges {
                try execution.consumeWork(1)
                var interior: [Point3D] = []
                for point in junctionPoints {
                    try execution.consumeWork(1)
                    if (point - edge.startPoint).length > tolerance.distance && (point - edge.endPoint).length > tolerance.distance {
                        try OriginalParameterQueryStorage.append(point, to: &interior, using: &execution)
                    }
                }
                guard !interior.isEmpty else {
                    try OriginalParameterQueryStorage.append(edge, to: &edges, using: &execution)
                    continue
                }
                let contained = try subdivider.containedPoints(from: interior, on: edge, tolerance: tolerance, using: &execution)
                guard !contained.isEmpty else {
                    try OriginalParameterQueryStorage.append(edge, to: &edges, using: &execution)
                    continue
                }
                changed = true
                let divided = try subdivider.subdivide(edge, at: contained, tolerance: tolerance, using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: divided, to: &edges, using: &execution)
            }
            try OriginalParameterQueryStorage.append(BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges), to: &loops, using: &execution)
        }
        guard changed else { return patch }
        return BRepSewingFacePatch(
            stableID: patch.stableID,
            surface: patch.surface,
            orientation: patch.orientation,
            loops: loops,
            parentSubshapeIDs: patch.parentSubshapeIDs
        )
    }

    private func faceIDs(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [FaceID] {
        try execution.consumeWork(1)
        guard let body = model.bodies[bodyID],
              body.shellIDs.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Closed-intersection materialization references a missing operand shell."
            )
        }
        var result: [FaceID] = []
        for shellID in body.shellIDs.sorted() {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Closed-intersection materialization references a missing operand shell."
                )
            }
            try OriginalParameterQueryStorage.append(contentsOf: shell.faceIDs, to: &result, using: &execution)
        }
        return result.sorted()
    }

    private func classification(
        of point: Point3D,
        in bodyIDs: [BodyID],
        classificationSessions: SolidPointClassificationSessionSet
    , using execution: inout OriginalQueryExecution) throws -> SolidPointClassification {
        try execution.consumeWork(1)
        var isInside = false
        for bodyID in bodyIDs {
            try execution.consumeWork(1)
            let classification = try classificationSessions.classify(
                point,
                in: bodyID
            , using: &execution)
            if classification == .boundary {
                return .boundary
            }
            isInside = isInside || classification == .inside
        }
        return isInside ? .inside : .outside
    }

    private func reversed(_ orientation: Orientation) -> Orientation {
        orientation == .forward ? .reversed : .forward
    }
}
