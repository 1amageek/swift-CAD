import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Sews sheet bodies along their exactly matching edges (`SheetBodyJoining`).
///
/// Each source's exact faces become sewing patches under a prefix of its own, so identities from
/// different sources never collide. An edge another sheet's edge ends inside is split there
/// (`BRepSewingTJunctionSplitter`), and boundary edges pair wherever they coincide within the
/// tolerance (`BRepSewingEdgeFan`); a pair traversed the same way by both faces means the faces
/// disagree about which side is front, so the second is reoriented, spreading from the first
/// source's first face. An edge met by more than two faces, a set of sheets that falls apart into
/// separate groups, or faces that cannot all agree (a one-sided result) are refused. A shell left
/// with no boundary edge is sewn as a solid whose faces face out of the volume it encloses.
struct DefaultSheetBodyJoiner: SheetBodyJoining {
    private let sewer: any BRepSewing

    init(sewer: any BRepSewing = DefaultBRepSewer()) {
        self.sewer = sewer
    }

    /// The sources' faces as one consistently oriented set of patches, and whether they close.
    struct Plan {
        let patches: [BRepSewingFacePatch]
        let closes: Bool
    }

    func plan(
        bodyIDs: [BodyID],
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> Plan {
        var patches: [BRepSewingFacePatch] = []
        for (index, bodyID) in bodyIDs.enumerated() {
            guard model.bodies[bodyID]?.kind == .sheet else {
                throw error(.invalidInput, featureID, tolerance, "Only sheets are sewn together.")
            }
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: bodyID,
                featureID: featureID,
                from: model,
                sourceSubshapes: subshapes,
                tolerance: tolerance
            )
            patches += extraction.request.shells.flatMap(\.patches).map {
                prefixed($0, "sheet:\(index)")
            }
        }
        // Edges sharing only part of their length meet end to end once split at each other's ends.
        patches = try BRepSewingTJunctionSplitter(tolerance: tolerance).split(patches)
        let groups = try BRepSewingEdgeFan(tolerance: tolerance).groups(of: patches)
        guard groups.allSatisfy({ $0.count <= 2 }) else {
            throw error(.nonManifoldResult, featureID, tolerance, "More than two sheet faces meet at one edge.")
        }
        let pairs = groups.filter { $0.count == 2 }.map { ($0[0], $0[1]) }
        let flips = try orientationFlips(patchCount: patches.count, pairs: pairs, featureID: featureID, tolerance: tolerance)
        let adapter = BRepSewingPatchOrientationAdapter()
        let oriented = try patches.enumerated().map { index, patch in
            flips[index] ? try adapter.reorient(patch, to: opposite(patch.orientation), tolerance: tolerance) : patch
        }
        return Plan(patches: oriented, closes: pairs.count == groups.count)
    }

