import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct ClosedIntersectionFacePatchMaterializer {
    private let unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer

    init(
        unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer = ClosedIntersectionUnsplitFaceMaterializer()
    ) {
        self.unsplitFaceMaterializer = unsplitFaceMaterializer
    }

    func materialize(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        coincidentFaceActions: [FaceID: BooleanRegionSelectionAction] = [:],
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard targetBodyIDs.isEmpty == false,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              targetBodyIDs.contains(toolBodyID) == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed-intersection materialization requires distinct Boolean operands and a result operation."
            )
        }
        let targetFaceIDs = try operandFaceIDs(
            bodyIDs: targetBodyIDs,
            model: model,
            tolerance: tolerance
        , using: &execution)
        let toolFaceIDs = try operandFaceIDs(
            bodyIDs: [toolBodyID],
            model: model,
            tolerance: tolerance
        , using: &execution)
        let boundaries = try faceBoundaries(
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: regionSelectionGraph,
            targetFaceIDs: targetFaceIDs,
            toolFaceIDs: toolFaceIDs,
            model: model,
            tolerance: tolerance
        , using: &execution)
        let effectiveBoundaries = boundaries.filter {
            coincidentFaceActions[$0.faceID] != .discard
        }
        guard effectiveBoundaries.isEmpty == false || coincidentFaceActions.isEmpty == false else {
            throw unsupported(
                "Closed-intersection materialization requires a transverse component or explicit coincident ownership.",
                tolerance: tolerance
            )
        }

        var groupedBoundaries: [FaceID: [FaceBoundary]] = [:]
        for boundary in effectiveBoundaries {
            try execution.consumeWork(1)
            var items = groupedBoundaries[boundary.faceID] ?? []
            try execution.retainKernelValues(count: items.count, stride: MemoryLayout<FaceBoundary>.stride)
            try OriginalParameterQueryStorage.append(boundary, to: &items, using: &execution)
            try OriginalParameterQueryStorage.set(items, for: boundary.faceID, in: &groupedBoundaries, using: &execution)
        }
        var splitPatches: [BRepSewingFacePatch] = []
        for faceID in groupedBoundaries.keys.sorted() {
            try execution.consumeWork(1)
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            try OriginalParameterQueryStorage.append(contentsOf: try facePatches(
                faceID: faceID,
                boundaries: faceBoundaries,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            , using: &execution), to: &splitPatches, using: &execution)
        }
        let splitFaceIDs = Set(groupedBoundaries.keys)
        let carriedPatches = try unsplitFaceMaterializer.patches(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            splitFaceIDs: splitFaceIDs,
            forcedActions: coincidentFaceActions,
            splitPatches: splitPatches,
            model: model,
            sourceSubshapes: sourceSubshapes,
            operands: operands,
            tolerance: tolerance
        , using: &execution)
        var patches = splitPatches
        try execution.retainKernelValues(count: patches.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
        try OriginalParameterQueryStorage.append(contentsOf: carriedPatches, to: &patches, using: &execution)
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Closed Boolean region selection produced no exact face patches."
            )
        }
        let shells = try BRepSewingPatchShellPartitioner().shells(
            patches: patches,
            stablePrefix: "closed-intersection:shell",
            tolerance: tolerance
        , using: &execution)
        var bodyParents: [SubshapeID] = []
        for id in targetBodyIDs {
            try execution.consumeWork(1)
            let parents = try parentSubshapeIDs(for: .body(id), in: sourceSubshapes, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: parents, to: &bodyParents, using: &execution)
        }
        let toolParents = try parentSubshapeIDs(for: .body(toolBodyID), in: sourceSubshapes, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: toolParents, to: &bodyParents, using: &execution)
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: operands.resultBodyKind,
            shells: shells,
            bodyParentSubshapeIDs: bodyParents
        )
        try request.validate(tolerance: tolerance, using: &execution)
        return request
    }

    private func faceBoundaries(
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        targetFaceIDs: Set<FaceID>,
        toolFaceIDs: Set<FaceID>,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [FaceBoundary] {
        try execution.consumeWork(1)
        var result: [FaceBoundary] = []
        for split in uvSplitGraph.splits {
            try execution.consumeWork(1)
            guard targetFaceIDs.contains(split.facePair.targetFaceID),
                  toolFaceIDs.contains(split.facePair.toolFaceID),
                  let targetFace = model.faces[split.facePair.targetFaceID],
                  let toolFace = model.faces[split.facePair.toolFaceID],
                  let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
                  let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Closed Boolean split references topology outside its declared operands."
                )
            }
            for component in split.components {
            try execution.consumeWork(1)
                if case .coincident = component.geometry { continue }
                guard case let .closedCurve(closedIntersection) = component.geometry else {
                    if case .tangent = component.geometry { continue }
                    throw unsupported(
                        "Closed-intersection materialization requires closed partition components.",
                        tolerance: tolerance
                    )
                }
                guard closedIntersection.intersection.kind == .transverse else {
                    throw unsupported(
                        "Closed-intersection materialization requires an exact closed transverse curve with dual pcurves.",
                        tolerance: tolerance
                    )
                }
                let reference = BooleanFaceSplitComponentReference(
                    facePair: split.facePair,
                    componentID: component.id
                )
                try OriginalParameterQueryStorage.append(try faceBoundary(
                    reference: reference,
                    face: targetFace,
                    surface: targetSurface,
                    surfaceSide: .first,
                    closedIntersection: closedIntersection,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                , using: &execution), to: &result, using: &execution)
                try OriginalParameterQueryStorage.append(try faceBoundary(
                    reference: reference,
                    face: toolFace,
                    surface: toolSurface,
                    surfaceSide: .second,
                    closedIntersection: closedIntersection,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                , using: &execution), to: &result, using: &execution)
            }
        }
        return result
    }

    private func faceBoundary(
        reference: BooleanFaceSplitComponentReference,
        face: Face,
        surface: Surface3D,
        surfaceSide: BooleanClosedPcurveRegion.SurfaceSide,
        closedIntersection: BooleanClosedFaceIntersection,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> FaceBoundary {
        try execution.consumeWork(1)
        let region = try BooleanClosedPcurveRegion(
            reference: reference,
            closedIntersection: closedIntersection,
            surfaceSide: surfaceSide,
            surface: surface,
            tolerance: tolerance
        , using: &execution)
        let interiorIsPositive = region.isCounterclockwise == (face.orientation == .forward)
        let interiorSide: BooleanClassificationGraph.Side = interiorIsPositive ? .positive : .negative
        let exteriorSide: BooleanClassificationGraph.Side = interiorIsPositive ? .negative : .positive
        let decisions = regionSelectionGraph.decisions.filter {
            $0.sample.facePair == reference.facePair
                && $0.sample.componentID == reference.componentID
                && $0.sample.sourceFaceID == face.id
        }
        guard decisions.count == 2,
              Set(decisions.map(\.sample.side)) == Set([.negative, .positive]),
              decisions.allSatisfy({ $0.action != .partitionBoundary }),
              let interiorAction = decisions.first(where: {
                  $0.sample.side == interiorSide
              })?.action,
              let exteriorAction = decisions.first(where: {
                  $0.sample.side == exteriorSide
              })?.action else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Each closed pcurve boundary requires resolved decisions on both face regions."
            )
        }
        return FaceBoundary(
            faceID: face.id,
            reference: reference,
            surfaceSide: surfaceSide,
            closedIntersection: closedIntersection,
            region: region,
            interiorAction: interiorAction,
            exteriorAction: exteriorAction
        )
    }

    private func facePatches(
        faceID: FaceID,
        boundaries: [FaceBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        try execution.consumeWork(1)
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID],
              Set(boundaries.map(\.reference)).count == boundaries.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A split face requires unique closed pcurve components and exact geometry."
            )
        }
        let sortedBoundaries = boundaries.sorted { $0.reference < $1.reference }
        var boundaryByReference: [BooleanFaceSplitComponentReference: FaceBoundary] = [:]
        for boundary in sortedBoundaries {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.set(boundary, for: boundary.reference, in: &boundaryByReference, using: &execution) }
        let tree = try BooleanClosedPcurveContainmentTree(
            regions: try OriginalParameterQueryStorage.map(sortedBoundaries, using: &execution) { boundary, execution in boundary.region },
            tolerance: tolerance
        , using: &execution)
        var actions: [BooleanFaceSplitComponentReference?: BooleanRegionSelectionAction] = [:]
        let rootAction = try consistentAction(
            tree.roots.compactMap { boundaryByReference[$0]?.exteriorAction },
            tolerance: tolerance
        , using: &execution)
        try OriginalParameterQueryStorage.set(rootAction, for: nil, in: &actions, using: &execution)
        for reference in tree.nodes.keys.sorted() {
            try execution.consumeWork(1)
            guard let node = tree.nodes[reference],
                  let boundary = boundaryByReference[reference] else {
                throw missingBoundary(tolerance: tolerance)
            }
            let candidates = [boundary.interiorAction] + node.children.compactMap {
                boundaryByReference[$0]?.exteriorAction
            }
            let action = try consistentAction(candidates, tolerance: tolerance, using: &execution)
            try OriginalParameterQueryStorage.set(action, for: reference, in: &actions, using: &execution)
        }

        let orderedStarts = [Optional<BooleanFaceSplitComponentReference>.none]
            + tree.nodes.keys.sorted().map(Optional.some)
        var result: [BRepSewingFacePatch] = []
        for start in orderedStarts {
            try execution.consumeWork(1)
            guard let action = actions[start], action.isSelected else { continue }
            let parent = parent(of: start, in: tree)
            if start != nil,
               let parentAction = actions[parent],
               parentAction == action {
                continue
            }
            let component = try sameActionComponent(
                startingAt: start,
                action: action,
                actions: actions,
                tree: tree
            , using: &execution)
            try OriginalParameterQueryStorage.append(try facePatch(
                face: face,
                surface: surface,
                start: start,
                component: component,
                action: action,
                actions: actions,
                tree: tree,
                boundaryByReference: boundaryByReference,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            , using: &execution), to: &result, using: &execution)
        }
        return result
    }

    private func facePatch(
        face: Face,
        surface: Surface3D,
        start: BooleanFaceSplitComponentReference?,
        component: Set<BooleanFaceSplitComponentReference?>,
        action: BooleanRegionSelectionAction,
        actions: [BooleanFaceSplitComponentReference?: BooleanRegionSelectionAction],
        tree: BooleanClosedPcurveContainmentTree,
        boundaryByReference: [BooleanFaceSplitComponentReference: FaceBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        let outputOrientation = resultOrientation(source: face.orientation, action: action)
        let patchStableID = "closed-intersection:face:\(face.id):region:\(stableKey(start))"
        let orientedSource: BRepSewingFacePatch?
        if face.loops.isEmpty {
            orientedSource = nil
        } else {
            let source = try SourceBRepFacePatchBuilder().build(
                faceID: face.id,
                stableID: "\(patchStableID):source",
                from: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            , using: &execution).patch
            orientedSource = try BRepSewingPatchOrientationAdapter().reorient(
                source,
                to: outputOrientation,
                tolerance: tolerance
            , using: &execution)
        }
        let sourceOuterLoops = orientedSource?.loops.filter { $0.role == .outer } ?? []
        guard start != nil || sourceOuterLoops.count == 1 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "An exterior Boolean face region requires exactly one source outer loop."
            )
        }

        var loops: [BRepSewingLoop] = []
        if let start {
            guard let boundary = boundaryByReference[start] else {
                throw missingBoundary(tolerance: tolerance)
            }
            try OriginalParameterQueryStorage.append(try intersectionLoop(
                boundary: boundary,
                role: .outer,
                selectedBoundedInterior: true,
                outputOrientation: outputOrientation,
                stableID: "\(patchStableID):outer",
                tolerance: tolerance
            , using: &execution), to: &loops, using: &execution)
        } else {
            try OriginalParameterQueryStorage.append(sourceOuterLoops[0], to: &loops, using: &execution)
        }

        let frontier = component.flatMap { node in
            children(of: node, in: tree).filter {
                actions[$0] != action
            }
        }.sorted()
        for reference in frontier {
            try execution.consumeWork(1)
            guard let boundary = boundaryByReference[reference] else {
                throw missingBoundary(tolerance: tolerance)
            }
            try OriginalParameterQueryStorage.append(try intersectionLoop(
                boundary: boundary,
                role: .inner,
                selectedBoundedInterior: false,
                outputOrientation: outputOrientation,
                stableID: "\(patchStableID):inner:\(stableKey(reference))",
                tolerance: tolerance
            , using: &execution), to: &loops, using: &execution)
        }

        let sourceInnerLoops = orientedSource?.loops.filter { $0.role == .inner } ?? []
        for loop in sourceInnerLoops {
            try execution.consumeWork(1)
            let owner = try sourceLoopOwner(
                loop,
                tree: tree,
                tolerance: tolerance
            , using: &execution)
            if component.contains(owner) {
                try OriginalParameterQueryStorage.append(loop, to: &loops, using: &execution)
            }
        }
        let parents = try orientedSource?.parentSubshapeIDs
            ?? parentSubshapeIDs(for: .face(face.id), in: sourceSubshapes, using: &execution)
        let patch = try BRepSewingFacePatch(
            stableID: patchStableID,
            surface: surface,
            orientation: outputOrientation,
            loops: loops,
            parentSubshapeIDs: parents, using: &execution
        )
        try patch.validate(tolerance: tolerance, using: &execution)
        return patch
    }

    private func intersectionLoop(
        boundary: FaceBoundary,
        role: LoopRole,
        selectedBoundedInterior: Bool,
        outputOrientation: Orientation,
        stableID: String,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingLoop {
        try execution.consumeWork(1)
        let boundedInteriorIsLeft = boundary.region.isCounterclockwise
            == (outputOrientation == .forward)
        let curveDirectionIsForward = selectedBoundedInterior
            ? boundedInteriorIsLeft
            : boundedInteriorIsLeft == false
        let surfaceSide: ClosedIntersectionSewingLoopBuilder.SurfaceSide =
            boundary.surfaceSide == .first ? .first : .second
        return try ClosedIntersectionSewingLoopBuilder().loop(
            for: boundary.closedIntersection,
            surfaceSide: surfaceSide,
            stableID: stableID,
            role: role,
            curveDirection: curveDirectionIsForward ? .forward : .reversed,
            tolerance: tolerance
        , using: &execution)
    }

    private func sourceLoopOwner(
        _ loop: BRepSewingLoop,
        tree: BooleanClosedPcurveContainmentTree,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BooleanFaceSplitComponentReference? {
        try execution.consumeWork(1)
        guard let edge = loop.edges.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A source face inner loop cannot be empty."
            )
        }
        let parameter = try edge.surfaceParameterCurve.startParameter(tolerance: tolerance, using: &execution)
        let point = Point2D(x: parameter.u, y: parameter.v)
        let containers = try tree.nodes.values.filter {
            try $0.region.containsStrictly(point, tolerance: tolerance, using: &execution)
        }
        let ranked = try containers.map { node in
            (
                node: node,
                depth: try tree.depth(
                    of: node.region.reference,
                    tolerance: tolerance
                , using: &execution)
            )
        }.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth > rhs.depth
            }
            return lhs.node.region.reference < rhs.node.region.reference
        }
        return ranked.first?.node.region.reference
    }

    private func sameActionComponent(
        startingAt start: BooleanFaceSplitComponentReference?,
        action: BooleanRegionSelectionAction,
        actions: [BooleanFaceSplitComponentReference?: BooleanRegionSelectionAction],
        tree: BooleanClosedPcurveContainmentTree
    , using execution: inout OriginalQueryExecution) throws -> Set<BooleanFaceSplitComponentReference?> {
        try execution.consumeWork(1)
        var result: Set<BooleanFaceSplitComponentReference?> = []
        var pending = [start]
        while let current = pending.popLast() {
            try execution.consumeWork(1)
            guard try OriginalParameterQueryStorage.insert(current, in: &result, using: &execution) else { continue }
            try OriginalParameterQueryStorage.append(contentsOf: children(of: current, in: tree).filter {
                actions[$0] == action
            }, to: &pending, using: &execution)
        }
        return result
    }

    private func children(
        of reference: BooleanFaceSplitComponentReference?,
        in tree: BooleanClosedPcurveContainmentTree
    ) -> [BooleanFaceSplitComponentReference] {
        guard let reference else { return tree.roots }
        return tree.nodes[reference]?.children ?? []
    }

    private func parent(
        of reference: BooleanFaceSplitComponentReference?,
        in tree: BooleanClosedPcurveContainmentTree
    ) -> BooleanFaceSplitComponentReference? {
        guard let reference else { return nil }
        return tree.nodes[reference]?.parent
    }

    private func consistentAction(
        _ candidates: [BooleanRegionSelectionAction],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BooleanRegionSelectionAction {
        try execution.consumeWork(1)
        guard candidates.isEmpty == false,
              candidates.allSatisfy({ $0 != .partitionBoundary }),
              Set(candidates).count == 1,
              let action = candidates.first else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Closed pcurve containment produced inconsistent decisions for one atomic face region."
            )
        }
        return action
    }

    private func operandFaceIDs(
        bodyIDs: [BodyID],
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Set<FaceID> {
        try execution.consumeWork(1)
        var result: Set<FaceID> = []
        for bodyID in bodyIDs {
            try execution.consumeWork(1)
            guard let body = model.bodies[bodyID], body.shellIDs.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Closed Boolean materialization references a missing operand body."
                )
            }
            for shellID in body.shellIDs {
            try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Closed Boolean materialization references a missing operand shell."
                    )
                }
                for id in shell.faceIDs {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(id, in: &result, using: &execution) }
            }
        }
        return result
    }

    private func resultOrientation(
        source: Orientation,
        action: BooleanRegionSelectionAction
    ) -> Orientation {
        guard action == .keepReversed else { return source }
        return source == .forward ? .reversed : .forward
    }

    private func stableKey(_ reference: BooleanFaceSplitComponentReference?) -> String {
        guard let reference else { return "root" }
        return stableKey(reference)
    }

    private func stableKey(_ reference: BooleanFaceSplitComponentReference) -> String {
        "\(reference.facePair.targetFaceID):\(reference.facePair.toolFaceID):\(reference.componentID.ordinal)"
    }

    private func parentSubshapeIDs(for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference], using execution: inout OriginalQueryExecution) throws -> [SubshapeID] {
        var result: [SubshapeID] = []
        for (id, candidate) in sourceSubshapes {
            try execution.consumeWork(1)
            if candidate == reference { try OriginalParameterQueryStorage.append(id, to: &result, using: &execution) }
        }
        try OriginalParameterQueryStorage.sort(&result, using: &execution) { $0 < $1 }
        return result
    }

    private func missingBoundary(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: "Closed pcurve containment lost a component boundary."
        )
    }

    private func unsupported(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: message
        )
    }

    private struct FaceBoundary: Sendable {
        let faceID: FaceID
        let reference: BooleanFaceSplitComponentReference
        let surfaceSide: BooleanClosedPcurveRegion.SurfaceSide
        let closedIntersection: BooleanClosedFaceIntersection
        let region: BooleanClosedPcurveRegion
        let interiorAction: BooleanRegionSelectionAction
        let exteriorAction: BooleanRegionSelectionAction
    }
}

private extension BooleanRegionSelectionAction {
    var isSelected: Bool {
        self == .keep || self == .keepReversed
    }
}
