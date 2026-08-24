import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel
@testable import CADExchange

@Suite("Exact affine-image exchange")
struct ExactAffineImageExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func stepMaterializesAffineImagesAsExactStandardCurves() throws {
        let fixture = try affineImageSheet()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: fixture.model,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("SWIFTCAD_BSPLINE_TRIM"))

        let imported = try STEPExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try verify(result, against: fixture)
    }

    @Test(.timeLimit(.minutes(1)))
    func igesMaterializesAffineImagesAsExactStandardCurves() throws {
        let fixture = try affineImageSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(
            brep: fixture.model,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("NURBSCRV"))

        let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try verify(result, against: fixture)
    }

    private func verify(
        _ result: BRepModel,
        against fixture: AffineImageFixture
    ) throws {
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.edges.count == fixture.model.edges.count)
        #expect(result.vertices.count == fixture.model.vertices.count)

        let expectedVertices = fixture.model.vertices.values.map(\.point).sorted(by: pointOrder)
        let actualVertices = result.vertices.values.map(\.point).sorted(by: pointOrder)
        for (expected, actual) in zip(expectedVertices, actualVertices) {
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
        }

        let transferred = try #require(result.geometry.curves.values.compactMap { curve -> BSplineCurve3D? in
            guard case let .bSpline(spline) = curve, spline.degree == 2 else {
                return nil
            }
            return spline
        }.first)
        for parameter in stride(from: 0.0, through: 1.0, by: 0.125) {
            let expected = try fixture.curve.point(
                at: parameter,
                tolerance: .standard
            )
            let projection = try Curve3D.bSpline(transferred).parameterProjection(
                of: expected,
                tolerance: .standard
            )
            #expect(projection.residual <= ModelingTolerance.standard.distance)
        }
    }

    private func affineImageSheet() throws -> AffineImageFixture {
        let transform = try AffineTransform3D(
            basisX: Vector3D(x: 1.2, y: 0.3, z: 0.0),
            basisY: Vector3D(x: 0.2, y: 0.8, z: 0.0),
            basisZ: .unitZ,
            translation: Vector3D(x: 0.010, y: -0.020, z: 0.0)
        )
        let knots = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let weights = [1.0, 0.75, 1.0]
        let sourceControlPoints = [
            Point3D(x: 0.040, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.030, z: 0.0),
            Point3D(x: -0.040, y: 0.0, z: 0.0),
        ]
        let sourceSpline = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: sourceControlPoints,
            weights: weights
        )
        let image = Curve3D.affineImage(try AffineImageCurve3D(
            source: .bSpline(sourceSpline),
            transform: transform,
            tolerance: .standard
        ))
        let start = try image.point(at: 0.0, tolerance: .standard)
        let end = try image.point(at: 1.0, tolerance: .standard)
        let parameterControlPoints = sourceControlPoints.map {
            let point = transform.applying(to: $0)
            return Point2D(x: point.x, y: point.y)
        }
        let parameterSpline = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: parameterControlPoints,
            weights: weights
        )

        let sourceStart = try sourceSpline.point(at: 0.0, tolerance: .standard)
        let sourceEnd = try sourceSpline.point(at: 1.0, tolerance: .standard)
        let chordVector = sourceStart - sourceEnd
        let chordLength = chordVector.length
        let chordSource = Curve3D.line(Line3D(
            origin: sourceEnd,
            direction: try chordVector.normalized(tolerance: ModelingTolerance.standard.distance)
        ))
        let chordImage = Curve3D.affineImage(try AffineImageCurve3D(
            source: chordSource,
            transform: transform,
            tolerance: .standard
        ))
        let edges = [
            BRepSewingEdge(
                stableID: "exact:affine-image:curve",
                curve: image,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .bSpline(parameterSpline)
            ),
            BRepSewingEdge(
                stableID: "exact:affine-image:chord",
                curve: chordImage,
                startParameter: 0.0,
                endParameter: chordLength,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .affine(
                    origin: Point2D(x: end.x, y: end.y),
                    direction: Point2D(x: start.x - end.x, y: start.y - end.y),
                    startParameter: 0.0,
                    endParameter: 1.0
                )
            ),
        ]
        let model = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: FeatureID(),
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "exact:affine-image:shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "exact:affine-image:face",
                        surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "exact:affine-image:outer",
                            role: .outer,
                            edges: edges
                        )]
                    )]
                )]
            ),
            tolerance: .standard
        ).brep
        return AffineImageFixture(model: model, curve: image)
    }

    private func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}

private struct AffineImageFixture {
    let model: BRepModel
    let curve: Curve3D
}
