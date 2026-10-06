import CADGeometry
import CADTopology

/// An independent curve and its optional ordered parameter trim.
public struct IndependentSTEPCurve: Sendable {
    public let name: String
    public let curve: Curve3D
    public let trim: CurveTrim?

    public init(name: String, curve: Curve3D, trim: CurveTrim? = nil) {
        self.name = name
        self.curve = curve
        self.trim = trim
    }
}
