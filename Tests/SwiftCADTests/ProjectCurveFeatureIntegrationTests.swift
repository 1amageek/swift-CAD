import Foundation
import Testing
@testable import SwiftCAD

@Suite("Project curve feature integration")
struct ProjectCurveFeatureIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func projectsLineOntoPlaneAlongTiltedDirection() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(
                from: SketchPoint(
                    x: .constant(.length(10.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                ),
                to: SketchPoint(
                    x: .constant(.length(30.0, unit: .millimeter)),
                    y: .constant(.length(20.0, unit: .millimeter))
                )
            )
        }
        let projectID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitZ,
            direction: Vector3D(x: 0.2, y: 0.0, z: 1.0)
        )
        let document = try builder.build(name: "Project line")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let output = try #require(evaluated.curves[projectID]?.first)

        // The zx sketch maps (x, y) to world (y, 0, x), so the source spans
        // (0, 0, 0.01) to (0.02, 0, 0.03); projecting along (0.2, 0, 1) onto
        // z = 0 yields P(x, y, z) = (x - 0.2 z, y, 0) in closed form.
        let expectedStart = Point3D(x: -0.002, y: 0.0, z: 0.0)
        let expectedEnd = Point3D(x: 0.014, y: 0.0, z: 0.0)
        let start = try #require(output.points.first)
        let end = try #require(output.points.last)
        #expect((start - expectedStart).length <= 1.0e-9)
        #expect((end - expectedEnd).length <= 1.0e-9)
        guard case let .line(line) = output.exactCurve else {
            Issue.record("Line projection must preserve an exact line representation.")
            return
        }
        #expect((line.origin - expectedStart).length <= 1.0e-9)
        guard case let .closed(lower, upper) = try #require(output.exactParameterDomain) else {
            Issue.record("Line projection must recompute a finite arc-length domain.")
            return
        }
        #expect(lower == 0.0)
        #expect(abs(upper - 0.016) <= 1.0e-9)
        #expect((line.origin + line.direction * upper - expectedEnd).length <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func projectsCircleOffItsAxisAsExactRationalBSpline() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.circle(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                ),
                radius: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let featureID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitX,
            direction: Vector3D(x: 1.0, y: 0.5, z: 0.25)
        )
        let document = try builder.build(name: "Project circle off axis")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let output = try #require(evaluated.curves[featureID]?.first)

        guard case let .bSpline(curve) = output.exactCurve else {
            Issue.record("An obliquely projected circle must use an exact rational B-spline.")
            return
        }
        #expect(curve.degree == 2)
        #expect(curve.isRational)
        #expect(output.isClosed)
        for point in output.points {
            #expect(abs(point.x) <= 1.0e-12)
            let projection = try Curve3D.bSpline(curve).parameterProjection(
                of: point,
                tolerance: .standard
            )
            #expect(projection.residual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func projectsCircularArcOffItsAxisWithoutLosingEndpoints() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.arc(
                center: point(0.0, 0.0),
                radius: .constant(.length(20.0, unit: .millimeter)),
                startAngle: .constant(.angle(20.0, unit: .degree)),
                endAngle: .constant(.angle(220.0, unit: .degree))
            )
        }
        let featureID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitX,
            direction: Vector3D(x: 1.0, y: 0.5, z: 0.25)
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(
            builder.build(name: "Project circular arc off axis")
        )
        let output = try #require(evaluated.curves[featureID]?.first)
        let exactCurve = try #require(output.exactCurve)
        guard case let .closed(lower, upper) = output.parameterDomain else {
            Issue.record("Projected arc must have a finite exact parameter domain.")
            return
        }
        let first = try #require(output.points.first)
        let last = try #require(output.points.last)
        #expect(try exactCurve.point(at: lower, tolerance: .standard)
            .isApproximatelyEqual(to: first, tolerance: 1.0e-12))
        #expect(try exactCurve.point(at: upper, tolerance: .standard)
            .isApproximatelyEqual(to: last, tolerance: 1.0e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsCircleProjectionThatCollapsesToLine() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.circle(
                center: point(0.0, 0.0),
                radius: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let featureID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitX,
            direction: .unitX
        )

        do {
            _ = try CADPipeline(tolerance: .standard).evaluate(
                builder.build(name: "Degenerate circle projection")
            )
            Issue.record("A circle projection that collapses to a line must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
            #expect(error.featureID == featureID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func projectsBSplineByAffineControlPointTransformation() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.spline(SketchSpline(controlPoints: [
                point(-30.0, 0.0),
                point(-10.0, 20.0),
                point(10.0, -20.0),
                point(30.0, 0.0),
            ]))
        }
        let featureID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitX,
            direction: Vector3D(x: 1.0, y: 0.5, z: 0.25)
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(
            builder.build(name: "Project B-spline")
        )
        let sourceCurve = try #require(evaluated.curves[source.featureID]?.first)
        let output = try #require(evaluated.curves[featureID]?.first)
        guard case let .bSpline(sourceSpline) = sourceCurve.exactCurve,
              case let .bSpline(projectedSpline) = output.exactCurve else {
            Issue.record("B-spline projection must preserve the exact B-spline representation.")
            return
        }
        #expect(projectedSpline.degree == sourceSpline.degree)
        #expect(projectedSpline.knots == sourceSpline.knots)
        #expect(projectedSpline.weights == sourceSpline.weights)
        #expect(projectedSpline.controlPoints.count == sourceSpline.controlPoints.count)
        for point in projectedSpline.controlPoints {
            #expect(abs(point.x) <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripPreservesProjectCurveOperation() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(
                from: SketchPoint(
                    x: .constant(.length(10.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                ),
                to: SketchPoint(
                    x: .constant(.length(30.0, unit: .millimeter)),
                    y: .constant(.length(20.0, unit: .millimeter))
                )
            )
        }
        let projectID = try builder.projectCurve(
            CurveOutputReference(featureID: source.featureID),
            planeOrigin: .origin,
            planeNormal: .unitZ,
            direction: Vector3D(x: 0.2, y: 0.0, z: 1.0)
        )
        let document = try builder.build(name: "Project curve parity")
        let pipeline = CADPipeline(tolerance: .standard)
        _ = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        guard case let .projectCurve(loadedFeature) = loaded.designGraph.nodes[projectID]?.operation else {
            Issue.record("Native package persistence must preserve the shared projectCurve operation.")
            return
        }
        #expect(loadedFeature.source == CurveOutputReference(featureID: source.featureID))
        #expect(loadedFeature.planeOrigin == .origin)
        #expect(loadedFeature.planeNormal == .unitZ)
        #expect(loadedFeature.direction == Vector3D(x: 0.2, y: 0.0, z: 1.0))
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
}
