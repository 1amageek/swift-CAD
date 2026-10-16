import CADCore
import CADGeometry
import CADTopology

/// Selects a material offset side only from a complete original edge cover.
// FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary KernelRollingBallFilletEvaluator
// consumes this original whole-edge sign producer before constructing offsets.
// Mixed-sign root strata, periodic unwrapped winding and complete lower query
// temporary-byte admission remain required for the full concave/network domain.
struct OriginalEdgeDihedralClassifier {
    private struct Cell { let lower: Double; let upper: Double; let depth: Int }

    func isConcave(edgeID: EdgeID, first: Face, second: Face, shell: Shell,
        input: ValidatedBRepModel, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.checkpoint()
        let model = input.model, tolerance = input.tolerance
        guard input.validationLevel != .modeling,
              let edge = model.edges[edgeID], edge.trim != nil,
              model.geometry.curves[edge.curveID] != nil,
              let firstSurface = model.geometry.surfaces[first.surfaceID],
              let secondSurface = model.geometry.surfaces[second.surfaceID] else {
            throw failure(.invalidInput, tolerance, "Original dihedral classification requires retained exact edge and face sources.")
        }
        func use(_ face: Face, using execution: inout OriginalQueryExecution) throws -> (coedge: Coedge, loop: Loop) {
            var selected: (coedge: Coedge, loop: Loop)?
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw failure(.missingReference, tolerance, "Missing original dihedral loop.")
                }
                for coedge in loop.edges {
                    try execution.consumeWork(1)
                    if coedge.edgeID == edgeID {
                        guard selected == nil else {
                            throw failure(.ambiguousSelection, tolerance, "An original dihedral requires one edge use per incident face.")
                        }
                        selected = (coedge, loop)
                    }
                }
            }
            guard let selected else { throw failure(.missingReference, tolerance, "Missing original dihedral coedge.") }
            return selected
        }
        let aUse = try use(first, using: &execution), bUse = try use(second, using: &execution)
        let a = aUse.coedge, b = bUse.coedge
        guard let aCurve = a.surfaceParameterCurve, let bCurve = b.surfaceParameterCurve else {
            throw failure(.missingReference, tolerance, "Original dihedral uses require native face pcurves.")
        }
        let preparedA = try PreparedSurfaceDifferentialEncloser(surface: firstSurface,
            tolerance: tolerance, remainingSourceDepth: RollingBallIntersectionPolicy.maximumSourceDepth,
            maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth,
            maximumAlgebraicDepth: RollingBallIntersectionPolicy.maximumAlgebraicDepth, using: &execution)
        let preparedB = try PreparedSurfaceDifferentialEncloser(surface: secondSurface,
            tolerance: tolerance, remainingSourceDepth: RollingBallIntersectionPolicy.maximumSourceDepth,
            maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth,
            maximumAlgebraicDepth: RollingBallIntersectionPolicy.maximumAlgebraicDepth, using: &execution)
        let originalBoundary = Curve3D.surfaceLift(.init(surface: secondSurface, parameterCurve: bCurve))
        let preparedCurve = try PreparedCurveDifferentialEncloser(curve: originalBoundary,
            tolerance: tolerance, remainingSourceDepth: RollingBallIntersectionPolicy.maximumSourceDepth,
            maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth,
            maximumAlgebraicDepth: RollingBallIntersectionPolicy.maximumAlgebraicDepth, using: &execution)
        var loopOrientation: Int?
        var requestedWidth = 1.0
        for refinement in 0...RollingBallIntersectionPolicy.maximumDepth {
            try execution.admitGeometricDepth(refinement); try execution.consumeWork(1)
            let integral = SurfaceParameterCurveAreaIntegrator(
                maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth - refinement,
                remainingSourceDepth: min(16, RollingBallIntersectionPolicy.maximumSourceDepth),
                maximumAlgebraicDepth: RollingBallIntersectionPolicy.maximumAlgebraicDepth)
            var area = OutwardScalarInterval.exact(0)
            for use in bUse.loop.edges {
                try execution.admitGeometricDepth(refinement); try execution.consumeWork(1)
                guard let pcurve = use.surfaceParameterCurve else {
                    throw failure(.missingReference, tolerance, "Original material-side winding requires every source pcurve.")
                }
                let contribution = try execution.withGeometricDepthOffset(refinement) { execution in
                    try integral.bounds(for: pcurve, on: secondSurface,
                    uShift: 0, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
                }
                area = area + .init(lower: contribution.lower, upper: contribution.upper)
            }
            if area.lower > 0 { loopOrientation = 1; break }
            if area.upper < 0 { loopOrientation = -1; break }
            requestedWidth *= 0.5
        }
        guard let loopOrientation else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original periodic trim winding
            // needs its retained unwrapped chart before this zero/inconclusive
            // native area can authorize a material side. No numeric UV wrapping
            // or vertex probe replaces the original loop authority.
            throw failure(.resourceLimitExceeded, tolerance, "Original material-side loop orientation is not certified.")
        }
        let materialLeftSign = Double(bUse.loop.role == .outer ? loopOrientation : -loopOrientation)
        let outwardSign = first.orientation == shell.orientation ? 1.0 : -1.0
        func box(_ pcurve: SurfaceParameterCurve, on surface: Surface3D,
            cell: Cell, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
            let enclosure = CertifiedSurfaceParameterCurveEncloser(
                maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth - cell.depth,
                maximumAlgebraicDepth: RollingBallIntersectionPolicy.maximumAlgebraicDepth)
            let cover = try execution.withGeometricDepthOffset(cell.depth) { execution in
                try enclosure.enclosures(for: pcurve, on: surface,
                fromNormalizedFraction: cell.lower, toNormalizedFraction: cell.upper,
                maximumWidth: Double.greatestFiniteMagnitude, tolerance: tolerance, using: &execution)
            }
            guard let first = cover.first else {
                throw failure(.classificationFailure, tolerance, "An original pcurve cover cannot be empty.")
            }
            var u = first.u, v = first.v
            for panel in cover {
                try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
                u = try ScalarInterval(lower: min(u.lower, panel.u.lower), upper: max(u.upper, panel.u.upper))
                v = try ScalarInterval(lower: min(v.lower, panel.v.lower), upper: max(v.upper, panel.v.upper))
            }
            func retained(_ interval: ScalarInterval, domain: ParameterDomain) throws -> ScalarInterval {
                guard case let .closed(lower, upper) = domain else { return interval }
                // Exact input admission binds the original pcurve to this source
                // domain. Intersecting its outward hull retains the complete law.
                return try ScalarInterval(lower: max(lower, interval.lower), upper: min(upper, interval.upper))
            }
            return try SurfaceParameterBox(u: retained(u, domain: surface.uDomain), v: retained(v, domain: surface.vDomain))
        }
        func normal(_ prepared: PreparedSurfaceDifferentialEncloser, box: SurfaceParameterBox,
            cell: Cell, using execution: inout OriginalQueryExecution) throws -> IntervalVector3DBounds {
            let q = try execution.withGeometricDepthOffset(cell.depth) { execution in
                try prepared.intervalJet(overClosedBox: box, tolerance: tolerance,
                maximumSpanCount: 4096, maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth - cell.depth,
                remainingSourceDepth: RollingBallIntersectionPolicy.maximumSourceDepth, using: &execution)
            }
            let u = IntervalVector3DBounds(x: q.x.derivativeU, y: q.y.derivativeU, z: q.z.derivativeU)
            let v = IntervalVector3DBounds(x: q.x.derivativeV, y: q.y.derivativeV, z: q.z.derivativeV)
            return u.cross(v)
        }
        let capacity = RollingBallIntersectionPolicy.maximumDepth + 1
        try execution.retainStorage(bytes: capacity * MemoryLayout<Cell>.stride)
        var pending: [Cell] = []
        pending.reserveCapacity(capacity)
        pending.append(Cell(lower: 0, upper: 1, depth: 0))
        var selectedSign: Int?
        while let cell = pending.popLast() {
            try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
            let firstCell = a.orientation == b.orientation ? cell
                : Cell(lower: 1 - cell.upper, upper: 1 - cell.lower, depth: cell.depth)
            let aBox = try box(aCurve, on: firstSurface, cell: firstCell, using: &execution)
            let bBox = try box(bCurve, on: secondSurface, cell: cell, using: &execution)
            let na = try normal(preparedA, box: aBox, cell: cell, using: &execution)
            let nb = try normal(preparedB, box: bBox, cell: cell, using: &execution)
            let receipt = try execution.withGeometricDepthOffset(cell.depth) { execution in
                try preparedCurve.closedNativeJets(
                over: ScalarInterval(lower: cell.lower, upper: cell.upper), tolerance: tolerance,
                maximumSpanCount: 4096, maximumSubdivisionDepth: RollingBallIntersectionPolicy.maximumDepth - cell.depth,
                remainingSourceDepth: RollingBallIntersectionPolicy.maximumSourceDepth, using: &execution)
            }
            guard let firstJet = receipt.spans.first else {
                throw failure(.classificationFailure, tolerance, "An original edge tangent cover cannot be empty.")
            }
            var jet = firstJet.jet
            for owner in receipt.spans { try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1); jet = jet.union(owner.jet) }
            let tangent = IntervalVector3DBounds(x: jet.x.derivativeU, y: jet.y.derivativeU,
                z: jet.z.derivativeU)
            let side = nb.cross(tangent).dot(na) * .exact(outwardSign * materialLeftSign)
            let sign = side.lower > 0 ? 1 : side.upper < 0 ? -1 : 0
            if sign != 0 {
                if let selectedSign, selectedSign != sign {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Public ordinary Fillet
                    // needs retained original dihedral-zero strata and mixed-side
                    // network composition before an edge with both material
                    // signs can publish a successful constant-side treatment.
                    throw failure(.unsupportedCapability, tolerance, "Original edge dihedral changes material side within the selected trim.")
                }
                selectedSign = sign
                continue
            }
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            guard cell.depth < RollingBallIntersectionPolicy.maximumDepth, middle > cell.lower, middle < cell.upper else {
                throw failure(.resourceLimitExceeded, tolerance, "Original dihedral sign exhausted whole-edge subdivision precision.")
            }
            guard pending.count <= capacity - 2 else {
                throw failure(.resourceLimitExceeded, tolerance, "Original dihedral exceeded its admitted live DFS capacity.")
            }
            pending.append(Cell(lower: middle, upper: cell.upper, depth: cell.depth + 1))
            pending.append(Cell(lower: cell.lower, upper: middle, depth: cell.depth + 1))
        }
        guard let selectedSign else {
            throw failure(.classificationFailure, tolerance, "Original dihedral cover supplied no material-side witness.")
        }
        try execution.checkpoint()
        return selectedSign > 0
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .classification, code: code, tolerance: tolerance, message: message)
    }
}
