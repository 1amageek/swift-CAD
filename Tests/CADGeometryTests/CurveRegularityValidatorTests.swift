import Testing
import CADCore
@testable import CADGeometry

@Suite("Curve regularity certification")
struct CurveRegularityValidatorTests {
    @Test(.timeLimit(.minutes(1)))
    func acceptsRegularAffineEllipse() throws {
        let curve = try affineEllipse(
            transform: AffineTransform3D(
                basisX: Vector3D(x: 0.0, y: -0.2, z: -0.1),
                basisY: .unitY,
                basisZ: .unitZ,
                translation: .zero
            )
        )
        try DefaultCurveRegularityValidator().validate(
            curve,
            over: ScalarInterval(lower: 0.0, upper: 2.0 * .pi),
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAffineEllipseCollapsedToLine() throws {
        let curve = try affineEllipse(
            transform: AffineTransform3D(
                basisX: .zero,
                basisY: .unitY,
                basisZ: .unitZ,
                translation: .zero
            )
        )
        do {
            try DefaultCurveRegularityValidator().validate(
                curve,
                over: ScalarInterval(lower: 0.0, upper: 2.0 * .pi),
                tolerance: .standard
            )
            Issue.record("A collapsed ellipse must not pass curve regularity certification.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
        }
    }

    private func affineEllipse(transform: AffineTransform3D) throws -> Curve3D {
        .affineImage(try AffineImageCurve3D(
            source: .analytic(.ellipse(
                center: Point3D(x: 0.0, y: 0.0, z: 1.0),
                normal: .unitZ,
                majorAxis: .unitX,
                majorRadius: 2.0,
                minorRadius: 1.0
            )),
            transform: transform,
            tolerance: .standard
        ))
    }
}
