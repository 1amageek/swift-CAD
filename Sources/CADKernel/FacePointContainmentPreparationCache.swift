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
        let polygon: [UV]
    }

    struct PreparedFace: Sendable {
        let surface: Surface3D
        let loops: [LoopRegion]
    }

    var faces: [FaceID: PreparedFace] = [:]
}
