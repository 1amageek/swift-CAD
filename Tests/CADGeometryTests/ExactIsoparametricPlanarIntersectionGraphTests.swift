import CADCore
@testable import CADGeometry
import Testing

@Suite("Exact Isoparametric Planar Intersection Graph")
struct ExactIsoparametricPlanarIntersectionGraphTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func sphereEquatorProducesFourCompleteGraphCellsInBothOrders() throws {
        let plane = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.5, y: -1.5, z: 0.0),
                    Point3D(x: 1.5, y: -1.5, z: 0.0),
                ],
                [
                    Point3D(x: -1.5, y: 1.5, z: 0.0),
                    Point3D(x: 1.5, y: 1.5, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.25], [0.8, 1.0]]
        )
        let sphere = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(.analytic(.sphere(
                center: .origin,
                radius: 1.0
            ))),
            boundedBy: plane,
            periodicSeamOffset: Double.pi * 0.125,
            tolerance: tolerance
        )

        for operands in [(sphere, plane), (plane, sphere)] {
            let candidate = try ExactIsoparametricPlanarIntersectionGraph.certified(
                first: operands.0,
                second: operands.1,
                tolerance: tolerance
            )
            let graph = try #require(candidate)
            #expect(graph.cells.count == 4)
            for cell in graph.cells {
                for fraction in [0.0, 0.5, 1.0] {
                    let parameters = try graph.normalizedParameterPair(
                        in: cell,
                        at: fraction,
                        tolerance: tolerance
                    )
                    let values = parameters.values
                    let firstPoint = try operands.0.point(
                        u: Self.actual(values[0], in: operands.0.uDomain),
                        v: Self.actual(values[1], in: operands.0.vDomain),
                        tolerance: tolerance
                    )
                    let secondPoint = try operands.1.point(
                        u: Self.actual(values[2], in: operands.1.uDomain),
                        v: Self.actual(values[3], in: operands.1.vDomain),
                        tolerance: tolerance
                    )
                    #expect(firstPoint.isApproximatelyEqual(
                        to: secondPoint,
                        tolerance: tolerance.distance
                    ))
                }
            }
        }

        var perturbedSphere = sphere
        perturbedSphere.controlPoints[2][0].z = Double.ulpOfOne
        let perturbedCandidate = try ExactIsoparametricPlanarIntersectionGraph.certified(
            first: perturbedSphere,
            second: plane,
            tolerance: tolerance
        )
        #expect(perturbedCandidate == nil)

        var nonAffinePlane = plane
        nonAffinePlane.controlPoints[1][1].x += 0.125
        let nonAffineCandidate = try ExactIsoparametricPlanarIntersectionGraph.certified(
            first: sphere,
            second: nonAffinePlane,
            tolerance: tolerance
        )
        #expect(nonAffineCandidate == nil)
    }

    private static func actual(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
    }
}
