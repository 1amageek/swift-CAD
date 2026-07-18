import CADCore
import CADIR
import CADTopology

struct OrthogonalSolidOperand: Sendable {
    var cells: [AxisAlignedBox]

    init(bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing boolean target body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal boolean evaluation currently requires solid operands."
            )
        }
        try Self.validateOrthogonalTopology(body: body, in: model, tolerance: tolerance)
        let coordinates = try Self.coordinateGrid(for: body, in: model, tolerance: tolerance)
        var cells: [AxisAlignedBox] = []
        for xIndex in 0..<(coordinates.x.count - 1) {
            for yIndex in 0..<(coordinates.y.count - 1) {
                for zIndex in 0..<(coordinates.z.count - 1) {
                    let minimum = Point3D(
                        x: coordinates.x[xIndex],
                        y: coordinates.y[yIndex],
                        z: coordinates.z[zIndex]
                    )
                    let maximum = Point3D(
                        x: coordinates.x[xIndex + 1],
                        y: coordinates.y[yIndex + 1],
                        z: coordinates.z[zIndex + 1]
                    )
                    let center = Point3D(
                        x: (minimum.x + maximum.x) * 0.5,
                        y: (minimum.y + maximum.y) * 0.5,
                        z: (minimum.z + maximum.z) * 0.5
                    )
                    guard try Self.contains(center, in: body, model: model, tolerance: tolerance) else {
                        continue
                    }
                    cells.append(try AxisAlignedBox(minimum: minimum, maximum: maximum, tolerance: tolerance))
                }
            }
        }
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Orthogonal boolean operand has no occupied cells.")
        }
        self.cells = cells
    }

    private struct CoordinateGrid: Sendable {
        var x: [Double]
        var y: [Double]
        var z: [Double]
    }

    private enum AxisDirection: Sendable {
        case positiveX
        case negativeX
        case positiveY
        case negativeY
        case positiveZ
        case negativeZ

        var isX: Bool {
            switch self {
            case .positiveX, .negativeX:
                return true
            case .positiveY, .negativeY, .positiveZ, .negativeZ:
                return false
            }
        }
    }

    private static func validateOrthogonalTopology(
        body: Body,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard body.shellIDs.isEmpty == false else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal boolean evaluation requires closed solid shells."
            )
        }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            guard shell.faceIDs.isEmpty == false else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Orthogonal boolean evaluation requires faces."
                )
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID],
                      let surface = model.geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                guard case let .plane(plane) = surface else {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                        "Orthogonal boolean evaluation currently requires planar faces."
                    )
                }
                _ = try axisDirection(for: plane.normal, tolerance: tolerance)
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
                        guard let edge = model.edges[orientedEdge.edgeID],
                              let curve = model.geometry.curves[edge.curveID],
                              let start = model.vertices[edge.startVertexID]?.point,
                              let end = model.vertices[edge.endVertexID]?.point else {
                            throw TopologyError.missingReference("Missing boolean edge geometry.")
                        }
                        guard case let .line(line) = curve else {
                            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                                "Orthogonal boolean evaluation currently requires linear edges."
                            )
                        }
                        _ = try axisDirection(for: line.direction, tolerance: tolerance)
                        try validateAxisAlignedSegment(start: start, end: end, tolerance: tolerance)
                    }
                }
            }
        }
    }

    private static func coordinateGrid(
        for body: Body,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> CoordinateGrid {
        var x: [Double] = []
        var y: [Double] = []
        var z: [Double] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                for loopID in face.loops {
                    for point in try model.orderedPoints(for: loopID) {
                        x.append(point.x)
                        y.append(point.y)
                        z.append(point.z)
                    }
                }
            }
        }
        let coordinates = CoordinateGrid(
            x: uniqueSorted(x, tolerance: tolerance),
            y: uniqueSorted(y, tolerance: tolerance),
            z: uniqueSorted(z, tolerance: tolerance)
        )
        guard coordinates.x.count >= 2,
              coordinates.y.count >= 2,
              coordinates.z.count >= 2 else {
            throw FeatureEvaluationError.emptyResult("Orthogonal boolean operand collapsed to an empty grid.")
        }
        return coordinates
    }

    private static func contains(
        _ point: Point3D,
        in body: Body,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var crossingCount = 0
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                if try crossesPositiveXRay(faceID: faceID, from: point, model: model, tolerance: tolerance) {
                    crossingCount += 1
                }
            }
        }
        return crossingCount % 2 == 1
    }

    private static func crossesPositiveXRay(
        faceID: FaceID,
        from point: Point3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Missing boolean face \(faceID).")
        }
        guard case let .plane(plane) = surface else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal boolean evaluation currently requires planar faces."
            )
        }
        let direction = try axisDirection(for: plane.normal, tolerance: tolerance)
        guard direction.isX else {
            return false
        }
        let x = plane.origin.x
        guard x > point.x + tolerance.distance else {
            return false
        }
        return try faceContainsProjectedPoint(
            Point2D(x: point.y, y: point.z),
            face: face,
            model: model,
            tolerance: tolerance
        )
    }

    private static func faceContainsProjectedPoint(
        _ point: Point2D,
        face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var containsOuterLoop = false
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Missing boolean loop \(loopID).")
            }
            let polygon = try model.orderedPoints(for: loopID).map { Point2D(x: $0.y, y: $0.z) }
            guard pointInPolygon(point, polygon: polygon, tolerance: tolerance) else {
                continue
            }
            switch loop.role {
            case .outer:
                containsOuterLoop = true
            case .inner:
                return false
            }
        }
        return containsOuterLoop
    }

    private static func pointInPolygon(
        _ point: Point2D,
        polygon: [Point2D],
        tolerance: ModelingTolerance
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        var inside = false
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[index == polygon.count - 1 ? 0 : index + 1]
            if pointOnSegment(point, start: start, end: end, tolerance: tolerance) {
                return true
            }
            let crossesHorizontalRay = (start.y > point.y) != (end.y > point.y)
            guard crossesHorizontalRay else {
                continue
            }
            let xIntersection = start.x + (point.y - start.y) * (end.x - start.x) / (end.y - start.y)
            if xIntersection > point.x + tolerance.distance {
                inside.toggle()
            }
        }
        return inside
    }

    private static func pointOnSegment(
        _ point: Point2D,
        start: Point2D,
        end: Point2D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let cross = (point.x - start.x) * (end.y - start.y) - (point.y - start.y) * (end.x - start.x)
        guard abs(cross) <= tolerance.distance else {
            return false
        }
        let minX = min(start.x, end.x) - tolerance.distance
        let maxX = max(start.x, end.x) + tolerance.distance
        let minY = min(start.y, end.y) - tolerance.distance
        let maxY = max(start.y, end.y) + tolerance.distance
        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    private static func validateAxisAlignedSegment(
        start: Point3D,
        end: Point3D,
        tolerance: ModelingTolerance
    ) throws {
        let delta = end - start
        let changingAxes = [
            abs(delta.x) > tolerance.distance,
            abs(delta.y) > tolerance.distance,
            abs(delta.z) > tolerance.distance,
        ].filter { $0 }.count
        guard changingAxes == 1 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal boolean evaluation currently requires axis-aligned edges."
            )
        }
    }

    private static func axisDirection(
        for vector: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> AxisDirection {
        let normalized = try vector.normalized(tolerance: tolerance.distance)
        let epsilon = max(tolerance.distance, tolerance.angle)
        if abs(normalized.x - 1.0) <= epsilon, abs(normalized.y) <= epsilon, abs(normalized.z) <= epsilon {
            return .positiveX
        }
        if abs(normalized.x + 1.0) <= epsilon, abs(normalized.y) <= epsilon, abs(normalized.z) <= epsilon {
            return .negativeX
        }
        if abs(normalized.y - 1.0) <= epsilon, abs(normalized.x) <= epsilon, abs(normalized.z) <= epsilon {
            return .positiveY
        }
        if abs(normalized.y + 1.0) <= epsilon, abs(normalized.x) <= epsilon, abs(normalized.z) <= epsilon {
            return .negativeY
        }
        if abs(normalized.z - 1.0) <= epsilon, abs(normalized.x) <= epsilon, abs(normalized.y) <= epsilon {
            return .positiveZ
        }
        if abs(normalized.z + 1.0) <= epsilon, abs(normalized.x) <= epsilon, abs(normalized.y) <= epsilon {
            return .negativeZ
        }
        throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
            "Orthogonal boolean evaluation currently requires axis-aligned planes and edges."
        )
    }
}
