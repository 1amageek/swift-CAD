import Foundation
import Testing
import CADCore
import CADIR
import CADModeling
import CADGeometry
@testable import CADKernel

@Suite("Sketch spline constraint solver")
struct SketchSplineConstraintSolverTests {
    @Test(.timeLimit(.minutes(1)))
    func smoothControlPointMovesOntoTheNeighborTangent() throws {
        let splineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                splineID: .spline(SketchSpline(controlPoints: [
                    point(0.0, 0.0),
                    point(1.0, 0.0),
                    point(2.0, 0.0),
                    point(3.0, 0.5),
                    point(4.0, 0.0),
                    point(5.0, 0.0),
                    point(6.0, 0.0),
                ])),
            ],
            constraints: [
                .fixed(.splineControlPoint(entity: splineID, index: 2)),
                .fixed(.splineControlPoint(entity: splineID, index: 4)),
                .smoothSplineControlPoint(entity: splineID, index: 3),
            ]
        )

        let result = try solve(sketch)
        let points = try splinePoints(splineID, in: result.sketch)

        #expect(result.status == .underConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(abs(cross(points[3] - points[2], points[4] - points[3])) <= 1.0e-8)
        #expect(dot(points[3] - points[2], points[4] - points[3]) > 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func endpointTangentAlignsTheSplineHandleWithTheLine() throws {
        let lineID = SketchEntityID()
        let splineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: point(0.0, 0.0),
                    end: point(1.0, 0.0)
                )),
                splineID: .spline(SketchSpline(controlPoints: [
                    point(0.0, 1.0),
                    point(1.0, 1.5),
                    point(2.0, 1.0),
                    point(3.0, 1.0),
                ])),
            ],
            constraints: [
                .fixed(.entity(lineID)),
                .fixed(.splineControlPoint(entity: splineID, index: 0)),
                .splineEndpointTangent(
                    SketchSplineLineTangencyConstraint(
                        splineEndpoint: SketchSplineEndpointReference(
                            splineID: splineID,
                            endpoint: .start
                        ),
                        line: lineID,
                        orientation: .aligned
                    )
                ),
            ]
        )

        let result = try solve(sketch)
        let line = try linePoints(lineID, in: result.sketch)
        let spline = try splinePoints(splineID, in: result.sketch)

        #expect(result.status == .underConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(abs(cross(line.end - line.start, spline[1] - spline[0])) <= 1.0e-8)
        #expect(dot(line.end - line.start, spline[1] - spline[0]) > 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentEndpointsJoinAndAlignIndependentSplines() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = endpointPairSketch(
            firstID: firstID,
            secondID: secondID,
            constraint: .tangentSplineEndpoints(
                SketchSplineEndpointTangencyConstraint(
                    first: SketchSplineEndpointReference(splineID: firstID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: secondID, endpoint: .start),
                    orientation: .aligned
                )
            )
        )

        let result = try solve(sketch)
        let first = try splinePoints(firstID, in: result.sketch)
        let second = try splinePoints(secondID, in: result.sketch)

        #expect(result.status == .underConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(distance(first[3], second[0]) <= 1.0e-8)
        #expect(abs(cross(first[3] - first[2], second[1] - second[0])) <= 1.0e-8)
        #expect(dot(first[3] - first[2], second[1] - second[0]) > 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func smoothEndpointsJoinWithEqualCurvatureVectors() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .spline(SketchSpline(controlPoints: [
                    point(0.0, 0.0), point(1.0, 1.0), point(2.0, 1.2), point(3.0, 1.0),
                ])),
                secondID: .spline(SketchSpline(controlPoints: [
                    point(3.1, 1.2), point(3.8, 1.3), point(5.0, 0.4), point(6.0, 0.0),
                ])),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .fixed(.splineControlPoint(entity: secondID, index: 3)),
                .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: SketchSplineEndpointReference(splineID: firstID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: secondID, endpoint: .start),
                    orientation: .aligned
                )),
            ]
        )

        let result = try solve(sketch)
        let first = try curve(firstID, in: result.sketch)
        let second = try curve(secondID, in: result.sketch)
        let end = try first.differentialGeometry(at: 1.0, tolerance: .standard)
        let start = try second.differentialGeometry(at: 0.0, tolerance: .standard)

        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(distance(end.position, start.position) <= 1.0e-8)
        #expect(abs(cross(end.firstDerivative, start.firstDerivative)) <= 1.0e-8)
        #expect(dot(end.firstDerivative, start.firstDerivative) > 0.0)
        let endCurvature = curvatureVector(end)
        let startCurvature = curvatureVector(start)
        #expect(length(endCurvature) > 0.1)
        #expect(distance(endCurvature, startCurvature) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func smoothEndpointsHoldAQuinticToACubicWithExplicitKnots() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                // A cubic B-spline with one simple interior knot, not in chain form.
                firstID: .spline(SketchSpline(
                    controlPoints: [point(0.0, 0.0), point(1.0, 1.0), point(2.0, 1.5), point(3.0, 1.2), point(4.0, 1.0)],
                    degree: 3,
                    knots: [0, 0, 0, 0, 0.4, 1, 1, 1, 1]
                )),
                // A quintic in chain form, one span.
                secondID: .spline(SketchSpline(
                    controlPoints: [point(4.2, 1.1), point(4.8, 1.0), point(5.4, 0.7), point(6.0, 0.3), point(6.5, 0.1), point(7.0, 0.0)],
                    degree: 5
                )),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .fixed(.splineControlPoint(entity: secondID, index: 3)),
                .fixed(.splineControlPoint(entity: secondID, index: 4)),
                .fixed(.splineControlPoint(entity: secondID, index: 5)),
                .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: SketchSplineEndpointReference(splineID: firstID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: secondID, endpoint: .start),
                    orientation: .aligned
                )),
            ]
        )

        let result = try solve(sketch)
        guard case let .spline(solvedSecond) = result.sketch.entities[secondID] else {
            Issue.record("The solved sketch must keep the quintic.")
            return
        }
        #expect(solvedSecond.degree == 5 && solvedSecond.knots == nil)
        let first = try curve(firstID, in: result.sketch)
        let second = try curve(secondID, in: result.sketch)
        let end = try first.differentialGeometry(at: 1.0, tolerance: .standard)
        let start = try second.differentialGeometry(at: 0.0, tolerance: .standard)

        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(distance(end.position, start.position) <= 1.0e-8)
        #expect(abs(cross(end.firstDerivative, start.firstDerivative)) <= 1.0e-8)
        #expect(distance(curvatureVector(end), curvatureVector(start)) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func endpointTangentPreservesExplicitOpposedBranch() throws {
        let lineID = SketchEntityID()
        let splineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: point(0.0, 0.0),
                    end: point(1.0, 0.0)
                )),
                splineID: .spline(SketchSpline(controlPoints: [
                    point(0.0, 1.0),
                    point(-1.0, 1.4),
                    point(-2.0, 1.0),
                    point(-3.0, 1.0),
                ])),
            ],
            constraints: [
                .fixed(.entity(lineID)),
                .fixed(.splineControlPoint(entity: splineID, index: 0)),
                .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: SketchSplineEndpointReference(
                        splineID: splineID,
                        endpoint: .start
                    ),
                    line: lineID,
                    orientation: .opposed
                )),
            ]
        )

        let result = try solve(sketch)
        let line = try linePoints(lineID, in: result.sketch)
        let spline = try splinePoints(splineID, in: result.sketch)
        let lineDirection = line.end - line.start
        let splineTangent = spline[1] - spline[0]

        #expect(result.status == .underConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(abs(cross(lineDirection, splineTangent)) <= 1.0e-8)
        #expect(dot(lineDirection, splineTangent) < 0.0)
    }

    private func endpointPairSketch(
        firstID: SketchEntityID,
        secondID: SketchEntityID,
        constraint: SketchConstraint
    ) -> Sketch {
        Sketch(
            plane: .xy,
            entities: [
                firstID: .spline(SketchSpline(controlPoints: [
                    point(0.0, 0.0),
                    point(1.0, 0.0),
                    point(2.0, 0.0),
                    point(3.0, 0.0),
                ])),
                secondID: .spline(SketchSpline(controlPoints: [
                    point(3.0, 0.2),
                    point(3.8, 0.4),
                    point(5.0, 0.0),
                    point(6.0, 0.0),
                ])),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .fixed(.splineControlPoint(entity: secondID, index: 2)),
                .fixed(.splineControlPoint(entity: secondID, index: 3)),
                constraint,
            ]
        )
    }

    private func solve(_ sketch: Sketch) throws -> SketchConstraintSolveResult {
        try LevenbergMarquardtSketchConstraintSolver().solve(
            sketch,
            parameters: ParameterResolver().resolve(ParameterTable()),
            tolerance: .standard
        )
    }

    private func splinePoints(
        _ entityID: SketchEntityID,
        in sketch: Sketch
    ) throws -> [Point2D] {
        guard case let .spline(spline) = sketch.entities[entityID] else {
            throw SketchError.invalidReference("Solved sketch is missing the expected spline.")
        }
        return try spline.controlPoints.map(resolve)
    }

    private func curve(_ entityID: SketchEntityID, in sketch: Sketch) throws -> BSplineCurve2D {
        guard case let .spline(spline) = sketch.entities[entityID], let knots = spline.knotVector else {
            throw SketchError.invalidReference("Solved sketch is missing the expected spline.")
        }
        return BSplineCurve2D(degree: spline.degree, knots: knots, controlPoints: try spline.controlPoints.map(resolve))
    }

    /// The curvature vector (C″ − (C″·T)T)/|C′|², independent of the parameter direction.
    private func curvatureVector(_ geometry: BSplineCurve2D.DifferentialGeometry) -> Point2D {
        let d1 = geometry.firstDerivative, d2 = geometry.secondDerivative
        let speedSquared = dot(d1, d1)
        let along = dot(d2, d1) / speedSquared
        return Point2D(x: (d2.x - along * d1.x) / speedSquared, y: (d2.y - along * d1.y) / speedSquared)
    }

    private func linePoints(
        _ entityID: SketchEntityID,
        in sketch: Sketch
    ) throws -> (start: Point2D, end: Point2D) {
        guard case let .line(line) = sketch.entities[entityID] else {
            throw SketchError.invalidReference("Solved sketch is missing the expected line.")
        }
        return (try resolve(line.start), try resolve(line.end))
    }

    private func resolve(_ point: SketchPoint) throws -> Point2D {
        let parameters = try ParameterResolver().resolve(ParameterTable())
        let resolver = ParameterResolver()
        let x = try resolver.evaluate(point.x, parameters: parameters, variables: [:])
        let y = try resolver.evaluate(point.y, parameters: parameters, variables: [:])
        return Point2D(x: x.value, y: y.value)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }

    private func cross(_ first: Point2D, _ second: Point2D) -> Double {
        first.x * second.y - first.y * second.x
    }

    private func dot(_ first: Point2D, _ second: Point2D) -> Double {
        first.x * second.x + first.y * second.y
    }

    private func distance(_ first: Point2D, _ second: Point2D) -> Double {
        length(first - second)
    }

    private func length(_ point: Point2D) -> Double {
        hypot(point.x, point.y)
    }
}

private extension Point2D {
    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}
