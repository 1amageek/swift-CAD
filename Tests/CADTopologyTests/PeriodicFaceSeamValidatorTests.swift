import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("Periodic face seam validation")
struct PeriodicFaceSeamValidatorTests {
    @Test
    func acceptsOppositeUsesSeparatedByOneSurfacePeriod() throws {
        let edgeID = EdgeID()
        let loop = Loop(coedges: [
            Coedge(
                edgeID: edgeID,
                orientation: .forward,
                surfaceParameterCurve: .constantU(
                    u: 2.0 * Double.pi,
                    vStart: -1.0,
                    vEnd: 1.0
                )
            ),
            Coedge(
                edgeID: edgeID,
                orientation: .reversed,
                surfaceParameterCurve: .constantU(
                    u: 0.0,
                    vStart: 1.0,
                    vEnd: -1.0
                )
            ),
        ])
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))

        try PeriodicFaceSeamValidator().validateRepeatedEdgeUses(
            in: loop,
            on: cylinder,
            tolerance: .standard
        )
    }

    @Test
    func rejectsRepeatedUsesWithoutPeriodicChartSeparation() {
        let edgeID = EdgeID()
        let loop = Loop(coedges: [
            Coedge(
                edgeID: edgeID,
                orientation: .forward,
                surfaceParameterCurve: .constantU(
                    u: 0.0,
                    vStart: -1.0,
                    vEnd: 1.0
                )
            ),
            Coedge(
                edgeID: edgeID,
                orientation: .reversed,
                surfaceParameterCurve: .constantU(
                    u: 0.0,
                    vStart: 1.0,
                    vEnd: -1.0
                )
            ),
        ])
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))

        #expect(throws: TopologyError.self) {
            try PeriodicFaceSeamValidator().validateRepeatedEdgeUses(
                in: loop,
                on: cylinder,
                tolerance: .standard
            )
        }
    }
}
