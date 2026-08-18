import Foundation
import CADCore
import CADIR
import CADModeling
import CADTopology

struct OpenIntersectionFacePatchMaterializer {
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
        coincidentArrangementBoundaries: [BooleanFaceArrangementBoundary] = [],
        coincidentFaceActions: [FaceID: BooleanRegionSelectionAction] = [:],
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
                message: "Open-intersection materialization requires distinct Boolean operands and a result operation."
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
        let boundaries: [BooleanFaceArrangementBoundary]
        do {
            boundaries = try faceBoundaries(
                uvSplitGraph: uvSplitGraph,
                regionSelectionGraph: regionSelectionGraph,
                targetFaceIDs: targetFaceIDs,
                toolFaceIDs: toolFaceIDs,
                model: model,
                sourceSubshapes: sourceSubshapes,
                coincidentArrangementBoundaries: coincidentArrangementBoundaries,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "face-boundary materialization",
                tolerance: tolerance
            )
        }
        // Coincident-region ownership removes whole faces; boundaries whose
        // pair twin lives on such a face must drop on the surviving side as
        // well, or their intersection edges sew single-sided.
        let discardedFaceIDs = Set(
            coincidentFaceActions.filter { $0.value == .discard }.map(\.key)
        )
        let effectiveBoundaries = boundaries.filter { boundary in
            guard discardedFaceIDs.contains(boundary.faceID) == false else {
                return false
            }
            let pair = boundary.reference.facePair
            return discardedFaceIDs.contains(pair.targetFaceID) == false
                && discardedFaceIDs.contains(pair.toolFaceID) == false
        }
        let groupedBoundaries = Dictionary(grouping: effectiveBoundaries, by: \.faceID)
        // Faces sharing one intersection curve must segment it identically
        // for solid sewing to pair twins, so every boundary endpoint is
        // shared across all faces carrying the same curve.
        // A registry ordinal is allocated only after exact Curve3D equality.
        // This avoids both deep hash recursion and sample-signature collisions.
        var curveIdentityRegistry = ExactCurveIdentityRegistry()
        func curveKey(_ edge: BRepSewingEdge) -> ExactCurveIdentity {
            curveIdentityRegistry.identity(for: edge.curve)
        }
        var sharedPointsByCurve: [ExactCurveIdentity: [Point3D]] = [:]
        for boundary in effectiveBoundaries {
            let key = curveKey(boundary.edge)
            sharedPointsByCurve[key, default: []]
                .append(boundary.edge.startPoint)
            sharedPointsByCurve[key, default: []]
                .append(boundary.edge.endPoint)
        }
        // Pass one discovers every face's own segmentation (including
        // in-face crossings); its patch-edge endpoints join the shared set
        // so pass two segments every curve identically on all faces.
        for faceID in groupedBoundaries.keys.sorted() {
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let preview: BooleanOpenFaceArrangementBuilder.Result
            do {
                preview = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: coincidentFaceActions[faceID],
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "preliminary arrangement of face \(faceID)",
                    tolerance: tolerance
                )
            }
            for patch in preview.patches {
                for loop in patch.loops {
                    for edge in loop.edges {
                        guard edge.stableID.hasPrefix("face-intersection:") else {
                            continue
                        }
                        let key = curveKey(edge)
                        sharedPointsByCurve[key, default: []]
                            .append(edge.startPoint)
                        sharedPointsByCurve[key, default: []]
                            .append(edge.endPoint)
                    }
                }
            }
        }
        // Independently computed copies of one split point differ by
        // rounding across faces; clustering to canonical representatives
        // keeps every face's segmentation bitwise identical.
        for (key, points) in sharedPointsByCurve {
            var representatives: [Point3D] = []
            for point in points.sorted(by: {
                ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z)
            }) {
                if representatives.contains(where: {
                    ($0 - point).length <= tolerance.distance * 8.0
                }) == false {
                    representatives.append(point)
                }
            }
            sharedPointsByCurve[key] = representatives
        }
        var splitPatches: [BRepSewingFacePatch] = []
        var splitFaceIDs: Set<FaceID> = []
        for faceID in groupedBoundaries.keys.sorted() {
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let result: BooleanOpenFaceArrangementBuilder.Result
            do {
                var sharedSubdivisionPoints: [Point3D] = []
                for boundary in faceBoundaries {
                    sharedSubdivisionPoints.append(
                        contentsOf: sharedPointsByCurve[
                            curveKey(boundary.edge)
                        ] ?? []
                    )
                }
                result = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: coincidentFaceActions[faceID],
                    sharedSubdivisionPoints: sharedSubdivisionPoints,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "arrangement of face \(faceID)",
                    tolerance: tolerance
                )
            }
            if result.isPartitioned {
                splitFaceIDs.insert(faceID)
                splitPatches.append(contentsOf: result.patches)
            }
        }
        guard splitFaceIDs.isEmpty == false || coincidentFaceActions.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Open-intersection materialization requires at least one action-changing exact pcurve."
            )
        }
        let carriedPatches: [BRepSewingFacePatch]
        do {
            carriedPatches = try unsplitFaceMaterializer.patches(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                splitFaceIDs: splitFaceIDs,
                forcedActions: coincidentFaceActions,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "unsplit-face materialization",
                tolerance: tolerance
            )
        }
        let patches = splitPatches + carriedPatches
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean region selection produced no exact face patches."
            )
        }
        let shells: [BRepSewingShell]
        do {
            shells = try BRepSewingPatchShellPartitioner().shells(
                patches: patches,
                stablePrefix: "open-intersection:shell",
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "shell partitioning",
                tolerance: tolerance
            )
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: shells,
            bodyParentSubshapeIDs: (targetBodyIDs + [toolBodyID]).flatMap {
                parentSubshapeIDs(for: .body($0), in: sourceSubshapes)
            }
        )
        return request
    }

    private func faceBoundaries(
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        targetFaceIDs: Set<FaceID>,
        toolFaceIDs: Set<FaceID>,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        coincidentArrangementBoundaries: [BooleanFaceArrangementBoundary],
        tolerance: ModelingTolerance
    ) throws -> [BooleanFaceArrangementBoundary] {
        let operandFaceIDs = targetFaceIDs.union(toolFaceIDs)
        guard coincidentArrangementBoundaries.allSatisfy({
            operandFaceIDs.contains($0.faceID)
        }) else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Coincident arrangement boundary belongs to a face outside the Boolean operands."
            )
        }
        var result = coincidentArrangementBoundaries
        for split in uvSplitGraph.splits {
            guard targetFaceIDs.contains(split.facePair.targetFaceID),
                  toolFaceIDs.contains(split.facePair.toolFaceID),
                  let targetFace = model.faces[split.facePair.targetFaceID],
                  let toolFace = model.faces[split.facePair.toolFaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Open Boolean split references topology outside its declared operands."
                )
            }
            let componentParents = parentSubshapeIDs(
                for: .face(targetFace.id),
                in: sourceSubshapes
            ) + parentSubshapeIDs(
                for: .face(toolFace.id),
                in: sourceSubshapes
            )
            for component in split.components {
                if case .coincident = component.geometry {
                    continue
                }
                let reference = BooleanFaceSplitComponentReference(
                    facePair: split.facePair,
                    componentID: component.id
                )
                let targetBoundaries = try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: targetFace,
                    surfaceSide: .first,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                )
                let toolBoundaries = try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: toolFace,
                    surfaceSide: .second,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                )
                result.append(contentsOf: targetBoundaries)
                result.append(contentsOf: toolBoundaries)
            }
        }
        // Solid sewing pairs every intersection edge across its face pair,
        // so a component partitioning one face forces its kept-kept twin
        // face to partition as well.
        var partitioningByComponent: [BooleanFaceSplitComponentReference: Bool] = [:]
        for boundary in result where boundary.isPartitioning {
            partitioningByComponent[boundary.reference] = true
        }
        for index in result.indices {
            let boundary = result[index]
            if boundary.isPartitioning == false,
               partitioningByComponent[boundary.reference] == true,
               boundary.forwardLeftAction != .discard,
               boundary.forwardRightAction != .discard {
                result[index].forcedPartitioning = true
            }
        }
        return result
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
                    message: "Open Boolean materialization references a missing operand body."
                )
            }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Open Boolean materialization references a missing operand shell."
                    )
                }
                result.formUnion(shell.faceIDs)
            }
        }
        return result
    }

    private func parentSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference]
    ) -> [SubshapeID] {
        sourceSubshapes.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        if let error = error as? KernelError {
            return KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Open-intersection \(stage) failed: \(error.message)"
            )
        }
        return KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Open-intersection \(stage) failed: \(error)"
        )
    }
}
