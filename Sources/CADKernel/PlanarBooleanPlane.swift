import CADCore
import CADTopology
import CADGeometry

struct PlanarBooleanPlane {
    let normal: Vector3D
    let offset: Double

    init(
        origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        self.normal = try normal.normalized(tolerance: tolerance.distance)
        self.offset = self.normal.dot(origin - .origin)
    }

    private init(normal: Vector3D, offset: Double) {
        self.normal = normal
        self.offset = offset
    }

    var inverted: PlanarBooleanPlane {
        PlanarBooleanPlane(normal: -normal, offset: -offset)
    }

    func split(
        _ polygon: PlanarBooleanPolygon,
        coplanarFront: inout [PlanarBooleanPolygon],
        coplanarBack: inout [PlanarBooleanPolygon],
        front: inout [PlanarBooleanPolygon],
        back: inout [PlanarBooleanPolygon],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let classifications = try OriginalParameterQueryStorage.map(polygon.vertices, using: &execution) { point, execution -> Classification in
            let distance = signedDistance(to: point)
            if distance > tolerance.distance { return .front }
            if distance < -tolerance.distance { return .back }
            return .coplanar
        }
        let hasFront = classifications.contains(.front)
        let hasBack = classifications.contains(.back)
        if hasFront == false, hasBack == false {
            if normal.dot(polygon.plane.normal) >= 0.0 {
                try OriginalParameterQueryStorage.append(polygon, to: &coplanarFront, using: &execution)
            } else {
                try OriginalParameterQueryStorage.append(polygon, to: &coplanarBack, using: &execution)
            }
            return
        }
        if hasBack == false {
            try OriginalParameterQueryStorage.append(polygon, to: &front, using: &execution)
            return
        }
        if hasFront == false {
            try OriginalParameterQueryStorage.append(polygon, to: &back, using: &execution)
            return
        }

        var frontVertices: [Point3D] = []
        var backVertices: [Point3D] = []
        for index in polygon.vertices.indices {
            try execution.consumeWork(1)
            let nextIndex = (index + 1) % polygon.vertices.count
            let current = polygon.vertices[index]
            let next = polygon.vertices[nextIndex]
            let currentType = classifications[index]
            let nextType = classifications[nextIndex]
            if currentType != .back {
                try append(current, to: &frontVertices, tolerance: tolerance.distance, using: &execution)
            }
            if currentType != .front {
                try append(current, to: &backVertices, tolerance: tolerance.distance, using: &execution)
            }
            if (currentType == .front && nextType == .back)
                || (currentType == .back && nextType == .front) {
                let direction = next - current
                let denominator = normal.dot(direction)
                guard abs(denominator) > Double.ulpOfOne else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Planar Boolean spanning edge is parallel to its splitting plane."
                    )
                }
                let fraction = min(1.0, max(0.0, (offset - normal.dot(current - .origin)) / denominator))
                let intersection = current + direction * fraction
                try append(intersection, to: &frontVertices, tolerance: tolerance.distance, using: &execution)
                try append(intersection, to: &backVertices, tolerance: tolerance.distance, using: &execution)
            }
        }
        if frontVertices.count >= 3 {
            let fragment = try PlanarBooleanPolygon(
                vertices: frontVertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                tolerance: tolerance
            , using: &execution)
            try OriginalParameterQueryStorage.append(fragment, to: &front, using: &execution)
        }
        if backVertices.count >= 3 {
            let fragment = try PlanarBooleanPolygon(
                vertices: backVertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                tolerance: tolerance
            , using: &execution)
            try OriginalParameterQueryStorage.append(fragment, to: &back, using: &execution)
        }
    }

    private func signedDistance(to point: Point3D) -> Double {
        normal.dot(point - .origin) - offset
    }

    private func append(
        _ point: Point3D,
        to points: inout [Point3D],
        tolerance: Double,
        using execution: inout OriginalQueryExecution
    ) throws {
        if points.last?.isApproximatelyEqual(to: point, tolerance: tolerance) != true {
            try OriginalParameterQueryStorage.append(point, to: &points, using: &execution)
        }
    }

    private enum Classification {
        case coplanar
        case front
        case back
    }
}
