import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Imprints curves on the faces of one body: every face a curve lies on is split along it with
/// both sides kept, and the body stays the same solid or sheet with the new edges.
///
/// Each curve is an exact edge on one face (its model-space curve and its parameter curve on that
/// face) whose ends lie on the face's boundary, on another imprinted curve, or meet each other in
/// a closed chain. Every curve end and every crossing becomes a point the faces sharing an edge
/// split that edge at, so a neighbouring face that no curve reaches still meets the split face
/// edge to edge. The faces keep their surfaces and sides; every shell keeps its faces and role, so
/// a solid stays a solid of the same components. The source body and every subshape within it
/// are replaced, each new face and edge tracing to the one it came from.
struct BRepFaceImprinter {
    /// One curve to imprint on one face.
    struct Curve {
        let faceID: FaceID
        let edge: BRepSewingEdge
    }

    private let sewer: any BRepSewing

    init(sewer: any BRepSewing = DefaultBRepSewer()) {
        self.sewer = sewer
    }

    func imprint(
        _ curves: [Curve],
        on bodyID: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let model = context.brep
        let tolerance = context.tolerance
        let subshapes = context.subshapes.entries
        guard let body = model.bodies[bodyID] else {
            throw failure(.missingReference, featureID, tolerance, "The body to imprint on is missing.")
        }
        guard curves.isEmpty == false else {
            throw failure(.invalidInput, featureID, tolerance, "There is nothing to imprint on the body.")
        }
        var shellIndexByFace: [FaceID: Int] = [:]
        let shells = try body.shellIDs.map { shellID -> Shell in
            guard let shell = model.shells[shellID] else {
                throw failure(.missingReference, featureID, tolerance, "An imprinted body's shell is missing.")
            }
            return shell
        }
        for (index, shell) in shells.enumerated() {
            for faceID in shell.faceIDs { shellIndexByFace[faceID] = index }
        }
        guard curves.allSatisfy({ shellIndexByFace[$0.faceID] != nil }) else {
            throw failure(.invalidInput, featureID, tolerance, "An imprinted curve does not lie on a face of the body.")
        }
        var boundariesByFace: [FaceID: [BooleanFaceArrangementBoundary]] = [:]
        for (ordinal, curve) in curves.enumerated() {
            boundariesByFace[curve.faceID, default: []].append(BooleanFaceArrangementBoundary(
                reference: BooleanFaceSplitComponentReference(
                    facePair: BooleanFacePairCandidate(targetFaceID: curve.faceID, toolFaceID: curve.faceID),
                    componentID: BooleanFaceSplitComponentID(ordinal: ordinal)
                ),
                segmentOrdinal: 0, faceID: curve.faceID, edge: curve.edge,
                forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true
            ))
        }
        let builder = BooleanOpenFaceArrangementBuilder()
        // Pass one finds where each face's arrangement splits its curves and its own edges; every
        // such point is shared, so pass two splits every edge the same way on both of its faces.
        var points = curves.flatMap { [$0.edge.startPoint, $0.edge.endPoint] }
        for faceID in boundariesByFace.keys.sorted() {
            let preview = try builder.build(
                faceID: faceID, boundaries: boundariesByFace[faceID] ?? [], model: model,
                sourceSubshapes: subshapes, tolerance: tolerance
            )
            points += preview.patches.flatMap { $0.loops.flatMap(\.edges).flatMap { [$0.startPoint, $0.endPoint] } }
        }
        let sharedPoints = representatives(of: points, tolerance: tolerance)
        let neighbours = try neighbouringFaces(of: Set(boundariesByFace.keys), in: shells, model: model, featureID: featureID, tolerance: tolerance)
        var sewingShells: [BRepSewingShell] = []
        for (index, shell) in shells.enumerated() {
            var patches: [BRepSewingFacePatch] = []
            for faceID in shell.faceIDs {
                if let boundaries = boundariesByFace[faceID] {
                    let arranged = try builder.build(
                        faceID: faceID, boundaries: boundaries, model: model, sourceSubshapes: subshapes,
                        sharedSubdivisionPoints: sharedPoints, tolerance: tolerance
                    )
                    guard arranged.isPartitioned else {
                        throw failure(.invalidInput, featureID, tolerance, "An imprinted curve does not divide its face.")
                    }
                    patches += arranged.patches
                } else if neighbours.contains(faceID) {
                    patches += try builder.build(
                        faceID: faceID, boundaries: [], model: model, sourceSubshapes: subshapes,
                        forcedAction: .keep, sharedSubdivisionPoints: sharedPoints, tolerance: tolerance
                    ).patches
                } else {
                    patches.append(try SourceBRepFacePatchBuilder().build(
                        faceID: faceID, stableID: "imprint:face:\(faceID)", from: model,
                        sourceSubshapes: subshapes, tolerance: tolerance
                    ).patch)
                }
            }
            sewingShells.append(BRepSewingShell(stableID: "imprint:shell:\(index)", patches: patches, orientation: shell.orientation))
        }
        let stableIDByShell = Dictionary(uniqueKeysWithValues: zip(body.shellIDs, sewingShells.map(\.stableID)))
        let topology: BRepSewingBodyTopology
        switch body.topology {
        case .sheet:
            topology = .sheet(shellStableIDs: sewingShells.map(\.stableID))
        case .solid(let components):
            topology = .solid(components: try components.map { component in
                guard let outer = stableIDByShell[component.outerShellID] else {
                    throw failure(.missingReference, featureID, tolerance, "An imprinted solid lost its outer shell.")
                }
                return BRepSewingSolidComponent(
                    outerShellStableID: outer,
                    voidShellStableIDs: component.voidShellIDs.compactMap { stableIDByShell[$0] }
                )
            })
        }
        let bodySubshapes = subshapes.filter { $0.value == .body(bodyID) }.map(\.key)
        let sewn = try sewer.sew(
            BRepSewingRequest(featureID: featureID, bodyTopology: topology, shells: sewingShells, bodyParentSubshapeIDs: bodySubshapes),
            tolerance: tolerance
        )
        let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: model)
        try replaced.validate(level: .exact, tolerance: tolerance)
        return EvaluationResult(
            brep: replaced,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: try BodyTopologyScope(bodyID: bodyID, model: model).subshapeIDs(in: context.subshapes),
            lineage: sewn.lineage
        )
    }

    /// The faces of the body that share an edge with a split face and are not split themselves:
    /// their shared edges must be split where the split faces' edges are.
    private func neighbouringFaces(
        of splitFaces: Set<FaceID>,
        in shells: [Shell],
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Set<FaceID> {
        func edges(of faceID: FaceID) throws -> Set<EdgeID> {
            guard let face = model.faces[faceID] else {
                throw failure(.missingReference, featureID, tolerance, "An imprinted body's face is missing.")
            }
            return Set(face.loops.flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] })
        }
        let splitEdges = try splitFaces.reduce(into: Set<EdgeID>()) { $0.formUnion(try edges(of: $1)) }
        var neighbours: Set<FaceID> = []
        for faceID in shells.flatMap(\.faceIDs) where splitFaces.contains(faceID) == false {
            if try edges(of: faceID).isDisjoint(with: splitEdges) == false { neighbours.insert(faceID) }
        }
        return neighbours
    }

    /// One point for each cluster of points closer than a few tolerances, so every face splits a
    /// shared edge at the very same point.
    private func representatives(of points: [Point3D], tolerance: ModelingTolerance) -> [Point3D] {
        var result: [Point3D] = []
        for point in points.sorted(by: { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) })
        where result.contains(where: { ($0 - point).length <= tolerance.distance * 8.0 }) == false {
            result.append(point)
        }
        return result
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
