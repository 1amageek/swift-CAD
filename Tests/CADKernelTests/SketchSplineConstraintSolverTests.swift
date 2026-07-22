import Foundation
import Testing
import CADCore
import CADIR
import CADModeling
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
    func smoothEndpointsJoinWithEqualAlignedHandles() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = endpointPairSketch(
            firstID: firstID,
            secondID: secondID,
            constraint: .smoothSplineEndpoints(
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
        let firstHandle = first[3] - first[2]
        let secondHandle = second[1] - second[0]

        #expect(result.status == .fullyConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(distance(first[3], second[0]) <= 1.0e-8)
        #expect(abs(cross(firstHandle, secondHandle)) <= 1.0e-8)
        #expect(dot(firstHandle, secondHandle) > 0.0)
        #expect(abs(length(firstHandle) - length(secondHandle)) <= 1.0e-8)
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
