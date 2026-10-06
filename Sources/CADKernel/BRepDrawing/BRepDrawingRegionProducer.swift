import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Composes original section boundaries through the existing exact halfedge arrangement.
public struct BRepDrawingRegionProducer: BRepDrawingRegionProducing {
    private let classifier: any SolidPointClassifying
    private let containment: any FacePointContainmentTesting

    public init(classifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier(),
                containment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()) {
        self.classifier = classifier
        self.containment = containment
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The public original section material path
    // still composes legacy classifier samples/clearance, arrangement subdivision
    // and patch validation without the caller's cumulative work/byte admission.
    // Those actual lower operations must share independent source/geometric/algebra
    // capabilities before this route can complete bounded D3 or page-region output.
    public func regions(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                        maximumBoundaryEdges: Int, maximumRegions: Int) throws -> [BRepDrawingMaterialRegion] {
        try section.validateCurrent(evaluated)
        let sourceSnapshot = BRepDrawingSourceSnapshot(evaluated)
        let working = section.workingBRep
        let tolerance = evaluated.configuration.tolerance
        guard maximumBoundaryEdges > 0, maximumRegions > 0 else {
            throw failure(.invalidInput, "Section material capacities must be positive.", tolerance)
        }
        guard let model = section.cuttingModel, let cuttingFaceID = section.cuttingFaceID,
              let split = section.splitGraph else {
            guard section.components.isEmpty else {
                throw failure(.missingReference, "Section material composition has no original cutting graph.", tolerance)
            }
            return []
        }
        guard let cuttingFace = model.faces[cuttingFaceID],
              let cuttingSurface = model.geometry.surfaces[cuttingFace.surfaceID] else {
            throw failure(.missingReference, "Section material composition has no cutting face.", tolerance)
        }
        var bodyByFace: [FaceID: BodyID] = [:]
        var facesByBody: [BodyID: Set<FaceID>] = [:]
        var coincidentFaces: [BodyID: Set<FaceID>] = [:]
        for component in section.components {
            try CurrentTaskCancellationChecker().checkCancellation()
            if let previous = bodyByFace[component.faceID], previous != component.bodyID {
                throw failure(.topologyFailure, "Section source face has conflicting body ownership.", tolerance)
            }
            bodyByFace[component.faceID] = component.bodyID
            facesByBody[component.bodyID, default: []].insert(component.faceID)
            if case .coincident = component.geometry {
                coincidentFaces[component.bodyID, default: []].insert(component.faceID)
            }
        }
        let solidBodies = facesByBody.keys.filter { working.bodies[$0]?.kind == .solid }.sorted()
        let solidSplit = BooleanUVSplitGraph(splits: split.splits.filter { faceSplit in
            bodyByFace[faceSplit.facePair.targetFaceID].map { solidBodies.contains($0) } ?? false
        })
        let closedMaterial = BRepDrawingClosedMaterialClassifier(base: classifier,
            coincidentFaces: coincidentFaces, containment: containment)
        let regularSamples = solidBodies.isEmpty ? BooleanClassificationGraph(samples: [])
            : try DefaultBooleanRegionClassifier().planeSideClassification(uvSplitGraph: solidSplit,
                targetBodyIDs: solidBodies, toolBodyID: try cuttingBodyID(of: cuttingFaceID, in: model, tolerance: tolerance),
                model: model, pointClassifier: closedMaterial, tolerance: tolerance)
        let regularDecisions = try BooleanRegionSelectionGraph(decisions: regularSamples.samples.map { sample in
            let action: BooleanRegionSelectionAction
            switch sample.classification {
            case .inside: action = .keep
            case .outside: action = .discard
            case .boundary:
                throw failure(.classificationFailure, "Section curve has unresolved material sectors.", tolerance)
            }
            return BooleanRegionSelectionGraph.Decision(sample: sample, action: action)
        })
        var boundariesByBody: [BodyID: [BooleanFaceArrangementBoundary]] = [:]
        var boundaryCount = 0
        var inputs: [PlaneEdgeClassificationBoundary] = []
        var nextOrdinal = Dictionary(uniqueKeysWithValues: split.splits.map { ($0.facePair, $0.components.count) })
        func append(_ edge: BRepSewingEdge, pair: BooleanFacePairCandidate, bodyID: BodyID) throws {
            guard boundaryCount < maximumBoundaryEdges else {
                throw failure(.resourceLimitExceeded, "Section material boundary allowance exhausted.", tolerance)
            }
            let ordinal = nextOrdinal[pair, default: 0]
            let advanced = ordinal.addingReportingOverflow(1)
            guard !advanced.overflow else {
                throw failure(.resourceLimitExceeded, "Section boundary ordinal overflowed.", tolerance)
            }
            nextOrdinal[pair] = advanced.partialValue
            boundaryCount += 1
            inputs.append(PlaneEdgeClassificationBoundary(
                reference: BooleanFaceSplitComponentReference(facePair: pair,
                    componentID: BooleanFaceSplitComponentID(ordinal: ordinal)),
                edge: edge, cuttingFaceID: cuttingFaceID, targetBodyID: bodyID))
        }
        var output: [BRepDrawingMaterialRegion] = []
        for faceSplit in split.splits {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard faceSplit.facePair.toolFaceID == cuttingFaceID,
                  let bodyID = bodyByFace[faceSplit.facePair.targetFaceID],
                  let body = working.bodies[bodyID] else {
                throw failure(.missingReference, "Section material split lost cutting or source ownership.", tolerance)
            }
            for component in faceSplit.components {
                let reference = BooleanFaceSplitComponentReference(facePair: faceSplit.facePair, componentID: component.id)
                if case .coincident = component.geometry {
                    guard let sourceFace = working.faces[faceSplit.facePair.targetFaceID] else {
                        throw failure(.missingReference, "Section cap source face is absent.", tolerance)
                    }
                    var capEdgeCount = 0
                    for loopID in sourceFace.loops {
                        guard let loop = working.loops[loopID] else {
                            throw failure(.missingReference, "Section cap loop is absent.", tolerance)
                        }
                        let total = capEdgeCount.addingReportingOverflow(loop.coedges.count)
                        guard !total.overflow, total.partialValue <= maximumBoundaryEdges - boundaryCount else {
                            throw failure(.resourceLimitExceeded, "Section cap boundary allowance exhausted.", tolerance)
                        }
                        capEdgeCount = total.partialValue
                    }
                    let original = try SourceBRepFacePatchBuilder().build(
                        faceID: faceSplit.facePair.targetFaceID,
                        stableID: "drawing:cap:\(bodyID):\(faceSplit.facePair.targetFaceID)",
                        from: working, sourceSubshapes: evaluated.subshapes.entries, tolerance: tolerance).patch
                    if body.kind != .solid {
                        boundaryCount += capEdgeCount
                        guard output.count < maximumRegions else {
                            throw failure(.resourceLimitExceeded, "Section material region allowance exhausted.", tolerance)
                        }
                        try original.validate(tolerance: tolerance)
                        output.append(BRepDrawingMaterialRegion(bodyID: bodyID, materialID: body.material,
                            sourceFaceIDs: [faceSplit.facePair.targetFaceID], patch: original, sourceSnapshot: sourceSnapshot, sectionIdentity: section.publicationIdentity, placement: section.placement))
                        continue
                    }
                    for loop in original.loops {
                        for edge in loop.edges {
                            guard boundaryCount < maximumBoundaryEdges else {
                                throw failure(.resourceLimitExceeded, "Section cap boundary allowance exhausted.", tolerance)
                            }
                            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(for: edge.curve,
                                startParameter: edge.startParameter, endParameter: edge.endParameter,
                                on: cuttingSurface, tolerance: tolerance)
                            let projected = BRepSewingEdge(stableID: edge.stableID, curve: edge.curve,
                                startParameter: edge.startParameter, endParameter: edge.endParameter,
                                startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: pcurve,
                                parentSubshapeIDs: edge.parentSubshapeIDs,
                                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                            try append(projected, pair: faceSplit.facePair, bodyID: bodyID)
                        }
                    }
                } else if body.kind == .solid {
                    let count: Int
                    switch component.geometry {
                    case .transverseSegment: count = 1
                    case .closedCurve: count = 2
                    case .trimmedCurve(let chain): count = chain.segments.count
                    case .tangent, .coincident: count = 0
                    }
                    guard count <= maximumBoundaryEdges - boundaryCount else {
                        throw failure(.resourceLimitExceeded, "Section curve boundary allowance exhausted.", tolerance)
                    }
                    let parents = evaluated.subshapes.entries.compactMap { id, topology in
                        topology == .face(faceSplit.facePair.targetFaceID) ? id : nil
                    }
                    let boundaries = try BooleanFaceArrangementBoundary.make(reference: reference,
                        geometry: component.geometry, face: cuttingFace, surfaceSide: .second,
                        regionSelectionGraph: regularDecisions, parentSubshapeIDs: parents, tolerance: tolerance)
                    guard boundaries.count <= maximumBoundaryEdges - boundaryCount else {
                        throw failure(.resourceLimitExceeded, "Section curve boundary allowance exhausted.", tolerance)
                    }
                    boundaryCount += boundaries.count
                    boundariesByBody[bodyID, default: []].append(contentsOf: boundaries)
                }
            }
        }
        let classified = inputs.isEmpty ? BooleanClassificationGraph(samples: [])
            : try DefaultBooleanRegionClassifier().planeEdgeSideClassification(
                boundaries: inputs, model: model, pointClassifier: closedMaterial, tolerance: tolerance)
        var samples: [BooleanFaceSplitComponentReference: [BooleanClassificationGraph.Sample]] = [:]
        for sample in classified.samples {
            let reference = BooleanFaceSplitComponentReference(facePair: sample.facePair, componentID: sample.componentID)
            samples[reference, default: []].append(sample)
        }
        for input in inputs {
            try CurrentTaskCancellationChecker().checkCancellation()
            let pair = samples[input.reference] ?? []
            guard pair.count == 2, let positive = pair.first(where: { $0.side == .positive }),
                  let negative = pair.first(where: { $0.side == .negative }),
                  pair.allSatisfy({ $0.sourceFaceID == cuttingFaceID && $0.oppositeBodyID == input.targetBodyID }) else {
                throw failure(.classificationFailure, "Section edge has no complete two-sided material classification.", tolerance)
            }
            func action(_ state: SolidPointClassification) throws -> BooleanRegionSelectionAction {
                switch state {
                case .inside: return .keep
                case .outside: return .discard
                case .boundary:
                    throw failure(.classificationFailure, "Section material sector remains unresolved.", tolerance)
                }
            }
            let left = try action(cuttingFace.orientation == .forward ? positive.classification : negative.classification)
            let right = try action(cuttingFace.orientation == .forward ? negative.classification : positive.classification)
            boundariesByBody[input.targetBodyID, default: []].append(BooleanFaceArrangementBoundary(
                reference: input.reference, segmentOrdinal: 0, faceID: cuttingFaceID, edge: input.edge,
                forwardLeftAction: left, forwardRightAction: right))
        }
        for bodyID in boundariesByBody.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            let arranged = try BooleanOpenFaceArrangementBuilder().build(faceID: cuttingFaceID,
                boundaries: boundariesByBody[bodyID] ?? [], model: model,
                sourceSubshapes: evaluated.subshapes.entries, tolerance: tolerance)
            for patch in arranged.patches {
                guard output.count < maximumRegions else {
                    throw failure(.resourceLimitExceeded, "Section material region allowance exhausted.", tolerance)
                }
                try patch.validate(tolerance: tolerance)
                output.append(BRepDrawingMaterialRegion(bodyID: bodyID,
                    materialID: working.bodies[bodyID]?.material,
                    sourceFaceIDs: (facesByBody[bodyID] ?? []).sorted(), patch: patch, sourceSnapshot: sourceSnapshot, sectionIdentity: section.publicationIdentity, placement: section.placement))
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return output
    }

    private func cuttingBodyID(of faceID: FaceID, in model: BRepModel,
                               tolerance: ModelingTolerance) throws -> BodyID {
        var result: BodyID?
        for body in model.bodies.values {
            for shellID in body.shellIDs where model.shells[shellID]?.faceIDs.contains(faceID) == true {
                guard result == nil else {
                    throw failure(.topologyFailure, "Cutting face has ambiguous body ownership.", tolerance)
                }
                result = body.id
            }
        }
        guard let result else { throw failure(.missingReference, "Cutting face has no body owner.", tolerance) }
        return result
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
