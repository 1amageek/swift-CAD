import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact curve trim modeling")
struct CurveTrimFeatureEvaluatorTests {
    @Test(.timeLimit(.minutes(1)))
    func trimKeepsExactCircleAndAddsFiniteDomain() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let exactCurve = Curve3D.circle(
            Circle3D(center: .origin, normal: .unitZ, radius: 0.020)
        )
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .circle,
            points: [
                try exactCurve.point(at: 0.0, tolerance: .standard),
                try exactCurve.point(at: .pi, tolerance: .standard),
                try exactCurve.point(at: 2.0 * .pi, tolerance: .standard),
            ],
            isClosed: true,
            plane: .xy,
            exactCurve: exactCurve
        )
        let feature = FeatureNode(
            id: featureID,
            operation: .curveTrim(CurveTrimFeature(
                source: CurveOutputReference(featureID: sourceID),
                domain: .closed(0.0, .pi / 2.0)
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveTrimFeatureEvaluator().evaluate(
            feature: feature,
            context: context(curves: [sourceID: [source]])
        )
        let output = try #require(result.generatedCurves.first)

        guard case .circle = output.exactCurve else {
            Issue.record("Curve trim must retain the exact circle geometry.")
            return
        }
        #expect(output.exactParameterDomain == .closed(0.0, .pi / 2.0))
        #expect(output.kind == .arc)
        #expect(output.isClosed == false)
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: try exactCurve.point(at: 0.0, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(try #require(output.points.last).isApproximatelyEqual(
            to: try exactCurve.point(at: .pi / 2.0, tolerance: .standard),
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func trimPreservesEveryExactCurveRepresentation() throws {
        for testCase in try exactCurveCases() {
            let sourceID = FeatureID()
            let featureID = FeatureID()
            let midpoint = (testCase.lowerBound + testCase.upperBound) * 0.5
            let domain = ParameterDomain.closed(testCase.lowerBound, testCase.upperBound)
            let source = EvaluatedCurve(
                sourceFeatureID: sourceID,
                source: .generatedFeature,
                kind: testCase.kind,
                points: [
                    try testCase.curve.point(at: testCase.lowerBound, tolerance: .standard),
                    try testCase.curve.point(at: midpoint, tolerance: .standard),
                    try testCase.curve.point(at: testCase.upperBound, tolerance: .standard),
                ],
                exactCurve: testCase.curve,
                exactParameterDomain: domain
            )
            let feature = FeatureNode(
                id: featureID,
                operation: .curveTrim(CurveTrimFeature(
                    source: CurveOutputReference(featureID: sourceID),
                    domain: domain
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .curve)],
                outputs: [FeatureOutput(role: .curve)]
            )

            let result: EvaluationResult
            do {
                result = try CurveTrimFeatureEvaluator().evaluate(
                    feature: feature,
                    context: context(curves: [sourceID: [source]])
                )
            } catch {
                Issue.record("Curve trim failed for \(testCase.curve): \(error)")
                continue
            }
            let output = try #require(result.generatedCurves.first)

            #expect(output.exactCurve == testCase.curve)
            #expect(output.exactParameterDomain == domain)
            #expect(try #require(output.points.first).isApproximatelyEqual(
                to: try testCase.curve.point(at: testCase.lowerBound, tolerance: .standard),
                tolerance: 1.0e-10
            ))
            #expect(try #require(output.points.last).isApproximatelyEqual(
                to: try testCase.curve.point(at: testCase.upperBound, tolerance: .standard),
                tolerance: 1.0e-10
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicTrimRejectsMoreThanOneTurn() throws {
        let sourceID = FeatureID()
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .circle,
            points: [
                try curve.point(at: 0.0, tolerance: .standard),
                try curve.point(at: .pi, tolerance: .standard),
                try curve.point(at: 2.0 * .pi, tolerance: .standard),
            ],
            isClosed: true,
            exactCurve: curve
        )
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .curveTrim(CurveTrimFeature(
                source: CurveOutputReference(featureID: sourceID),
                domain: .closed(0.0, 4.0 * .pi)
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )

        do {
            _ = try CurveTrimFeatureEvaluator().evaluate(
                feature: feature,
                context: context(curves: [sourceID: [source]])
            )
            Issue.record("Periodic trim must reject domains longer than one turn.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.featureID == featureID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func requestUsesStrictCurrentSchema() throws {
        let feature = CurveTrimFeature(
            source: CurveOutputReference(featureID: FeatureID()),
            domain: .closed(0.0, 1.0)
        )
        let data = try JSONEncoder().encode(feature)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["legacySampleCount"] = 33
        let invalid = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CurveTrimFeature.self, from: invalid)
        }
    }

    private func context(curves: [FeatureID: [EvaluatedCurve]]) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: curves,
            tolerance: .standard
        )
    }

    private func exactCurveCases() throws -> [ExactCurveCase] {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let planeTorus = try #require(
            CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: torus,
                options: .init(),
                tolerance: .standard
            ).first
        )
        let bSpline = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 0.25, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        let surfaceLift = SurfaceLiftCurve3D(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            parameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.5),
                startParameter: 0.0,
                endParameter: 1.0
            )
        )
        let implicit = try implicitIntersectionCurve()
        return [
            ExactCurveCase(
                curve: .line(Line3D(origin: .origin, direction: .unitX)),
                lowerBound: -0.5,
                upperBound: 0.75,
                kind: .line
            ),
            ExactCurveCase(
                curve: .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0)),
                lowerBound: 0.2,
                upperBound: 1.4,
                kind: .circle
            ),
            ExactCurveCase(
                curve: .analytic(.line(origin: .origin, direction: .unitY)),
                lowerBound: -0.25,
                upperBound: 0.5,
                kind: .line
            ),
            ExactCurveCase(
                curve: .analytic(.circle(center: .origin, normal: .unitZ, radius: 1.5)),
                lowerBound: 0.1,
                upperBound: 1.0,
                kind: .circle
            ),
            ExactCurveCase(
                curve: .analytic(.arc(
                    center: .origin,
                    normal: .unitZ,
                    radius: 1.0,
                    startAngle: 0.0,
                    endAngle: .pi
                )),
                lowerBound: 0.25,
                upperBound: 2.5,
                kind: .arc
            ),
            ExactCurveCase(
                curve: .analytic(.ellipse(
                    center: .origin,
                    normal: .unitZ,
                    majorAxis: .unitX,
                    majorRadius: 2.0,
                    minorRadius: 1.0
                )),
                lowerBound: 0.2,
                upperBound: 2.0,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .analytic(.hyperbola(Hyperbola3D(
                    center: .origin,
                    normal: .unitZ,
                    transverseAxis: .unitX,
                    transverseRadius: 1.0,
                    conjugateRadius: 0.5
                ))),
                lowerBound: -0.4,
                upperBound: 0.6,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .analytic(.parabola(Parabola3D(
                    vertex: .origin,
                    normal: .unitZ,
                    axis: .unitY,
                    focalLength: 0.5
                ))),
                lowerBound: -0.5,
                upperBound: 0.75,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .analytic(.planeTorus(planeTorus)),
                lowerBound: 0.2,
                upperBound: 1.1,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .bSpline(bSpline),
                lowerBound: 0.1,
                upperBound: 0.9,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .implicit(implicit),
                lowerBound: 0.2,
                upperBound: 0.8,
                kind: .spline
            ),
            ExactCurveCase(
                curve: .surfaceLift(surfaceLift),
                lowerBound: 0.2,
                upperBound: 0.8,
                kind: .spline
            ),
        ]
    }

    private func implicitIntersectionCurve() throws -> CertifiedImplicitIntersectionCurve {
        let first = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
        let second = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.5, y: 0.0, z: 0.0),
                    Point3D(x: 0.5, y: 1.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 1.0),
                    Point3D(x: 0.5, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
        func parameters(at value: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(u: value, v: value)
            )
        }
        let lower = 0.1
        let upper = 0.9
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01),
                secondU: try ScalarInterval(lower: lower, upper: upper),
                secondV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01)
            ),
            freeParameter: .secondU,
            direction: .forward,
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: 0.5),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
    }
}

private struct ExactCurveCase {
    let curve: Curve3D
    let lowerBound: Double
    let upperBound: Double
    let kind: EvaluatedCurveKind
}
