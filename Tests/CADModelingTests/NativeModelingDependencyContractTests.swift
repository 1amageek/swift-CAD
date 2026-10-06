import CADCore
import CADGeometry
import CADIR
@testable import CADTopology
import Testing
@testable import CADModeling

@Suite("Native modeling dependency contracts")
struct NativeModelingDependencyContractTests {
    @Test(.timeLimit(.minutes(1)))
    func projectionRetainsOriginalParameterImageAndNativeLabels() throws {
        let source = try parameterImage()
        let feature = FeatureNode(operation: .projectCurve(ProjectCurveFeature(
            source: CurveOutputReference(featureID: source.sourceFeatureID),
            planeOrigin: .origin, planeNormal: .unitZ)),
            inputs: [FeatureInput(featureID: source.sourceFeatureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)])
        let result = try ProjectCurveFeatureEvaluator().evaluate(feature: feature, context: context(source))
        let output = try #require(result.generatedCurves.first)
        guard case let .affineImage(image) = output.exactCurve else {
            Issue.record("Projection must retain the full original parameter image.")
            return
        }
        #expect(image.source == source.exactCurve)
        #expect(output.exactParameterDomain == source.exactParameterDomain)
        #expect(output.exactPointParameters == source.exactPointParameters)
        for parameter in [0.0, 0.25, 0.5] {
            let point = try image.point(at: parameter, tolerance: .standard)
            #expect(point.isApproximatelyEqual(to: Point3D(x: 2 * parameter, y: 0, z: 0), tolerance: 1e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func extensionDoesNotReplaceParameterImageWithAnUnwrappedLine() throws {
        let source = try parameterImage()
        let feature = FeatureNode(operation: .curveExtend(CurveExtendFeature(
            source: CurveOutputReference(featureID: source.sourceFeatureID), end: .end,
            distance: .constant(.length(0.1, unit: .meter)))),
            inputs: [FeatureInput(featureID: source.sourceFeatureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)])
        do {
            _ = try CurveExtendFeatureEvaluator().evaluate(feature: feature, context: context(source))
            Issue.record("An unfinished native extension must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetDoesNotReplaceOriginalParameterImageWithCandidateGeometry() throws {
        let source = try parameterImage()
        let feature = FeatureNode(operation: .curveOffset(CurveOffsetFeature(
            source: CurveOutputReference(featureID: source.sourceFeatureID),
            distance: .constant(.length(0.1, unit: .meter)), planeNormal: .unitZ)),
            inputs: [FeatureInput(featureID: source.sourceFeatureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)])
        do {
            _ = try CurveOffsetFeatureEvaluator().evaluate(feature: feature, context: context(source))
            Issue.record("An unfinished original offset must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func zeroSubdivisionTrimKeepsOriginalChartAndPropagatesCallerFailure() throws {
        let source = try parameterImage()
        let admission = try GeometryConversionAdmission(maximumSpanCount: 8,
            maximumSubdivisionDepth: 0, remainingSourceDepth: 4,
            consumeWork: { _ in }, consumeStorage: { _ in }, maximumAlgebraicDepth: 0)
        let output = try CurveTrimFeatureEvaluator().trimmedCurve(featureID: FeatureID(),
            source: source, domain: .closed(0.125, 0.375), tolerance: .standard, admission: admission)
        #expect(output.exactCurve == source.exactCurve)
        #expect(output.exactParameterDomain == .closed(0.125, 0.375))
        #expect(output.isClosed == false)
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: Point3D(x: 0.25, y: 0, z: 1), tolerance: 1e-12))
        enum CallerFailure: Error { case exhausted }
        let exhausted = try GeometryConversionAdmission(maximumSpanCount: 8,
            maximumSubdivisionDepth: 0, remainingSourceDepth: 4,
            consumeWork: { _ in throw CallerFailure.exhausted }, consumeStorage: { _ in },
            maximumAlgebraicDepth: 0)
        #expect(throws: CallerFailure.self) {
            try CurveTrimFeatureEvaluator().trimmedCurve(featureID: FeatureID(), source: source,
                domain: .closed(0.125, 0.375), tolerance: .standard, admission: exhausted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func signedAreaAccumulationPreservesOutwardBoundsAndZeroRejection() {
        let cancellation = SurfaceParameterAreaBounds(lower: -2, upper: -1)
            .adding(SurfaceParameterAreaBounds(lower: 1, upper: 3))
        #expect(cancellation.lower < -1)
        #expect(cancellation.upper > 2)
        #expect(cancellation.minimumAbsoluteValue == 0)
        let positive = SurfaceParameterAreaBounds(lower: 1, upper: 2)
            .adding(SurfaceParameterAreaBounds(lower: 1, upper: 3))
        #expect(positive.lower < 2)
        #expect(positive.upper > 5)
        #expect(positive.minimumAbsoluteValue > 0 && positive.minimumAbsoluteValue < 2)
        let negative = SurfaceParameterAreaBounds(lower: -3, upper: -2)
            .adding(SurfaceParameterAreaBounds(lower: -1, upper: -0.5))
        #expect(negative.lower < -4)
        #expect(negative.upper > -2.5)
        #expect(negative.minimumAbsoluteValue > 0 && negative.minimumAbsoluteValue < 2.5)
        #expect(SurfaceParameterAreaBounds.zero.minimumAbsoluteValue == 0)
    }

    private func parameterImage() throws -> EvaluatedCurve {
        let curve = Curve3D.parameterImage(try ParameterImageCurve3D(
            source: .line(Line3D(origin: Point3D(x: 0, y: 0, z: 1), direction: .unitX)),
            gain: 2, tolerance: .standard))
        let parameters = [0.0, 0.25, 0.5]
        return EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .line,
            points: try parameters.map { try curve.point(at: $0, tolerance: .standard) },
            plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 1), normal: .unitZ)), exactCurve: curve, exactParameterDomain: .closed(0, 0.5),
            exactPointParameters: parameters)
    }

    private func context(_ source: EvaluatedCurve) -> EvaluationContext {
        EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(), profiles: [:],
            curves: [source.sourceFeatureID: [source]], tolerance: .standard)
    }
}
