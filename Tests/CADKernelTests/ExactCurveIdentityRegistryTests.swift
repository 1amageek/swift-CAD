import CADCore
import CADGeometry
@testable import CADKernel
import Testing

@Suite("Exact curve identity registry")
struct ExactCurveIdentityRegistryTests {
    @Test(.timeLimit(.minutes(1)))
    func sharesIdentityOnlyForCompleteRepresentationAndParameterizationEquality() throws {
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
        var execution = OriginalQueryExecution(budget: try .init(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        var registry = ExactCurveIdentityRegistry()

        let lineID = try registry.identity(for: line, using: &execution)

        #expect(try registry.identity(for: equalLine, using: &execution) == lineID)
        #expect(try registry.identity(for: coincidentAnalyticLine, using: &execution) != lineID)
        #expect(try registry.identity(for: distinctLine, using: &execution) != lineID)
    }
}