    func joinSheets(
        bodyIDs: [BodyID],
        closed: Bool,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BRepSewingResult {
        let tolerance = context.tolerance
        let plan = try plan(
            bodyIDs: bodyIDs, featureID: featureID, model: context.brep,
            subshapes: context.subshapes.entries, tolerance: tolerance
        )
        guard plan.closes == closed else {
            throw error(
                .invalidInput, featureID, tolerance,
                plan.closes ? "The sheets close; they join as a solid." : "The sheets leave open edges; they join as a sheet."
            )
        }
        let oriented = plan.patches
        let shell = BRepSewingShell(stableID: "join:shell", patches: oriented)
        guard closed else {
            return try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: [shell]), tolerance: tolerance)
        }
        // Closed: sewn once as a sheet to measure which way the faces face, then as the solid.
        let trial = try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: [shell]), tolerance: tolerance)
        guard let trialBody = trial.brep.bodies[trial.bodyID], trialBody.shellIDs.count == 1 else {
            throw error(.topologyFailure, featureID, tolerance, "Joined sheets did not sew into one shell.")
        }
        let volume = try trial.brep.signedVolume(ofShell: trialBody.shellIDs[0], tolerance: tolerance)
        let minimumVolume = tolerance.distance * tolerance.distance * tolerance.distance
        guard volume.isFinite, abs(volume) > minimumVolume else {
            throw error(.topologyFailure, featureID, tolerance, "Joined sheets close but enclose no volume.")
        }
        // A solid's outer shell is forward, so faces that face in are turned over instead.
        let adapter = BRepSewingPatchOrientationAdapter()
        let outwardPatches = volume > 0 ? oriented : try oriented.map {
            try adapter.reorient($0, to: opposite($0.orientation), tolerance: tolerance)
        }
        let outward = BRepSewingShell(stableID: shell.stableID, patches: outwardPatches)
        return try sewer.sew(
            BRepSewingRequest(
                featureID: featureID,
                bodyTopology: .solid(components: [BRepSewingSolidComponent(outerShellStableID: outward.stableID, voidShellStableIDs: [])]),
                shells: [outward]
            ),
            tolerance: tolerance
        )
    }

    /// Which patches must turn over so every shared edge is traversed once each way, the first
    /// patch keeping its side. Throws when the patches do not all connect or cannot agree.
    private func orientationFlips(
        patchCount: Int,
        pairs: [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)],
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [Bool] {
        var neighbours = Array(repeating: [(index: Int, differs: Bool)](), count: patchCount)
        for (first, second) in pairs where first.patchIndex != second.patchIndex {
            // Agreeing faces traverse their shared edge in opposite directions.
            let sameDirection = first.edge.startPoint.isApproximatelyEqual(to: second.edge.startPoint, tolerance: tolerance.distance)
            neighbours[first.patchIndex].append((second.patchIndex, sameDirection))
            neighbours[second.patchIndex].append((first.patchIndex, sameDirection))
        }
        var flips: [Bool?] = Array(repeating: nil, count: patchCount)
        flips[0] = false
        var pending = [0]
        while let index = pending.popLast() {
            guard let flipped = flips[index] else { continue }
            for neighbour in neighbours[index] {
                let expected = flipped != neighbour.differs
                if let known = flips[neighbour.index] {
                    guard known == expected else {
                        throw error(.invalidInput, featureID, tolerance, "The sheets cannot be joined with one front side.")
                    }
                } else {
                    flips[neighbour.index] = expected
                    pending.append(neighbour.index)
                }
            }
        }
        guard flips.allSatisfy({ $0 != nil }) else {
            throw error(.invalidInput, featureID, tolerance, "The sheets do not all meet along matching edges.")
        }
        return flips.map { $0 ?? false }
    }

    private func prefixed(_ patch: BRepSewingFacePatch, _ prefix: String) -> BRepSewingFacePatch {
        BRepSewingFacePatch(
            stableID: "\(prefix):\(patch.stableID)",
            surface: patch.surface,
            orientation: patch.orientation,
            loops: patch.loops.map { loop in
                BRepSewingLoop(
                    stableID: "\(prefix):\(loop.stableID)",
                    role: loop.role,
                    edges: loop.edges.map { edge in
                        BRepSewingEdge(
                            stableID: "\(prefix):\(edge.stableID)",
                            curve: edge.curve,
                            startParameter: edge.startParameter,
                            endParameter: edge.endParameter,
                            startPoint: edge.startPoint,
                            endPoint: edge.endPoint,
                            surfaceParameterCurve: edge.surfaceParameterCurve,
                            parentSubshapeIDs: edge.parentSubshapeIDs,
                            startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                            endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
                        )
                    }
                )
            },
            parentSubshapeIDs: patch.parentSubshapeIDs
        )
    }

    private func opposite(_ orientation: Orientation) -> Orientation {
        orientation == .forward ? .reversed : .forward
    }

    private func error(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}

/// Whether sheets would close into a solid when joined, so an author can choose the join mode.
public struct JoinSheetClosure {
    public init() {}

    /// Each target moved to its placement first, as joining moves it. Throws where joining itself
    /// would refuse: a source that is no sheet, an edge met by more than two faces, sheets that do
    /// not all meet, or faces that cannot agree on a front side.
    public func closes(sheets targets: [JoinBodiesTargetReference], in document: EvaluatedDocument) throws -> Bool {
        let tolerance = document.configuration.tolerance
        let featureID = FeatureID()
        let context = EvaluationContext(
            parameters: document.parameters,
            brep: document.brep,
            profiles: [:],
            curves: document.curves,
            subshapes: document.subshapes,
            lineage: document.lineage,
            tolerance: tolerance
        )
        let sewer = DefaultBRepSewer()
        let (stages, bodyIDs) = try JoinTargetPlacement(relocator: DefaultExactBodyPatternRebuilder(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator()
        )).place(targets, featureID: featureID, context: context)
        return try DefaultSheetBodyJoiner(sewer: sewer).plan(
            bodyIDs: bodyIDs, featureID: featureID, model: stages.context.brep,
            subshapes: stages.context.subshapes.entries, tolerance: tolerance
        ).closes
    }
}
