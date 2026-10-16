import CADCore

extension DefaultSurfaceDifferentialEncloser {
    package func originalNativeSpanTessellationBounds(
        of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try originalNativeSpanTessellationBounds(of: surface, over: parameters,
            tolerance: tolerance, maximumCellCount: 262_144, using: &execution)
    }

    func originalNativeSpanTessellationBounds(
        of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, maximumCellCount: Int
    ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try originalNativeSpanTessellationBounds(of: surface, over: parameters,
            tolerance: tolerance, maximumCellCount: maximumCellCount, using: &execution)
    }

    package func originalNativeSpanTessellationBounds(
        of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
        try originalNativeSpanTessellationBounds(of: surface, over: parameters,
            tolerance: tolerance, maximumCellCount: 262_144, using: &execution)
    }

    func originalNativeSpanTessellationBounds(
        of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, maximumCellCount: Int,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
        guard (1...262_144).contains(maximumCellCount) else {
            throw GeometryConversionError.invalidInput("Original native panels require their existing finite cell ceiling.")
        }
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: Int.max,
            maximumCoefficientDepth: Int.max, maximumCells: maximumCellCount,
            maximumSubdivisionDepth: 32)
        let contribution = try execution.makeContributionHandle(workLimit: maximumCellCount,
            cellLimit: maximumCellCount, allocationPolicy: .uint32WordWork, executionLimits: limits)
        return try execution.withContributionScope(contribution) { execution in
            try originalNativePanels(of: surface, over: parameters,
                tolerance: tolerance, using: &execution)
        }
    }

    private func originalNativePanels(
        of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
        try tolerance.validate()
        try parameters.validate(for: .bSpline(surface), tolerance: tolerance, using: &execution)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(
            surface: surface, tolerance: tolerance, using: &execution)
        let maximumSpans = min(execution.availableWork, execution.effectiveLimits.maximumSpans)
        guard maximumSpans > 0 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original native panel preparation exhausted the caller's span allowance.")
        }
        let spans = try prepared.originalNativeSpans(over: parameters, tolerance: tolerance,
            maximumSpanCount: maximumSpans, using: &execution)
        typealias Span = PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
        struct Panel {
            let span: Span
            let parameters: SurfaceParameterBox
            var aggregate: SurfaceTessellationDifferentialBounds?
        }
        struct Cell {
            let panelIndex: Int
            let parameters: SurfaceParameterBox
            let depth: Int
        }
        var panels: [Panel] = []
        try execution.retainStorage(count: spans.count, stride: MemoryLayout<Panel>.stride)
        panels.reserveCapacity(spans.count)
        for span in spans {
            try execution.consumeWork(1)
            let uLower = max(parameters.u.lower, span.uBounds.lower)
            let uUpper = min(parameters.u.upper, span.uBounds.upper)
            let vLower = max(parameters.v.lower, span.vBounds.lower)
            let vUpper = min(parameters.v.upper, span.vBounds.upper)
            guard uUpper > uLower, vUpper > vLower else { continue }
            panels.append(Panel(span: span, parameters: try SurfaceParameterBox(
                u: ScalarInterval(lower: uLower, upper: uUpper),
                v: ScalarInterval(lower: vLower, upper: vUpper))))
        }
        var pending: [Cell] = []
        var pendingCapacity = panels.count
        try execution.retainStorage(count: pendingCapacity, stride: MemoryLayout<Cell>.stride)
        pending.reserveCapacity(pendingCapacity)
        for index in panels.indices.reversed() {
            try execution.consumeWork(1)
            pending.append(Cell(panelIndex: index, parameters: panels[index].parameters, depth: 0))
        }
        while let cell = pending.popLast() {
            try execution.visitCertificationCell(depth: cell.depth)
            let span = panels[cell.panelIndex].span
            let local = try execution.withGeometricDepthOffset(cell.depth) { execution -> SurfaceTessellationDifferentialBounds? in
                let jet: SurfaceIntervalVectorJet?
                do {
                    jet = try span.intervalJet(overClosedBox: cell.parameters,
                        on: surface, tolerance: tolerance, using: &execution)
                } catch let error as KernelError where error.code == .singularSystem {
                    jet = nil
                }
                if let jet, let result = try certifiedTessellationBounds(
                    jet: jet, tolerance: tolerance, using: &execution) {
                    return result
                }
                return try originalPolePanelBounds(surface: surface,
                    parameters: cell.parameters, span: span, prepared: prepared,
                    tolerance: tolerance, using: &execution)
            }
            if let local {
                panels[cell.panelIndex].aggregate = panels[cell.panelIndex].aggregate.map {
                    union($0, local)
                } ?? local
                continue
            }
            do {
                _ = try surface.normal(u: cell.parameters.u.midpoint, v: cell.parameters.v.midpoint,
                    owning: span, tolerance: tolerance, using: &execution)
            } catch let error as KernelError where error.code == .singularSystem {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                    message: "Native surface tessellation encountered a singular original tangent frame.")
            }
            guard cell.depth < 32 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    residual: max(cell.parameters.u.width, cell.parameters.v.width), tolerance: tolerance,
                    message: "Native surface tessellation could not certify an original span within its subdivision limit.")
            }
            let children = try subdivided(cell.parameters, surface: .bSpline(surface),
                depth: cell.depth + 1, using: &execution)
            for child in children.reversed() {
                try OriginalCoefficientAllocation.reserveAppend(to: &pending,
                    capacity: &pendingCapacity, using: &execution)
                try execution.consumeWork(1)
                pending.append(Cell(panelIndex: cell.panelIndex, parameters: child, depth: cell.depth + 1))
            }
        }
        guard !panels.isEmpty else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Native surface tessellation requires a nonempty original rectangle.")
        }
        try execution.retainStorage(count: panels.count,
            stride: MemoryLayout<SurfaceTessellationDifferentialBounds.OriginalNativePanel>.stride)
        var result: [SurfaceTessellationDifferentialBounds.OriginalNativePanel] = []
        result.reserveCapacity(panels.count)
        for panel in panels {
            try execution.consumeWork(1)
            guard let bounds = panel.aggregate else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Native surface tessellation did not certify every original panel.")
            }
            result.append(.init(span: panel.span, parameters: panel.parameters, bounds: bounds))
        }
        try execution.checkpoint()
        return result
    }

    private func originalPolePanelBounds(
        surface: BSplineSurface3D, parameters: SurfaceParameterBox,
        span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        prepared: PreparedBSplineSurfaceDifferentialEncloser,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceTessellationDifferentialBounds? {
        guard case .closed(let u0, let u1) = surface.uDomain,
              case .closed(let v0, let v1) = surface.vDomain else { return nil }
        let pole = OriginalBSplinePoleNormal(surface: surface, tolerance: tolerance, prepared: prepared)
        for index in 0..<2 {
            try execution.consumeWork(1)
            guard index == 0 ? (parameters.u.lower == u0 || parameters.u.upper == u1)
                : (parameters.v.lower == v0 || parameters.v.upper == v1) else { continue }
            let direction: OriginalBSplinePoleNormal.Direction = index == 0 ? .constantU : .constantV
            do {
                return try pole.panelBounds(over: parameters, direction: direction,
                    owning: span, using: &execution).differentialBounds
            } catch let error as KernelError where error.code == .invalidInput || error.code == .singularGeometry {
                do {
                    let exact = try pole.prepareExactPanel(over: parameters, direction: direction,
                        owning: span, usage: &execution)
                    return try exact.panelBounds(over: parameters, tolerance: tolerance,
                        usage: &execution).differentialBounds
                } catch let exactError as KernelError where exactError.code == .invalidInput || exactError.code == .singularGeometry {
                    continue
                }
            }
        }
        return nil
    }
}
