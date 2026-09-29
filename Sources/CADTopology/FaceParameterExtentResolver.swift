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
        let lower: Double
        let upper: Double
        let u: ScalarInterval
        let v: ScalarInterval
    }

    /// The overhang allowed on each side, as a fraction of the curves' width that way.
    private let resolution = 1.0e-7
    private let maximumCellCount = 65_536
    private let encloser = CertifiedSurfaceParameterCurveEncloser()

    package init() {}

    package func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox {
        try tolerance.validate()
        guard let face = model.faces[faceID] else {
            throw failure(.missingReference, tolerance, "Face parameter extent references a missing face.")
        }
        // An untrimmed face spans its support's whole domain, which the default resolver reads.
        guard face.loops.isEmpty == false else {
            return try DefaultFaceParameterBoundsResolver().bounds(for: faceID, in: model, tolerance: tolerance)
        }
        var curves: [SurfaceParameterCurve] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw failure(.missingReference, tolerance, "Face parameter extent references a missing loop.")
            }
            for coedge in loop.coedges {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw failure(.topologyFailure, tolerance, "A bounded face requires an exact pcurve on every coedge.")
                }
                curves.append(pcurve)
            }
        }
        var inner = Extent()
        var cells: [Cell] = []
        for (index, curve) in curves.enumerated() {
            inner.include(try curve.parameter(atNormalizedFraction: 0, tolerance: tolerance))
            inner.include(try curve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
            cells.append(try cell(index, curve, 0, 1, tolerance))
        }
        var cellCount = cells.count
        while true {
            try Task.checkCancellation()
            let slackU = max(inner.u.upper - inner.u.lower, tolerance.relative) * resolution
            let slackV = max(inner.v.upper - inner.v.lower, tolerance.relative) * resolution
            var refined: [Cell] = []
            var didSplit = false
            for cell in cells {
                guard cell.u.upper > inner.u.upper + slackU || cell.u.lower < inner.u.lower - slackU
                        || cell.v.upper > inner.v.upper + slackV || cell.v.lower < inner.v.lower - slackV else {
                    refined.append(cell)
                    continue
                }
                let middle = cell.lower + (cell.upper - cell.lower) * 0.5
                cellCount += 2
                guard cellCount <= maximumCellCount, middle > cell.lower, middle < cell.upper else {
                    throw failure(.resourceLimitExceeded, tolerance,
                        "A face's trimming curves could not be enclosed within \(resolution) of their extent.")
                }
                let curve = curves[cell.curve]
                inner.include(try curve.parameter(atNormalizedFraction: middle, tolerance: tolerance))
                refined.append(try self.cell(cell.curve, curve, cell.lower, middle, tolerance))
                refined.append(try self.cell(cell.curve, curve, middle, cell.upper, tolerance))
                didSplit = true
            }
            cells = refined
            if !didSplit { break }
        }
        var outer = Extent()
        for cell in cells {
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

    /// The certified enclosure of `curve` over the fractions from `lower` to `upper`, as one box.
    private func cell(
        _ index: Int,
        _ curve: SurfaceParameterCurve,
        _ lower: Double,
        _ upper: Double,
        _ tolerance: ModelingTolerance
    ) throws -> Cell {
        let enclosures = try encloser.enclosures(
            for: curve,
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
            extent.include(u: enclosure.u, v: enclosure.v)
        }
        return Cell(
            curve: index, lower: lower, upper: upper,
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

    mutating func include(_ parameter: SurfaceParameter) {
        u = (min(u.lower, parameter.u), max(u.upper, parameter.u))
        v = (min(v.lower, parameter.v), max(v.upper, parameter.v))
    }

    mutating func include(u interval: ScalarInterval, v other: ScalarInterval) {
        u = (min(u.lower, interval.lower), max(u.upper, interval.upper))
        v = (min(v.lower, other.lower), max(v.upper, other.upper))
    }
}
