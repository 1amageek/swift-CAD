import CADCore
import CADGeometry

public struct BRepDistanceMinimumRegion: Sendable {
    public let firstSupport: BRepDistanceSelection
    public let secondSupport: BRepDistanceSelection
    public let firstParameterRanges: [ScalarInterval]
    public let secondParameterRanges: [ScalarInterval]
    public let lowerDistanceBound: Double
}
