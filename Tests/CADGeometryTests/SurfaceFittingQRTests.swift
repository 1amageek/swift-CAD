import CADCore
import CADGeometry
import Testing

@Suite("Surface fitting QR", .timeLimit(.minutes(1)))
struct SurfaceFittingQRTests {
    @Test(arguments: [(4, 3), (2, 3), (3, 3), (1, 1)])
    func reconstructionAndOrthogonality(shape: (Int, Int)) throws {
        let (rows, columns) = shape
        let a = (0..<(rows * columns)).map { i in
            Double((i * 7 + i * i) % 13 - 6) * (i % columns == 0 ? 0.01 : 1)
        }
        let qr = try SurfaceFittingQR(coefficients: a, rows: rows, columns: columns,
            relativeRankTolerance: 1e-12, maximumElements: a.count)
        #expect(Set(qr.permutation) == Set(0..<columns))
        if columns > 1 { #expect(qr.permutation[0] != 0) }
        for column in 0..<columns {
            let r = try (0..<rows).map { try qr.upperCoefficient(row: $0, column: column) }
            let reconstructed = try qr.applyingQ(to: r)
            for row in 0..<rows {
                #expect(abs(reconstructed[row] * qr.scale - a[row * columns + qr.permutation[column]]) < 1e-12)
            }
        }
        for column in 0..<rows {
            var unit = Array(repeating: 0.0, count: rows)
            unit[column] = 1
            let restored = try qr.applyingQ(to: qr.applyingQ(to: unit), transpose: true)
            for row in 0..<rows { #expect(abs(restored[row] - unit[row]) < 1e-12) }
        }
    }

    @Test(arguments: [1e-250, 1.0, 1e250])
    func leastSquaresPreservesScaleAndResidualOptimality(scale: Double) throws {
        let a = [1.0, 1, 1, 2, 1, 3].map { $0 * scale }
        let b = [1.0, 2, 2].map { $0 * scale }
        let qr = try SurfaceFittingQR(coefficients: a, rows: 3, columns: 2,
            relativeRankTolerance: 1e-12, maximumElements: 6)
        let x = try qr.solveFullRankLeastSquares(b)
        #expect(abs(x[0] - 2.0 / 3) < 1e-12)
        #expect(abs(x[1] - 0.5) < 1e-12)
        for column in 0..<2 {
            var normalResidual = 0.0
            for row in 0..<3 {
                let residual = a[row * 2] / scale * x[0] + a[row * 2 + 1] / scale * x[1] - b[row] / scale
                normalResidual += a[row * 2 + column] / scale * residual
            }
            #expect(abs(normalResidual) < 1e-11)
        }
    }

    @Test func rankDeficiencyAndZeroMatrixAreNotSuccessfulSolves() throws {
        for (a, rank) in [([1.0, 2, 2, 4, 3, 6], 1), (Array(repeating: 0.0, count: 6), 0)] {
            let qr = try SurfaceFittingQR(coefficients: a, rows: 3, columns: 2,
                relativeRankTolerance: 1e-12, maximumElements: 6)
            #expect(qr.rank == rank)
            #expect(throws: KernelError.self) { try qr.solveFullRankLeastSquares([1, 2, 3]) }
        }
    }

    @Test func invalidInputAndResourceLimitsFailExplicitly() throws {
        #expect(throws: KernelError.self) {
            try SurfaceFittingQR(coefficients: [], rows: Int.max, columns: 2,
                relativeRankTolerance: 1e-12, maximumElements: Int.max)
        }
        #expect(throws: KernelError.self) {
            try SurfaceFittingQR(coefficients: [.nan], rows: 1, columns: 1,
                relativeRankTolerance: 1e-12, maximumElements: 1)
        }
        #expect(throws: KernelError.self) {
            try SurfaceFittingQR(coefficients: [1, 2], rows: 2, columns: 1,
                relativeRankTolerance: 1e-12, maximumElements: 1)
        }
        let qr = try SurfaceFittingQR(coefficients: [1], rows: 1, columns: 1,
            relativeRankTolerance: 1e-12, maximumElements: 1)
        #expect(try qr.applyingQ(to: [Double.greatestFiniteMagnitude]) == [-Double.greatestFiniteMagnitude])
        #expect(throws: KernelError.self) { try qr.upperCoefficient(row: -1, column: 0) }
        #expect(throws: KernelError.self) { try qr.applyingQ(to: []) }
        #expect(throws: KernelError.self) { try qr.solveFullRankLeastSquares([.infinity]) }
    }
}
