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
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let simplified = try Self.simplified(
            vertices,
            preserveCollinearVertices: preserveCollinearVertices,
            tolerance: tolerance.distance
        , using: &execution)
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

    func inverted(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> PlanarBooleanPolygon {
        try execution.consumeWork(1)
        return try PlanarBooleanPolygon(
            vertices: vertices.reversed(),
            surface: surface,
            surfaceOrientation: surfaceOrientation == .forward ? .reversed : .forward,
            plane: plane.inverted,
            tolerance: tolerance
        , using: &execution)
    }

    private static func simplified(
        _ vertices: some Sequence<Point3D>,
        preserveCollinearVertices: Bool,
        tolerance: Double
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        try execution.consumeWork(1)
        var result: [Point3D] = []
        for vertex in vertices {
            try execution.consumeWork(1)
            if result.last?.isApproximatelyEqual(to: vertex, tolerance: tolerance) != true {
                try OriginalParameterQueryStorage.append(vertex, to: &result, using: &execution)
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
            try execution.consumeWork(1)
            changed = false
            for index in result.indices {
            try execution.consumeWork(1)
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
