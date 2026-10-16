import CADCore

/// Complete crossing isolation on transverse monotone graph cells, including
/// Rectangular C0/C1 collars with certified one-sided derivative bounds.
struct OverlapRegularGraphBoundaryResolver {
    func parameters(graph: OverlapRegularGraphCorrespondence, uValues: [Double], vValues: [Double],
                    policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> [Double] {
        var cuts: [Double] = []
        var cutsCapacity = 0
        for (variesU, values) in [(true, uValues), (false, vValues)] {
            for boundary in values {
                for cell in graph.cells {
                    try policy.work(using: &execution)
                    let box = variesU ? cell.box.u : cell.box.v
                    if boundary < box.lower || boundary > box.upper { continue }
                    if let stationary = variesU ? cell.stationaryU : cell.stationaryV {
                        // The original identity classifies this complete cell: its
                        // entire axis image is one represented native coordinate.
                        // Other boundary values have no incidence; equality owns
                        // the whole interval rather than an isolated transverse root.
                        if boundary == stationary {
                            try policy.storage(2, using: &execution)
                            try CertifiedAnalyticCurveEvaluation.append(cell.range.lower, to: &cuts, using: &execution, capacity: &cutsCapacity); try CertifiedAnalyticCurveEvaluation.append(cell.range.upper, to: &cuts, using: &execution, capacity: &cutsCapacity)
                        }
                        continue
                    }
                    let derivative = variesU ? cell.derivativeU : cell.derivativeV
                    // FIXME(INCOMPLETE_IMPLEMENTATION): non-transverse and continuous
                    // chart-boundary coincidence lacks complete graph clipping here.
                    // intersectionResult's regular graph route must fail until all such
                    // roots and boundary intervals have certified isolation and coverage.
                    guard derivative.lower > 0 || derivative.upper < 0 else {
                        throw failure(.unsupportedCapability, "Regular graph clipping requires a proved transverse chart crossing.", graph)
                    }
                    if let cut = try crossing(graph: graph, cell: cell, boundary: boundary,
                        variesU: variesU, policy: policy, using: &execution) {
                        try policy.storage(using: &execution)
                        try CertifiedAnalyticCurveEvaluation.append(cut, to: &cuts, using: &execution, capacity: &cutsCapacity)
                    }
                }
            }
        }
        return cuts
    }

    private func crossing(graph: OverlapRegularGraphCorrespondence, cell: OverlapRegularGraphCell,
                          boundary: Double, variesU: Bool, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Double? {
        let root = graph.root
        let resolver = SurfaceParameterRangeResolver()
        let domain = variesU ? root.originalSurface.uDomain : root.originalSurface.vDomain
        let boundaryRange = try ScalarInterval(lower: boundary, upper: boundary)
        func residual(at t: Double, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
            if let endpoint = try root.exactEndpoint(at: t, pair: cell.pair, policy: policy, using: &execution) {
                return .exact(variesU ? endpoint.u : endpoint.v) - .exact(boundary)
            }
            let proof = try root.pointProof(at: t, cell: cell, policy: policy, using: &execution)
            let box = variesU ? proof.box.u : proof.box.v
            return OutwardScalarInterval(lower: box.lower, upper: box.upper) - .exact(boundary)
        }
        func admitted(_ interval: OutwardScalarInterval) -> Bool {
            let coordinate = OutwardScalarInterval.exact(boundary) + interval
            return resolver.resolvedParameter(coordinate.lower, domain: domain, requestedRange: boundaryRange, tolerance: root.tolerance) != nil
                && resolver.resolvedParameter(coordinate.upper, domain: domain, requestedRange: boundaryRange, tolerance: root.tolerance) != nil
        }
        var lower = cell.range.lower, upper = cell.range.upper
        var left = try residual(at: lower, policy: policy, using: &execution), right = try residual(at: upper, policy: policy, using: &execution)
        let increasing = (variesU ? cell.derivativeU : cell.derivativeV).lower > 0
        func sign(_ value: OutwardScalarInterval) -> Int {
            value.lower > 0 ? 1 : value.upper < 0 ? -1 : 0
        }
        if sign(left) != 0, sign(left) == sign(right) { return nil }
        if sign(left) == 0, admitted(left) { return lower }
        if sign(right) == 0, admitted(right) { return upper }
        guard sign(left) != 0, sign(right) != 0 else {
            throw failure(.intersectionFailure, "A graph boundary endpoint cannot be separated or admitted at the existing tolerance.", graph)
        }
        for _ in 0..<policy.options.maximumIterations {
            try policy.work(using: &execution)
            let middle = lower + (upper - lower) * 0.5
            guard middle > lower, middle < upper else {
                throw failure(.intersectionFailure, "A transverse boundary has no representable interior refinement.", graph)
            }
            let value = try residual(at: middle, policy: policy, using: &execution)
            let slope = (variesU ? cell.derivativeU : cell.derivativeV).absoluteLowerBound
            guard let sourceError = OutwardScalarInterval.exact(value.absoluteUpperBound).divided(by: .exact(slope)), sourceError.isFinite else {
                throw failure(.intersectionFailure, "A transverse root has no finite source rounding enclosure.", graph)
            }
            let chartError = OutwardScalarInterval.exact((variesU ? cell.derivativeU : cell.derivativeV).absoluteUpperBound) * sourceError
            let corridor = value + OutwardScalarInterval(lower: -chartError.upper, upper: chartError.upper)
            if admitted(corridor) {
                let uv = try graph.parameter(at: middle, policy: policy, using: &execution)
                let coordinate = variesU ? uv.u : uv.v
                guard resolver.resolvedParameter(coordinate, domain: domain, requestedRange: boundaryRange, tolerance: root.tolerance) != nil else {
                    throw failure(.intersectionFailure, "A represented graph boundary cut failed its forward chart admission.", graph)
                }
                // Certified monotonicity and opposite endpoint signs prove exactly
                // one crossing. Retain its isolation corridor, not an exact-root claim.
                return middle
            }
            guard sign(value) != 0 else { throw failure(.intersectionFailure, "A transverse boundary root enclosure exceeds chart rounding admission.", graph) }
            if (sign(value) < 0) == increasing { lower = middle; left = value }
            else { upper = middle; right = value }
        }
        throw failure(.resourceLimitExceeded, "Transverse graph boundary isolation exhausted its iteration policy.", graph)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ graph: OverlapRegularGraphCorrespondence) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: graph.root.tolerance, message: message)
    }
}
