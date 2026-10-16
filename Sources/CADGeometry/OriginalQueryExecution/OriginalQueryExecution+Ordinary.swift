import CADCore

extension OriginalQueryExecution {
    public static func curveSurface(options: CurveSurfaceIntersectionOptions,
        context: OriginalQueryFailureContext = .unspecified) throws -> OriginalQueryExecution {
        let work = try exactScalarCount(options.maximumSubdivisionCells, options.maximumIterations, multiply: true)
        let bytes = try exactScalarCount(work, MemoryLayout<OriginalRationalIntersectionCells.Cell>.stride, multiply: true)
        return try .init(budget: OriginalQueryBudget(workLimit: work, storageByteLimit: bytes),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumCells: options.maximumSubdivisionCells, maximumCharts: options.maximumSubdivisionCells,
                maximumFamilies: options.maximumSubdivisionCells, maximumResults: options.maximumCandidateCount,
                remainingSourceDepth: options.maximumSubdivisionDepth, maximumTransportDepth: 32,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                maximumSpans: options.maximumSubdivisionCells, maximumPolynomialDegree: options.maximumPolynomialDegree,
                maximumNativeSpans: options.maximumCandidateCount),
            context: context)
    }
    public static func surfaceSurface(options: SurfaceSurfaceIntersectionOptions,
        context: OriginalQueryFailureContext = .unspecified) throws -> OriginalQueryExecution {
        let work = try exactScalarCount(options.maximumSubdivisionCells, options.maximumIterations, multiply: true)
        let bytes = try exactScalarCount(work, MemoryLayout<OriginalRationalIntersectionCells.Cell>.stride, multiply: true)
        return try .init(budget: OriginalQueryBudget(workLimit: work, storageByteLimit: bytes),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumCells: options.maximumSubdivisionCells, maximumCharts: options.maximumSubdivisionCells,
                maximumFamilies: options.maximumSubdivisionCells, maximumResults: options.maximumSeedCount,
                remainingSourceDepth: options.maximumSubdivisionDepth, maximumTransportDepth: 32,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth, maximumSpans: 262_144),
            context: context)
    }
}
