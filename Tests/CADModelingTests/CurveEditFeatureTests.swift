import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact B-spline curve edit")
struct CurveEditFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func appliesEveryEditAtomicallyAndPreservesTrimDomain() throws {
        let sourceID = FeatureID()
        let sourceReference = CurveOutputReference(featureID: sourceID)
        let sourceCurve = editableCurve()
        let source = try evaluatedSource(
            id: sourceID,
            curve: sourceCurve,
            domain: .closed(0.2, 0.8)
        )
        let edits: [CurveEdit] = [
            .setControlPoint(CurveControlPointEdit(
                target: CurveControlPointReference(
                    curve: sourceReference,
                    controlPointIndex: 1
                ),
                point: Point3D(x: 0.25, y: 0.8, z: 0.1)
            )),
            .setKnot(CurveKnotEdit(
                target: CurveKnotReference(curve: sourceReference, knotIndex: 3),
                value: 0.25
            )),
            .setWeight(CurveWeightEdit(
                target: CurveControlPointReference(
                    curve: sourceReference,
                    controlPointIndex: 2
                ),
                value: 0.5
            )),
        ]

        let output = try evaluate(source: source, edits: edits)
        guard case let .bSpline(edited) = output.exactCurve else {
            Issue.record("Curve edit must produce an exact B-spline curve.")
            return
        }

        #expect(edited.controlPoints[1] == Point3D(x: 0.25, y: 0.8, z: 0.1))
        #expect(edited.knots[3] == 0.25)
        #expect(edited.weights[2] == 0.5)
        #expect(output.exactParameterDomain == .closed(0.2, 0.8))
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: try edited.point(at: 0.2, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(try #require(output.points.last).isApproximatelyEqual(
            to: try edited.point(at: 0.8, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(sourceCurve.controlPoints[1] != edited.controlPoints[1])
        #expect(sourceCurve.knots[3] != edited.knots[3])
        #expect(sourceCurve.weights[2] != edited.weights[2])
    }

    @Test(.timeLimit(.minutes(1)))
    func orderedKnotEditsValidateTheFinalAtomicCurve() throws {
        let sourceID = FeatureID()
        let sourceReference = CurveOutputReference(featureID: sourceID)
        let source = try evaluatedSource(id: sourceID, curve: editableCurve(), domain: nil)
        let output = try evaluate(source: source, edits: [
            .setKnot(CurveKnotEdit(
                target: CurveKnotReference(curve: sourceReference, knotIndex: 3),
                value: 0.8
            )),
            .setKnot(CurveKnotEdit(
                target: CurveKnotReference(curve: sourceReference, knotIndex: 4),
                value: 0.9
            )),
        ])

        guard case let .bSpline(edited) = output.exactCurve else {
            Issue.record("Atomic knot edit must preserve exact B-spline geometry.")
            return
        }
        #expect(edited.knots[3] == 0.8)
        #expect(edited.knots[4] == 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidFinalCurveAndMissingEditTargetReturnTypedFailures() throws {
        let sourceID = FeatureID()
        let sourceReference = CurveOutputReference(featureID: sourceID)
        let source = try evaluatedSource(id: sourceID, curve: editableCurve(), domain: nil)

        do {
            _ = try evaluate(source: source, edits: [
                .setKnot(CurveKnotEdit(
                    target: CurveKnotReference(curve: sourceReference, knotIndex: 3),
                    value: 0.95
                )),
            ])
            Issue.record("A non-monotone final knot vector must fail.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }

        do {
            _ = try evaluate(source: source, edits: [
                .setControlPoint(CurveControlPointEdit(
                    target: CurveControlPointReference(
                        curve: sourceReference,
                        controlPointIndex: 99
                    ),
                    point: .origin
                )),
            ])
            Issue.record("A missing control point target must fail.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedEditPayloadUsesStrictCurrentSchema() throws {
        let source = CurveOutputReference(featureID: FeatureID())
        let feature = CurveEditFeature(
            source: source,
            edits: [.setControlPoint(CurveControlPointEdit(
                target: CurveControlPointReference(
                    curve: source,
                    controlPointIndex: 1
                ),
                point: Point3D(x: 1.0, y: 2.0, z: 3.0)
            ))]
        )
        let data = try JSONEncoder().encode(feature)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var edits = try #require(object["edits"] as? [[String: Any]])
        var first = edits[0]
        var controlPoint = try #require(first["controlPoint"] as? [String: Any])
        controlPoint["legacyApproximation"] = [0.0, 0.0, 0.0]
        first["controlPoint"] = controlPoint
        edits[0] = first
        object["edits"] = edits
        let invalid = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CurveEditFeature.self, from: invalid)
        }
    }

    private func evaluate(
        source: EvaluatedCurve,
        edits: [CurveEdit]
    ) throws -> EvaluatedCurve {
        let featureID = FeatureID()
        let sourceReference = CurveOutputReference(featureID: source.sourceFeatureID)
        let feature = FeatureNode(
            id: featureID,
            operation: .curveEdit(CurveEditFeature(
                source: sourceReference,
                edits: edits
            )),
            inputs: [FeatureInput(featureID: source.sourceFeatureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveEditFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [source.sourceFeatureID: [source]],
                tolerance: .standard
            )
        )
        return try #require(result.generatedCurves.first)
    }

    private func evaluatedSource(
        id: FeatureID,
        curve: BSplineCurve3D,
        domain: ParameterDomain?
    ) throws -> EvaluatedCurve {
        let lower: Double
        let upper: Double
        if case let .closed(domainLower, domainUpper) = domain {
            lower = domainLower
            upper = domainUpper
        } else {
            lower = 0.0
            upper = 1.0
        }
        return EvaluatedCurve(
            sourceFeatureID: id,
            source: .generatedFeature,
            kind: .spline,
            points: [
                try curve.point(at: lower, tolerance: .standard),
                try curve.point(at: upper, tolerance: .standard),
            ],
            plane: .xy,
            exactCurve: .bSpline(curve),
            exactParameterDomain: domain
        )
    }

    private func editableCurve() -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 0.3, 0.7, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.2, y: 0.4, z: 0.0),
                Point3D(x: 0.5, y: 0.6, z: 0.0),
                Point3D(x: 0.8, y: 0.4, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 1.0, 0.8, 1.0, 1.0]
        )
    }
}
