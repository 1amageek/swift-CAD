import CADCore
import CADIR
import CADModeling
import CADTopology

struct ClosedIntersectionUnsplitFaceMaterializer {
    private let pointSampler: BRepFaceInteriorPointSampler
    private let pointClassifier: any SolidPointClassifying

    init(
        pointSampler: BRepFaceInteriorPointSampler = BRepFaceInteriorPointSampler(),
        pointClassifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier()
    ) {
        self.pointSampler = pointSampler
        self.pointClassifier = pointClassifier
    }

    func patches(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        splitFaceIDs: Set<FaceID>,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingFacePatch] {
        try tolerance.validate()
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
        let targetFaceIDs = try targetBodyIDs.flatMap {
            try faceIDs(in: $0, model: model, tolerance: tolerance)
        }
        let toolFaceIDs = try faceIDs(
            in: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        guard splitFaceIDs.isSubset(of: Set(targetFaceIDs + toolFaceIDs)) else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Closed face split does not belong to a declared Boolean operand."
            )
        }
        let targetPatches = try carriedPatches(
            faceIDs: targetFaceIDs,
            excluding: splitFaceIDs,
            oppositeBodyIDs: [toolBodyID],
            isToolFace: false,
            operation: operation,
            stablePrefix: "closed-intersection:carried:target",
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )
        let toolPatches = try carriedPatches(
            faceIDs: toolFaceIDs,
            excluding: splitFaceIDs,
            oppositeBodyIDs: targetBodyIDs,
            isToolFace: true,
            operation: operation,
            stablePrefix: "closed-intersection:carried:tool",
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )
        return targetPatches + toolPatches
    }

    private func carriedPatches(
        faceIDs: [FaceID],
        excluding splitFaceIDs: Set<FaceID>,
        oppositeBodyIDs: [BodyID],
        isToolFace: Bool,
        operation: BooleanOperation,
        stablePrefix: String,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingFacePatch] {
        var patches: [BRepSewingFacePatch] = []
        for (faceIndex, faceID) in faceIDs.sorted().enumerated()
            where splitFaceIDs.contains(faceID) == false {
            let point = try pointSampler.point(
                on: faceID,
                in: model,
                tolerance: tolerance
            )
            let classification = try classification(
                of: point,
                in: oppositeBodyIDs,
                model: model,
                tolerance: tolerance
            )
            guard classification != .boundary else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "An unsplit Boolean face resolved to the opposite operand boundary."
                )
            }
            let action = BooleanRegionSelectionRule().action(
                operation: operation,
                classification: classification,
                isToolFace: isToolFace
            )
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
            let source = try SourceBRepFacePatchBuilder().build(
                faceID: faceID,
                stableID: stableID,
                from: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            ).patch
            let orientation = action == .keepReversed
                ? reversed(face.orientation)
                : face.orientation
            patches.append(try BRepSewingPatchOrientationAdapter().reorient(
                source,
                to: orientation,
                tolerance: tolerance
            ))
        }
        return patches
    }

    private func faceIDs(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID] {
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
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Closed-intersection materialization references a missing operand shell."
                )
            }
            result.append(contentsOf: shell.faceIDs)
        }
        return result.sorted()
    }

    private func classification(
        of point: Point3D,
        in bodyIDs: [BodyID],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        var isInside = false
        for bodyID in bodyIDs {
            let classification = try pointClassifier.classify(
                point,
                in: bodyID,
                model: model,
                tolerance: tolerance
            )
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
