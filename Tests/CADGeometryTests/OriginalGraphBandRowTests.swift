import CADCore
@testable import CADGeometry
import Testing

@Suite("Immutable original graph-band row authority")
struct OriginalGraphBandRowTests {
    private let tolerance = ModelingTolerance.standard
    private let certifier = DefaultOriginalRationalGraphBandCertifier()
    private let fidelity = OriginalGraphBandInput.Fidelity(
        linearTolerance: 0.01, angularTolerance: 0.03, maximumEdgeLength: 2)

    private func execution(maximumCells: Int = 262_144) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: 262_144, cellLimit: maximumCells),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumCells: maximumCells, remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }

    @Test(.timeLimit(.minutes(1)))
    func oneOriginalRowRetainsLiteralPointsNormalsAndPaidInverseReuse() throws {
        var usage = try execution()
        let receipt = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                          tolerance: tolerance, using: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.contains(0.5) })
        let beforeRow = usage.visitedCells
        let row = try receipt.stationRow(cellIndex: index, u: 0.5, using: &usage)
        let rowWork = usage.visitedCells - beforeRow
        #expect(rowWork > 1)
        for w in [0.0, 0.25, 0.5, 1.0] {
            let beforeStation = usage.visitedCells
            let station = try receipt.station(row: row, w: w, using: &usage)
            // Original literal laws are S(u,v)=(u,v,0), L(u)=-u(1-u), H(u)=0.
            // At u=1/2, F(1/2,w)=(1/2,-(1-w)/4,0) and its normal is +Z.
            let expected = Point3D(x: 0.5, y: -(1 - w) / 4, z: 0)
            #expect((station.point - expected).length <= station.positionErrorUpperBound)
            #expect(station.positionErrorUpperBound <= fidelity.linearTolerance)
            #expect(abs(station.normal.x) < 1e-10 && abs(station.normal.y) < 1e-10)
            #expect(abs(station.normal.z - 1) < 1e-10)
            #expect(station.normalErrorUpperBound <= fidelity.angularTolerance)
            // Each W still pays surface materialization; none repeats the row inverses.
            #expect(usage.visitedCells - beforeStation == 1)
        }
        #expect(usage.visitedCells - beforeRow == rowWork + 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func foreignReceiptRowsAndInvalidClosedStationsRefuse() throws {
        var usage = try execution()
        let input = literalLens()
        let a = try certifier.certify(input: input, fidelity: fidelity,
                                     tolerance: tolerance, using: &usage)
        let b = try certifier.certify(input: input, fidelity: fidelity,
                                     tolerance: tolerance, using: &usage)
        let index = try #require(a.referenceCells.firstIndex { $0.u.contains(0.5) })
        let row = try a.stationRow(cellIndex: index, u: 0.5, using: &usage)
        try expectFailure(.invalidInput) {
            _ = try b.station(row: row, w: 0.5, using: &usage)
        }
        try expectFailure(.invalidInput) {
            _ = try a.station(row: row, w: .nan, using: &usage)
        }
        try expectFailure(.invalidInput) {
            _ = try a.station(row: row, w: 1.0.nextUp, using: &usage)
        }
        try expectFailure(.invalidInput) {
            _ = try a.stationRow(cellIndex: index, u: .infinity, using: &usage)
        }
        try expectFailure(.invalidInput) {
            _ = try a.stationRow(cellIndex: index,
                u: a.referenceCells[index].u.lower.nextDown, using: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aPreparedRowDoesNotBypassExhaustedMaterializationUsage() throws {
        var usage = try execution(maximumCells: 10_000)
        let receipt = try certifier.certify(input: literalLens(), fidelity: fidelity,
                                          tolerance: tolerance, using: &usage)
        let index = try #require(receipt.referenceCells.firstIndex { $0.u.contains(0.5) })
        let row = try receipt.stationRow(cellIndex: index, u: 0.5, using: &usage)
        while usage.visitedCells < usage.effectiveLimits.maximumCells { try usage.visitGeometricCell(depth: 0) }
        try expectFailure(.resourceLimitExceeded) {
            _ = try receipt.station(row: row, w: 0.5, using: &usage)
        }
        #expect(usage.visitedCells == usage.effectiveLimits.maximumCells)
    }

    @Test(.timeLimit(.minutes(1)))
    func c0RowsKeepIndependentClosedSideNormalsAndStationEvidence() throws {
        var usage = try execution()
        let receipt = try certifier.certify(input: literalLens(crease: true), fidelity: fidelity,
                                          tolerance: tolerance, using: &usage)
        let left = try #require(receipt.referenceCells.firstIndex { $0.u.upper == 0.5 })
        let right = try #require(receipt.referenceCells.firstIndex { $0.u.lower == 0.5 })
        let leftRow = try receipt.stationRow(cellIndex: left, u: 0.5, using: &usage)
        let rightRow = try receipt.stationRow(cellIndex: right, u: 0.5, using: &usage)
        let a = try receipt.station(row: leftRow, w: 0.5, using: &usage)
        let b = try receipt.station(row: rightRow, w: 0.5, pointCandidate: a.point, using: &usage)
        let expected = Point3D(x: 0.5, y: -0.125, z: 0)
        #expect((a.point - expected).length <= a.positionErrorUpperBound)
        #expect((b.point - expected).length <= b.positionErrorUpperBound)
        // Original S=(u,v,max(0,u-1/2)) has the two literal one-sided normals.
        let diagonal = 1 / Double(2).squareRoot()
        #expect(abs(a.normal.x) < 1e-10 && abs(a.normal.z - 1) < 1e-10)
        #expect(abs(b.normal.x + diagonal) < 1e-10 && abs(b.normal.z - diagonal) < 1e-10)
        #expect(a.normalErrorUpperBound <= fidelity.angularTolerance)
        #expect(b.normalErrorUpperBound <= fidelity.angularTolerance)
        try expectFailure(.invalidInput) {
            try receipt.admitReferenceFacet(cellIndex: left, stations: [a, a, b],
                positions: [a.point, a.point, b.point], normals: [a.normal, a.normal, b.normal],
                using: &usage)
        }
    }

    private func literalLens(crease: Bool = false) -> OriginalGraphBandInput {
        let axis = crease ? [0.0, 0.5, 1.0] : [0.0, 1.0]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: crease ? [0, 0, 0.5, 1, 1] : [0, 0, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [-1.0, 1.0].map { v in
                axis.map { u in Point3D(x: u, y: v, z: crease ? max(0, u - 0.5) : 0) }
            })
        let lower = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: -0.5), Point2D(x: 1, y: 0)])
        return OriginalGraphBandInput(surface: surface,
            boundaries: [.bSpline(lower), .constantV(v: 0, uStart: 1, uEnd: 0)],
            sharedVertices: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: crease ? 0.5 : 0)],
            lowerChain: [.init(boundaryIndex: 0)], upperChain: [.init(boundaryIndex: 1, reversed: true)])
    }

    private func expectFailure(_ code: KernelErrorCode, body: () throws -> Void) throws {
        do {
            try body()
            Issue.record("Expected typed original graph-band row refusal.")
        } catch {
            let published = OriginalQueryFailure.published(error, context: .unspecified, tolerance: tolerance)
            let failure = try #require(OriginalQueryFailure.classification(of: published))
            #expect(failure.code == code)
        }
    }
}
