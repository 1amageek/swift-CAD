import CADCore
import CADIR
import CADModeling
import CADTopology
import CADGeometry

public enum BooleanPipelinePhase: String, Codable, Hashable, Sendable, CaseIterable {
    case operandValidation
    case facePairBroadPhase
    case faceIntersection
    case uvFaceSplitting
    case pointInSolidClassification
    case resultRegionSelection
    case sewing
    case topologyValidation
    case lineageGeneration
}

/// Fixed-order orchestration boundary for exact Boolean evaluators.
/// The concrete evaluator may reject a phase when its declared capability is incomplete,
/// but it cannot silently bypass validation or return an unvalidated B-rep.
public struct BooleanPipeline: Sendable {
    private struct BoundaryContactCacheKey: Hashable {
        let edgeID: EdgeID
        let surfaceID: SurfaceID
    }

    private enum BoundaryContactCacheEntry {
        case empty
        case geometry(BooleanBoundaryContactGeometry)
    }

    private let evaluator: any BRepBooleanEvaluating
    private let intersector: any CurveSurfaceIntersecting
    private let surfaceIntersector: any SurfaceSurfaceIntersecting
    private let boundedSurfaceIntersector: any BoundedSurfaceSurfaceIntersecting
    private let uvFaceSplitter: any BooleanUVFaceSplitting
    private let regionClassifier: any BooleanRegionClassifying
    private let regionSelector: any BooleanResultRegionSelecting

    public init(
        evaluator: any BRepBooleanEvaluating,
        intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        surfaceIntersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector(),
        boundedSurfaceIntersector: any BoundedSurfaceSurfaceIntersecting = DefaultBoundedSurfaceSurfaceIntersector(),
        uvFaceSplitter: any BooleanUVFaceSplitting = DefaultBooleanUVFaceSplitter(),
        regionClassifier: any BooleanRegionClassifying = DefaultBooleanRegionClassifier(),
        regionSelector: any BooleanResultRegionSelecting = DefaultBooleanResultRegionSelector()
    ) {
        self.evaluator = evaluator
        self.intersector = intersector
        self.surfaceIntersector = surfaceIntersector
        self.boundedSurfaceIntersector = boundedSurfaceIntersector
        self.uvFaceSplitter = uvFaceSplitter
        self.regionClassifier = regionClassifier
        self.regionSelector = regionSelector
    }

