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
        let role: LoopRole
        let center: UV
        let certifiedPredicate: CertifiedSurfaceParameterLoopPredicate?
        let uWinding: Int
        let vWinding: Int
        let constantULevel: Double?
        let constantVLevel: Double?

        init(
            role: LoopRole,
            polygon: [UV],
            certifiedPredicate: CertifiedSurfaceParameterLoopPredicate?,
            uWinding: Int,
            vWinding: Int,
            constantULevel: Double?,
            constantVLevel: Double?
        ) {
            self.role = role
            self.certifiedPredicate = certifiedPredicate
            self.uWinding = uWinding
            self.vWinding = vWinding
            self.constantULevel = constantULevel
            self.constantVLevel = constantVLevel

            guard polygon.isEmpty == false else {
                center = UV(u: 0.0, v: 0.0)
                return
            }
            var sumU = 0.0
            var sumV = 0.0
            for vertex in polygon {
                sumU += vertex.u
                sumV += vertex.v
            }
            center = UV(
                u: sumU / Double(polygon.count),
                v: sumV / Double(polygon.count)
            )
        }
    }

    struct PreparedFace: Sendable {
        let surface: Surface3D
        let loops: [LoopRegion]
    }

    var faces: [FaceID: PreparedFace] = [:]
}
