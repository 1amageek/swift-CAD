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
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
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
        )
        let toolFaceIDs = try operandFaceIDs(
            bodyIDs: [toolBodyID],
            model: model,
            tolerance: tolerance
        )
        let boundaries = try faceBoundaries(
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: regionSelectionGraph,
            targetFaceIDs: targetFaceIDs,
            toolFaceIDs: toolFaceIDs,
            model: model,
            tolerance: tolerance
        )
        guard boundaries.isEmpty == false else {
            throw unsupported(
                "Closed-intersection materialization requires at least one exact transverse closed component.",
                tolerance: tolerance
            )
        }

        let groupedBoundaries = Dictionary(grouping: boundaries, by: \.faceID)
        var splitPatches: [BRepSewingFacePatch] = []
        for faceID in groupedBoundaries.keys.sorted() {
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            splitPatches.append(contentsOf: try facePatches(
                faceID: faceID,
                boundaries: faceBoundaries,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            ))
        }
        let splitFaceIDs = Set(groupedBoundaries.keys)
        let carriedPatches = try unsplitFaceMaterializer.patches(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            splitFaceIDs: splitFaceIDs,
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )
        let patches = splitPatches + carriedPatches
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
        )
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: shells,
            bodyParentSubshapeIDs: (targetBodyIDs + [toolBodyID]).flatMap {
                parentSubshapeIDs(for: .body($0), in: sourceSubshapes)
            }
        )
        try request.validate(tolerance: tolerance)
        return request
    }

    private func faceBoundaries(
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        targetFaceIDs: Set<FaceID>,
        toolFaceIDs: Set<FaceID>,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceBoundary] {
        var result: [FaceBoundary] = []
        for split in uvSplitGraph.splits {
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
                guard case let .closedCurve(closedIntersection) = component.geometry else {
                    if case .tangent = component.geometry { continue }
                    throw unsupported(
                        "Closed-intersection materialization requires closed partition components.",
                        tolerance: tolerance
                    )
                }
                guard closedIntersection.intersection.kind == .transverse,
                      case .bSpline = closedIntersection.intersection.firstSurfaceParameterCurve,
                      case .bSpline = closedIntersection.intersection.secondSurfaceParameterCurve else {
                    throw unsupported(
                        "Closed-intersection materialization requires an exact closed transverse curve with dual B-spline pcurves.",
                        tolerance: tolerance
                    )
                }
                let reference = BooleanFaceSplitComponentReference(
                    facePair: split.facePair,
                    componentID: component.id
                )
                result.append(try faceBoundary(
                    reference: reference,
                    face: targetFace,
                    surface: targetSurface,
                    surfaceSide: .first,
                    closedIntersection: closedIntersection,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                ))
                result.append(try faceBoundary(
                    reference: reference,
                    face: toolFace,
                    surface: toolSurface,
                    surfaceSide: .second,
                    closedIntersection: closedIntersection,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                ))
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
    ) throws -> FaceBoundary {
        let region = try BooleanClosedPcurveRegion(
            reference: reference,
            closedIntersection: closedIntersection,
            surfaceSide: surfaceSide,
            surface: surface,
            tolerance: tolerance
        )
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
    ) throws -> [BRepSewingFacePatch] {
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
        let boundaryByReference = Dictionary(uniqueKeysWithValues: sortedBoundaries.map {
            ($0.reference, $0)
        })
        let tree = try BooleanClosedPcurveContainmentTree(
            regions: sortedBoundaries.map(\.region),
            tolerance: tolerance
        )
        var actions: [BooleanFaceSplitComponentReference?: BooleanRegionSelectionAction] = [:]
        actions[nil] = try consistentAction(
            tree.roots.compactMap { boundaryByReference[$0]?.exteriorAction },
            tolerance: tolerance
        )
        for reference in tree.nodes.keys.sorted() {
            guard let node = tree.nodes[reference],
                  let boundary = boundaryByReference[reference] else {
                throw missingBoundary(tolerance: tolerance)
            }
            let candidates = [boundary.interiorAction] + node.children.compactMap {
                boundaryByReference[$0]?.exteriorAction
            }
            actions[reference] = try consistentAction(candidates, tolerance: tolerance)
        }

        let orderedStarts = [Optional<BooleanFaceSplitComponentReference>.none]
            + tree.nodes.keys.sorted().map(Optional.some)
        var result: [BRepSewingFacePatch] = []
        for start in orderedStarts {
            guard let action = actions[start], action.isSelected else { continue }
            let parent = parent(of: start, in: tree)
            if start != nil,
               let parentAction = actions[parent],
               parentAction == action {
                continue
            }
            let component = sameActionComponent(
                startingAt: start,
                action: action,
                actions: actions,
                tree: tree
            )
            result.append(try facePatch(
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
            ))
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
    ) throws -> BRepSewingFacePatch {
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
            ).patch
            orientedSource = try BRepSewingPatchOrientationAdapter().reorient(
                source,
                to: outputOrientation,
                tolerance: tolerance
            )
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
            loops.append(try intersectionLoop(
                boundary: boundary,
                role: .outer,
                selectedBoundedInterior: true,
                outputOrientation: outputOrientation,
                stableID: "\(patchStableID):outer",
                tolerance: tolerance
            ))
        } else {
            loops.append(sourceOuterLoops[0])
        }

        let frontier = component.flatMap { node in
            children(of: node, in: tree).filter {
                actions[$0] != action
            }
        }.sorted()
        for reference in frontier {
            guard let boundary = boundaryByReference[reference] else {
                throw missingBoundary(tolerance: tolerance)
            }
            loops.append(try intersectionLoop(
                boundary: boundary,
                role: .inner,
                selectedBoundedInterior: false,
                outputOrientation: outputOrientation,
                stableID: "\(patchStableID):inner:\(stableKey(reference))",
                tolerance: tolerance
            ))
        }

        let sourceInnerLoops = orientedSource?.loops.filter { $0.role == .inner } ?? []
        for loop in sourceInnerLoops {
            let owner = try sourceLoopOwner(
                loop,
                tree: tree,
                tolerance: tolerance
            )
            if component.contains(owner) {
                loops.append(loop)
            }
        }
        let patch = BRepSewingFacePatch(
            stableID: patchStableID,
            surface: surface,
            orientation: outputOrientation,
            loops: loops,
            parentSubshapeIDs: orientedSource?.parentSubshapeIDs
                ?? parentSubshapeIDs(for: .face(face.id), in: sourceSubshapes)
        )
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func intersectionLoop(
        boundary: FaceBoundary,
        role: LoopRole,
        selectedBoundedInterior: Bool,
        outputOrientation: Orientation,
        stableID: String,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingLoop {
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
        )
    }

    private func sourceLoopOwner(
        _ loop: BRepSewingLoop,
        tree: BooleanClosedPcurveContainmentTree,
        tolerance: ModelingTolerance
    ) throws -> BooleanFaceSplitComponentReference? {
        guard let edge = loop.edges.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A source face inner loop cannot be empty."
            )
        }
        let parameter = try edge.surfaceParameterCurve.startParameter(tolerance: tolerance)
        let point = Point2D(x: parameter.u, y: parameter.v)
        let containers = try tree.nodes.values.filter {
            try $0.region.containsStrictly(point, tolerance: tolerance)
        }.sorted {
            if $0.region.absoluteArea != $1.region.absoluteArea {
                return $0.region.absoluteArea < $1.region.absoluteArea
            }
            return $0.region.reference < $1.region.reference
        }
        return containers.first?.region.reference
    }

    private func sameActionComponent(
        startingAt start: BooleanFaceSplitComponentReference?,
        action: BooleanRegionSelectionAction,
        actions: [BooleanFaceSplitComponentReference?: BooleanRegionSelectionAction],
        tree: BooleanClosedPcurveContainmentTree
    ) -> Set<BooleanFaceSplitComponentReference?> {
        var result: Set<BooleanFaceSplitComponentReference?> = []
        var pending = [start]
        while let current = pending.popLast() {
            guard result.insert(current).inserted else { continue }
            pending.append(contentsOf: children(of: current, in: tree).filter {
                actions[$0] == action
            })
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
    ) throws -> BooleanRegionSelectionAction {
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
    ) throws -> Set<FaceID> {
        var result: Set<FaceID> = []
        for bodyID in bodyIDs {
            guard let body = model.bodies[bodyID], body.shellIDs.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Closed Boolean materialization references a missing operand body."
                )
            }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Closed Boolean materialization references a missing operand shell."
                    )
                }
                result.formUnion(shell.faceIDs)
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

    private func parentSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference]
    ) -> [SubshapeID] {
        sourceSubshapes.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
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