    public func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage] = [:],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        do {
            let intersectionGraph: BooleanIntersectionGraph
            do {
                intersectionGraph = try self.intersectionGraph(
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    operation: operation,
                    model: model,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "intersection graph construction",
                    tolerance: tolerance
                )
            }
            let uvSplitGraph: BooleanUVSplitGraph
            do {
                uvSplitGraph = try self.uvSplitGraph(
                    intersectionGraph: intersectionGraph,
                    model: model,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "UV split graph construction",
                    tolerance: tolerance
                )
            }
            let classificationGraph: BooleanClassificationGraph
            do {
                classificationGraph = try self.classificationGraph(
                    uvSplitGraph: uvSplitGraph,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    model: model,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "classification graph construction",
                    tolerance: tolerance
                )
            }
            let regionSelectionGraph: BooleanRegionSelectionGraph
            do {
                regionSelectionGraph = try self.regionSelectionGraph(
                    operation: operation,
                    classificationGraph: classificationGraph,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "region selection graph construction",
                    tolerance: tolerance
                )
            }
            let exactRegionSelectionGraph: BooleanExactRegionSelectionGraph
            do {
                exactRegionSelectionGraph = try evaluator.exactRegionSelection(
                    operation: operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    featureID: featureID,
                    model: model,
                    subshapes: subshapes,
                    uvSplitGraph: uvSplitGraph,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "exact region materialization",
                    tolerance: tolerance
                )
            }

            // Exact selected regions are the sole input to the sewing phase.
            var result: EvaluationResult
            do {
                result = try evaluator.evaluate(
                    operation: operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    keepTools: keepTools,
                    featureID: featureID,
                    model: model,
                    subshapes: subshapes,
                    toolSubshapes: toolSubshapes,
                    intersectionGraph: intersectionGraph,
                    uvSplitGraph: uvSplitGraph,
                    classificationGraph: classificationGraph,
                    exactRegionSelectionGraph: exactRegionSelectionGraph,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "exact sewing evaluation",
                    tolerance: tolerance
                )
            }
            let topologyLineage: [SubshapeID: TopologyLineage]
            do {
                topologyLineage = try BooleanTopologyLineageBuilder().build(
                    featureID: featureID,
                    operandBodyIDs: targetBodyIDs + [toolBodyID],
                    inputModel: model,
                    resultModel: result.brep,
                    inputSubshapes: subshapes.merging(toolSubshapes) { current, _ in current },
                    outputSubshapes: result.subshapes,
                    inputLineage: inputLineage,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "topology lineage construction",
                    tolerance: tolerance
                )
            }
            for (subshapeID, entry) in topologyLineage where result.lineage[subshapeID] == nil {
                result.lineage[subshapeID] = entry
            }
            return result
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        let wrapped = KernelError.wrapping(
            error,
            phase: .topology,
            tolerance: tolerance
        )
        return KernelError(
            phase: wrapped.phase,
            code: wrapped.code,
            featureID: wrapped.featureID,
            subshapeID: wrapped.subshapeID,
            residual: wrapped.residual,
            tolerance: wrapped.tolerance ?? tolerance,
            message: "Boolean \(stage) failed: \(wrapped.message)"
        )
    }

    public func intersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let requirement = try evaluator.intersectionRequirement(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        if case .provenEmpty = requirement {
            return BooleanIntersectionGraph(
                facePairs: [],
                boundaryContacts: [],
                faceIntersections: []
            )
        }
        let facePairs = try facePairBroadPhase(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            operation: operation,
            in: model,
            tolerance: tolerance
        )
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance
        )
        try graph.validate(in: model, tolerance: tolerance)
        return graph
    }

    /// Builds the complete geometric intersection graph without accepting an
    /// evaluator-specific empty-intersection shortcut.
    func completeIntersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let facePairs = try facePairBroadPhase(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            operation: operation,
            in: model,
            tolerance: tolerance
        )
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance
        )
        try graph.validate(in: model, tolerance: tolerance)
        return graph
    }

    public func uvSplitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph {
        try uvFaceSplitter.splitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
        )
    }

    public func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph {
        try regionClassifier.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
    }

    public func regionSelectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph {
        try regionSelector.selectionGraph(
            operation: operation,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
    }

    private func operandValidation(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard !targetBodyIDs.isEmpty,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean operands must be distinct and contain at least one target."
            )
        }
        for bodyID in targetBodyIDs + [toolBodyID] {
            guard model.bodies[bodyID] != nil else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean operand body is missing."
                )
            }
        }
        try model.validate(tolerance: tolerance)
    }

    private func facePairBroadPhase(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [BooleanFacePairCandidate] {
        let toolFaceIDs = try faceIDs(for: toolBodyID, in: model, tolerance: tolerance)
        var candidates: [BooleanFacePairCandidate] = []
        for targetBodyID in targetBodyIDs {
            for targetFaceID in try faceIDs(
                for: targetBodyID,
                in: model,
                tolerance: tolerance
            ) {
                let targetBounds = try bounds(
                    for: targetFaceID,
                    in: model,
                    tolerance: tolerance
                )
                for toolFaceID in toolFaceIDs {
                    let toolBounds = try bounds(
                        for: toolFaceID,
                        in: model,
                        tolerance: tolerance
                    )
                    guard targetBounds.intersects(
                        toolBounds,
                        tolerance: tolerance.distance
                    ) else {
                        continue
                    }
                    candidates.append(BooleanFacePairCandidate(
                        targetFaceID: targetFaceID,
                        toolFaceID: toolFaceID
                    ))
                }
            }
        }
        return candidates.sorted {
            if $0.targetFaceID != $1.targetFaceID {
                return $0.targetFaceID < $1.targetFaceID
            }
            return $0.toolFaceID < $1.toolFaceID
        }
    }

    private func faceIntersection(
        facePairs: [BooleanFacePairCandidate],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        var contacts: [BooleanBoundaryContact] = []
        var faceIntersections: [BooleanFaceSurfaceIntersection] = []
        var boundaryContactCache: [
            BoundaryContactCacheKey: BoundaryContactCacheEntry
        ] = [:]
        var surfaceIntersectionCache: [
            Surface3D: [Surface3D: [SurfaceSurfaceIntersection]]
        ] = [:]
        for pair in facePairs {
            let targetBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.targetFaceID,
                surfaceFaceID: pair.toolFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance
            )
            let toolBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.toolFaceID,
                surfaceFaceID: pair.targetFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance
            )
            contacts.append(contentsOf: targetBoundaryContacts)
            contacts.append(contentsOf: toolBoundaryContacts)
            guard let targetFace = model.faces[pair.targetFaceID],
                  let toolFace = model.faces[pair.toolFaceID],
                  let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
                  let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean surface intersection references missing face geometry."
                )
            }
            let intersections: [SurfaceSurfaceIntersection]
            let boundaryPoints = (targetBoundaryContacts + toolBoundaryContacts).flatMap {
                contact -> [Point3D] in
                guard case let .points(values) = contact.geometry else { return [] }
                return values.map(\.point)
            }
            do {
                if let boundedIntersections = try boundedSurfaceIntersector.intersections(
                    first: targetSurface,
                    second: toolSurface,
                    boundaryPoints: boundaryPoints,
                    options: .init(),
                    tolerance: tolerance
                ) {
                    intersections = boundedIntersections
                } else if let cached = surfaceIntersectionCache[targetSurface]?[toolSurface] {
                    intersections = cached
                } else {
                    intersections = try surfaceIntersector.intersections(
                        first: targetSurface,
                        second: toolSurface,
                        options: .init(),
                        tolerance: tolerance
                    )
                    surfaceIntersectionCache[targetSurface, default: [:]][toolSurface]
                        = intersections
                }
            } catch {
                let wrapped = KernelError.wrapping(
                    error,
                    phase: .geometry,
                    tolerance: tolerance
                )
                throw KernelError(
                    phase: wrapped.phase,
                    code: wrapped.code,
                    featureID: wrapped.featureID,
                    subshapeID: wrapped.subshapeID,
                    residual: wrapped.residual,
                    tolerance: wrapped.tolerance ?? tolerance,
                    message: "Boolean face-pair intersection failed for target face \(pair.targetFaceID) on surface \(targetFace.surfaceID) and tool face \(pair.toolFaceID) on surface \(toolFace.surfaceID): \(wrapped.message)"
                )
            }
            faceIntersections.append(contentsOf: intersections.map {
                BooleanFaceSurfaceIntersection(facePair: pair, geometry: $0)
            })
        }
        let orderedContacts = contacts.sorted {
            if $0.curveFaceID != $1.curveFaceID { return $0.curveFaceID < $1.curveFaceID }
            if $0.surfaceFaceID != $1.surfaceFaceID { return $0.surfaceFaceID < $1.surfaceFaceID }
            return $0.edgeID < $1.edgeID
        }
        return BooleanIntersectionGraph(
            facePairs: facePairs,
            boundaryContacts: orderedContacts,
            faceIntersections: faceIntersections
        )
    }

    private func boundaryContacts(
        curveFaceID: FaceID,
        surfaceFaceID: FaceID,
        in model: BRepModel,
        cache: inout [BoundaryContactCacheKey: BoundaryContactCacheEntry],
        tolerance: ModelingTolerance
    ) throws -> [BooleanBoundaryContact] {
        guard let curveFace = model.faces[curveFaceID],
              let surfaceFace = model.faces[surfaceFaceID],
              let surface = model.geometry.surfaces[surfaceFace.surfaceID] else {
            throw KernelError(
                phase: .geometry,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean face-pair intersection references missing face geometry."
            )
        }
        let edgeIDs = try Set(curveFace.loops.flatMap { loopID -> [EdgeID] in
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face-pair intersection references a missing loop."
                )
            }
            return loop.coedges.map(\.edgeID)
        }).sorted()
        var contacts: [BooleanBoundaryContact] = []
        for edgeID in edgeIDs {
            let key = BoundaryContactCacheKey(
                edgeID: edgeID,
                surfaceID: surfaceFace.surfaceID
            )
            if let cached = cache[key] {
                if case let .geometry(geometry) = cached {
                    contacts.append(BooleanBoundaryContact(
                        edgeID: edgeID,
                        curveFaceID: curveFaceID,
                        surfaceFaceID: surfaceFaceID,
                        geometry: geometry
                    ))
                }
                continue
            }
            guard let edge = model.edges[edgeID],
                  let curve = model.geometry.curves[edge.curveID] else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face-pair intersection references missing edge geometry."
                )
            }
            let options = CurveSurfaceIntersectionOptions(
                curveRange: try curveRange(for: edge, curve: curve, in: model, tolerance: tolerance)
            )
            do {
                let intersections = try intersector.intersections(
                    curve: curve,
                    surface: surface,
                    options: options,
                    tolerance: tolerance
                )
                if intersections.isEmpty == false {
                    let geometry = BooleanBoundaryContactGeometry.points(intersections)
                    cache[key] = .geometry(geometry)
                    contacts.append(BooleanBoundaryContact(
                        edgeID: edgeID,
                        curveFaceID: curveFaceID,
                        surfaceFaceID: surfaceFaceID,
                        geometry: geometry
                    ))
                } else {
                    cache[key] = .empty
                }
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                cache[key] = .geometry(.coincident)
                contacts.append(BooleanBoundaryContact(
                    edgeID: edgeID,
                    curveFaceID: curveFaceID,
                    surfaceFaceID: surfaceFaceID,
                    geometry: .coincident
                ))
            }
        }
        return contacts
    }

    private func curveRange(
        for edge: Edge,
        curve: Curve3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let trim = edge.trim {
            return try ScalarInterval(
                lower: min(trim.startParameter, trim.endParameter),
                upper: max(trim.startParameter, trim.endParameter)
            )
        }
        guard let startPoint = model.vertices[edge.startVertexID]?.point,
              let endPoint = model.vertices[edge.endVertexID]?.point else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean edge range references missing vertices."
            )
        }
        guard let line = lineGeometry(curve) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A bounded non-line edge must persist an explicit curve trim."
            )
        }
        let directionSquared = line.direction.dot(line.direction)
        guard directionSquared > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean edge line has a degenerate direction."
            )
        }
        let start = (startPoint - line.origin).dot(line.direction) / directionSquared
        let end = (endPoint - line.origin).dot(line.direction) / directionSquared
        return try ScalarInterval(lower: min(start, end), upper: max(start, end))
    }

    private func lineGeometry(_ curve: Curve3D) -> Line3D? {
        switch curve {
        case let .line(line):
            return line
        case let .analytic(.line(origin, direction)):
            return Line3D(origin: origin, direction: direction)
        case let .rigidImage(image):
            guard let source = lineGeometry(image.source) else { return nil }
            return Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case let .affineImage(image):
            guard let source = lineGeometry(image.source) else { return nil }
            return Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private func faceIDs(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID] {
        guard let body = model.bodies[bodyID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean body is missing during face enumeration."
            )
        }
        var faceIDs: [FaceID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean body references a missing shell."
                )
            }
            faceIDs.append(contentsOf: shell.faceIDs)
        }
        return faceIDs.sorted()
    }

    private func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        try BRepFaceBoundingBoxBuilder().bounds(
            for: faceID,
            in: model,
            tolerance: tolerance
        )
    }
}
