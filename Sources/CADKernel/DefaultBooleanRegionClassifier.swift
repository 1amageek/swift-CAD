import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Classifies both sides of every intersection component against the opposite operand's
/// material, through the pass's operand point classifier.
public struct DefaultBooleanRegionClassifier: BooleanRegionClassifying {
    public init() {}

    public func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph {
        var resultSamples: [BooleanClassificationGraph.Sample] = []
        let classificationSessions = try SolidPointClassificationSessionSet(
            bodyIDs: targetBodyIDs + [toolBodyID],
            pointClassifier: operands.pointClassifier,
            model: model,
            tolerance: tolerance
        )
        for split in uvSplitGraph.splits {
            let targetBodyID = try bodyID(
                containing: split.facePair.targetFaceID,
                candidates: targetBodyIDs,
                model: model,
                tolerance: tolerance
            )
            for component in split.components {
                guard let sample = try intersectionSample(
                    component: component,
                    tolerance: tolerance
                ) else {
                    continue
                }
                resultSamples.append(contentsOf: try classificationSamples(
                    facePair: split.facePair,
                    componentID: component.id,
                    sourceFaceID: split.facePair.targetFaceID,
                    oppositeBodyID: toolBodyID,
                    midpoint: sample.point,
                    intersectionDirection: sample.direction,
                    surfaceParameter: sample.targetParameter,
                    model: model,
                    classificationSessions: classificationSessions,
                    tolerance: tolerance
                ))
                resultSamples.append(contentsOf: try classificationSamples(
                    facePair: split.facePair,
                    componentID: component.id,
                    sourceFaceID: split.facePair.toolFaceID,
                    oppositeBodyID: targetBodyID,
                    midpoint: sample.point,
                    intersectionDirection: sample.direction,
                    surfaceParameter: sample.toolParameter,
                    model: model,
                    classificationSessions: classificationSessions,
                    tolerance: tolerance
                ))
            }
        }
        let graph = BooleanClassificationGraph(samples: resultSamples)
        try graph.validate(uvSplitGraph: uvSplitGraph, model: model, tolerance: tolerance)
        return graph
    }

    /// Classifies only cutting-tool face sectors against their original target solid.
    /// The invocation retains one prepared target session set and the existing clearance budget.
    func planeSideClassification(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        pointClassifier: any SolidPointClassifying,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        guard !targetBodyIDs.isEmpty, Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID), model.bodies[toolBodyID] != nil else {
            throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Plane-side classification requires distinct original target and cutting-tool bodies.")
        }
        let sessions = try SolidPointClassificationSessionSet(bodyIDs: targetBodyIDs,
            pointClassifier: pointClassifier, model: model, tolerance: tolerance)
        var resultSamples: [BooleanClassificationGraph.Sample] = []
        for split in uvSplitGraph.splits {
            try CurrentTaskCancellationChecker().checkCancellation()
            let targetBodyID = try bodyID(containing: split.facePair.targetFaceID,
                candidates: targetBodyIDs, model: model, tolerance: tolerance)
            _ = try bodyID(containing: split.facePair.toolFaceID, candidates: [toolBodyID],
                model: model, tolerance: tolerance)
            for component in split.components {
                guard let sample = try intersectionSample(component: component, tolerance: tolerance) else { continue }
                resultSamples.append(contentsOf: try classificationSamples(facePair: split.facePair,
                    componentID: component.id, sourceFaceID: split.facePair.toolFaceID,
                    oppositeBodyID: targetBodyID, midpoint: sample.point,
                    intersectionDirection: sample.direction, surfaceParameter: sample.toolParameter,
                    model: model, classificationSessions: sessions, tolerance: tolerance))
            }
        }
        let graph = BooleanClassificationGraph(samples: resultSamples)
        try graph.validate(uvSplitGraph: uvSplitGraph, model: model, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return graph
    }

