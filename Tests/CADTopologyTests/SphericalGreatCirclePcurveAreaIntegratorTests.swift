import CADCore
import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Spherical great-circle pcurve area integration")
struct SphericalGreatCirclePcurveAreaIntegratorTests {
    @Test(.timeLimit(.minutes(1)))
    func meridianBoundsContainExactForwardAndReversedArea() throws {
        let start = 0.2
        let end = 0.8
        let forward = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            sine: .unitZ,
            startParameter: start,
            endParameter: end
        )
        let reversed = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            sine: .unitZ,
            startParameter: end,
            endParameter: start
        )
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: forward,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )
        let reversedBounds = try integrator.bounds(
            for: reversed,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )

        let expected = Double.pi * 0.5 * (end - start)
        #expect(forwardBounds.lower <= expected)
        #expect(forwardBounds.upper >= expected)
        #expect(forwardBounds.width <= 1.0e-6)
        #expect(reversedBounds.lower <= -expected)
        #expect(reversedBounds.upper >= -expected)
        #expect(reversedBounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueArcBoundsContainIndependentHighResolutionIntegral() throws {
        let inverseSquareRootTwo = sqrt(0.5)
        let cosine = Vector3D.unitY
        let sine = Vector3D(
            x: inverseSquareRootTwo,
            y: 0.0,
            z: inverseSquareRootTwo
        )
        let start = 0.2
        let end = 0.8
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: start,
            endParameter: end
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: curve,
            uShift: 0.0,
            requestedWidth: 1.0e-5,
            tolerance: .standard
        )
        let reference = simpsonIntegral(
            lower: start,
            upper: end,
            intervalCount: 16_384
        ) { parameter in
            let sineValue = sin(parameter)
            let cosineValue = cos(parameter)
            var longitude = atan2(
                -inverseSquareRootTwo * sineValue,
                cosineValue
            )
            if longitude < 0.0 {
                longitude += 2.0 * Double.pi
            }
            let latitudeDerivative = inverseSquareRootTwo * cosineValue
                / sqrt(1.0 - 0.5 * sineValue * sineValue)
            return longitude * latitudeDerivative
        }

        #expect(bounds.lower <= reference)
        #expect(bounds.upper >= reference)
        #expect(bounds.width <= 1.0e-5)
        #expect(bounds.minimumAbsoluteValue > 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func meridianCrossingPoleUsesExactHalfArcContributions() throws {
        let start = 0.2
        let end = 2.9
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            sine: .unitZ,
            startParameter: start,
            endParameter: end
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: curve,
            uShift: 0.0,
            requestedWidth: 1.0e-8,
            tolerance: .standard
        )
        let poleLatitude = Double.pi * 0.5
        let endLatitude = Double.pi - end
        let expected = Double.pi * 0.5 * (poleLatitude - start)
            + Double.pi * 1.5 * (endLatitude - poleLatitude)

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.width <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueArcCrossingLongitudeSeamIsSplitAnalytically() throws {
        let inverseSquareRootTwo = sqrt(0.5)
        let cosine = Vector3D.unitY
        let sine = Vector3D(
            x: inverseSquareRootTwo,
            y: 0.0,
            z: inverseSquareRootTwo
        )
        let start = -0.2
        let end = 0.2
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: start,
            endParameter: end
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: curve,
            uShift: 0.0,
            requestedWidth: 1.0e-5,
            tolerance: .standard
        )
        let reference = simpsonIntegral(
            lower: start,
            upper: 0.0,
            intervalCount: 8_192,
            integrand: { obliqueIntegrand($0, seamFromPositiveSide: false) }
        ) + simpsonIntegral(
            lower: 0.0,
            upper: end,
            intervalCount: 8_192,
            integrand: { obliqueIntegrand($0, seamFromPositiveSide: true) }
        )

        #expect(bounds.lower <= reference)
        #expect(bounds.upper >= reference)
        #expect(bounds.width <= 1.0e-5)
    }

    private func obliqueIntegrand(
        _ parameter: Double,
        seamFromPositiveSide: Bool
    ) -> Double {
        let inverseSquareRootTwo = sqrt(0.5)
        let sineValue = sin(parameter)
        let cosineValue = cos(parameter)
        var longitude = atan2(
            -inverseSquareRootTwo * sineValue,
            cosineValue
        )
        if longitude < 0.0 {
            longitude += 2.0 * Double.pi
        }
        if parameter == 0.0, seamFromPositiveSide {
            longitude = 2.0 * Double.pi
        }
        let latitudeDerivative = inverseSquareRootTwo * cosineValue
            / sqrt(1.0 - 0.5 * sineValue * sineValue)
        return longitude * latitudeDerivative
    }

    private func simpsonIntegral(
        lower: Double,
        upper: Double,
        intervalCount: Int,
        integrand: (Double) -> Double
    ) -> Double {
        let width = (upper - lower) / Double(intervalCount)
        var sum = integrand(lower) + integrand(upper)
        for index in 1..<intervalCount {
            sum += (index.isMultiple(of: 2) ? 2.0 : 4.0)
                * integrand(lower + Double(index) * width)
        }
        return sum * width / 3.0
    }
}
