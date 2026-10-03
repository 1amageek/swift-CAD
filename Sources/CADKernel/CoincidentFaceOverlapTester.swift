import CADCore
import CADIR
import CADModeling
import CADTopology

/// Distinguishes coincident supporting surfaces from overlapping trimmed faces.
struct CoincidentFaceOverlapTester {
    private let facePointContainment: any FacePointContainmentTesting

    init(facePointContainment: any FacePointContainmentTesting) {
        self.facePointContainment = facePointContainment
    }

    func overlapsOrTouches(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try overlapWitness(
            firstFaceID,
            secondFaceID,
            in: model,
            tolerance: tolerance
        ) != nil
    }

    /// Returns a point certified by trim-edge intersection or face
    /// containment to belong to both coincident trimmed faces.
    func overlapWitness(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Point3D? {
        let firstPatch = try patch(
            faceID: firstFaceID,
            stableID: "coincident-overlap:first",
            model: model,
            tolerance: tolerance
        )
        let secondPatch = try patch(
            faceID: secondFaceID,
            stableID: "coincident-overlap:second",
            model: model,
            tolerance: tolerance
        )
        let firstEdges = firstPatch.loops.flatMap(\.edges)
        let secondEdges = secondPatch.loops.flatMap(\.edges)

        let intersector = ExactTrimEdgeIntersector()
        for firstEdge in firstEdges {
            for secondEdge in secondEdges {
                switch try intersector.intersections(
                    firstEdge,
                    secondEdge,
                    tolerance: tolerance
                ) {
                case .coincident:
                    return firstEdge.startPoint
                case let .subdivisionPoints(points) where points.isEmpty == false:
                    return points.sorted(by: pointOrder).first
                case .subdivisionPoints:
                    continue
                }
            }
        }

        for edge in firstEdges where try containsOnCoincidentSupport(
            edge.startPoint,
            on: secondFaceID,
            in: model,
            tolerance: tolerance
        ) {
            return edge.startPoint
        }
        for edge in secondEdges where try containsOnCoincidentSupport(
            edge.startPoint,
            on: firstFaceID,
            in: model,
            tolerance: tolerance
        ) {
            return edge.startPoint
        }
        return nil
    }

    /// Whether two coincident faces share area, not only a boundary they touch along: a point
    /// just inside one face beside one of its edges lies inside the other. Points are taken at a
    /// quarter, half and three quarters along each edge of each face, a small step to either
    /// side, keeping the side inside the face's own trim.
    func overlapsInArea(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for (own, other) in [(firstFaceID, secondFaceID), (secondFaceID, firstFaceID)] {
            guard let face = model.faces[own], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A coincident face is missing.")
            }
            let edges = try patch(faceID: own, stableID: "coincident-area", model: model, tolerance: tolerance).loops.flatMap(\.edges)
            for edge in edges {
                let span = edge.endParameter - edge.startParameter
                for fraction in [0.25, 0.5, 0.75] {
                    let parameter = edge.startParameter + span * fraction
                    let geometry = try edge.curve.differentialGeometry(at: parameter, tolerance: tolerance)
                    let normal = try SurfaceFootResolver().foot(of: geometry.position, on: surface, tolerance: tolerance).normal
                    let length = (edge.endPoint - edge.startPoint).length
                    let step = max(length * 1e-3, tolerance.distance * 100)
                    let crossing = normal.cross(geometry.firstDerivative)
                    // A point where the edge stops turning has no side to step to.
                    guard crossing.length > Double.ulpOfOne * 1_024 else { continue }
                    let across = crossing * (1 / crossing.length)
                    for side in [across, across * -1] {
                        let point = geometry.position + side * step
                        if try containsOnCoincidentSupport(point, on: own, in: model, tolerance: tolerance),
                           try containsOnCoincidentSupport(point, on: other, in: model, tolerance: tolerance) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func containsOnCoincidentSupport(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try facePointContainment.contains(
            point,
            on: faceID,
            in: model,
            tolerance: tolerance
        )
    }

    private func pointOrder(_ first: Point3D, _ second: Point3D) -> Bool {
        (first.x, first.y, first.z) < (second.x, second.y, second.z)
    }

    private func patch(
        faceID: FaceID,
        stableID: String,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        try SourceBRepFacePatchBuilder().build(
            faceID: faceID,
            stableID: stableID,
            from: model,
            sourceSubshapes: [:],
            tolerance: tolerance
        ).patch
    }
}
