import CADCore

/// Immutable original geometry and complete, coherently joined UV root cells.
struct OverlapRegularGraphCorrespondence: Sendable {
    let root: OverlapRegularGraphRootCertifier
    let cells: [OverlapRegularGraphCell]
    let options: CurveSurfaceIntersectionOptions
    let range: ScalarInterval

    init(root: OverlapRegularGraphRootCertifier, cells: [OverlapRegularGraphCell],
         options: CurveSurfaceIntersectionOptions) throws {
        guard let first = cells.first, let last = cells.last else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: root.tolerance,
                message: "A regular correspondence requires a nonempty certified cover.")
        }
        self.root = root
        self.cells = cells
        self.options = options
        range = try ScalarInterval(lower: first.range.lower, upper: last.range.upper)
    }

    var maximumDeviation: Double { cells.map({ $0.maximumDeviation }).max() ?? .infinity }

    func sharesAuthority(with other: Self) -> Bool {
        root.curve.curve == other.root.curve.curve && root.originalSurface == other.root.originalSurface
            && root.tolerance == other.root.tolerance && options == other.options && range == other.range
            && cells.count == other.cells.count && zip(cells, other.cells).allSatisfy {
                $0.0.range == $0.1.range && $0.0.box == $0.1.box && $0.0.pair == $0.1.pair
                    && $0.0.authority == $0.1.authority
                    && $0.0.stationaryU == $0.1.stationaryU && $0.0.stationaryV == $0.1.stationaryV
            }
    }

    func parameter(at t: Double) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        let policy = try OverlapProofPolicy(options: options, tolerance: root.tolerance, using: &execution)
        return try parameter(at: t, policy: policy, using: &execution)
    }

    func parameter(at t: Double, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        let cell = try selectedCell(at: t, policy: policy, using: &execution)
        if let endpoint = try root.exactEndpoint(at: t, pair: cell.pair, policy: policy, using: &execution) { return endpoint }
        let proof = try root.pointProof(at: t, cell: cell, policy: policy, using: &execution)
        guard proof.stationaryParameters.u == cell.stationaryU,
              proof.stationaryParameters.v == cell.stationaryV else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: root.tolerance,
                message: "A reproduced root changed its original stationary native-axis authority.")
        }
        return SurfaceParameter(u: cell.stationaryU ?? proof.box.u.midpoint,
            v: cell.stationaryV ?? proof.box.v.midpoint)
    }

    func selectedCell(at t: Double, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> OverlapRegularGraphCell {
        var lower = 0, upper = cells.count
        while lower < upper {
            try policy.work(using: &execution)
            let middle = lower + (upper - lower) / 2
            if cells[middle].range.upper < t { lower = middle + 1 } else { upper = middle }
        }
        guard lower < cells.count, cells[lower].range.contains(t) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: root.tolerance,
                message: "A regular overlap parameter is outside its complete owned cell cover.")
        }
        return cells[lower]
    }
}
