import CADCore
import CADGeometry

public struct BRepDistanceWitness: Sendable {
    public let firstSupport: BRepDistanceSelection
    public let secondSupport: BRepDistanceSelection
    public let firstPoint: Point3D
    public let secondPoint: Point3D
    public init(firstSupport: BRepDistanceSelection, secondSupport: BRepDistanceSelection,
        firstPoint: Point3D, secondPoint: Point3D, firstParameters: [Double], secondParameters: [Double]) {
        self.firstSupport=firstSupport;self.secondSupport=secondSupport;self.firstPoint=firstPoint
        self.secondPoint=secondPoint;self.firstParameters=firstParameters;self.secondParameters=secondParameters
    }
    public let firstParameters: [Double]
    public let secondParameters: [Double]
    public var distance: Double { (secondPoint - firstPoint).length }
}
