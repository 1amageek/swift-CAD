import CADCore
import CADGeometry

/// Immutable lifetime owner shared by construction views of one original curve.
package final class OriginalCurveSpanSource: Sendable {
    package let curve: Curve3D
    package let admission: GeometryConversionAdmission?
    package let prepared: PreparedCurveDifferentialEncloser?
    package let preparationTolerance: ModelingTolerance?

    package init(curve: Curve3D) {
        self.curve = curve; admission = nil; prepared = nil; preparationTolerance = nil
    }

    package init(curve: Curve3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        self.curve = curve; self.admission = admission; preparationTolerance = tolerance
        prepared = try PreparedCurveDifferentialEncloser(curve: curve,
            tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) },
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
    }
}
