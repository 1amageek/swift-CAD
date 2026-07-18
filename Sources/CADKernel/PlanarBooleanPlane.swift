import CADCore
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
    ) throws {
        let classifications = polygon.vertices.map { point -> Classification in
            let distance = signedDistance(to: point)
            if distance > tolerance.distance { return .front }
            if distance < -tolerance.distance { return .back }
            return .coplanar
        }
        let hasFront = classifications.contains(.front)
        let hasBack = classifications.contains(.back)
        if hasFront == false, hasBack == false {
            if normal.dot(polygon.plane.normal) >= 0.0 {
                coplanarFront.append(polygon)
            } else {
                coplanarBack.append(polygon)
            }
            return
        }
        if hasBack == false {
            front.append(polygon)
            return
        }
        if hasFront == false {
            back.append(polygon)
            return
        }

        var frontVertices: [Point3D] = []
        var backVertices: [Point3D] = []
        for index in polygon.vertices.indices {
            let nextIndex = (index + 1) % polygon.vertices.count
            let current = polygon.vertices[index]
            let next = polygon.vertices[nextIndex]
            let currentType = classifications[index]
            let nextType = classifications[nextIndex]
            if currentType != .back {
                append(current, to: &frontVertices, tolerance: tolerance.distance)
            }
            if currentType != .front {
                append(current, to: &backVertices, tolerance: tolerance.distance)
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
                append(intersection, to: &frontVertices, tolerance: tolerance.distance)
                append(intersection, to: &backVertices, tolerance: tolerance.distance)
            }
        }
        if frontVertices.count >= 3 {
            front.append(try PlanarBooleanPolygon(
                vertices: frontVertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                tolerance: tolerance
            ))
        }
        if backVertices.count >= 3 {
            back.append(try PlanarBooleanPolygon(
                vertices: backVertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                tolerance: tolerance
            ))
        }
    }

    private func signedDistance(to point: Point3D) -> Double {
        normal.dot(point - .origin) - offset
    }

    private func append(
        _ point: Point3D,
        to points: inout [Point3D],
        tolerance: Double
    ) {
        if points.last?.isApproximatelyEqual(to: point, tolerance: tolerance) != true {
            points.append(point)
        }
    }

    private enum Classification {
        case coplanar
        case front
        case back
    }
}
