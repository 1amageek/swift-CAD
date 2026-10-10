import HashTreeCollections
import CADCore
import CADGeometry

/// A face's parameter extent: the box its trimming curves span, certified to hold every one of
/// them and within a ten-millionth of the box's width of their true extremes on each side.
///
/// `DefaultFaceParameterBoundsResolver` stops at enclosures a quarter of a parameter unit wide,
/// which may overhang the curves by half their own span; this refines the certified enclosure of
/// each trimming curve only where it overhangs the points the curves are known to reach, so the
/// box is the face's own extent. It is what a face's UVN coordinates are normalized over and what
/// a support refitted under a trimmed face must cover.
package struct FaceParameterExtentResolver: FaceParameterBoundsResolving {
    private struct Cell {
        let curve: Int
        let depth: Int
        let lower: Double
        let upper: Double
        let u: ScalarInterval
        let v: ScalarInterval
    }

    /// The overhang allowed on each side, as a fraction of the curves' width that way.
    private let resolution = 1.0e-7
    private let maximumCellCount = 65_536
    private let maximumSubdivisionDepth: Int
    private let consumeWork: (@Sendable (Int) throws -> Void)?
    private let consumeStorage: (@Sendable (Int) throws -> Void)?
    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int

    package init(maximumSubdivisionDepth: Int = 48,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) {
        self.maximumSubdivisionDepth = min(48, maximumSubdivisionDepth)
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.remainingSourceDepth = min(16, remainingSourceDepth)
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    package func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
            (0...32).contains(maximumAlgebraicDepth) else {
            throw failure(.invalidInput, tolerance, "Face extent requires a nonnegative proof depth.")
        }
        try consumeWork?(0)
        guard let face = model.faces[faceID],
            let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, tolerance, "Face parameter extent references a missing face or support.")
        }
        // An untrimmed face spans its support's whole domain, which the default resolver reads.
        guard face.loops.isEmpty == false else {
            return try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth).bounds(for: faceID, in: model, tolerance: tolerance)
        }
        var curves: [SurfaceParameterCurve] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw failure(.missingReference, tolerance, "Face parameter extent references a missing loop.")
            }
            for coedge in loop.coedges {
                try consumeWork?(0)
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw failure(.topologyFailure, tolerance, "A bounded face requires an exact pcurve on every coedge.")
                }
                guard curves.count < maximumCellCount else {
                    throw failure(.resourceLimitExceeded, tolerance, "Face extent exceeded its original curve/cell admission.")
                }
                try OriginalParameterQueryStorage.append(pcurve, to: &curves,
                    consumeStorage: consumeStorage)
            }
        }
        var inner = Extent()
        var cells: [Cell] = []
        for (index, curve) in curves.enumerated() {
            try consumeWork?(0)
            inner.includeWitness(try witnessBox(curve, on: surface, at: 0, depth: 0, tolerance: tolerance))
            try consumeWork?(0)
            inner.includeWitness(try witnessBox(curve, on: surface, at: 1, depth: 0, tolerance: tolerance))
            let original = try cell(index, curve, on: surface, 0, 1, depth: 0, tolerance)
            try OriginalParameterQueryStorage.append(original, to: &cells, consumeStorage: consumeStorage)
        }
        var cellCount = cells.count
        while true {
            try CurrentTaskCancellationChecker().checkCancellation()
            let slackU = max(inner.u.upper - inner.u.lower, tolerance.relative) * resolution
            let slackV = max(inner.v.upper - inner.v.lower, tolerance.relative) * resolution
            var refined: [Cell] = []
            var didSplit = false
            for cell in cells {
                try consumeWork?(cell.depth)
                guard cell.u.upper > inner.u.upper + slackU || cell.u.lower < inner.u.lower - slackU
                        || cell.v.upper > inner.v.upper + slackV || cell.v.lower < inner.v.lower - slackV else {
                    try OriginalParameterQueryStorage.append(cell, to: &refined,
                        consumeStorage: consumeStorage)
                    continue
                }
                let middle = cell.lower + (cell.upper - cell.lower) * 0.5
                cellCount += 2
                guard cell.depth < maximumSubdivisionDepth, cellCount <= maximumCellCount, middle > cell.lower, middle < cell.upper else {
                    throw failure(.resourceLimitExceeded, tolerance,
                        "A face's trimming curves could not be enclosed within \(resolution) of their extent.")
                }
                let curve = curves[cell.curve]
                try consumeWork?(cell.depth + 1)
                inner.includeWitness(try witnessBox(curve, on: surface, at: middle,
                    depth: cell.depth + 1, tolerance: tolerance))
                let left = try self.cell(cell.curve, curve, on: surface, cell.lower, middle, depth: cell.depth + 1, tolerance)
                try OriginalParameterQueryStorage.append(left, to: &refined, consumeStorage: consumeStorage)
                let right = try self.cell(cell.curve, curve, on: surface, middle, cell.upper, depth: cell.depth + 1, tolerance)
                try OriginalParameterQueryStorage.append(right, to: &refined, consumeStorage: consumeStorage)
                didSplit = true
            }
            cells = refined
            if !didSplit { break }
        }
        var outer = Extent()
        for cell in cells {
            try consumeWork?(cell.depth)
            outer.include(u: cell.u, v: cell.v)
        }
        guard outer.u.upper > outer.u.lower, outer.v.upper > outer.v.lower else {
            throw failure(.topologyFailure, tolerance, "A bounded face requires a nondegenerate parameter extent.")
        }
        return SurfaceParameterBox(
            u: try ScalarInterval(lower: outer.u.lower, upper: outer.u.upper),
            v: try ScalarInterval(lower: outer.v.lower, upper: outer.v.upper)
        )
    }

    private func witnessBox(_ curve: SurfaceParameterCurve, on surface: Surface3D, at fraction: Double,
        depth: Int, tolerance: ModelingTolerance) throws -> SurfaceParameterBox {
        try curve.originalParameterBounds(on: surface, over: ScalarInterval(lower: fraction, upper: fraction),
            tolerance: tolerance, maximumSpanCount: maximumCellCount,
            maximumSubdivisionDepth: min(32, maximumSubdivisionDepth - depth),
            remainingSourceDepth: remainingSourceDepth,
            consumeWork: { try consumeWork?(depth) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    /// The certified enclosure of `curve` over the fractions from `lower` to `upper`, as one box.
    private func cell(
        _ index: Int,
        _ curve: SurfaceParameterCurve,
        on surface: Surface3D,
        _ lower: Double,
        _ upper: Double,
        depth: Int,
        _ tolerance: ModelingTolerance
    ) throws -> Cell {
        try consumeWork?(depth)
        let enclosures = try CertifiedSurfaceParameterCurveEncloser(
            maximumSubdivisionDepth: maximumSubdivisionDepth - depth,
            consumeWork: { try consumeWork?(depth + $0) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth
        ).enclosures(
            for: curve,
            on: surface,
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            maximumWidth: .greatestFiniteMagnitude,
            tolerance: tolerance
        )
        guard enclosures.isEmpty == false else {
            throw failure(.topologyFailure, tolerance, "A face pcurve produced no certified parameter enclosure.")
        }
        var extent = Extent()
        for enclosure in enclosures {
            try consumeWork?(depth)
            extent.include(u: enclosure.u, v: enclosure.v)
        }
        return Cell(
            curve: index, depth: depth, lower: lower, upper: upper,
            u: try ScalarInterval(lower: extent.u.lower, upper: extent.u.upper),
            v: try ScalarInterval(lower: extent.v.lower, upper: extent.v.upper)
        )
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}

/// A growing box, empty until it includes something.
private struct Extent {
    var u = (lower: Double.infinity, upper: -Double.infinity)
    var v = (lower: Double.infinity, upper: -Double.infinity)

    mutating func includeWitness(_ box: SurfaceParameterBox) {
        u = (min(u.lower, box.u.upper), max(u.upper, box.u.lower))
        v = (min(v.lower, box.v.upper), max(v.upper, box.v.lower))
    }

    mutating func include(_ parameter: SurfaceParameter) {
        u = (min(u.lower, parameter.u), max(u.upper, parameter.u))
        v = (min(v.lower, parameter.v), max(v.upper, parameter.v))
    }

    mutating func include(u interval: ScalarInterval, v other: ScalarInterval) {
        u = (min(u.lower, interval.lower), max(u.upper, interval.upper))
        v = (min(v.lower, other.lower), max(v.upper, other.upper))
    }
}
