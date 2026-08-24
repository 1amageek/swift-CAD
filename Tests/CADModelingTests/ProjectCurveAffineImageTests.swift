import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Project curve affine image")
struct ProjectCurveAffineImageTests {
    @Test(.timeLimit(.minutes(1)))
    func projectsAnalyticEllipseAsRegularExactAffineImage() throws {
        let sourceID = FeatureID()
        let sourceCurve = analyticEllipse()
        let parameters = [0.0, 0.5 * Double.pi, Double.pi, 1.5 * Double.pi, 2.0 * Double.pi]
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .spline,
            points: try parameters.map {
                try sourceCurve.point(at: $0, tolerance: .standard)
            },
            isClosed: true,
            exactCurve: sourceCurve,
            exactParameterDomain: .closed(0.0, 2.0 * .pi),
            exactPointParameters: parameters
        )
        let output = try evaluate(
            sourceID: sourceID,
            source: source,
            planeNormal: .unitX,
            direction: Vector3D(x: 1.0, y: 0.2, z: 0.1)
        )
        guard case let .affineImage(image) = output.exactCurve else {
            Issue.record("A general exact curve projection must retain an affine-image representation.")
            return
        }
        #expect(image.source == sourceCurve)
        for (point, parameter) in zip(output.points, parameters) {
            #expect(abs(point.x) <= 1.0e-12)
            let exact = try image.point(at: parameter, tolerance: .standard)
            #expect(exact.isApproximatelyEqual(to: point, tolerance: 1.0e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAnalyticEllipseProjectionCollapsedToLine() throws {
        let sourceID = FeatureID()
        let sourceCurve = analyticEllipse()
        let parameters = [0.0, 0.5 * Double.pi, Double.pi, 1.5 * Double.pi, 2.0 * Double.pi]
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .spline,
            points: try parameters.map {
                try sourceCurve.point(at: $0, tolerance: .standard)
            },
            isClosed: true,
            exactCurve: sourceCurve,
            exactParameterDomain: .closed(0.0, 2.0 * .pi),
            exactPointParameters: parameters
        )
        do {
            _ = try evaluate(
                sourceID: sourceID,
                source: source,
                planeNormal: .unitX,
                direction: .unitX
            )
            Issue.record("A projected ellipse with a singular tangent must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
        }
    }

    private func evaluate(
        sourceID: FeatureID,
        source: EvaluatedCurve,
        planeNormal: Vector3D,
        direction: Vector3D
    ) throws -> EvaluatedCurve {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .projectCurve(ProjectCurveFeature(
                source: CurveOutputReference(featureID: sourceID),
                planeOrigin: .origin,
                planeNormal: planeNormal,
                direction: direction
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try ProjectCurveFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [sourceID: [source]],
                tolerance: .standard
            )
        )
        return try #require(result.generatedCurves.first)
    }

    private func analyticEllipse() -> Curve3D {
        .analytic(.ellipse(
            center: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
    }
}
