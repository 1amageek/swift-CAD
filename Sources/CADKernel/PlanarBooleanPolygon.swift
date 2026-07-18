import CADCore
import CADGeometry
import CADIR
import CADTopology

struct PlanarBooleanPolygon {
    let vertices: [Point3D]
    let surface: Surface3D
    let surfaceOrientation: Orientation
    let plane: PlanarBooleanPlane

    init(
        vertices: [Point3D],
        surface: Surface3D,
        surfaceOrientation: Orientation,
        plane: PlanarBooleanPlane,
        preserveCollinearVertices: Bool = false,
        tolerance: ModelingTolerance
    ) throws {
        let simplified = Self.simplified(
            vertices,
            preserveCollinearVertices: preserveCollinearVertices,
            tolerance: tolerance.distance
        )
        guard simplified.count >= 3 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Planar Boolean polygon collapsed below three vertices."
            )
        }
        self.vertices = simplified
        self.surface = surface
        self.surfaceOrientation = surfaceOrientation
        self.plane = plane
    }

    func inverted(tolerance: ModelingTolerance) throws -> PlanarBooleanPolygon {
        try PlanarBooleanPolygon(
            vertices: vertices.reversed(),
            surface: surface,
            surfaceOrientation: surfaceOrientation == .forward ? .reversed : .forward,
            plane: plane.inverted,
            tolerance: tolerance
        )
    }

    private static func simplified(
        _ vertices: some Sequence<Point3D>,
        preserveCollinearVertices: Bool,
        tolerance: Double
    ) -> [Point3D] {
        var result: [Point3D] = []
        for vertex in vertices {
            if result.last?.isApproximatelyEqual(to: vertex, tolerance: tolerance) != true {
                result.append(vertex)
            }
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           first.isApproximatelyEqual(to: last, tolerance: tolerance) {
            result.removeLast()
        }
        guard preserveCollinearVertices == false else {
            return result
        }
        var changed = true
        while changed, result.count >= 3 {
            changed = false
            for index in result.indices {
                let previous = result[(index + result.count - 1) % result.count]
                let current = result[index]
                let next = result[(index + 1) % result.count]
                let incoming = current - previous
                let outgoing = next - current
                let scale = incoming.length + outgoing.length
                if incoming.length <= tolerance
                    || outgoing.length <= tolerance
                    || incoming.cross(outgoing).length <= tolerance * scale {
                    result.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return result
    }
}