    /// Classifies explicit original coplanar boundaries under one invocation-owned session set.
    func planeEdgeSideClassification(
        boundaries: [PlaneEdgeClassificationBoundary],
        model: BRepModel,
        pointClassifier: any SolidPointClassifying,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        guard Set(boundaries.map(\.reference)).count == boundaries.count else {
            throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Every explicit plane boundary must retain a distinct sector component identity.")
        }
        let sessions = try SolidPointClassificationSessionSet(
            bodyIDs: Array(Set(boundaries.map(\.targetBodyID))).sorted(),
            pointClassifier: pointClassifier, model: model, tolerance: tolerance)
        var samples: [BooleanClassificationGraph.Sample] = []
        for boundary in boundaries {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard boundary.cuttingFaceID == boundary.reference.facePair.toolFaceID,
                  model.faces[boundary.cuttingFaceID] != nil else {
                throw KernelError(phase: .classification, code: .missingReference, tolerance: tolerance,
                    message: "An explicit plane boundary has no matching original cutting face.")
            }
            _ = try bodyID(containing: boundary.reference.facePair.targetFaceID,
                candidates: [boundary.targetBodyID], model: model, tolerance: tolerance)
            guard let cuttingFace = model.faces[boundary.cuttingFaceID],
                  let cuttingSurface = model.geometry.surfaces[cuttingFace.surfaceID],
                  let sourceFace = model.faces[boundary.reference.facePair.targetFaceID] else {
                throw TopologyError.missingReference("An original plane-sector face is missing.")
            }
            let ownsOriginalSpan = sourceFace.loops.contains { loopID in
                model.loops[loopID]?.edges.contains { use in
                    guard let original = model.edges[use.edgeID], let trim = original.trim,
                          model.geometry.curves[original.curveID] == boundary.edge.curve else { return false }
                    return min(trim.startParameter, trim.endParameter) == min(boundary.edge.startParameter, boundary.edge.endParameter)
                        && max(trim.startParameter, trim.endParameter) == max(boundary.edge.startParameter, boundary.edge.endParameter)
                } == true
            }
            guard ownsOriginalSpan else {
                throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                    message: "An explicit plane-sector boundary is not an original span owned by its referenced face.")
            }
            try boundary.edge.validate(on: cuttingSurface, tolerance: tolerance)
            let native = try boundary.edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
            let midpoint = try cuttingSurface.point(u: native.u, v: native.v, tolerance: tolerance)
            let range = try ScalarInterval(lower: min(boundary.edge.startParameter, boundary.edge.endParameter),
                upper: max(boundary.edge.startParameter, boundary.edge.endParameter))
            let projection = try boundary.edge.curve.closestParameterProjection(of: midpoint,
                options: CurveParameterProjectionOptions(parameterRange: range), tolerance: tolerance)
            guard projection.residual <= tolerance.distance else {
                throw KernelError(phase: .classification, code: .classificationFailure, residual: projection.residual,
                    tolerance: tolerance, message: "A plane-sector point does not lie on its original boundary span.")
            }
            let geometry = try boundary.edge.curve.differentialGeometry(at: projection.parameter, tolerance: tolerance)
            let direction = boundary.edge.endParameter > boundary.edge.startParameter ? geometry.tangent : geometry.tangent * -1
            samples.append(contentsOf: try classificationSamples(facePair: boundary.reference.facePair,
                componentID: boundary.reference.componentID, sourceFaceID: boundary.cuttingFaceID,
                oppositeBodyID: boundary.targetBodyID, midpoint: midpoint,
                intersectionDirection: direction, surfaceParameter: native, model: model,
                classificationSessions: sessions, tolerance: tolerance))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return BooleanClassificationGraph(samples: samples)
    }

    private func intersectionSample(
        component: BooleanFaceSplitComponent,
        tolerance: ModelingTolerance
    ) throws -> IntersectionSample? {
        switch component.geometry {
        case let .transverseSegment(start, end):
            return IntersectionSample(
                point: Point3D(
                    x: (start.point.x + end.point.x) * 0.5,
                    y: (start.point.y + end.point.y) * 0.5,
                    z: (start.point.z + end.point.z) * 0.5
                ),
                direction: try (end.point - start.point).normalized(
                    tolerance: tolerance.distance
                ),
                targetParameter: SurfaceParameter(
                    u: (start.targetU + end.targetU) * 0.5,
                    v: (start.targetV + end.targetV) * 0.5
                ),
                toolParameter: SurfaceParameter(
                    u: (start.toolU + end.toolU) * 0.5,
                    v: (start.toolV + end.toolV) * 0.5
                )
            )
        case let .closedCurve(closedCurve):
            let sampleIndex = min(1, closedCurve.samples.count - 1)
            let sample = closedCurve.samples[sampleIndex]
            return IntersectionSample(
                point: sample.uvPoint.point,
                direction: try closedCurve.intersection.curve.differentialGeometry(
                    at: sample.curveParameter,
                    tolerance: tolerance
                ).tangent,
                targetParameter: SurfaceParameter(
                    u: sample.uvPoint.targetU,
                    v: sample.uvPoint.targetV
                ),
                toolParameter: SurfaceParameter(
                    u: sample.uvPoint.toolU,
                    v: sample.uvPoint.toolV
                )
            )
        case let .trimmedCurve(chain):
            let curve = chain.classificationSegment
            let targetParameter = try curve.intersection.surfaceParameter(
                on: .first,
                atCurveParameter: curve.midpointParameter,
                tolerance: tolerance
            )
            let toolParameter = try curve.intersection.surfaceParameter(
                on: .second,
                atCurveParameter: curve.midpointParameter,
                tolerance: tolerance
            )
            return IntersectionSample(
                point: try curve.intersection.curve.point(
                    at: curve.midpointParameter,
                    tolerance: tolerance
                ),
                direction: try curve.intersection.curve.differentialGeometry(
                    at: curve.midpointParameter,
                    tolerance: tolerance
                ).tangent,
                targetParameter: targetParameter,
                toolParameter: toolParameter
            )
        case .tangent, .coincident:
            return nil
        }
    }

