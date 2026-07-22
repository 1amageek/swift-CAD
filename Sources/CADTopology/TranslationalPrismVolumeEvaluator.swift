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
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        let vertices = try shellVertices(shell, model: model)
        guard vertices.count >= 4 else { return nil }
        let planarFaces = try shell.faceIDs.compactMap { faceID -> PlanarFace? in
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Translational prism volume references missing face geometry."
                )
            }
            guard let plane = try planeDescriptor(
                for: surface,
                tolerance: tolerance
            ) else {
                return nil
            }
            return PlanarFace(id: faceID, face: face, plane: plane)
        }
        guard planarFaces.count >= 2 else { return nil }

        for firstIndex in planarFaces.indices {
            for secondIndex in planarFaces.indices where secondIndex > firstIndex {
                if let result = try certifiedVolume(
                    firstCap: planarFaces[firstIndex],
                    secondCap: planarFaces[secondIndex],
                    shell: shell,
                    vertices: vertices,
                    model: model,
                    tolerance: tolerance
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
        tolerance: ModelingTolerance
    ) throws -> Double? {
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
        vertexSides.reserveCapacity(vertices.count)
        for (vertexID, point) in vertices {
            let firstResidual = abs(
                (point - firstCap.plane.origin).dot(firstCap.plane.normal)
            )
            let secondResidual = abs(
                (point - secondCap.plane.origin).dot(secondCap.plane.normal)
            )
            if firstResidual <= tolerance.distance,
               secondResidual > tolerance.distance {
                vertexSides[vertexID] = .first
            } else if secondResidual <= tolerance.distance,
                      firstResidual > tolerance.distance {
                vertexSides[vertexID] = .second
            } else {
                return nil
            }
        }

        let edgeIDs = try shellEdgeIDs(shell, model: model)
        var translation: Vector3D?
        var crossEdgeIDs = Set<EdgeID>()
        for edgeID in edgeIDs {
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
                  isLine(curve) else {
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
            crossEdgeIDs.insert(edgeID)
        }
        guard crossEdgeIDs.count >= 2,
              let translation else {
            return nil
        }
        let normalHeight = abs(translation.dot(firstCap.plane.normal))
        guard abs(normalHeight - normalSeparation) <= tolerance.distance else {
            return nil
        }

        let capIDs = Set([firstCap.id, secondCap.id])
        for faceID in shell.faceIDs where !capIDs.contains(faceID) {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID],
                  try faceIsTranslatedSide(
                      face,
                      surface: surface,
                      translation: translation,
                      crossEdgeIDs: crossEdgeIDs,
                      model: model,
                      tolerance: tolerance
                  ) else {
                return nil
            }
        }
        guard try capContainsOnlyBoundaryEdges(
            firstCap.face,
            crossEdgeIDs: crossEdgeIDs,
            model: model
        ), try capContainsOnlyBoundaryEdges(
            secondCap.face,
            crossEdgeIDs: crossEdgeIDs,
            model: model
        ) else {
            return nil
        }

        let characteristicLength = max(
            tolerance.distance,
            try BoundingBox3D(points: Array(vertices.values)).size.length
        )
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
            tolerance: tolerance
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
        tolerance: ModelingTolerance
    ) throws -> AreaBounds? {
        let coedgeCount = try face.loops.reduce(into: 0) { count, loopID in
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing loop."
                )
            }
            count += loop.coedges.count
        }
        guard coedgeCount > 0 else { return nil }
        let curveWidth = requestedWidth / Double(coedgeCount)
        let integrator = SurfaceParameterCurveAreaIntegrator()
        var result = AreaBounds.zero
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing or empty loop."
                )
            }
            var signed = SurfaceParameterAreaBounds.zero
            for coedge in loop.coedges {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                signed = signed.adding(try integrator.bounds(
                    for: pcurve,
                    uShift: 0.0,
                    requestedWidth: curveWidth,
                    tolerance: tolerance
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
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.filter({ crossEdgeIDs.contains($0.edgeID) }).count == 2 else {
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
            return exactTranslationDirection(
                spline,
                translation: translation,
                tolerance: tolerance
            )
        case .analytic:
            return false
        }
    }

    private func exactTranslationDirection(
        _ surface: BSplineSurface3D,
        translation: Vector3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        if surface.vDegree == 1,
           surface.vControlPointCount == 2,
           surface.controlPoints.count == 2,
           surface.weights.count == 2,
           surface.controlPoints[0].count == surface.controlPoints[1].count,
           surface.weights[0].count == surface.weights[1].count,
           surface.controlPoints[0].count == surface.weights[0].count {
            return surface.controlPoints[0].indices.allSatisfy { index in
                translatedPairMatches(
                    surface.controlPoints[0][index],
                    surface.controlPoints[1][index],
                    firstWeight: surface.weights[0][index],
                    secondWeight: surface.weights[1][index],
                    translation: translation,
                    tolerance: tolerance
                )
            }
        }
        if surface.uDegree == 1,
           surface.uControlPointCount == 2,
           surface.controlPoints.allSatisfy({ $0.count == 2 }),
           surface.weights.count == surface.controlPoints.count,
           surface.weights.allSatisfy({ $0.count == 2 }) {
            return surface.controlPoints.indices.allSatisfy { index in
                translatedPairMatches(
                    surface.controlPoints[index][0],
                    surface.controlPoints[index][1],
                    firstWeight: surface.weights[index][0],
                    secondWeight: surface.weights[index][1],
                    translation: translation,
                    tolerance: tolerance
                )
            }
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
        model: BRepModel
    ) throws -> Bool {
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference(
                    "Translational prism cap references a missing loop."
                )
            }
            if loop.coedges.contains(where: { crossEdgeIDs.contains($0.edgeID) }) {
                return false
            }
        }
        return true
    }

    private func shellVertices(
        _ shell: Shell,
        model: BRepModel
    ) throws -> [VertexID: Point3D] {
        var result: [VertexID: Point3D] = [:]
        for edgeID in try shellEdgeIDs(shell, model: model) {
            guard let edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference(
                    "Translational prism volume references missing vertices."
                )
            }
            result[edge.startVertexID] = start
            result[edge.endVertexID] = end
        }
        return result
    }

    private func shellEdgeIDs(
        _ shell: Shell,
        model: BRepModel
    ) throws -> Set<EdgeID> {
        var result = Set<EdgeID>()
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Translational prism volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Translational prism volume references a missing loop."
                    )
                }
                result.formUnion(loop.coedges.map(\.edgeID))
            }
        }
        return result
    }

    private func planeDescriptor(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> PlaneDescriptor? {
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
        }
    }

    private func isLine(_ curve: Curve3D) -> Bool {
        switch curve {
        case .line, .analytic(.line):
            return true
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift:
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
