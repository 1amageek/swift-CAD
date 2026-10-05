import CADCore
import Testing
@testable import CADGeometry

@Suite("Original ruled conversion authority", .timeLimit(.minutes(1)))
struct OriginalRuledConversionAuthorityTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func literalOriginalRowsEncloseEveryJetWithDifferentConstantWeights() throws {
        let ruled = quadraticLaw()
        #expect(OriginalPolynomialRuledConversionSource.accepts(ruled))
        let source: any GeometrySurfaceConversionSource = try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: -1, upper: 2), v: try ScalarInterval(lower: 0.2, upper: 0.8))
        let jets = try source.enclosure(over: box, tolerance: tolerance)
        for i in 0...8 {
            for j in 0...8 {
                let u = box.u.lower + box.u.width * Double(i) / 8
                let v = box.v.lower + box.v.width * Double(j) / 8
                let t = (u + 2) / 5
                #expect(jets.position.contains(Point3D(x: t, y: 2 * v, z: t * t + t * v)))
                #expect(jets.tangentU.contains(Vector3D(x: 0.2, y: 0, z: (2 * t + v) / 5)))
                #expect(jets.tangentV.contains(Vector3D(x: 0, y: 2, z: t)))
                #expect(jets.secondDerivativeUU.contains(Vector3D(x: 0, y: 0, z: 2.0 / 25)))
                #expect(jets.secondDerivativeUV.contains(Vector3D(x: 0, y: 0, z: 0.2)))
                #expect(jets.secondDerivativeVV.contains(Vector3D.zero))
            }
        }
    }

    @Test
    func closedOriginalKnotRetainsBothIndependentDerivativeSides() throws {
        let lower = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 1)], weights: [3, 3, 3])
        let upper = BSplineCurve3D(degree: 1, knots: lower.knots,
            controlPoints: [.init(x: 0, y: 2, z: 0), .init(x: 0.5, y: 2, z: 0.5), .init(x: 1, y: 2, z: 2)], weights: [7, 7, 7])
        let ruled = RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))
        #expect(OriginalPolynomialRuledConversionSource.accepts(ruled))
        let source = try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.499, upper: 0.501), v: try ScalarInterval(lower: 0.2, upper: 0.3))
        let jets = try source.enclosure(over: box, tolerance: tolerance)
        #expect(jets.position.contains(Point3D(x: 0.5, y: 0.5, z: 0.125)))
        #expect(jets.tangentU.contains(Vector3D(x: 1, y: 0, z: 0.25)))
        #expect(jets.tangentU.contains(Vector3D(x: 1, y: 0, z: 2.25)))
        #expect(jets.secondDerivativeUV.contains(Vector3D(x: 0, y: 0, z: 1)))
    }

    @Test
    func differentRationalBasisRetainsTheOriginalIndependentBoundaryLaw() throws {
        let lower = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0)], weights: [1, 2])
        let upper = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0, y: 2, z: 0), .init(x: 0.5, y: 2, z: 0), .init(x: 1, y: 2, z: 0)])
        let ruled = RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))
        #expect(!OriginalPolynomialRuledConversionSource.accepts(ruled))
        let source = try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.2, upper: 0.4), v: try ScalarInterval(lower: 0.25, upper: 0.75))
        let jets = try source.enclosure(over: box, tolerance: tolerance)
        for u in [0.2, 0.3, 0.4] {
            for v in [0.25, 0.5, 0.75] {
                let h = 2 * u / (1 + u), first = 2 / ((1 + u) * (1 + u))
                #expect(jets.position.contains(Point3D(x: (1 - v) * h + v * u, y: 2 * v, z: 0)))
                #expect(jets.tangentU.contains(Vector3D(x: (1 - v) * first + v, y: 0, z: 0)))
                #expect(jets.tangentV.contains(Vector3D(x: u - h, y: 2, z: 0)))
                #expect(jets.secondDerivativeUU.contains(Vector3D(x: -(1 - v) * 4 / ((1 + u) * (1 + u) * (1 + u)), y: 0, z: 0)))
                #expect(jets.secondDerivativeUV.contains(Vector3D(x: 1 - first, y: 0, z: 0)))
            }
        }
    }

    @Test
    func legalOriginalRuledPreparationDoesNotInvokeAnAuthoringDegreeBudget() throws {
        // This exact constant law needs no degree-66 replacement tensor.
        let degree = 33, knots = Array(repeating: 0.0, count: 34) + Array(repeating: 1.0, count: 34)
        let lower = BSplineCurve3D(degree: degree, knots: knots, controlPoints: Array(repeating: .origin, count: 34),
            weights: Array(repeating: 3, count: 34))
        let upper = BSplineCurve3D(degree: degree, knots: knots, controlPoints: Array(repeating: Point3D(x: 0, y: 1, z: 0), count: 34),
            weights: Array(repeating: 7, count: 34))
        let ruled = RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))
        let source: any GeometrySurfaceConversionSource = try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.25, upper: 0.75), v: try ScalarInterval(lower: 0.25, upper: 0.75))
        let jets = try source.enclosure(over: box, tolerance: tolerance)
        #expect(jets.position.contains(Point3D(x: 0, y: 0.5, z: 0)))
        #expect(jets.tangentU.contains(Vector3D.zero))
        #expect(jets.tangentV.contains(Vector3D.unitY))
    }

    @Test
    func originalChartAndRetainedValueAreImmutable() throws {
        var ruled = quadraticLaw()
        let original = ruled
        let source = try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        ruled = RuledSurface3D(startBoundary: .analytic(.line(origin: .origin, direction: .unitX)),
            endBoundary: .analytic(.line(origin: .origin, direction: .unitY)))
        #expect(source.surface == .procedural(.ruled(original)))
        #expect(try source.point(u: 0.5, v: 0.5, tolerance: tolerance) == original.point(u: 0.5, v: 0.5, tolerance: tolerance))
        let outside = SurfaceParameterBox(u: try ScalarInterval(lower: -2.1, upper: 0), v: try ScalarInterval(lower: 0, upper: 1))
        do {
            _ = try source.enclosure(over: outside, tolerance: tolerance)
            Issue.record("Original ruled enclosure accepted an outside native chart.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }

    @Test
    func malformedOriginalGeometryFailsBeforePolynomialSelection() throws {
        let invalid = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0)], weights: [1, -1, 1])
        let ruled = RuledSurface3D(startBoundary: .bSpline(invalid), endBoundary: .bSpline(invalid))
        #expect(throws: GeometryError.invalidDistance(-1)) {
            try NativeSurfaceConversionSource(.procedural(.ruled(ruled)), tolerance: tolerance)
        }
    }

    @Test
    func cancelledOriginalPreparationPropagates() async {
        let source = quadraticLaw(), tolerance = tolerance
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try NativeSurfaceConversionSource(.procedural(.ruled(source)), tolerance: tolerance)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled original source preparation published a value.")
        } catch is CancellationError { }
        catch { Issue.record("Original source preparation changed cancellation into another failure.") }
    }

    private func quadraticLaw() -> RuledSurface3D {
        let knots = [-2.0, -2, -2, 3, 3, 3]
        let lower = BSplineCurve3D(degree: 2, knots: knots,
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 1)], weights: [3, 3, 3])
        let upper = BSplineCurve3D(degree: 2, knots: knots,
            controlPoints: [.init(x: 0, y: 2, z: 0), .init(x: 0.5, y: 2, z: 0.5), .init(x: 1, y: 2, z: 2)], weights: [7, 7, 7])
        return .init(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper), uDomain: .closed(-2, 3))
    }
}
