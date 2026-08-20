import CADCore
import CADGeometry
import CADIR
import CADTopology

struct FacePointContainmentPreparationCache {
    struct UV: Sendable {
        let u: Double
        let v: Double
    }

    struct LoopRegion: Sendable {
        struct ParameterBounds: Sendable {
            let minimumU: Double
            let maximumU: Double
            let minimumV: Double
            let maximumV: Double
        }

        let role: LoopRole
        let polygon: [UV]
        let planarPolygon: [Point2D]
        let center: UV
        let bounds: ParameterBounds?

        init(role: LoopRole, polygon: [UV]) {
            self.role = role
            self.polygon = polygon
            planarPolygon = polygon.map { Point2D(x: $0.u, y: $0.v) }

            guard let first = polygon.first else {
                center = UV(u: 0.0, v: 0.0)
                bounds = nil
                return
            }
            var minimumU = first.u
            var maximumU = first.u
            var minimumV = first.v
            var maximumV = first.v
            var sumU = 0.0
            var sumV = 0.0
            for vertex in polygon {
                minimumU = min(minimumU, vertex.u)
                maximumU = max(maximumU, vertex.u)
                minimumV = min(minimumV, vertex.v)
                maximumV = max(maximumV, vertex.v)
                sumU += vertex.u
                sumV += vertex.v
            }
            center = UV(
                u: sumU / Double(polygon.count),
                v: sumV / Double(polygon.count)
            )
            bounds = ParameterBounds(
                minimumU: minimumU,
                maximumU: maximumU,
                minimumV: minimumV,
                maximumV: maximumV
            )
        }
    }

    struct PreparedFace: Sendable {
        let surface: Surface3D
        let loops: [LoopRegion]
    }

    var faces: [FaceID: PreparedFace] = [:]
}
