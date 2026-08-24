import Testing
import CADCore
@testable import CADGeometry

@Suite("Surface parameter topology")
struct SurfaceParameterTopologyTests {
    @Test
    func analyticAndOffsetChartsSharePeriodicityAndSingularities() {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let sphereTopology = SurfaceParameterTopology(surface: sphere)
        #expect(sphereTopology.uPeriod == 2.0 * Double.pi)
        #expect(sphereTopology.vPeriod == nil)
        #expect(sphereTopology.uSingularVValues == [
            -Double.pi * 0.5,
            Double.pi * 0.5,
        ])

        let offsetTopology = SurfaceParameterTopology(
            surface: .procedural(.offset(OffsetSurface3D(
                source: sphere,
                distance: 0.25
            )))
        )
        #expect(offsetTopology == sphereTopology)
    }

    @Test
    func torusRetainsTwoPeriodicDirectionsWithoutChartPoles() {
        let topology = SurfaceParameterTopology(surface: .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        )))
        #expect(topology.uPeriod == 2.0 * Double.pi)
        #expect(topology.vPeriod == 2.0 * Double.pi)
        #expect(topology.uSingularVValues.isEmpty)
    }
}
