import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Analytic Geometry Integration")
struct AnalyticGeometryIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func canonicalGeometryStoreRoundTripsAnalyticPayloads() throws {
        let curveID = CurveID()
        let surfaceID = SurfaceID()
        let store = GeometryStore(
            curves: [
                curveID: .analytic(.ellipse(
                    center: .origin,
                    normal: .unitZ,
                    majorAxis: .unitX,
                    majorRadius: 4.0,
                    minorRadius: 2.0
                )),
            ],
            surfaces: [
                surfaceID: .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 5.0,
                    minorRadius: 1.0
                )),
            ]
        )

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(GeometryStore.self, from: data)

        #expect(decoded == store)
        try decoded.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveQueryProjectsOntoCanonicalEllipse() throws {
        let featureID = FeatureID()
        let exactCurve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 4.0,
            minorRadius: 2.0
        ))
        let evaluatedCurve = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: [
                Point3D(x: 4.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 2.0, z: 0.0),
                Point3D(x: -4.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: -2.0, z: 0.0),
                Point3D(x: 4.0, y: 0.0, z: 0.0),
            ],
            isClosed: true,
            exactCurve: exactCurve
        )
        let document = makeEvaluatedDocument(curves: [featureID: [evaluatedCurve]])

        let result = try CurveQueryEvaluator(tolerance: .standard).closestPoint(
            to: Point3D(x: 6.0, y: 0.0, z: 0.0),
            on: CurveOutputReference(featureID: featureID, curveIndex: 0),
            in: document
        )

        #expect(result.projectedPoint.isApproximatelyEqual(
            to: Point3D(x: 4.0, y: 0.0, z: 0.0),
            tolerance: 1.0e-9
        ))
        #expect(result.converged)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveQueryResolvesCenterThroughAnAffineImage() throws {
        let featureID = FeatureID()
        let source = Curve3D.analytic(.ellipse(
            center: Point3D(x: 1.0, y: 2.0, z: 3.0),
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 4.0,
            minorRadius: 2.0
        ))
        let transform = try AffineTransform3D(
            basisX: Vector3D(x: 2.0, y: 0.0, z: 0.0),
            basisY: Vector3D(x: 0.0, y: 3.0, z: 0.0),
            basisZ: .unitZ,
            translation: Vector3D(x: -1.0, y: 5.0, z: 7.0)
        )
        let exactCurve = Curve3D.affineImage(try AffineImageCurve3D(
            source: source,
            transform: transform,
            tolerance: .standard
        ))
        let parameters = [0.0, 0.5 * Double.pi, Double.pi, 1.5 * Double.pi, 2.0 * Double.pi]
        let curve = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: try parameters.map { try exactCurve.point(at: $0, tolerance: .standard) },
            isClosed: true,
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, 2.0 * Double.pi),
            exactPointParameters: parameters
        )
        let document = makeEvaluatedDocument(curves: [featureID: [curve]])

        let center = try CurveQueryEvaluator(tolerance: .standard).center(
            CurveCenterReference(curve: CurveOutputReference(featureID: featureID)),
            in: document
        )

        #expect(center.isApproximatelyEqual(
            to: transform.applying(to: Point3D(x: 1.0, y: 2.0, z: 3.0)),
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func curveQueryResolvesBSplineSubobjectsThroughAnAffineImage() throws {
        let featureID = FeatureID()
        let source = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 1.0, y: 2.0, z: 0.0),
                Point3D(x: 3.0, y: 0.0, z: 0.0),
            ]
        )
        let transform = try AffineTransform3D(
            basisX: Vector3D(x: 2.0, y: 0.0, z: 0.0),
            basisY: Vector3D(x: 0.0, y: 0.5, z: 0.0),
            basisZ: .unitZ,
            translation: Vector3D(x: 4.0, y: -3.0, z: 2.0)
        )
        let exactCurve = Curve3D.affineImage(try AffineImageCurve3D(
            source: .bSpline(source),
            transform: transform,
            tolerance: .standard
        ))
        let parameters = [0.0, 0.5, 1.0]
        let curve = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: try parameters.map { try exactCurve.point(at: $0, tolerance: .standard) },
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, 1.0),
            exactPointParameters: parameters
        )
        let document = makeEvaluatedDocument(curves: [featureID: [curve]])
        let reference = CurveOutputReference(featureID: featureID)
        let evaluator = CurveQueryEvaluator(tolerance: .standard)

        let controlPoint = try evaluator.controlPoint(
            CurveControlPointReference(curve: reference, controlPointIndex: 1),
            in: document
        )
        let knot = try evaluator.knot(
            CurveKnotReference(curve: reference, knotIndex: 3),
            in: document
        )
        let span = try evaluator.span(
            CurveSpanReference(curve: reference, spanIndex: 0),
            in: document
        )

        #expect(controlPoint.isApproximatelyEqual(
            to: transform.applying(to: source.controlPoints[1]),
            tolerance: 1.0e-12
        ))
        #expect(knot == 1.0)
        #expect(span.lowerParameter == 0.0)
        #expect(span.upperParameter == 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryProjectsOntoCanonicalSphere() throws {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let faceSubshapeID = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let brep = BRepModel(
            geometry: GeometryStore(surfaces: [surfaceID: sphere]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [])]
        )
        let document = makeEvaluatedDocument(
            brep: brep,
            subshapes: [faceSubshapeID: .face(faceID)]
        )
        let reference = SurfaceReference(subshape: StableSubshapeReference(
            subshapeID: faceSubshapeID,
            geometrySignature: .untrimmedFace(surface: sphere)
        ))
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

        let closest = try evaluator.closestPoint(
            to: Point3D(x: 4.0, y: 0.0, z: 0.0),
            on: reference,
            in: document
        )
        let directional = try evaluator.project(
            Point3D(x: 4.0, y: 0.0, z: 0.0),
            along: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            onto: reference,
            in: document
        )

        let expected = Point3D(x: 2.0, y: 0.0, z: 0.0)
        #expect(closest.projectedPoint.isApproximatelyEqual(to: expected, tolerance: 1.0e-9))
        #expect(directional.projectedPoint.isApproximatelyEqual(to: expected, tolerance: 1.0e-9))
        #expect(abs(directional.signedDistanceAlongDirection - 2.0) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryProjectsOntoCanonicalTorusWithQuarticIntersection() throws {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let faceSubshapeID = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 5.0,
            minorRadius: 1.0
        ))
        let brep = BRepModel(
            geometry: GeometryStore(surfaces: [surfaceID: torus]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [])]
        )
        let document = makeEvaluatedDocument(
            brep: brep,
            subshapes: [faceSubshapeID: .face(faceID)]
        )

        let result = try SurfaceQueryEvaluator(tolerance: .standard).project(
            Point3D(x: 8.0, y: 0.0, z: 0.0),
            along: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            onto: SurfaceReference(subshape: StableSubshapeReference(
                subshapeID: faceSubshapeID,
                geometrySignature: .untrimmedFace(surface: torus)
            )),
            in: document
        )

        #expect(result.projectedPoint.isApproximatelyEqual(
            to: Point3D(x: 6.0, y: 0.0, z: 0.0),
            tolerance: 1.0e-8
        ))
        #expect(abs(result.signedDistanceAlongDirection - 2.0) <= 1.0e-8)
        #expect(result.lineDistance <= 1.0e-8)
    }

    private func makeEvaluatedDocument(
        brep: BRepModel = BRepModel(),
        curves: [FeatureID: [EvaluatedCurve]] = [:],
        subshapes: [SubshapeID: TopologyReference] = [:]
    ) -> EvaluatedDocument {
        EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: [:],
            curves: curves,
            caches: DocumentCaches(),
            subshapes: SubshapeIndex(subshapes),
            configuration: DocumentEvaluationConfiguration(
                tolerance: .standard,
                tessellationOptions: .standard
            )
        )
    }
}
