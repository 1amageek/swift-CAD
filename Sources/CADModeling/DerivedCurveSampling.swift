import CADCore
import CADGeometry
import CADIR

public protocol DerivedCurveSampling: Sendable {
    func points(
        for curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]
}
