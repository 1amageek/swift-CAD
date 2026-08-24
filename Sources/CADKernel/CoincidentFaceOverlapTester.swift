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
