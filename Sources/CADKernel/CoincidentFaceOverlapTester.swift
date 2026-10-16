import CADCore
import CADGeometry
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
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        return try overlapWitness(
            firstFaceID,
            secondFaceID,
            in: model,
            tolerance: tolerance
        , using: &execution) != nil
    }

    /// Returns a point certified by trim-edge intersection or face
    /// containment to belong to both coincident trimmed faces.
    func overlapWitness(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> Point3D? {
        try execution.consumeWork(1)
        let firstPatch = try patch(
            faceID: firstFaceID,
            stableID: "coincident-overlap:first",
            model: model,
            tolerance: tolerance
        , using: &execution)
        let secondPatch = try patch(
            faceID: secondFaceID,
            stableID: "coincident-overlap:second",
            model: model,
            tolerance: tolerance
        , using: &execution)
        var firstEdges: [BRepSewingEdge] = []
        var secondEdges: [BRepSewingEdge] = []
        for loop in firstPatch.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: loop.edges, to: &firstEdges, using: &execution)
        }
        for loop in secondPatch.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: loop.edges, to: &secondEdges, using: &execution)
        }

        let intersector = ExactTrimEdgeIntersector()
        var endpointWitness: Point3D?
        for firstEdge in firstEdges {
            try execution.consumeWork(1)
            for secondEdge in secondEdges {
                try execution.consumeWork(1)
                switch try intersector.intersections(
                    firstEdge,
                    secondEdge,
                    tolerance: tolerance
                , using: &execution) {
                case .coincident:
                    let kind = try BRepEdgeGeometryClassifier().kind(curve: firstEdge.curve,
                        from: firstEdge.startParameter, to: firstEdge.endParameter, tolerance: tolerance, using: &execution)
                    if kind != .singular {
                        return try firstEdge.curve.point(at: firstEdge.startParameter
                            + (firstEdge.endParameter - firstEdge.startParameter) * 0.5, tolerance: tolerance, using: &execution)
                    }
                    if endpointWitness == nil { endpointWitness = firstEdge.startPoint }
                case let .subdivisionPoints(points) where points.isEmpty == false:
                    if endpointWitness == nil { endpointWitness = try OriginalParameterQueryStorage.ordered(points, using: &execution, less: pointOrder).first }
                case .subdivisionPoints:
                    continue
                }
            }
        }

        try execution.retainKernelValues(count: 2, stride: MemoryLayout<([BRepSewingEdge], FaceID)>.stride)
        for (edges, oppositeFaceID) in [(firstEdges, secondFaceID), (secondEdges, firstFaceID)] {
            try execution.consumeWork(1)
            for edge in edges {
                try execution.consumeWork(1)
                let kind = try BRepEdgeGeometryClassifier().kind(curve: edge.curve,
                    from: edge.startParameter, to: edge.endParameter, tolerance: tolerance, using: &execution)
                if kind != .singular {
                    let middle = try edge.curve.point(at: edge.startParameter
                        + (edge.endParameter - edge.startParameter) * 0.5, tolerance: tolerance, using: &execution)
                    if try containsOnCoincidentSupport(middle, on: oppositeFaceID, in: model, tolerance: tolerance, using: &execution) {
                        return middle
                    }
                }
                if endpointWitness == nil,
                   try containsOnCoincidentSupport(edge.startPoint, on: oppositeFaceID,
                       in: model, tolerance: tolerance, using: &execution) {
                    endpointWitness = edge.startPoint
                }
            }
        }
        return endpointWitness
    }

    /// Classifies finite area using the complete original trim-event partition.
    func overlapsInArea(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        return try FiniteCoincidentFaceAreaClassifier().overlaps(firstFaceID, secondFaceID,
            model: model, tolerance: tolerance, using: &execution)
    }

    private func containsOnCoincidentSupport(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        return try facePointContainment.contains(
            point,
            on: faceID,
            in: model,
            tolerance: tolerance
        , using: &execution)
    }

    private func pointOrder(_ first: Point3D, _ second: Point3D) -> Bool {
        (first.x, first.y, first.z) < (second.x, second.y, second.z)
    }

    private func patch(
        faceID: FaceID,
        stableID: String,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        return try SourceBRepFacePatchBuilder().build(
            faceID: faceID,
            stableID: stableID,
            from: model,
            sourceSubshapes: [:],
            tolerance: tolerance
        , using: &execution).patch
    }
}
