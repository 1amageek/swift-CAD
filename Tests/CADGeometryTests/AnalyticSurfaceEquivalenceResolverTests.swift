import CADCore
@testable import CADGeometry
import Testing

struct AnalyticSurfaceEquivalenceResolverTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func analyticRepresentationsRespectGeometricEquivalence() throws {
        let resolver = DefaultAnalyticSurfaceEquivalenceResolver()
        let plane = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 2.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: 0.5
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))

        #expect(try resolver.areEquivalent(
            plane,
            .analytic(.plane(
                origin: Point3D(x: 2.0, y: -3.0, z: 0.0),
                normal: -Vector3D.unitZ
            )),
            tolerance: tolerance
        ))
        #expect(try resolver.areEquivalent(
            sphere,
            .analytic(.sphere(
                center: Point3D(
                    x: tolerance.distance * 0.5,
                    y: 0.0,
                    z: 0.0
                ),
                radius: 2.0 + tolerance.distance * 0.5
            )),
            tolerance: tolerance
        ))
        #expect(try resolver.areEquivalent(
            cylinder,
            .analytic(.cylinder(
                origin: Point3D(x: 1.0, y: 4.0, z: 0.0),
                axis: -Vector3D.unitY,
                radius: 2.0
            )),
            tolerance: tolerance
        ))
        #expect(try resolver.areEquivalent(
            cone,
            .analytic(.cone(
                apex: .origin,
                axis: -Vector3D.unitZ,
                halfAngle: 0.5
            )),
            tolerance: tolerance
        ))
        #expect(try resolver.areEquivalent(
            torus,
            .analytic(.torus(
                center: .origin,
                axis: -Vector3D.unitZ,
                majorRadius: 3.0,
                minorRadius: 0.5
            )),
            tolerance: tolerance
        ))
        #expect(try resolver.areEquivalent(
            sphere,
            .analytic(.sphere(
                center: Point3D(x: 1.0e-3, y: 0.0, z: 0.0),
                radius: 2.0
            )),
            tolerance: tolerance
        ) == false)
        #expect(try resolver.areEquivalent(
            cylinder,
            .analytic(.cylinder(
                origin: Point3D(x: 1.01, y: 0.0, z: 0.0),
                axis: .unitY,
                radius: 2.0
            )),
            tolerance: tolerance
        ) == false)
        #expect(try resolver.areEquivalent(
            cone,
            torus,
            tolerance: tolerance
        ) == false)
    }
}
