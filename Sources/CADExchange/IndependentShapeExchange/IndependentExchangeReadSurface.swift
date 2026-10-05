import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct IndependentExchangeReadSurface: Sendable {
    public let id: SurfaceID
    public let surface: Surface3D
    public let basisName: String
    public let positionEntityID: Int?
    public let angularMeasure: IndependentShapeSurfaceAngularMeasure?
    public let splineSource: OriginalSTEPSplineSurfaceSource?
    public init(id: SurfaceID, surface: Surface3D, basisName: String, positionEntityID: Int? = nil, angularMeasure: IndependentShapeSurfaceAngularMeasure? = nil, splineSource: OriginalSTEPSplineSurfaceSource? = nil) {
        self.id = id; self.surface = surface; self.basisName = basisName; self.positionEntityID = positionEntityID; self.angularMeasure = angularMeasure; self.splineSource = splineSource
    }
}
