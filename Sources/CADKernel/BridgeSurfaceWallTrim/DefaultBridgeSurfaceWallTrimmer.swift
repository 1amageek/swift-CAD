import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Partitions a bridge by its selected finite BRep walls and publishes the unique connecting region.
public struct DefaultBridgeSurfaceWallTrimmer: BridgeSurfaceWallTrimming {
    private let sewer: any BRepSewing
    private let resolver: any StableSubshapeResolving

    public init(sewer: any BRepSewing = DefaultBRepSewer(),
                resolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.sewer = sewer
        self.resolver = resolver
    }

    public func trim(feature: FeatureNode, candidate: EvaluationResult,
                     context: EvaluationContext) throws -> EvaluationResult {
        guard case let .bridgeSurface(bridge) = feature.operation,
              case let .body(bodyID)? = candidate.subshapes[SubshapeID(featureID: feature.id, role: "body", ordinal: 0)],
              let body = candidate.brep.bodies[bodyID], body.kind == .sheet else {
            throw failure(.invalidInput, feature, context, "Wall trimming requires the generated bridge sheet.")
        }
        let model = candidate.brep
        let tolerance = context.tolerance
        let faces = body.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        guard faces.count == 1, let faceID = faces.first,
              let face = model.faces[faceID], case let .bSpline(surface)? = model.geometry.surfaces[face.surfaceID],
              case let .closed(vLower, vUpper) = surface.vDomain else {
            throw failure(.invalidInput, feature, context, "The admitted bridge candidate must retain its single native B-spline chart.")
        }
        var sourceSubshapes = context.subshapes.entries.merging(candidate.subshapes) { _, new in new }
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Bridge candidate loop is missing.") }
            for coedge in loop.edges {
                if case let .constantV(v, _, _)? = coedge.surfaceParameterCurve {
                    if v == vLower { sourceSubshapes[bridge.startBoundary.subshapeID] = .edge(coedge.edgeID) }
                    if v == vUpper { sourceSubshapes[bridge.endBoundary.subshapeID] = .edge(coedge.edgeID) }
                }
            }
        }
        var partitionModel = model
        var walls: [(parentID: SubshapeID, faceID: FaceID, bodyID: BodyID,
                     sourceMapping: [SubshapeID: TopologyReference])] = []
        let declarations = [(bridge.startWall, bridge.startBoundary, bridge.startTransform),
                            (bridge.endWall, bridge.endBoundary, bridge.endTransform)]
        for (wallOrdinal, declaration) in declarations.enumerated() {
            let (explicit, boundary, transform) = declaration
            let wallID: FaceID
            let parentID: SubshapeID
            let wallBodyID: BodyID
            if let explicit {
                guard case let .face(resolved) = try resolver.topologyReference(for: explicit,
                    model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance) else {
                    throw failure(.missingReference, feature, context, "A declared bridge wall must be a live finite face.")
                }
                wallID = resolved
                parentID = explicit.subshapeID
                wallBodyID = try context.bodyID(generatedBy: explicit.subshapeID.featureID)
            } else {
                guard case let .edge(edgeID) = try resolver.topologyReference(for: boundary,
                    model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance) else {
                    throw failure(.missingReference, feature, context, "An implicit bridge wall requires its original live boundary edge.")
                }
                wallBodyID = try context.bodyID(generatedBy: boundary.subshapeID.featureID)
                guard let sourceBody = context.brep.bodies[wallBodyID] else {
                    throw TopologyError.missingReference("The implicit bridge wall source body is missing.")
                }
                let incident = sourceBody.shellIDs.flatMap { context.brep.shells[$0]?.faceIDs ?? [] }.filter { ownerID in
                    context.brep.faces[ownerID]?.loops.contains { loopID in
                        context.brep.loops[loopID]?.edges.contains { $0.edgeID == edgeID } == true
                    } == true
                }
                guard incident.count == 1, let owner = incident.first,
                      let identity = context.subshapes.entries.filter({ $0.value == .face(owner) }).map(\.key).sorted().first else {
                    throw failure(.ambiguousSelection, feature, context,
                        "An implicit finite bridge wall requires one original incident face with retained source identity.")
                }
                wallID = owner
                parentID = identity
            }
            if let transform {
                let image = try placedWall(faceID: wallID, parentID: parentID, transform: transform,
                    ordinal: wallOrdinal, feature: feature, context: context)
                try BRepModelCombiner().merge(image.brep, into: &partitionModel)
                guard let imageBody = image.brep.bodies[image.bodyID], let shellID = imageBody.shellIDs.first,
                      let imageFaceID = image.brep.shells[shellID]?.faceIDs.first else {
                    throw TopologyError.missingReference("A retained affine wall image has no finite face.")
                }
                var mapping: [SubshapeID: TopologyReference] = [:]
                for (temporary, reference) in image.subshapes {
                    for parent in image.lineage[temporary]?.parents ?? [] { mapping[parent] = reference }
                }
                mapping[parentID] = .face(imageFaceID)
                walls.append((parentID, imageFaceID, image.bodyID, mapping))
            } else if !walls.contains(where: { $0.faceID == wallID }) {
                walls.append((parentID, wallID, wallBodyID, [:]))
            }
        }
        var boundaries: [BooleanFaceArrangementBoundary] = []
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        for wall in walls {
            try CurrentTaskCancellationChecker().checkCancellation()
            sourceSubshapes.merge(wall.sourceMapping) { _, new in new }
            let graph = try pipeline.completeIntersectionGraph(facePairs: [
                BooleanFacePairCandidate(targetFaceID: faceID, toolFaceID: wall.faceID)
            ], model: partitionModel, tolerance: tolerance)
            let splits = try pipeline.uvSplitGraph(intersectionGraph: graph, model: partitionModel, tolerance: tolerance)
            for split in splits.splits {
                for component in split.components {
                    let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                    let edges: [BRepSewingEdge]
                    if case .coincident = component.geometry {
                        edges = try CoincidentBooleanFaceArrangementBoundaryBuilder().outlineEdges(
                            of: wall.faceID, onto: faceID, reference: reference, model: partitionModel,
                            sourceSubshapes: sourceSubshapes, tolerance: tolerance)
                    } else {
                        edges = try BooleanFaceArrangementBoundary.edges(reference: reference, geometry: component.geometry,
                            faceID: faceID, surfaceSide: .first,
                            parentSubshapeIDs: [wall.parentID], tolerance: tolerance)
                    }
                    boundaries += edges.enumerated().map { ordinal, edge in
                        BooleanFaceArrangementBoundary(reference: reference, segmentOrdinal: ordinal, faceID: faceID,
                            edge: edge, forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true)
                    }
                }
            }
        }
        let patches: [BRepSewingFacePatch]
        if boundaries.isEmpty {
            patches = [try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: "bridge-wall:source",
                from: partitionModel, sourceSubshapes: sourceSubshapes, tolerance: tolerance).patch]
        } else {
            patches = try BooleanOpenFaceArrangementBuilder().build(faceID: faceID, boundaries: boundaries,
                model: partitionModel, sourceSubshapes: sourceSubshapes, tolerance: tolerance).patches
        }
        let connecting = try patches.filter { patch in
            let parents = Set(patch.loops.flatMap(\.edges).flatMap(\.parentSubshapeIDs))
            guard parents.contains(bridge.startBoundary.subshapeID), parents.contains(bridge.endBoundary.subshapeID) else { return false }
            for wall in walls where !parents.contains(wall.parentID) {
                // A wall coincident with an existing candidate boundary contributes no
                // new region; prove that whole boundary span against its finite split.
                let contacts = boundaries.filter { $0.edge.parentSubshapeIDs.contains(wall.parentID) }
                var hasContact = false
                for edge in patch.loops.flatMap(\.edges) {
                    for contact in contacts {
                        if case .coincident = try ExactTrimEdgeIntersector().intersections(edge, contact.edge,
                            sharedSurface: patch.surface, tolerance: tolerance) {
                            hasContact = true
                        }
                    }
                }
                if !hasContact { return false }
            }
            return true
        }
        guard connecting.count == 1, let selected = connecting.first else {
            throw failure(connecting.isEmpty ? .classificationFailure : .ambiguousSelection, feature, context,
                "Finite bridge walls did not determine one region connecting both original boundaries.")
        }
        let originalParents = [bridge.startBoundary.subshapeID, bridge.endBoundary.subshapeID] + walls.map { $0.parentID }
        let published = BRepSewingFacePatch(stableID: "bridge-wall:result", surface: selected.surface,
            orientation: selected.orientation, loops: selected.loops, parentSubshapeIDs: originalParents)
        let sewn = try sewer.sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "bridge-wall:shell", patches: [published])],
            bodyParentSubshapeIDs: originalParents), tolerance: tolerance)
        let replacement = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID,
            from: sewn.brep, in: model)
        let lineage = sewn.lineage.mapValues { entry in
            let parents = Array(Set(entry.parents.flatMap { $0.featureID == feature.id ? originalParents : [$0] })).sorted()
            return TopologyLineage(output: entry.output, parents: parents,
                relation: parents.isEmpty ? .generated : (parents.count == 1 ? .preserved : .merged))
        }
        try replacement.validate(level: .exact, tolerance: tolerance)
        return EvaluationResult(brep: replacement, subshapes: sewn.subshapes, lineage: lineage)
    }

    private func placedWall(faceID: FaceID, parentID: SubshapeID, transform: AffineTransform3D,
                            ordinal: Int, feature: FeatureNode, context: EvaluationContext) throws -> BRepSewingResult {
        let tolerance = context.tolerance
        let source = try SourceBRepFacePatchBuilder().build(faceID: faceID,
            stableID: "bridge-wall-image:\(ordinal)", from: context.brep,
            sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
        let surface = Surface3D.affineImage(try OriginalImageSurface3D(source: source.surface,
            transform: transform, tolerance: tolerance))
        let image = BRepSewingFacePatch(stableID: source.stableID, surface: surface,
            orientation: source.orientation, loops: try source.loops.map { loop in
                BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                    BRepSewingEdge(stableID: edge.stableID,
                        curve: .affineImage(try AffineImageCurve3D(source: edge.curve,
                            transform: transform, tolerance: tolerance)),
                        startParameter: edge.startParameter, endParameter: edge.endParameter,
                        startPoint: transform.applying(to: edge.startPoint), endPoint: transform.applying(to: edge.endPoint),
                        surfaceParameterCurve: edge.surfaceParameterCurve,
                        parentSubshapeIDs: edge.parentSubshapeIDs,
                        startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                        endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                })
            }, parentSubshapeIDs: [parentID])
        let determinantSign = try transform.originalDeterminantSign()
        let orientation = determinantSign == .negative
            ? (source.orientation == .forward ? Orientation.reversed : .forward) : source.orientation
        let oriented = try BRepSewingPatchOrientationAdapter().reorient(image, to: orientation, tolerance: tolerance)
        // This deterministic invocation namespace is never published as source identity.
        // The combiner checks every topology ID against the retained candidate snapshot.
        let bits = feature.id.bitPattern
        let temporary = FeatureID(highBits: bits.high ^ 0xB71D_9E4A_50C3_8621,
            lowBits: bits.low ^ 0x63A8_F245_C190_7BD4 ^ UInt64(ordinal))
        return try sewer.sew(BRepSewingRequest(featureID: temporary, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "bridge-wall-image:shell:\(ordinal)", patches: [oriented])],
            bodyParentSubshapeIDs: [parentID]), tolerance: tolerance)
    }

    private func failure(_ code: KernelErrorCode, _ feature: FeatureNode,
                         _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .classification, code: code, featureID: feature.id,
                    tolerance: context.tolerance, message: message)
    }
}