    private func classificationSamples(
        facePair: BooleanFacePairCandidate,
        componentID: BooleanFaceSplitComponentID,
        sourceFaceID: FaceID,
        oppositeBodyID: BodyID,
        midpoint: Point3D,
        intersectionDirection: Vector3D,
        surfaceParameter: SurfaceParameter,
        model: BRepModel,
        classificationSessions: SolidPointClassificationSessionSet,
        tolerance: ModelingTolerance
    ) throws -> [BooleanClassificationGraph.Sample] {
        guard let face = model.faces[sourceFaceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean region classification references missing face geometry."
            )
        }
        try surfaceParameter.validate()
        let parameterPoint = try surface.point(
            u: surfaceParameter.u,
            v: surfaceParameter.v,
            tolerance: tolerance
        )
        let parameterResidual = (parameterPoint - midpoint).length
        guard parameterResidual <= tolerance.distance else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: parameterResidual,
                tolerance: tolerance,
                message: "Boolean region classification received a pcurve point that disagrees with the intersection curve."
            )
        }
        let geometricNormal = try surface.normal(
            u: surfaceParameter.u,
            v: surfaceParameter.v,
            tolerance: tolerance
        )
        let normal = face.orientation == .forward ? geometricNormal : geometricNormal * -1.0
        let sideDirection = try normal.cross(intersectionDirection).normalized(
            tolerance: tolerance.distance
        )
        return [
            try classifiedSample(
                facePair: facePair,
                componentID: componentID,
                sourceFaceID: sourceFaceID,
                oppositeBodyID: oppositeBodyID,
                side: .negative,
                midpoint: midpoint,
                sideDirection: sideDirection * -1.0,
                sourceInwardDirection: normal * -1.0,
                classificationSessions: classificationSessions,
                tolerance: tolerance
            ),
            try classifiedSample(
                facePair: facePair,
                componentID: componentID,
                sourceFaceID: sourceFaceID,
                oppositeBodyID: oppositeBodyID,
                side: .positive,
                midpoint: midpoint,
                sideDirection: sideDirection,
                sourceInwardDirection: normal * -1.0,
                classificationSessions: classificationSessions,
                tolerance: tolerance
            ),
        ]
    }

    private func classifiedSample(
        facePair: BooleanFacePairCandidate,
        componentID: BooleanFaceSplitComponentID,
        sourceFaceID: FaceID,
        oppositeBodyID: BodyID,
        side: BooleanClassificationGraph.Side,
        midpoint: Point3D,
        sideDirection: Vector3D,
        sourceInwardDirection: Vector3D,
        classificationSessions: SolidPointClassificationSessionSet,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph.Sample {
        let maximumAttempts = 8
        var distance = tolerance.distance * 8.0
        for _ in 0..<maximumAttempts {
            let point = midpoint + sideDirection * distance
            let classification = try classificationSessions.classify(
                point,
                in: oppositeBodyID
            )
            if classification != .boundary {
                return BooleanClassificationGraph.Sample(
                    facePair: facePair,
                    componentID: componentID,
                    sourceFaceID: sourceFaceID,
                    oppositeBodyID: oppositeBodyID,
                    side: side,
                    point: point,
                    classification: classification
                )
            }
            let materialPoint = point + sourceInwardDirection * distance
            let materialClassification = try classificationSessions.classify(
                materialPoint,
                in: oppositeBodyID
            )
            if materialClassification != .boundary {
                return BooleanClassificationGraph.Sample(
                    facePair: facePair,
                    componentID: componentID,
                    sourceFaceID: sourceFaceID,
                    oppositeBodyID: oppositeBodyID,
                    side: side,
                    point: materialPoint,
                    classification: materialClassification
                )
            }
            distance *= 2.0
        }
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            tolerance: tolerance,
            message: "Boolean region classification could not resolve a non-boundary point within the adaptive offset budget."
        )
    }

    private func bodyID(
        containing faceID: FaceID,
        candidates: [BodyID],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BodyID {
        for bodyID in candidates {
            guard let body = model.bodies[bodyID] else { continue }
            for shellID in body.shellIDs where model.shells[shellID]?.faceIDs.contains(faceID) == true {
                return bodyID
            }
        }
        throw KernelError(
            phase: .classification,
            code: .missingReference,
            tolerance: tolerance,
            message: "Boolean target face does not belong to a target body."
        )
    }

    private struct IntersectionSample {
        let point: Point3D
        let direction: Vector3D
        let targetParameter: SurfaceParameter
        let toolParameter: SurfaceParameter
    }
}
