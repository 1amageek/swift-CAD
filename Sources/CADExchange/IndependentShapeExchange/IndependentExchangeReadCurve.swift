import CADCore
import CADIR
import CADGeometry
import CADTopology

/// Original basis identity is shared independently from each selected trim.
public struct IndependentExchangeReadCurve: Sendable {
    public let id: CurveID
    public let linearSource: OriginalSTEPLineSource?
    public let splineSource: OriginalSTEPSplineCurveSource?
    public let curve: Curve3D
    public let trim: CurveTrim?
    public let traversalSource: Curve3D?
    public let trimmingSource: IndependentShapeTrimmingSource?
    public let basisEntityID: Int
    public let basisName: String
    public let positionEntityID: Int?
    public let parameterLengthUnit: LengthUnit?
    public init(id: CurveID, curve: Curve3D, trim: CurveTrim?, basisEntityID: Int, basisName: String, positionEntityID: Int? = nil, parameterLengthUnit: LengthUnit? = nil, trimmingSource: IndependentShapeTrimmingSource? = nil, traversalSource: Curve3D? = nil, linearSource: OriginalSTEPLineSource? = nil, splineSource: OriginalSTEPSplineCurveSource? = nil) {
        self.linearSource = linearSource; self.splineSource = splineSource; self.id = id; self.curve = curve; self.trim = trim; self.trimmingSource = trimmingSource; self.traversalSource = traversalSource; self.basisEntityID = basisEntityID; self.basisName = basisName
        self.positionEntityID = positionEntityID; self.parameterLengthUnit = parameterLengthUnit
    }
}
