import Foundation
import CADCore
import CADGeometry
import CADIR
@testable import CADModeling
import Testing

@Suite("Exact trim loop adaptive area certification")
struct ExactSurfaceTrimLoopValidatorAdaptiveAreaTests {
    /// A strongly weighted rational pcurve loop must certify its area and
    /// orientation without exhausting the certified integration budget.
    @Test(.timeLimit(.minutes(1)))
    func certifiesStronglyWeightedRationalLoopWithinBudget() throws {
        let loop = SurfaceTrimLoop(
            role: .outer,
            parameterCurves: [
                .bSpline(BSplineCurve2D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        Point2D(x: 0.2, y: 0.2),
                        Point2D(x: 0.52, y: 0.42),
                        Point2D(x: 0.8, y: 0.25),
                    ],
                    weights: [1.0, 2.4, 1.0]
                )),
                .polyline([
                    SurfaceParameter(u: 0.8, v: 0.25),
                    SurfaceParameter(u: 0.45, v: 0.8),
                ]),
                .polyline([
                    SurfaceParameter(u: 0.45, v: 0.8),
                    SurfaceParameter(u: 0.2, v: 0.2),
                ]),
            ]
        )
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let validation = try ExactSurfaceTrimLoopValidator().validate(
            [loop],
            on: surface,
            inside: RectangularSurfaceParameterBounds(
                lowerU: 0.0,
                upperU: 1.0,
                lowerV: 0.0,
                upperV: 1.0
            ),
            tolerance: .standard
        )
        #expect(validation.parameterAreaLowerBound > 0.0)
        #expect(validation.parameterAreaUpperBound < 1.0)
    }
}
