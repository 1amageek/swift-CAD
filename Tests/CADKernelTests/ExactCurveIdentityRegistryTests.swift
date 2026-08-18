import CADCore
import CADGeometry
@testable import CADKernel
import Testing

@Suite("Exact curve identity registry")
struct ExactCurveIdentityRegistryTests {
    @Test(.timeLimit(.minutes(1)))
    func sharesIdentityOnlyForCompleteRepresentationAndParameterizationEquality() {
        let line = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let equalLine = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let coincidentAnalyticLine = Curve3D.analytic(.line(
            origin: .origin,
            direction: .unitX
        ))
        let distinctLine = Curve3D.line(Line3D(
            origin: Point3D(x: 0.0, y: 1.0, z: 0.0),
            direction: .unitX
        ))
        var registry = ExactCurveIdentityRegistry()

        let lineID = registry.identity(for: line)

        #expect(registry.identity(for: equalLine) == lineID)
        #expect(registry.identity(for: coincidentAnalyticLine) != lineID)
        #expect(registry.identity(for: distinctLine) != lineID)
    }
}
