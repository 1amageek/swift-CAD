import CADCore
import CADIR
import CADModeling
import CADTopology

/// The Region Boolean: every region the operands' faces divide space into becomes a solid
/// component of one body, which replaces all the operands.
///
/// Every pair of operands is intersected; each face is split along every curve where another
/// operand crosses it, keeping every piece, and the pieces are assembled into the bounded cells
/// they enclose. Solids and sheets alike contribute only their faces, so a sheet divides whatever
/// region it reaches across.
struct RegionBooleanEvaluator {
    private let pipeline: BooleanPipeline

    init(pipeline: BooleanPipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())) {
        self.pipeline = pipeline
    }

    func evaluate(
        operandBodyIDs: [BodyID],
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try tolerance.validate()
        guard operandBodyIDs.count >= 2, Set(operandBodyIDs).count == operandBodyIDs.count,
              operandBodyIDs.allSatisfy({ model.bodies[$0] != nil }) else {
            throw KernelError(phase: .topology, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                message: "A Region Boolean needs at least two distinct operand bodies.")
        }
        var boundaries: [BooleanFaceArrangementBoundary] = []
        for (index, first) in operandBodyIDs.enumerated() {
            for second in operandBodyIDs.dropFirst(index + 1) {
                boundaries += try pairBoundaries(first, second, model: model, subshapes: subshapes, tolerance: tolerance)
            }
        }
        let arrangement = try SharedCurveFaceArrangement().arrange(
            boundaries: boundaries, model: model, sourceSubshapes: subshapes, tolerance: tolerance
        )
        var patches = arrangement.patches
        for bodyID in operandBodyIDs {
            for faceID in try faceIDs(of: bodyID, in: model, tolerance: tolerance)
                where arrangement.splitFaceIDs.contains(faceID) == false {
                patches.append(try SourceBRepFacePatchBuilder().build(
                    faceID: faceID, stableID: "region:face:\(faceID)",
                    from: model, sourceSubshapes: subshapes, tolerance: tolerance
                ).patch)
            }
        }
        let request = try BRepCellComplexBuilder(tolerance: tolerance).request(patches: patches, featureID: featureID)
        var resultModel = model
        var removedSubshapeIDs = Set<SubshapeID>()
        let removal = BRepBodyTopologyRemoval()
        for bodyID in operandBodyIDs {
            removedSubshapeIDs.formUnion(removal.subshapeIDs(bodyID: bodyID, in: resultModel, subshapes: subshapes))
            try removal.remove(bodyID: bodyID, from: &resultModel)
        }
        let sewn = try DefaultBRepSewer().sew(request.namespaced(as: .booleanResult), tolerance: tolerance)
        try BRepModelCombiner().merge(sewn.brep, into: &resultModel)
        let builtSubshapes = try OrthogonalBooleanFacePatchBuilder(tolerance: tolerance).generatedSubshapes(
            featureID: featureID, stableReferences: sewn.stableReferences
        )
        var result = EvaluationResult(
            brep: resultModel, subshapes: builtSubshapes, removedSubshapeIDs: removedSubshapeIDs,
            lineage: sewn.lineage(remappedTo: builtSubshapes)
        )
        let topologyLineage = try BooleanTopologyLineageBuilder().build(
            featureID: featureID,
            operandBodyIDs: operandBodyIDs,
            inputModel: model,
            resultModel: result.brep,
            inputSubshapes: subshapes,
            outputSubshapes: result.subshapes,
            inputLineage: inputLineage,
            tolerance: tolerance
        )
        for (subshapeID, entry) in topologyLineage where result.lineage[subshapeID] == nil {
            result.lineage[subshapeID] = entry
        }
        return result
    }

    /// The curves where the faces of `first` and `second` cross, on the faces of both, each
    /// splitting its face with both sides kept.
    private func pairBoundaries(
        _ first: BodyID,
        _ second: BodyID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BooleanFaceArrangementBoundary] {
        let intersections = try pipeline.completeIntersectionGraph(
            targetBodyIDs: [first], toolBodyID: second, operation: .region, model: model, tolerance: tolerance
        )
        let splits = try pipeline.uvSplitGraph(intersectionGraph: intersections, model: model, tolerance: tolerance)
        var result: [BooleanFaceArrangementBoundary] = []
        for split in splits.splits {
            let parents = parentSubshapeIDs(.face(split.facePair.targetFaceID), subshapes)
                + parentSubshapeIDs(.face(split.facePair.toolFaceID), subshapes)
            for component in split.components {
                if case .coincident = component.geometry {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Operands whose faces overlap on a common
                    // surface are refused. The Region Boolean reaches here from every operand pair;
                    // it is incomplete until coincident regions are merged into one shared face
                    // piece bounding the cells on both sides, with volumes checked in a test.
                    throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                        message: "A Region Boolean cannot yet divide space where operand faces overlap.")
                }
                let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                for (faceID, side) in [(split.facePair.targetFaceID, BooleanFaceArrangementBoundary.SurfaceSide.first),
                                       (split.facePair.toolFaceID, .second)] {
                    let edges = try BooleanFaceArrangementBoundary.edges(
                        reference: reference, geometry: component.geometry, faceID: faceID,
                        surfaceSide: side, parentSubshapeIDs: parents, tolerance: tolerance
                    )
                    result += edges.enumerated().map { ordinal, edge in
                        BooleanFaceArrangementBoundary(
                            reference: reference, segmentOrdinal: ordinal, faceID: faceID, edge: edge,
                            forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true
                        )
                    }
                }
            }
        }
        return result
    }

    private func faceIDs(of bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance) throws -> [FaceID] {
        guard let body = model.bodies[bodyID] else {
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                message: "A Region Boolean operand body is missing.")
        }
        return try body.shellIDs.flatMap { shellID -> [FaceID] in
            guard let shell = model.shells[shellID] else {
                throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                    message: "A Region Boolean operand shell is missing.")
            }
            return shell.faceIDs
        }.sorted()
    }

    private func parentSubshapeIDs(_ reference: TopologyReference, _ subshapes: [SubshapeID: TopologyReference]) -> [SubshapeID] {
        subshapes.compactMap { $0.value == reference ? $0.key : nil }.sorted()
    }
}
