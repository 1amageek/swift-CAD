import CADCore
import CADGeometry
import Testing

@Suite("Rational surface point interpolation", .timeLimit(.minutes(1)))
struct SurfaceFittingPointInterpolationTests {
    typealias Constraint = SurfaceFittingPointInterpolator.Constraint
    let tolerance = ModelingTolerance.standard

    private var template: BSplineSurface3D {
        .cubicBezierPatch(bottomLeft: .origin, bottomRight: Point3D(x: 2, y: 0, z: 0),
            topRight: Point3D(x: 2, y: 3, z: 0), topLeft: Point3D(x: 0, y: 3, z: 0))
    }

    private func fit(_ source: BSplineSurface3D, _ constraints: [Constraint],
                     fairness: Double = 1, budget: Int = 10_000) throws -> BSplineSurface3D {
        try SurfaceFittingPointInterpolator.interpolate(template: source, constraints: constraints,
            referenceWeight: 1, controlNetFairnessWeight: fairness, positionTolerance: 1e-9,
            relativeRankTolerance: 1e-12, maximumElements: budget, tolerance: tolerance)
    }

    @Test(arguments: [0.0, 1.0, 100_000_000.0])
    func offGridPointsAreInterpolatedRegardlessOfFairness(fairness: Double) throws {
        let source = template
        let constraints = [
            Constraint(u: 0, v: 0, point: .origin),
            Constraint(u: 1, v: 0, point: Point3D(x: 2, y: 0, z: 0)),
            Constraint(u: 1, v: 1, point: Point3D(x: 2, y: 3, z: 0)),
            Constraint(u: 0, v: 1, point: Point3D(x: 0, y: 3, z: 0)),
            Constraint(u: 0.27, v: 0.61, point: Point3D(x: 0.54, y: 1.83, z: 0.7)),
            Constraint(u: 0.73, v: 0.38, point: Point3D(x: 1.46, y: 1.14, z: -0.2)),
        ]
        let result = try fit(source, constraints, fairness: fairness)
        #expect(source == template)
        #expect(result.uKnots == source.uKnots && result.vKnots == source.vKnots)
        #expect(result.weights == source.weights)
        #expect(result.controlPoints != source.controlPoints)
        for constraint in constraints {
            let point = try result.point(u: constraint.u, v: constraint.v, tolerance: tolerance)
            #expect((point - constraint.point).length < 1e-9)
        }
    }

    @Test func rationalWeightsAndNonUnitDomainsArePreserved() throws {
        var source = template
        source.uKnots = source.uKnots.map { 2 + $0 * 3 }
        source.vKnots = source.vKnots.map { -4 + $0 * 2 }
        for v in source.weights.indices {
            for u in source.weights[v].indices { source.weights[v][u] = 0.7 + Double((u + v) % 3) * 0.4 }
        }
        let uv = [(2.0, -4.0), (5.0, -2.0), (2.81, -2.78), (4.19, -3.24)]
        let constraints = try uv.map { u, v in
            Constraint(u: u, v: v, point: try source.point(u: u, v: v, tolerance: tolerance)
                + Vector3D(x: 0.1, y: -0.2, z: 0.5))
        }
        let result = try fit(source, constraints)
        #expect(result.weights == source.weights)
        #expect(result.uKnots == source.uKnots && result.vKnots == source.vKnots)
        for constraint in constraints {
            #expect((try result.point(u: constraint.u, v: constraint.v, tolerance: tolerance)
                - constraint.point).length < 1e-9)
        }
    }

    @Test func fairnessChangesTheFreeControlNetWithoutRelaxingThePoint() throws {
        let point = Constraint(u: 0.27, v: 0.61, point: Point3D(x: 0.54, y: 1.83, z: 0.7))
        let weak = try fit(template, [point], fairness: 0)
        let strong = try fit(template, [point], fairness: 100)
        func energy(_ surface: BSplineSurface3D) -> Double {
            var result = 0.0
            for v in 0..<surface.vControlPointCount {
                for u in 0..<(surface.uControlPointCount - 2) {
                    let a = surface.controlPoints[v][u + 2] - surface.controlPoints[v][u + 1]
                    let b = surface.controlPoints[v][u + 1] - surface.controlPoints[v][u]
                    result += (a - b).dot(a - b)
                }
            }
            for v in 0..<(surface.vControlPointCount - 2) {
                for u in 0..<surface.uControlPointCount {
                    let a = surface.controlPoints[v + 2][u] - surface.controlPoints[v + 1][u]
                    let b = surface.controlPoints[v + 1][u] - surface.controlPoints[v][u]
                    result += (a - b).dot(a - b)
                }
            }
            return result
        }
        #expect(energy(strong) < energy(weak) * 0.99)
        for surface in [weak, strong] {
            #expect((try surface.point(u: point.u, v: point.v, tolerance: tolerance) - point.point).length < 1e-9)
        }
    }

    @Test func redundantConstraintsAgreeAndContradictionsFail() throws {
        let first = Constraint(u: 0.4, v: 0.6, point: Point3D(x: 0.8, y: 1.8, z: 1))
        let result = try fit(template, [first, first])
        #expect((try result.point(u: first.u, v: first.v, tolerance: tolerance) - first.point).length < 1e-9)
        let conflict = Constraint(u: first.u, v: first.v, point: first.point + Vector3D(x: 0, y: 0, z: 1))
        #expect(throws: KernelError.self) { try fit(template, [first, conflict]) }
    }

    @Test func invalidDomainsWeightsAndBudgetsFailBeforeReturningASurface() throws {
        let valid = Constraint(u: 0.5, v: 0.5, point: Point3D(x: 1, y: 1.5, z: 1))
        #expect(throws: KernelError.self) { try fit(template, []) }
        #expect(throws: KernelError.self) { try fit(template, [valid], budget: 100) }
        #expect(throws: KernelError.self) { try fit(template, [valid], fairness: -1) }
        #expect(throws: KernelError.self) {
            try fit(template, [Constraint(u: -1e-12, v: 0.5, point: .origin)])
        }
        #expect(throws: KernelError.self) {
            try fit(template, [Constraint(u: .nan, v: 0.5, point: .origin)])
        }
        var malformed = template
        malformed.uDegree = Int.max
        #expect(throws: KernelError.self) { try fit(malformed, [valid]) }
        malformed = template
        malformed.weights[1][1] = 0
        #expect(throws: (any Error).self) { try fit(malformed, [valid]) }
    }
}
