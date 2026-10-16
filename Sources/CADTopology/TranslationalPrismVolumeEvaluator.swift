import HashTreeCollections
import CADCore
import CADGeometry

/// Certifies the volume of a straight translational prism from its exact B-rep.
///
/// The proof requires two parallel planar caps, line generators carrying one
/// cap to the other by one translation vector, and side surfaces whose exact
/// definitions preserve that translation. The cap area is enclosed through
/// its face-local pcurves, so mixed line, conic, and rational B-spline profiles
/// use one exact path without polygonalization.
struct TranslationalPrismVolumeEvaluator {
    func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        try tolerance.validate()
        let vertices = try shellVertices(shell, model: model, using: &execution)
        guard vertices.count >= 4 else { return nil }
        let planarFaces = try (try OriginalParameterQueryStorage.compactMap(shell.faceIDs, using: &execution) { faceID, execution -> PlanarFace? in
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Translational prism volume references missing face geometry."
                )
            }
            guard let plane = try planeDescriptor(
                for: surface,
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return PlanarFace(id: faceID, face: face, plane: plane)
        })
        guard planarFaces.count >= 2 else { return nil }

        for firstIndex in planarFaces.indices {

            try execution.consumeWork(1)
            for secondIndex in planarFaces.indices {
                try execution.consumeWork(1)
                guard secondIndex > firstIndex else { continue }
                if let result = try certifiedVolume(
                    firstCap: planarFaces[firstIndex],
                    secondCap: planarFaces[secondIndex],
                    shell: shell,
                    vertices: vertices,
                    model: model,
                    tolerance: tolerance, using: &execution
                ) {
                    return result
                }
            }
        }
        return nil
    }

    private func certifiedVolume(
        firstCap: PlanarFace,
        secondCap: PlanarFace,
        shell: Shell,
        vertices: [VertexID: Point3D],
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        let normalAlignment = firstCap.plane.normal.dot(secondCap.plane.normal)
        guard abs(abs(normalAlignment) - 1.0) <= tolerance.angle else {
            return nil
        }
        let normalSeparation = abs(
            (secondCap.plane.origin - firstCap.plane.origin)
                .dot(firstCap.plane.normal)
        )
        guard normalSeparation > tolerance.distance else { return nil }

        var vertexSides: [VertexID: CapSide] = [:]

        for (vertexID, point) in vertices {
            try execution.consumeWork(1)
            let firstResidual = abs(
                (point - firstCap.plane.origin).dot(firstCap.plane.normal)
            )
            let secondResidual = abs(
                (point - secondCap.plane.origin).dot(secondCap.plane.normal)
            )
            if firstResidual <= tolerance.distance,
               secondResidual > tolerance.distance {
                try OriginalParameterQueryStorage.set(CapSide.first, for: vertexID, in: &vertexSides, using: &execution)
            } else if secondResidual <= tolerance.distance,
                      firstResidual > tolerance.distance {
                try OriginalParameterQueryStorage.set(CapSide.second, for: vertexID, in: &vertexSides, using: &execution)
            } else {
                return nil
            }
        }

        let edgeIDs = try shellEdgeIDs(shell, model: model, using: &execution)
        var translation: Vector3D?
        var crossEdgeIDs = Set<EdgeID>()
        for edgeID in edgeIDs {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID],
                  let start = vertices[edge.startVertexID],
                  let end = vertices[edge.endVertexID],
                  let startSide = vertexSides[edge.startVertexID],
                  let endSide = vertexSides[edge.endVertexID] else {
                throw TopologyError.missingReference(
                    "Translational prism volume references missing edge topology."
                )
            }
            guard startSide != endSide else { continue }
            guard let curve = model.geometry.curves[edge.curveID],
                  try isLine(curve, using: &execution) else {
                return nil
            }
            let candidate = startSide == .first ? end - start : start - end
            guard candidate.length > tolerance.distance else { return nil }
            if let translation {
                guard (candidate - translation).length <= tolerance.distance else {
                    return nil
                }
            } else {
                translation = candidate
            }
            try OriginalParameterQueryStorage.insert(edgeID, in: &crossEdgeIDs, using: &execution)
        }
        guard crossEdgeIDs.count >= 2,
              let translation else {
            return nil
        }
        let normalHeight = abs(translation.dot(firstCap.plane.normal))
        guard abs(normalHeight - normalSeparation) <= tolerance.distance else {
            return nil
        }


        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard faceID != firstCap.id && faceID != secondCap.id else { continue }
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID],
                  try faceIsTranslatedSide(
                      face,
                      surface: surface,
                      translation: translation,
                      crossEdgeIDs: crossEdgeIDs,
                      model: model,
                      tolerance: tolerance, using: &execution
                  ) else {
                return nil
            }
        }
        guard try capContainsOnlyBoundaryEdges(
            firstCap.face,
            crossEdgeIDs: crossEdgeIDs,
            model: model, using: &execution
        ), try capContainsOnlyBoundaryEdges(
            secondCap.face,
            crossEdgeIDs: crossEdgeIDs,
            model: model, using: &execution
        ) else {
            return nil
        }

        guard let x = try OriginalParameterQueryStorage.extrema(vertices.values, using: &execution, projection: { point, execution in point.x }),
              let y = try OriginalParameterQueryStorage.extrema(vertices.values, using: &execution, projection: { point, execution in point.y }),
              let z = try OriginalParameterQueryStorage.extrema(vertices.values, using: &execution, projection: { point, execution in point.z }) else { return nil }
        let characteristicLength = max(tolerance.distance, Vector3D(x: x.upper - x.lower, y: y.upper - y.lower, z: z.upper - z.lower).length)
        let requestedVolumeError = max(
            tolerance.distance * characteristicLength * characteristicLength * 0.0625,
            characteristicLength * characteristicLength * characteristicLength * 1.0e-13
        )
        let requestedAreaWidth = max(
            requestedVolumeError / normalHeight,
            Double.ulpOfOne * characteristicLength * characteristicLength * 1_024.0
        )
        guard let area = try capAreaBounds(
            firstCap.face,
            requestedWidth: requestedAreaWidth,
            model: model,
            tolerance: tolerance, using: &execution
        ) else {
            return nil
        }
        let lower = (area.lower * normalHeight).nextDown
        let upper = (area.upper * normalHeight).nextUp
        guard lower > 0.0,
              lower.isFinite,
              upper.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: min(abs(lower), abs(upper)),
                tolerance: tolerance,
                message: "Translational prism volume could not certify a positive enclosed volume."
            )
        }
        let errorRadius = (upper - lower) * 0.5
        guard errorRadius <= requestedVolumeError else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: errorRadius,
                tolerance: tolerance,
                message: "Translational prism volume exceeded the requested enclosure width."
            )
        }
        return lower + (upper - lower) * 0.5
    }

    private func capAreaBounds(
        _ face: Face,
        requestedWidth: Double,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> AreaBounds? {
        try execution.consumeWork(1)
        let coedgeCount = try OriginalParameterQueryStorage.reduce(face.loops, initial: 0, using: &execution) { count, loopID, execution in
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing loop."
                )
            }
            let next = count.addingReportingOverflow(loop.coedges.count)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            return next.partialValue
        }
        guard coedgeCount > 0 else { return nil }
        let curveWidth = requestedWidth / Double(coedgeCount)
        let integrator = SurfaceParameterCurveAreaIntegrator()
        var result = AreaBounds.zero
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing or empty loop."
                )
            }
            var signed = SurfaceParameterAreaBounds.zero
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                signed = signed.adding(try integrator.bounds(
                    for: pcurve,
                    uShift: 0.0,
                    requestedWidth: curveWidth,
                    tolerance: tolerance, using: &execution
                ))
            }
            let absolute: AreaBounds
            if signed.lower > 0.0 {
                absolute = AreaBounds(lower: signed.lower, upper: signed.upper)
            } else if signed.upper < 0.0 {
                absolute = AreaBounds(lower: -signed.upper, upper: -signed.lower)
            } else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: signed.minimumAbsoluteValue,
                    tolerance: tolerance,
                    message: "Translational prism cap area could not certify loop orientation."
                )
            }
            result = loop.role == .outer
                ? result.adding(absolute)
                : result.subtracting(absolute)
        }
        guard result.lower > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: result.lower,
                tolerance: tolerance,
                message: "Translational prism cap loops do not enclose positive area."
            )
        }
        return result
    }

    private func faceIsTranslatedSide(
        _ face: Face,
        surface: Surface3D,
        translation: Vector3D,
        crossEdgeIDs: Set<EdgeID>,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              (try OriginalParameterQueryStorage.filter(loop.coedges, using: &execution) { item, execution in crossEdgeIDs.contains(item.edgeID) }).count == 2 else {
            return false
        }
        let axis = try translation.normalized(tolerance: tolerance.distance)
        switch surface {
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            return abs(normal.dot(axis)) <= tolerance.angle
        case let .analytic(.plane(_, normalValue)):
            let normal = try normalValue.normalized(tolerance: tolerance.distance)
            return abs(normal.dot(axis)) <= tolerance.angle
        case let .cylinder(cylinder):
            let cylinderAxis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            return abs(abs(cylinderAxis.dot(axis)) - 1.0) <= tolerance.angle
        case let .analytic(.cylinder(_, cylinderAxisValue, _)):
            let cylinderAxis = try cylinderAxisValue.normalized(tolerance: tolerance.distance)
            return abs(abs(cylinderAxis.dot(axis)) - 1.0) <= tolerance.angle
        case let .bSpline(spline):
            return try exactTranslationDirection(
                spline,
                translation: translation,
                tolerance: tolerance, using: &execution
            )
        case .analytic, .procedural(.rollingBall), .procedural(.originalImage), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAngularTransport), .procedural(.originalAffineWord), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return false
        case let .procedural(.offset(offset)):
            return try faceIsTranslatedSide(
                face,
                surface: offset.source,
                translation: translation,
                crossEdgeIDs: crossEdgeIDs,
                model: model,
                tolerance: tolerance, using: &execution
            )
        case let .procedural(.ruled(ruled)):
            return try ruledBoundariesDiffer(
                ruled,
                by: translation,
                tolerance: tolerance, using: &execution
            )
        }
    }

    private func ruledBoundariesDiffer(
        _ ruled: RuledSurface3D,
        by translation: Vector3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .surfaceLift(start) = ruled.startBoundary,
              case let .surfaceLift(end) = ruled.endBoundary else { return false }
        try GeometryStructuralComparisonWork.charge(parameterCurve: start.parameterCurve, using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: end.parameterCurve, using: &execution)
        guard start.parameterCurve == end.parameterCurve else {
            return false
        }
        let first = try offsetDescriptor(start.surface, using: &execution)
        let second = try offsetDescriptor(end.surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: first.source, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: second.source, using: &execution)
        guard first.source == second.source,
              let plane = try DefaultPlanarSurfaceResolver().exactPlane(
                  for: first.source,
                  tolerance: tolerance, using: &execution
              ) else {
            return false
        }
        let delta = plane.normal * (second.distance - first.distance)
        return (delta - translation).length <= tolerance.distance
            || (delta + translation).length <= tolerance.distance
    }

    private func offsetDescriptor(
        _ surface: Surface3D, using execution: inout OriginalQueryExecution
    ) throws -> (source: Surface3D, distance: Double) {
        try execution.consumeWork(1)
        guard case let .procedural(.offset(offset)) = surface else {
            return (surface, 0.0)
        }
        let nested = try offsetDescriptor(offset.source, using: &execution)
        return (nested.source, nested.distance + offset.distance)
    }

    private func exactTranslationDirection(
        _ surface: BSplineSurface3D,
        translation: Vector3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        if surface.vDegree == 1,
           surface.vControlPointCount == 2,
           surface.controlPoints.count == 2,
           surface.weights.count == 2,
           surface.controlPoints[0].count == surface.controlPoints[1].count,
           surface.weights[0].count == surface.weights[1].count,
           surface.controlPoints[0].count == surface.weights[0].count {
            return (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints[0].indices, using: &execution) { index, execution in
                translatedPairMatches(
                    surface.controlPoints[0][index],
                    surface.controlPoints[1][index],
                    firstWeight: surface.weights[0][index],
                    secondWeight: surface.weights[1][index],
                    translation: translation,
                    tolerance: tolerance
                )
            })
        }
        if surface.uDegree == 1,
           surface.uControlPointCount == 2,
           (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints, using: &execution) { item, execution in item.count == 2 }),
           surface.weights.count == surface.controlPoints.count,
           (try OriginalParameterQueryStorage.allSatisfy(surface.weights, using: &execution) { item, execution in item.count == 2 }) {
            return (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints.indices, using: &execution) { index, execution in
                translatedPairMatches(
                    surface.controlPoints[index][0],
                    surface.controlPoints[index][1],
                    firstWeight: surface.weights[index][0],
                    secondWeight: surface.weights[index][1],
                    translation: translation,
                    tolerance: tolerance
                )
            })
        }
        return false
    }

    private func translatedPairMatches(
        _ first: Point3D,
        _ second: Point3D,
        firstWeight: Double,
        secondWeight: Double,
        translation: Vector3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let weightScale = max(abs(firstWeight), abs(secondWeight), 1.0)
        guard abs(firstWeight - secondWeight) <= tolerance.relative * weightScale else {
            return false
        }
        let delta = second - first
        return (delta - translation).length <= tolerance.distance
            || (delta + translation).length <= tolerance.distance
    }

    private func capContainsOnlyBoundaryEdges(
        _ face: Face,
        crossEdgeIDs: Set<EdgeID>,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing loop."
                )
            }
            if (try OriginalParameterQueryStorage.contains(loop.coedges, using: &execution) { item, execution in crossEdgeIDs.contains(item.edgeID) }) {
                return false
            }
        }
        return true
    }

    private func shellVertices(
        _ shell: Shell,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> [VertexID: Point3D] {
        try execution.consumeWork(1)
        var result: [VertexID: Point3D] = [:]
        for edgeID in try shellEdgeIDs(shell, model: model, using: &execution) {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference(
                    "Translational prism volume references missing vertices."
                )
            }
            try OriginalParameterQueryStorage.set(start, for: edge.startVertexID, in: &result, using: &execution)
            try OriginalParameterQueryStorage.set(end, for: edge.endVertexID, in: &result, using: &execution)
        }
        return result
    }

    private func shellEdgeIDs(
        _ shell: Shell,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> Set<EdgeID> {
        try execution.consumeWork(1)
        var result = Set<EdgeID>()
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Translational prism volume references a missing face."
                )
            }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Translational prism volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.insert(coedge.edgeID, in: &result, using: &execution)
                }
            }
        }
        return result
    }

    private func planeDescriptor(
        for surface: Surface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> PlaneDescriptor? {
        try execution.consumeWork(1)
        switch surface {
        case let .plane(plane):
            return PlaneDescriptor(
                origin: plane.origin,
                normal: try plane.normal.normalized(
                    tolerance: tolerance.distance
                )
            )
        case let .analytic(.plane(origin, normal)):
            return PlaneDescriptor(
                origin: origin,
                normal: try normal.normalized(tolerance: tolerance.distance)
            )
        case .cylinder, .analytic, .bSpline:
            return nil
        case let .procedural(.offset(offset)):
            guard let source = try planeDescriptor(
                for: offset.source,
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return PlaneDescriptor(
                origin: source.origin + source.normal * offset.distance,
                normal: source.normal
            )
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalImage), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAngularTransport), .procedural(.originalAffineWord), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return nil
        }
    }

    private func isLine(_ curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch curve {
        case .line, .analytic(.line):
            return true
        case let .parameterImage(image):
            return try isLine(image.source, using: &execution)
        case let .rigidImage(image):
            return try isLine(image.source, using: &execution)
        case .affineImage, .originalAffineWord:
            return curve.hasExactLinearParameterization
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            return false
        }
    }

    private struct PlanarFace {
        let id: FaceID
        let face: Face
        let plane: PlaneDescriptor
    }

    private struct PlaneDescriptor {
        let origin: Point3D
        let normal: Vector3D
    }

    private enum CapSide {
        case first
        case second
    }

    private struct AreaBounds {
        static let zero = AreaBounds(lower: 0.0, upper: 0.0)

        let lower: Double
        let upper: Double

        func adding(_ other: AreaBounds) -> AreaBounds {
            AreaBounds(
                lower: (lower + other.lower).nextDown,
                upper: (upper + other.upper).nextUp
            )
        }

        func subtracting(_ other: AreaBounds) -> AreaBounds {
            AreaBounds(
                lower: (lower - other.upper).nextDown,
                upper: (upper - other.lower).nextUp
            )
        }
    }
}
