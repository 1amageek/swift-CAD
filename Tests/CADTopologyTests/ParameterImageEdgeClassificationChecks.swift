import CADCore
import CADGeometry
import CADTopology

enum ParameterImageEdgeClassificationChecks {
    enum Failure: Error { case wrongOpenKind, wrongClosedKind }

    static func run() throws {
        let tolerance = ModelingTolerance.standard
        let nativeOpen = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
        let nativeClosed = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .origin])
        let open = Curve3D.parameterImage(try ParameterImageCurve3D(
            source: .bSpline(nativeOpen), gain: -1, offset: 1, tolerance: tolerance))
        let closed = Curve3D.parameterImage(try ParameterImageCurve3D(
            source: .bSpline(nativeClosed), gain: -1, offset: 1, tolerance: tolerance))
        let classifier = BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 8,
            remainingSourceDepth: 8, maximumAlgebraicDepth: 32)
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 8, maximumSubdivisionDepth: 8))
        guard try classifier.kind(curve: open, from: 0, to: 1,
            tolerance: tolerance, using: &execution) == .open else {
            throw Failure.wrongOpenKind
        }
        guard try classifier.kind(curve: closed, from: 0, to: 1,
            tolerance: tolerance, using: &execution) == .closed else {
            throw Failure.wrongClosedKind
        }
    }
}
