import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Surface parameter loop lift")
struct SurfaceParameterLoopLiftTests {
    @Test
    func torusGeneratorRetainsNonContractibleWinding() throws {
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let lift = try SurfaceParameterLoopLift(
            samples: angularSamples(v: 0.4),
            surface: surface,
            tolerance: .standard
        )
        #expect(lift.uWinding == 1)
        #expect(lift.vWinding == 0)
        #expect(lift.isContractible == false)
        #expect(lift.planarBoundary == nil)
    }

    @Test
    func sphereLatitudeClosesThroughNearestParameterPole() throws {
        let surface = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let lift = try SurfaceParameterLoopLift(
            samples: angularSamples(v: 0.7),
            surface: surface,
            tolerance: .standard
        )
        #expect(lift.uWinding == 1)
        #expect(lift.closesThroughUSingularity)
        #expect(lift.isContractible)
        let boundary = try #require(lift.planarBoundary)
        #expect(boundary.suffix(2).allSatisfy {
            $0.y == Double.pi * 0.5
        })
    }

    @Test
    func seamCrossingContractibleTorusLoopHasZeroWinding() throws {
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let samples = (0..<16).map { index -> SurfaceParameter in
            let angle = Double(index) * 2.0 * Double.pi / 16.0
            let rawU = 0.2 * cos(angle)
            return SurfaceParameter(
                u: rawU >= 0.0 ? rawU : rawU + 2.0 * Double.pi,
                v: 0.2 * sin(angle)
            )
        }
        let lift = try SurfaceParameterLoopLift(
            samples: samples,
            surface: surface,
            tolerance: .standard
        )
        #expect(lift.uWinding == 0)
        #expect(lift.vWinding == 0)
        #expect(lift.isContractible)
    }

    private func angularSamples(v: Double) -> [SurfaceParameter] {
        (0..<16).map { index in
            SurfaceParameter(
                u: Double(index) * 2.0 * Double.pi / 16.0,
                v: v
            )
        }
    }
}
