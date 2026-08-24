import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact bridge curve feature")
struct BridgeCurveFeatureTests {
    private static let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-9,
        relative: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func resolvesStableFiniteEndpointsForEveryContinuityLevel() throws {
        for level in CurveContinuityLevel.allCases {
            let fixture = makeFixture(level: level)
            let result = try BridgeCurveFeatureEvaluator().evaluate(
                feature: fixture.feature,
                context: fixture.context
            )
            let output = try #require(result.generatedCurves.first)
            guard case let .bSpline(bridge) = output.exactCurve else {
                Issue.record("Bridge evaluation must return exact B-spline geometry.")
                continue
            }
            let expectedDegree: Int
            switch level {
            case .positional:
                expectedDegree = 1
            case .tangent:
                expectedDegree = 3
            case .curvature:
                expectedDegree = 5
            }
            #expect(bridge.degree == expectedDegree)

            let evaluator = CurveContinuityEvaluator(modelingTolerance: Self.tolerance)
            let bridgeCurve = Curve3D.bSpline(bridge)
            let startResult = try evaluator.evaluate(CurveContinuityRequest(
                first: CurveContinuityTarget(curve: fixture.startCurve, parameter: 0.0),
                second: CurveContinuityTarget(curve: bridgeCurve, parameter: 0.0),
                requiredLevel: level,
                tolerances: fixture.continuityTolerances
            ))
            let endResult = try evaluator.evaluate(CurveContinuityRequest(
                first: CurveContinuityTarget(curve: fixture.endCurve, parameter: 0.0),
                second: CurveContinuityTarget(curve: bridgeCurve, parameter: 1.0),
                requiredLevel: level,
                tolerances: fixture.continuityTolerances
            ))
            #expect(startResult.isSatisfied)
            #expect(endResult.isSatisfied)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func usesRetainedTrimDomainEndpointsInsteadOfBaseCurveDefaults() throws {
        let startID = FeatureID()
        let endID = FeatureID()
        let bridgeID = FeatureID()
        let startCurve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let endCurve = Curve3D.line(Line3D(
            origin: Point3D(x: 10.0, y: 0.0, z: 0.0),
            direction: .unitX
        ))
        let feature = makeFeature(
            id: bridgeID,
            startID: startID,
            endID: endID,
            level: .positional
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: [
                startID: [EvaluatedCurve(
                    sourceFeatureID: startID,
                    source: .generatedFeature,
                    kind: .line,
                    points: [
                        Point3D(x: 2.0, y: 0.0, z: 0.0),
                        Point3D(x: 3.0, y: 0.0, z: 0.0),
                    ],
                    exactCurve: startCurve,
                    exactParameterDomain: .closed(2.0, 3.0)
                )],
                endID: [EvaluatedCurve(
                    sourceFeatureID: endID,
                    source: .generatedFeature,
                    kind: .line,
                    points: [
                        Point3D(x: 8.0, y: 0.0, z: 0.0),
                        Point3D(x: 9.0, y: 0.0, z: 0.0),
                    ],
                    exactCurve: endCurve,
                    exactParameterDomain: .closed(-2.0, -1.0)
                )],
            ],
            tolerance: Self.tolerance
        )

        let result = try BridgeCurveFeatureEvaluator().evaluate(feature: feature, context: context)
        let exact = try #require(result.generatedCurves.first?.exactCurve)
        let startPoint = try exact.point(at: 0.0, tolerance: Self.tolerance)
        let endPoint = try exact.point(at: 1.0, tolerance: Self.tolerance)
        #expect(startPoint == Point3D(x: 3.0, y: 0.0, z: 0.0))
        #expect(endPoint == Point3D(x: 8.0, y: 0.0, z: 0.0))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMissingNonExactAndEndpointlessInputsWithTypedDiagnostics() throws {
        let fixture = makeFixture(level: .tangent)
        do {
            _ = try BridgeCurveFeatureEvaluator().evaluate(
                feature: fixture.feature,
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: BRepModel(),
                    profiles: [:],
                    tolerance: Self.tolerance
                )
            )
            Issue.record("A missing bridge source must fail.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == fixture.feature.id)
        }

        let startID = fixture.feature.inputs[0].featureID
        let endID = fixture.feature.inputs[1].featureID
        let nonExact = EvaluatedCurve(
            sourceFeatureID: startID,
            source: .generatedFeature,
            kind: .line,
            points: [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)]
        )
        var nonExactContext = fixture.context
        nonExactContext.curves[startID] = [nonExact]
        do {
            _ = try BridgeCurveFeatureEvaluator().evaluate(
                feature: fixture.feature,
                context: nonExactContext
            )
            Issue.record("A non-exact bridge source must fail.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
        }

        let endpointless = EvaluatedCurve(
            sourceFeatureID: startID,
            source: .generatedFeature,
            kind: .line,
            points: [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)],
            exactCurve: .line(Line3D(origin: .origin, direction: .unitX))
        )
        var endpointlessContext = fixture.context
        endpointlessContext.curves[startID] = [endpointless]
        endpointlessContext.curves[endID] = fixture.context.curves[endID]
        do {
            _ = try BridgeCurveFeatureEvaluator().evaluate(
                feature: fixture.feature,
                context: endpointlessContext
            )
            Issue.record("An unbounded bridge source must fail.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func schemaAndEndpointOptionsAreStrictlyValidated() throws {
        let startID = FeatureID()
        let endID = FeatureID()
        let feature = BridgeCurveFeature(
            start: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: startID),
                end: .end,
                requiredLevel: .tangent
            ),
            end: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: endID),
                end: .start,
                requiredLevel: .tangent
            ),
            continuityTolerances: .standard(modelingTolerance: Self.tolerance)
        )
        let encoded = try JSONEncoder().encode(feature)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var start = try #require(object["start"] as? [String: Any])
        start["parameter"] = 0.0
        object["start"] = start
        let obsoleteSchema = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeCurveFeature.self, from: obsoleteSchema)
        }

        let ignoredDerivative = BridgeCurveEndpointReference(
            curve: CurveOutputReference(featureID: startID),
            end: .end,
            requiredLevel: .positional,
            derivativeMagnitude: 1.0
        )
        #expect(throws: KernelError.self) {
            try ignoredDerivative.validate(tolerance: Self.tolerance)
        }
        let identicalEndpoint = BridgeCurveFeature(
            start: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: startID),
                end: .end,
                requiredLevel: .positional
            ),
            end: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: startID),
                end: .end,
                requiredLevel: .positional
            ),
            continuityTolerances: .standard(modelingTolerance: Self.tolerance)
        )
        #expect(throws: KernelError.self) {
            try identicalEndpoint.validate(tolerance: Self.tolerance)
        }
    }

    private func makeFixture(level: CurveContinuityLevel) -> Fixture {
        let startID = FeatureID()
        let endID = FeatureID()
        let bridgeID = FeatureID()
        let startCurve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let endCurve = Curve3D.line(Line3D(
            origin: Point3D(x: 2.0, y: 1.0, z: 0.0),
            direction: .unitY
        ))
        let tolerances = CurveContinuityTolerances.standard(
            modelingTolerance: Self.tolerance
        )
        return Fixture(
            feature: makeFeature(
                id: bridgeID,
                startID: startID,
                endID: endID,
                level: level,
                tolerances: tolerances
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [
                    startID: [EvaluatedCurve(
                        sourceFeatureID: startID,
                        source: .generatedFeature,
                        kind: .line,
                        points: [Point3D(x: -1.0, y: 0.0, z: 0.0), .origin],
                        exactCurve: startCurve,
                        exactParameterDomain: .closed(-1.0, 0.0)
                    )],
                    endID: [EvaluatedCurve(
                        sourceFeatureID: endID,
                        source: .generatedFeature,
                        kind: .line,
                        points: [
                            Point3D(x: 2.0, y: 1.0, z: 0.0),
                            Point3D(x: 2.0, y: 2.0, z: 0.0),
                        ],
                        exactCurve: endCurve,
                        exactParameterDomain: .closed(0.0, 1.0)
                    )],
                ],
                tolerance: Self.tolerance
            ),
            startCurve: startCurve,
            endCurve: endCurve,
            continuityTolerances: tolerances
        )
    }

    private func makeFeature(
        id: FeatureID,
        startID: FeatureID,
        endID: FeatureID,
        level: CurveContinuityLevel,
        tolerances: CurveContinuityTolerances = .standard(modelingTolerance: Self.tolerance)
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .bridgeCurve(BridgeCurveFeature(
                start: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: startID),
                    end: .end,
                    requiredLevel: level
                ),
                end: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: endID),
                    end: .start,
                    requiredLevel: level
                ),
                continuityTolerances: tolerances
            )),
            inputs: [
                FeatureInput(featureID: startID, role: .curve),
                FeatureInput(featureID: endID, role: .target),
            ],
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    private struct Fixture {
        let feature: FeatureNode
        let context: EvaluationContext
        let startCurve: Curve3D
        let endCurve: Curve3D
        let continuityTolerances: CurveContinuityTolerances
    }
}
