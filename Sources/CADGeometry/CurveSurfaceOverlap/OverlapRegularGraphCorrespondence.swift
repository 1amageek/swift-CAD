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

    var maximumDeviation: Double { cells.map(\.maximumDeviation).max() ?? .infinity }

    func sharesAuthority(with other: Self) -> Bool {
        root.curve.curve == other.root.curve.curve && root.originalSurface == other.root.originalSurface
            && root.tolerance == other.root.tolerance && options == other.options && range == other.range
            && cells.count == other.cells.count && zip(cells, other.cells).allSatisfy {
                $0.0.range == $0.1.range && $0.0.box == $0.1.box && $0.0.pair == $0.1.pair
                    && $0.0.authority == $0.1.authority
            }
    }

    func parameter(at t: Double) throws -> SurfaceParameter {
        var budget = OverlapProofBudget(options: options, tolerance: root.tolerance)
        return try parameter(at: t, budget: &budget)
    }

    func parameter(at t: Double, budget: inout OverlapProofBudget) throws -> SurfaceParameter {
        let cell = try selectedCell(at: t, budget: &budget)
        let proof = try root.pointProof(at: t, cell: cell, budget: &budget)
        return SurfaceParameter(u: proof.box.u.midpoint, v: proof.box.v.midpoint)
    }

    func selectedCell(at t: Double, budget: inout OverlapProofBudget) throws -> OverlapRegularGraphCell {
        var lower = 0, upper = cells.count
        while lower < upper {
            try budget.work()
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
