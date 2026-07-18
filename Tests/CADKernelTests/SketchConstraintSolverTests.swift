import Foundation
import Testing
import CADCore
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Sketch constraint solver")
struct SketchConstraintSolverTests {
    @Test(.timeLimit(.minutes(1)))
    func solvesCoupledFixedHorizontalDistanceSystem() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: point(0.0, 0.0),
                    end: point(0.8, 0.2)
                )),
            ],
            constraints: [
                .fixed(.lineStart(lineID)),
                .horizontal(lineID),
            ],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(1.0, unit: .meter))
                ),
            ]
        )

        let result = try solver().solve(
            sketch,
            parameters: resolvedParameters(),
            tolerance: .standard
        )

        #expect(result.status == .fullyConstrained)
        #expect(result.remainingDegreesOfFreedom == 0)
        #expect(result.maximumNormalizedResidual <= 1.0)
        let line = try solvedLine(lineID, in: result.sketch)
        #expect(abs(try value(line.start.x)) <= ModelingTolerance.standard.distance)
        #expect(abs(try value(line.start.y)) <= ModelingTolerance.standard.distance)
        #expect(abs(try value(line.end.x) - 1.0) <= 1.0e-6)
        #expect(abs(try value(line.end.y)) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func reportsUnderConstrainedDegreesOfFreedom() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.2)))],
            constraints: [.horizontal(lineID)]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .underConstrained)
        #expect(result.remainingDegreesOfFreedom == 3)
        #expect(result.redundantEquationCount == 0)
        #expect(result.maximumNormalizedResidual <= 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func reportsConsistentRedundantEquationsAsOverConstrained() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.2)))],
            constraints: [.horizontal(lineID), .horizontal(lineID)]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .overConstrained)
        #expect(result.redundantEquationCount == 1)
        #expect(result.maximumNormalizedResidual <= 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func reportsConflictingFixedGeometryAndDimension() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.0)))],
            constraints: [.fixed(.entity(lineID))],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(2.0, unit: .meter))
                ),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .conflicting)
        #expect(result.maximumNormalizedResidual > 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesConcentricEqualRadiusCircles() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .circle(SketchCircle(center: point(0.0, 0.0), radius: length(1.0))),
                secondID: .circle(SketchCircle(center: point(0.2, -0.3), radius: length(0.6))),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .concentric(firstID, secondID),
                .equalRadius(firstID, secondID),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .fullyConstrained)
        guard case let .circle(second) = result.sketch.entities[secondID] else {
            Issue.record("Expected the second entity to remain a circle.")
            return
        }
        #expect(abs(try value(second.center.x)) <= 1.0e-6)
        #expect(abs(try value(second.center.y)) <= 1.0e-6)
        #expect(abs(try value(second.radius) - 1.0) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesCoincidentPerpendicularEqualLengthLines() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.0))),
                secondID: .line(SketchLine(start: point(0.8, 0.2), end: point(1.1, 0.9))),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .coincident(.lineEnd(firstID), .lineStart(secondID)),
                .perpendicular(firstID, secondID),
                .equalLength(firstID, secondID),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .fullyConstrained)
        let second = try solvedLine(secondID, in: result.sketch)
        #expect(abs(try value(second.start.x) - 1.0) <= 1.0e-6)
        #expect(abs(try value(second.start.y)) <= 1.0e-6)
        #expect(abs(try value(second.end.x) - 1.0) <= 1.0e-6)
        #expect(abs(try value(second.end.y) - 1.0) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveExtractionConsumesSolvedConstraintGeometry() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(0.8, 0.2)))],
            constraints: [.fixed(.lineStart(lineID)), .horizontal(lineID)],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(1.0, unit: .meter))
                ),
            ]
        )

        let curves = try SketchCurveExtractor(tolerance: .standard).extractCurves(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: resolvedParameters()
        )

        let curve = try #require(curves.first)
        #expect(curve.points.first?.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 0.0, z: 0.0),
            tolerance: 1.0e-6
        ) == true)
        #expect(curve.points.last?.isApproximatelyEqual(
            to: Point3D(x: 1.0, y: 0.0, z: 0.0),
            tolerance: 1.0e-6
        ) == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveExtractionRejectsConflictingConstraintsWithTypedError() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.0)))],
            constraints: [.fixed(.entity(lineID))],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(2.0, unit: .meter))
                ),
            ]
        )

        do {
            _ = try SketchCurveExtractor(tolerance: .standard).extractCurves(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: resolvedParameters()
            )
            Issue.record("Conflicting sketch constraints must reject curve extraction.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .conflictingConstraints)
            #expect(error.residual.map { $0 > 1.0 } == true)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesVerticalLineWithAngleAndLengthDimensions() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [lineID: .line(SketchLine(start: point(0.0, 0.0), end: point(0.4, 0.8)))],
            constraints: [.fixed(.lineStart(lineID)), .vertical(lineID)],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: length(2.0)
                ),
                .angle(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.angle(90.0, unit: .degree))
                ),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .overConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        let line = try solvedLine(lineID, in: result.sketch)
        #expect(abs(try value(line.end.x)) <= 1.0e-6)
        #expect(abs(try value(line.end.y) - 2.0) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesCoincidentParallelEqualLengthLines() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .line(SketchLine(start: point(0.0, 0.0), end: point(1.0, 0.0))),
                secondID: .line(SketchLine(start: point(0.7, 0.2), end: point(1.6, 0.3))),
            ],
            constraints: [
                .fixed(.entity(firstID)),
                .coincident(.lineEnd(firstID), .lineStart(secondID)),
                .parallel(firstID, secondID),
                .equalLength(firstID, secondID),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .fullyConstrained)
        let second = try solvedLine(secondID, in: result.sketch)
        #expect(abs(try value(second.start.x) - 1.0) <= 1.0e-6)
        #expect(abs(try value(second.start.y)) <= 1.0e-6)
        #expect(abs(try value(second.end.x) - 2.0) <= 1.0e-6)
        #expect(abs(try value(second.end.y)) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesTangentCircleWithDiameterDimension() throws {
        let lineID = SketchEntityID()
        let anchorID = SketchEntityID()
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(start: point(-2.0, 0.0), end: point(2.0, 0.0))),
                anchorID: .point(point(0.0, 1.0)),
                circleID: .circle(SketchCircle(center: point(0.2, 0.7), radius: length(0.4))),
            ],
            constraints: [
                .fixed(.entity(lineID)),
                .fixed(.entity(anchorID)),
                .coincident(.circleCenter(circleID), .entity(anchorID)),
                .tangent(lineID, circleID),
            ],
            dimensions: [.diameter(entity: circleID, value: length(2.0))]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .overConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        guard case let .circle(circle) = result.sketch.entities[circleID] else {
            Issue.record("Expected the solved entity to remain a circle.")
            return
        }
        #expect(abs(try value(circle.center.x)) <= 1.0e-6)
        #expect(abs(try value(circle.center.y) - 1.0) <= 1.0e-6)
        #expect(abs(try value(circle.radius) - 1.0) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func solvesArcRadiusSpanWhileHoldingDerivedEndpoint() throws {
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                arcID: .arc(SketchArc(
                    center: point(0.0, 0.0),
                    radius: length(1.0),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(0.5, unit: .radian))
                )),
            ],
            constraints: [.fixed(.arcStart(arcID))],
            dimensions: [
                .radius(entity: arcID, value: length(2.0)),
                .angle(
                    from: .arcStart(arcID),
                    to: .arcEnd(arcID),
                    value: .constant(.angle(90.0, unit: .degree))
                ),
            ]
        )

        let result = try solver().solve(sketch, parameters: resolvedParameters(), tolerance: .standard)

        #expect(result.status == .underConstrained)
        #expect(result.maximumNormalizedResidual <= 1.0)
        #expect(try SketchDimensionEvaluator().evaluate(result.sketch, tolerance: .standard).isSatisfied(tolerance: .standard))
        guard case let .arc(arc) = result.sketch.entities[arcID] else {
            Issue.record("Expected the solved entity to remain an arc.")
            return
        }
        let centerX = try value(arc.center.x)
        let centerY = try value(arc.center.y)
        let radius = try value(arc.radius)
        let startAngle = try value(arc.startAngle)
        #expect(abs(centerX + radius * cos(startAngle) - 1.0) <= 1.0e-6)
        #expect(abs(centerY + radius * sin(startAngle)) <= 1.0e-6)
    }
}

private func solver() -> LevenbergMarquardtSketchConstraintSolver {
    LevenbergMarquardtSketchConstraintSolver()
}

private func resolvedParameters() throws -> ResolvedParameterTable {
    try ParameterResolver().resolve(ParameterTable())
}

private func point(_ x: Double, _ y: Double) -> SketchPoint {
    SketchPoint(x: length(x), y: length(y))
}

private func length(_ value: Double) -> CADExpression {
    .constant(.length(value, unit: .meter))
}

private func value(_ expression: CADExpression) throws -> Double {
    try ParameterResolver().evaluate(
        expression,
        parameters: resolvedParameters(),
        variables: [:]
    ).value
}

private func solvedLine(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchLine {
    guard case let .line(line) = sketch.entities[entityID] else {
        throw SketchError.invalidReference("Solved sketch is missing the expected line.")
    }
    return line
}
