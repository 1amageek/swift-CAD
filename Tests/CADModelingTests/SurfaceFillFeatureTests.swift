import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Source-boundary surface fill")
struct SurfaceFillFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsSingleFaceOuterPerimeterInsteadOfCreatingCoincidentDuplicate() throws {
        let sourceID = FeatureID()
        let sourceFeature = FeatureNode(
            id: sourceID,
            name: "Source sheet",
            operation: .bSplineSurface(BSplineSurfaceFeature(
                surface: BSplineSurface3D.cubicBezierPatch(
                    bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
                    bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    topRight: Point3D(x: 2.0, y: 1.0, z: 0.5),
                    topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
                )
            )),
            outputs: [FeatureOutput(role: .sheet)]
        )
        let source = try BSplineSurfaceFeatureEvaluator().evaluate(
            feature: sourceFeature,
            context: emptyContext()
        )
        let seed = try #require(source.subshapes.first { _, reference in
            if case .edge = reference { return true }
            return false
        })
        let stableSeed = StableSubshapeReference(
            subshapeID: seed.key,
            geometrySignature: try SubshapeGeometrySignatureBuilder(
                model: source.brep,
                tolerance: .standard
            ).signature(for: seed.value)
        )
        let fillID = FeatureID()
        let fill = FeatureNode(
            id: fillID,
            name: "Boundary fill",
            operation: .surfaceFill(SurfaceFillFeature(
                targetFeatureID: sourceID,
                boundarySeed: stableSeed
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: source.brep,
            profiles: [:],
            subshapes: SubshapeIndex(source.subshapes),
            lineage: source.lineage,
            tolerance: .standard
        )

        do {
            _ = try SurfaceFillFeatureEvaluator(sewer: UnusedSurfaceFillSewer())
                .evaluate(feature: fill, context: context)
            Issue.record("A single-face sheet's outer perimeter must not create an overlapping duplicate surface.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == fillID)
            #expect(error.tolerance == .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partitionsThreeEdgeBoundaryByCertifiedPerimeterWithoutChangingItsGeometry() throws {
        let points = [
            Point3D(x: 0, y: 0, z: 0),
            Point3D(x: 4, y: 0, z: 0),
            Point3D(x: 4, y: 3, z: 0),
            Point3D(x: 0, y: 0, z: 0),
        ]
        let curves = (0..<3).map { index in
            BSplineCurve3D(
                degree: 1,
                knots: [0, 0, 1, 1],
                controlPoints: [points[index], points[index + 1]]
            )
        }
        let evaluator = SurfaceFillFeatureEvaluator(sewer: UnusedSurfaceFillSewer())
        let sides = try evaluator.fourSides(from: curves, tolerance: .standard)
        #expect(sides.count == 4)

        let sideEnds = try sides.map { curve in
            guard case let .closed(lower, upper) = curve.domain else {
                Issue.record("Every partitioned boundary side must be bounded.")
                return (Point3D.origin, Point3D.origin)
            }
            return (
                try curve.point(at: lower, tolerance: .standard),
                try curve.point(at: upper, tolerance: .standard)
            )
        }
        for index in sides.indices {
            #expect((sideEnds[index].1 - sideEnds[(index + 1) % sides.count].0).length <= ModelingTolerance.standard.distance)
            guard case let .closed(lower, upper) = sides[index].domain else { continue }
            for sampleIndex in 0...8 {
                let parameter = lower + (upper - lower) * Double(sampleIndex) / 8
                let point = try sides[index].point(at: parameter, tolerance: .standard)
                let deviation = (0..<3).map { segmentIndex in
                    distance(
                        from: point,
                        toSegmentFrom: points[segmentIndex],
                        to: points[segmentIndex + 1]
                    )
                }.min() ?? .infinity
                #expect(deviation <= ModelingTolerance.standard.distance)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func buildsNonPlanarCoonsSurfaceFromThreeCurvedBoundaryEdges() throws {
        let first = Point3D(x: 0, y: 0, z: 0)
        let second = Point3D(x: 2, y: 0, z: 0)
        let third = Point3D(x: 0.5, y: 2, z: 1)
        let curves = [
            quadraticCurve(first, Point3D(x: 1, y: -0.4, z: 0.6), second),
            quadraticCurve(second, Point3D(x: 1.6, y: 1.2, z: 0.9), third),
            quadraticCurve(third, Point3D(x: -0.2, y: 0.8, z: -0.4), first),
        ]
        let sides = try SurfaceFillFeatureEvaluator(sewer: UnusedSurfaceFillSewer())
            .fourSides(from: curves, tolerance: .standard)
        let boundaries = try [
            sides[0],
            sides[2].reversed(tolerance: .standard),
            sides[3].reversed(tolerance: .standard),
            sides[1],
        ]
        let surface = try ExactCoonsBSplineSurfaceBuilder().build(
            vMinimumBoundary: boundaries[0],
            vMaximumBoundary: boundaries[1],
            uMinimumBoundary: boundaries[2],
            uMaximumBoundary: boundaries[3],
            tolerance: .standard
        )
        try surface.validate(tolerance: .standard)

        for index in 0...32 {
            let fraction = Double(index) / 32
            let actual = [
                try surface.point(u: fraction, v: 0, tolerance: .standard),
                try surface.point(u: fraction, v: 1, tolerance: .standard),
                try surface.point(u: 0, v: fraction, tolerance: .standard),
                try surface.point(u: 1, v: fraction, tolerance: .standard),
            ]
            let expected = try boundaries.map { curve in
                guard case let .closed(lower, upper) = curve.domain else {
                    throw GeometryError.invalidDistance(0)
                }
                return try curve.point(
                    at: lower + (upper - lower) * fraction,
                    tolerance: .standard
                )
            }
            for boundaryIndex in actual.indices {
                #expect((actual[boundaryIndex] - expected[boundaryIndex]).length
                    <= ModelingTolerance.standard.distance)
            }
        }
    }

    private func emptyContext() -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            tolerance: .standard
        )
    }

    private func distance(from point: Point3D, toSegmentFrom start: Point3D, to end: Point3D) -> Double {
        let direction = end - start
        let lengthSquared = direction.dot(direction)
        let fraction = min(max((point - start).dot(direction) / lengthSquared, 0), 1)
        return (point - (start + direction * fraction)).length
    }

    private func quadraticCurve(_ start: Point3D, _ control: Point3D, _ end: Point3D) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [start, control, end]
        )
    }
}

private struct UnusedSurfaceFillSewer: BRepSewing {
    func sew(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult {
        throw GeometryError.invalidDistance(0.0)
    }
}
