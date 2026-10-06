import CADCore
@testable import CADGeometry
import Testing

@Suite("Original graph-band reference authority")
struct OriginalGraphBandTests {
    private let tolerance = ModelingTolerance.standard
    private let certifier = DefaultOriginalRationalGraphBandCertifier()
    private var fidelity: OriginalGraphBandInput.Fidelity {
        .init(linearTolerance: 0.01, angularTolerance: 0.03, maximumEdgeLength: 2)
    }

    @Test func literalGraphRetainsFullOriginalIntervalsAndSimpleCaps() throws {
        var usage = OriginalTessellationProofUsage()
        let input = literalLens()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.input == input)
        #expect(receipt.originalBoundaryIntervals.count == 2)
        #expect(receipt.originalBoundaryIntervals.allSatisfy {
            $0.normalizedParameters.lower == 0 && $0.normalizedParameters.upper == 1
        })
        #expect(receipt.joinCells.count == 2)
        #expect(receipt.joinCells.allSatisfy { $0.entry.u == $0.exit.u && $0.entry.v.upper < $0.exit.v.lower })
        #expect(receipt.referenceCells.first!.u.lower == receipt.joinCells[0].parameters.u.upper)
        #expect(receipt.referenceCells.last!.u.upper == receipt.joinCells[1].parameters.u.lower)
        #expect(usage.usedCellCount > 2)
        #expect(receipt.winding == 1)
    }

    @Test func reversedOriginalLoopRetainsGeometryAndDirectedWinding() throws {
        let source = literalLens()
        let reverse = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 0.5, y: -0.5), Point2D(x: 0, y: 0)])
        let input = OriginalGraphBandInput(surface: source.surface,
            boundaries: [.constantV(v: 0, uStart: 0, uEnd: 1), .bSpline(reverse)],
            sharedVertices: source.sharedVertices, lowerChain: [.init(boundaryIndex: 1, reversed: true)],
            upperChain: [.init(boundaryIndex: 0)])
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.winding == -1)
        #expect(receipt.originalBoundaryIntervals.count == 2)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.contains(0.5) })
        let station = try receipt.station(cellIndex: index, u: 0.5, w: 0.5, proofUsage: &usage)
        #expect(abs(station.point.y + 0.125) < 1e-10)
    }

    @Test func flatSupportStillRejectsLiteralTrimInteriorError() throws {
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.lower <= 0.25 && $0.u.upper >= 0.75 })
        let stations = try [(0.25, 0.0), (0.75, 0.0), (0.25, 0.5)].map {
            try receipt.station(cellIndex: index, u: $0.0, w: $0.1, proofUsage: &usage)
        }
        // S(u,v)=(u,v,0), lower graph v=-u(1-u). The original
        // midpoint is -1/4 while the emitted boundary chord is -3/16.
        #expect(0.25 - 0.1875 == 0.0625)
        #expect(0.0625 > fidelity.linearTolerance)
        #expect(abs(stations[0].point.y + 0.1875) < 1e-10)
        #expect(abs(stations[1].point.y + 0.1875) < 1e-10)
        #expect(receipt.referenceCells[index].bounds.secondDerivativeUUMagnitudeUpperBound >= 2)
        try expectFailure(.unsupportedCapability) {
            try receipt.admitReferenceFacet(cellIndex: index, stations: stations,
                positions: stations.map(\.point), normals: stations.map(\.normal), proofUsage: &usage)
        }
        let fine = try [(0.25, 0.0), (0.251, 0.0), (0.25, 0.01)].map {
            try receipt.station(cellIndex: index, u: $0.0, w: $0.1, proofUsage: &usage)
        }
        try receipt.admitReferenceFacet(cellIndex: index, stations: fine,
            positions: fine.map(\.point), normals: fine.map(\.normal), proofUsage: &usage)
    }

    @Test func crossingOriginalTailsRemainCoveredUnderFullJoinStrip() throws {
        let aU = 0.5.nextUp
        let bV = 1.0.nextDown
        let du = aU - 0.5
        #expect(du == 1.0 - bV)
        #expect(1 / aU > 1)
        // At B.u the left graph is below B.v; at A.u it is above
        // the right graph. Exact original line slopes force an interior crossing.
        let input = crossingTails(aU: aU, bV: bV)
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.input.boundaries == input.boundaries)
        #expect(receipt.originalBoundaryIntervals.count == 3)
        let join = try #require(receipt.joinCells.first {
            $0.parameters.u.lower < 0.5 && $0.parameters.u.upper > aU
                && $0.parameters.v.lower > 0.5
        })
        let strip = receipt.referenceCells.filter {
            $0.u.lower >= join.parameters.u.lower && $0.u.upper <= join.parameters.u.upper
        }
        #expect(strip.isEmpty == false)
        #expect(strip.first!.u.lower == join.parameters.u.lower)
        #expect(strip.last!.u.upper == join.parameters.u.upper)
        #expect(strip.allSatisfy { $0.parameters.v.lower == 0 && $0.parameters.v.upper >= bV })
        #expect(strip.allSatisfy { $0.boundaryUncertaintyUpperBound > 0 })
        for pair in zip(receipt.referenceCells, receipt.referenceCells.dropFirst()) {
            #expect(pair.0.u.upper == pair.1.u.lower)
        }
    }

    @Test func hiddenOriginalEndpointsDoNotPartitionActiveConnector() throws {
        let input = crossingTails(aU: 0.5.nextUp, bV: 1.0.nextDown)
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.input == input)
        #expect(receipt.originalBoundaryIntervals.count == 3)
        #expect(Set(receipt.originalBoundaryIntervals.map(\.boundaryIndex)) == Set(0..<3))
        #expect(receipt.originalBoundaryIntervals.allSatisfy {
            $0.nativeParameters.lower == 0 && $0.nativeParameters.upper == 1
                && $0.normalizedParameters.lower == 0 && $0.normalizedParameters.upper == 1
        })
        let join = try #require(receipt.joinCells.first {
            $0.parameters.u.lower < 0.5 && $0.parameters.u.upper > 0.5.nextUp
                && $0.parameters.v.lower > 0.5
        })
        let strip = receipt.referenceCells.filter {
            $0.u.lower >= join.parameters.u.lower && $0.u.upper <= join.parameters.u.upper
        }
        #expect(strip.count == 1)
        let cell = try #require(strip.first)
        #expect(cell.u.lower == join.parameters.u.lower)
        #expect(cell.u.upper == join.parameters.u.upper)
        #expect(cell.parameters.v.lower == 0 && cell.parameters.v.upper >= 1.0.nextDown)
        #expect(cell.boundaryUncertaintyUpperBound > 0)
        #expect(receipt.referenceCells.allSatisfy {
            $0.u.lower != 0.5 && $0.u.upper != 0.5
                && $0.u.lower != 0.5.nextUp && $0.u.upper != 0.5.nextUp
        })
        for pair in zip(receipt.referenceCells, receipt.referenceCells.dropFirst()) {
            #expect(pair.0.u.upper == pair.1.u.lower)
        }
    }

    @Test func oppositeActiveOriginalBreakStillPartitionsConnectorStrip() throws {
        let source = crossingTails(aU: 0.5.nextUp, bV: 1.0.nextDown)
        let lower = BSplineCurve2D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: 0), Point2D(x: 1, y: 0)])
        let input = OriginalGraphBandInput(surface: source.surface,
            boundaries: [.bSpline(lower), source.boundaries[1], source.boundaries[2]],
            sharedVertices: source.sharedVertices, lowerChain: source.lowerChain,
            upperChain: source.upperChain)
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.input == input)
        #expect(receipt.originalBoundaryIntervals.count == 4)
        #expect(receipt.referenceCells.contains { $0.u.upper == 0.5 })
        #expect(receipt.referenceCells.contains { $0.u.lower == 0.5 })
        #expect(receipt.referenceCells.allSatisfy { $0.u.upper <= 0.5 || $0.u.lower >= 0.5 })
        #expect(receipt.referenceCells.allSatisfy {
            $0.u.lower != 0.5.nextUp && $0.u.upper != 0.5.nextUp
        })
    }

    @Test func selectedC0NormalsRemainSeparateAtTheSameStation() throws {
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: literalLens(crease: true), fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        #expect(receipt.referenceCells.allSatisfy { $0.u.upper <= 0.5 || $0.u.lower >= 0.5 })
        let left = try #require(receipt.referenceCells.firstIndex { $0.u.upper == 0.5 })
        let right = try #require(receipt.referenceCells.firstIndex { $0.u.lower == 0.5 })
        let a = try receipt.station(cellIndex: left, u: 0.5, w: 0.5, proofUsage: &usage)
        let b = try receipt.station(cellIndex: right, u: 0.5, w: 0.5,
                                    pointCandidate: a.point, proofUsage: &usage)
        #expect(abs(a.normal.x) < 1e-10)
        #expect(b.normal.x < -0.7)
        #expect((a.point - b.point).length <= a.positionErrorUpperBound + b.positionErrorUpperBound)
        try expectFailure(.invalidInput) {
            try receipt.admitReferenceFacet(cellIndex: left, stations: [a, a, b],
                positions: [a.point, a.point, b.point], normals: [a.normal, a.normal, b.normal],
                proofUsage: &usage)
        }
    }

    @Test func positiveUnequalOriginalWeightsRetainLiteralRationalPoint() throws {
        let source = literalLens()
        let graph = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: -0.5), Point2D(x: 1, y: 0)],
            weights: [1, 2, 1])
        let input = OriginalGraphBandInput(surface: source.surface,
            boundaries: [.bSpline(graph), source.boundaries[1]], sharedVertices: source.sharedVertices,
            lowerChain: source.lowerChain, upperChain: source.upperChain)
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.contains(0.5) })
        let station = try receipt.station(cellIndex: index, u: 0.5, w: 0, proofUsage: &usage)
        // At original t=1/2: W=3/2, X=3/4 and Y=-1/2.
        // Thus u=1/2, v=-1/3 and v_uu=4, independently of production evaluation.
        let third = -1.0 / 3.0
        #expect(station.point.y - station.positionErrorUpperBound <= third.nextDown)
        #expect(station.point.y + station.positionErrorUpperBound >= third.nextUp)
        #expect(receipt.referenceCells[index].bounds.secondDerivativeUUMagnitudeUpperBound >= 4)
    }

    @Test func actualFacetBindingAndEveryTriangleEdgeRemainRequired() throws {
        var usage = OriginalTessellationProofUsage()
        let receipt = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.lower <= 0.25 && $0.u.upper >= 0.26 })
        let stations = try [(0.25, 0.0), (0.251, 0.0), (0.25, 0.01)].map {
            try receipt.station(cellIndex: index, u: $0.0, w: $0.1, proofUsage: &usage)
        }
        var shifted = stations.map(\.point)
        shifted[0].x += 1e-6
        try expectFailure(.invalidInput) {
            try receipt.admitReferenceFacet(cellIndex: index, stations: stations, positions: shifted,
                                            normals: stations.map(\.normal), proofUsage: &usage)
        }
        let other = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                         tolerance: tolerance, proofUsage: &usage)
        try expectFailure(.invalidInput) {
            try other.admitReferenceFacet(cellIndex: index, stations: stations,
                positions: stations.map(\.point), normals: stations.map(\.normal), proofUsage: &usage)
        }
        let short = OriginalGraphBandInput.Fidelity(linearTolerance: 0.01,
                                                   angularTolerance: 0.03, maximumEdgeLength: 0.0019)
        let shortReceipt = try certifier.certify(input: literalLens(), fidelity: short,
                                              tolerance: tolerance, proofUsage: &usage)
        let triangle = try [(0.25, 0.0), (0.2515, 0.0), (0.25, 0.009)].map {
            try shortReceipt.station(cellIndex: index, u: $0.0, w: $0.1, proofUsage: &usage)
        }
        // Each axis edge is shorter than the limit; the diagonal is longer.
        #expect((triangle[0].point - triangle[1].point).length < short.maximumEdgeLength)
        #expect((triangle[0].point - triangle[2].point).length < short.maximumEdgeLength)
        #expect((triangle[1].point - triangle[2].point).length > short.maximumEdgeLength)
        try expectFailure(.unsupportedCapability) {
            try shortReceipt.admitReferenceFacet(cellIndex: index, stations: triangle,
                positions: triangle.map(\.point), normals: triangle.map(\.normal), proofUsage: &usage)
        }
    }

    @Test func originalNativePanelsShareOneActualCellCounter() throws {
        var usage = try OriginalTessellationProofUsage(maximumCellCount: 2, tolerance: tolerance)
        let input = literalLens(crease: true)
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1),
                                          v: ScalarInterval(lower: -1, upper: 1))
        let owner = DefaultSurfaceDifferentialEncloser()
        let panels = try owner.originalNativeSpanTessellationBounds(of: input.surface, over: box,
            tolerance: tolerance, proofUsage: &usage)
        #expect(panels.count == 2)
        #expect(usage.usedCellCount == 2)
        try expectFailure(.resourceLimitExceeded) {
            _ = try owner.originalNativeSpanTessellationBounds(of: input.surface, over: box,
                tolerance: tolerance, proofUsage: &usage)
        }
        var lower = try OriginalTessellationProofUsage(maximumCellCount: 1, tolerance: tolerance)
        try expectFailure(.resourceLimitExceeded) {
            _ = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                      tolerance: tolerance, proofUsage: &lower)
        }
    }

    @Test func nativeEndpointStationsConsumeBeforeOriginalMaterialization() throws {
        let source = literalLens()
        let knots = [0.0, 0, 0.5, 1, 1]
        let lower = BSplineCurve2D(degree: 1, knots: knots,
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: -0.5), Point2D(x: 1, y: 0)])
        let upper = BSplineCurve2D(degree: 1, knots: knots,
            controlPoints: [Point2D(x: 1, y: 0), Point2D(x: 0.5, y: 0), Point2D(x: 0, y: 0)])
        let input = OriginalGraphBandInput(surface: source.surface,
            boundaries: [.bSpline(lower), .bSpline(upper)], sharedVertices: source.sharedVertices,
            lowerChain: source.lowerChain, upperChain: source.upperChain)
        var usage = try OriginalTessellationProofUsage(maximumCellCount: 10_000, tolerance: tolerance)
        let receipt = try certifier.certify(input: input, fidelity: fidelity,
                                          tolerance: tolerance, proofUsage: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.upper == 0.5 })
        let before = usage.usedCellCount
        let station = try receipt.station(cellIndex: index, u: 0.5, w: 0.5, proofUsage: &usage)
        // Both original graph laws meet a native endpoint. Their exact inverse
        // shortcuts must not make the subsequent original surface proof free.
        #expect(abs(station.point.x - 0.5) < 1e-10 && abs(station.point.y + 0.25) < 1e-10)
        #expect(usage.usedCellCount > before)
        while usage.remainingCellCount > 0 { try usage.consume(depth: 0, tolerance: tolerance) }
        let originalPiece = try OriginalGraphBandRationalPiece(boundaryIndex: 0, nativeIndex: 0,
            nativeParameters: ScalarInterval(lower: 0, upper: 0.5),
            points: Array(lower.controlPoints.prefix(2)), weights: Array(lower.weights.prefix(2)),
            tolerance: tolerance)
        try expectFailure(.resourceLimitExceeded) {
            _ = try originalPiece.inverse(u: 0.5, tolerance: tolerance, proofUsage: &usage)
        }
        try expectFailure(.resourceLimitExceeded) {
            _ = try receipt.station(cellIndex: index, u: 0.5, w: 0.5, proofUsage: &usage)
        }
    }

    @Test func invalidVertexAndUnprovedOriginalGraphRefuse() throws {
        var input = literalLens()
        input = OriginalGraphBandInput(surface: input.surface, boundaries: input.boundaries,
            sharedVertices: [Point3D(x: 0, y: 0, z: 1), input.sharedVertices[1]],
            lowerChain: input.lowerChain, upperChain: input.upperChain)
        var usage = OriginalTessellationProofUsage()
        try expectFailure(.invalidInput) {
            _ = try certifier.certify(input: input, fidelity: fidelity,
                                      tolerance: tolerance, proofUsage: &usage)
        }
        let source = literalLens()
        let stationary = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0, y: -0.5), Point2D(x: 1, y: 0)])
        let unknown = OriginalGraphBandInput(surface: source.surface,
            boundaries: [.bSpline(stationary), source.boundaries[1]], sharedVertices: source.sharedVertices,
            lowerChain: source.lowerChain, upperChain: source.upperChain)
        var secondUsage = OriginalTessellationProofUsage()
        try expectFailure(.unsupportedCapability) {
            _ = try certifier.certify(input: unknown, fidelity: fidelity,
                                      tolerance: tolerance, proofUsage: &secondUsage)
        }
    }

    @Test func cancelledGraphProofCannotPublishAReceipt() async throws {
        let task = Task {
            while Task.isCancelled == false { await Task.yield() }
            var usage = OriginalTessellationProofUsage()
            return try certifier.certify(input: literalLens(), fidelity: fidelity,
                                         tolerance: tolerance, proofUsage: &usage)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled original graph proof published a receipt.")
        } catch is CancellationError {
        }
    }

    private func literalLens(crease: Bool = false) -> OriginalGraphBandInput {
        let coordinates = crease ? [0.0, 0.5, 1.0] : [0.0, 1.0]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: crease ? [0, 0, 0.5, 1, 1] : [0, 0, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [-1.0, 1.0].map { v in
                coordinates.map { u in Point3D(x: u, y: v, z: crease ? max(0, u - 0.5) : 0) }
            })
        let graph = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: -0.5), Point2D(x: 1, y: 0)])
        return OriginalGraphBandInput(surface: surface,
            boundaries: [.bSpline(graph), .constantV(v: 0, uStart: 1, uEnd: 0)],
            sharedVertices: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: crease ? 0.5 : 0)],
            lowerChain: [.init(boundaryIndex: 0)], upperChain: [.init(boundaryIndex: 1, reversed: true)])
    }

    private func crossingTails(aU: Double, bV: Double) -> OriginalGraphBandInput {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 2, 2],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 2, z: 0), Point3D(x: 1, y: 2, z: 0)]])
        func line(_ a: Point2D, _ b: Point2D) -> SurfaceParameterCurve {
            .bSpline(BSplineCurve2D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [a, b]))
        }
        return OriginalGraphBandInput(surface: surface,
            boundaries: [.constantV(v: 0, uStart: 0, uEnd: 1),
                line(Point2D(x: 1, y: 0), Point2D(x: 0.5, y: bV)),
                line(Point2D(x: aU, y: 1), Point2D(x: 0, y: 0))],
            sharedVertices: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
                             Point3D(x: 0.5, y: 1, z: 0)],
            lowerChain: [.init(boundaryIndex: 0)],
            upperChain: [.init(boundaryIndex: 2, reversed: true), .init(boundaryIndex: 1, reversed: true)])
    }

    private func expectFailure(_ code: KernelErrorCode, body: () throws -> Void) throws {
        do {
            try body()
            Issue.record("Expected typed original graph-band refusal.")
        } catch let error as KernelError {
            #expect(error.code == code)
        }
    }
}
