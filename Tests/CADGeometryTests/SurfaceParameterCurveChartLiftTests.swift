import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Surface parameter curve chart lift")
struct SurfaceParameterCurveChartLiftTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func sphericalEquatorCrossingSeamRetainsContinuousLongitude() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitY,
            sine: -.unitX,
            startParameter: -0.1,
            endParameter: 0.1
        )

        let lift = try curve.continuousChartLift(
            on: sphere,
            tolerance: tolerance
        )

        #expect(abs(lift.start.u - (2.0 * Double.pi - 0.1)) <= tolerance.angle)
        #expect(abs(lift.middle.u - 2.0 * Double.pi) <= tolerance.angle)
        #expect(abs(lift.end.u - (2.0 * Double.pi + 0.1)) <= tolerance.angle)
        #expect(lift.visitsUSingularity == false)
    }

    @Test
    func wholeTurnTranslationPreservesContinuousDisplacement() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let source = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitY,
            sine: -.unitX,
            startParameter: -0.1,
            endParameter: 0.1
        )
        let translated = SurfaceParameterCurve.periodicTranslation(
            base: source,
            uShift: 2.0 * Double.pi,
            vShift: 0.0
        )

        let sourceLift = try source.continuousChartLift(
            on: sphere,
            tolerance: tolerance
        )
        let translatedLift = try translated.continuousChartLift(
            on: sphere,
            tolerance: tolerance
        )

        #expect(abs(
            (translatedLift.end.u - translatedLift.start.u)
                - (sourceLift.end.u - sourceLift.start.u)
        ) <= tolerance.angle)
        #expect(abs(
            translatedLift.middle.u - sourceLift.middle.u
                - 2.0 * Double.pi
        ) <= tolerance.angle)
    }

    @Test
    func intrinsicDerivativeBoundPreventsExplicitMultiTurnAliasing() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let curve = SurfaceParameterCurve.constantV(
            v: 0.2,
            uStart: 0.0,
            uEnd: 20.0 * Double.pi
        )

        let lift = try curve.continuousChartLift(
            on: torus,
            tolerance: tolerance
        )

        #expect(abs(lift.end.u - 20.0 * Double.pi) <= tolerance.angle)
    }

    @Test
    func derivativeBoundPreventsHiddenMultiTurnAliasing() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let totalTurn = 20.0 * Double.pi
        let curve = SurfaceParameterCurve.constantV(
            v: 0.2,
            uStart: 0.0,
            uEnd: totalTurn
        )

        let lift = try curve.continuousChartLift(
            on: torus,
            maximumParameterFirstDerivativeMagnitude: totalTurn,
            tolerance: tolerance
        )

        #expect(abs(lift.end.u - totalTurn) <= tolerance.angle)
    }

    @Test
    func oddCertifiedSubdivisionRequirementRetainsExactMiddleParameter() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let totalTurn = 8.5 * Double.pi
        let curve = SurfaceParameterCurve.constantV(
            v: 0.2,
            uStart: 0.0,
            uEnd: totalTurn
        )

        let lift = try curve.continuousChartLift(
            on: torus,
            maximumParameterFirstDerivativeMagnitude: totalTurn,
            tolerance: tolerance
        )

        #expect(abs(lift.middle.u - totalTurn * 0.5) <= tolerance.angle)
    }

    @Test
    func excessiveFiniteDerivativeBoundFailsWithoutIntegerConversionTrap() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let curve = SurfaceParameterCurve.constantV(
            v: 0.2,
            uStart: 0.0,
            uEnd: 1.0
        )

        #expect(throws: KernelError.self) {
            _ = try curve.continuousChartLift(
                on: torus,
                maximumParameterFirstDerivativeMagnitude:
                    Double.greatestFiniteMagnitude,
                tolerance: tolerance
            )
        }
    }
}
