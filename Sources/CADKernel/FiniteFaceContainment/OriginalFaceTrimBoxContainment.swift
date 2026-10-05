import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// A whole connected original UV box stays in one trim region only after
/// every original outer/hole boundary has been excluded from that box.
package struct OriginalFaceTrimBoxContainment: OriginalFaceTrimBoxContaining {
    private struct Cell {
        let lower: Double
        let upper: Double
        let depth: Int
    }

    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int

    package init(remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) {
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    package func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try Self(remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
            .classifyOriginal(box, faceID: faceID, validatedModel: validatedModel,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    package func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> OriginalFaceTrimBoxClassification {
        try classifyOriginal(box, faceID: faceID, validatedModel: validatedModel,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: nil)
    }

    package func classify(_ box: SurfaceParameterBox, in faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try classifyOriginal(box, faceID: faceID, validatedModel: validatedModel,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func classifyOriginal(_ box: SurfaceParameterBox, faceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try Task.checkCancellation()
        try consumeWork(0)
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        guard validatedModel.validationLevel != .modeling, maximumSubdivisionDepth >= 0,
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
              box.u.width.isFinite, box.v.width.isFinite, let face = model.faces[faceID],
              !face.loops.isEmpty else {
            throw failure(.invalidInput, tolerance,
                "Original face-box classification requires an immutable exact face and finite caller bounds.")
        }
        let depthLimit = min(48, maximumSubdivisionDepth)
        var pending = try makeBoundaryStack(depthLimit: depthLimit, tolerance: tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        var outerCount = 0
        for loopID in face.loops {
            try consumeWork(0)
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference("Original face-box classification lost a retained source loop.")
            }
            if loop.role == .outer { outerCount += 1 }
            for coedge in loop.coedges {
                try consumeWork(0)
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.missingReference("An immutable exact face has a missing original pcurve.")
                }
                guard try excludes(box, curve: curve, tolerance: tolerance,
                    maximumDepth: depthLimit, pending: &pending, consumeWork: consumeWork, consumeStorage: consumeStorage) else { return .boundaryOverlap }
            }
        }
        guard outerCount == 1 else {
            throw failure(.invalidInput, tolerance, "An immutable exact finite face needs one outer trim.")
        }
        let center = Point2D(x: box.u.lower * 0.5 + box.u.upper * 0.5,
            y: box.v.lower * 0.5 + box.v.upper * 0.5)
        guard box.u.contains(center.x), box.v.contains(center.y) else {
            throw failure(.resourceLimitExceeded, tolerance, "The original finite UV box has no representable station.")
        }
        var insideOuter = false
        for loopID in face.loops {
            try consumeWork(0)
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("An original face-box loop disappeared.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The unchanged-source receipt
            // closes endpoint/source admission work and retains original loop
            // backing here. Query arrays forward bytes, while specialized lower
            // derivative/chart scratch still prevents complete storage accounting.
            let predicate = try CertifiedSurfaceParameterLoopPredicate(loopID: loopID,
                validatedModel: validatedModel, maximumSubdivisionDepth: depthLimit,
                maximumAlgebraicDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork)
            switch try predicate.signedWinding(center, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage, maximumSubdivisionDepth: depthLimit) {
            case .boundary: return .boundaryOverlap
            case let .winding(winding):
                if loop.role == .outer { insideOuter = winding != 0 }
                else if winding != 0 { return .outside }
            }
        }
        return insideOuter ? .inside : .outside
    }

    package func containsStrictly(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> Bool {
        try classify(box, inAdmitted: patch, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork) == .inside
    }

    package func classify(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try Self(remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
            .classifyPatch(box, patch: patch, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    package func classify(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> OriginalFaceTrimBoxClassification {
        try classifyPatch(box, patch: patch, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: nil)
    }

    package func classify(_ box: SurfaceParameterBox,
        inAdmitted patch: BRepSewingFacePatch, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try classifyPatch(box, patch: patch, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func classifyPatch(_ box: SurfaceParameterBox, patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFaceTrimBoxClassification {
        try Task.checkCancellation()
        try consumeWork(0)
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0,
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth), box.u.width.isFinite, box.v.width.isFinite,
              !patch.loops.isEmpty else {
            throw failure(.invalidInput, tolerance,
                "Original trim box containment needs finite original bounds and caller depth.")
        }
        let depthLimit = min(48, maximumSubdivisionDepth)
        var pending = try makeBoundaryStack(depthLimit: depthLimit, tolerance: tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        var outerCount = 0
        for loop in patch.loops {
            try consumeWork(0)
            if loop.role == .outer { outerCount += 1 }
            guard !loop.edges.isEmpty else {
                throw failure(.invalidInput, tolerance, "An original trim loop has no boundaries.")
            }
            for edge in loop.edges {
                try consumeWork(0)
                guard try excludes(box, curve: edge.surfaceParameterCurve,
                    tolerance: tolerance, maximumDepth: depthLimit,
                    pending: &pending, consumeWork: consumeWork, consumeStorage: consumeStorage) else { return .boundaryOverlap }
            }
        }
        guard outerCount == 1 else {
            throw failure(.invalidInput, tolerance, "An admitted finite face requires exactly one outer trim.")
        }
        let center = Point2D(x: box.u.lower + box.u.width * 0.5,
            y: box.v.lower + box.v.width * 0.5)
        guard box.u.contains(center.x), box.v.contains(center.y) else {
            throw failure(.resourceLimitExceeded, tolerance, "A finite original box has no numerical interior representative.")
        }
        var insideOuter = false
        for loop in patch.loops {
            try consumeWork(0)
            var curves: [SurfaceParameterCurve] = []
            if let consumeStorage {
                let bytes = loop.edges.count.multipliedReportingOverflow(by: MemoryLayout<SurfaceParameterCurve>.stride)
                guard !bytes.overflow else {
                    throw failure(.resourceLimitExceeded, tolerance, "Original patch curve-copy byte admission overflowed.")
                }
                try consumeStorage(bytes.partialValue)
                curves.reserveCapacity(loop.edges.count)
            }
            for edge in loop.edges {
                try consumeWork(0)
                curves.append(edge.surfaceParameterCurve)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original support-bound chart and
            // endpoint preparation now consumes caller work/depth/bytes. Full F8
            // storage still needs specialized lower derivative/chart scratch producers;
            // modified patch correspondence remains its separate admission premise.
            let predicate = try CertifiedSurfaceParameterLoopPredicate(curves: curves,
                on: patch.surface, tolerance: tolerance,
                maximumSubdivisionDepth: depthLimit, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            switch try predicate.signedWinding(center, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage, maximumSubdivisionDepth: depthLimit) {
            case .boundary:
                return .boundaryOverlap
            case let .winding(winding):
                if loop.role == .outer { insideOuter = winding != 0 }
                else if winding != 0 { return .outside }
            }
        }
        return insideOuter ? .inside : .outside
    }

    private func makeBoundaryStack(depthLimit: Int, tolerance: ModelingTolerance,
        consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> [Cell] {
        try Task.checkCancellation()
        try consumeWork(0)
        var result: [Cell] = []
        if let consumeStorage {
            let capacity = depthLimit.addingReportingOverflow(1)
            let bytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<Cell>.stride)
            guard depthLimit >= 0, !capacity.overflow, !bytes.overflow else {
                throw failure(.resourceLimitExceeded, tolerance, "Original boundary DFS stack byte admission overflowed.")
            }
            try consumeStorage(bytes.partialValue)
            result.reserveCapacity(capacity.partialValue)
        }
        return result
    }

    private func excludes(_ box: SurfaceParameterBox, curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance, maximumDepth: Int,
        pending: inout [Cell],
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> Bool {
        pending.removeAll(keepingCapacity: true)
        pending.append(Cell(lower: 0, upper: 1, depth: 0))
        var visited = 0
        while let cell = pending.popLast() {
            try Task.checkCancellation()
            try consumeWork(cell.depth)
            visited += 1
            guard visited <= 131_072, cell.depth <= maximumDepth else {
                throw failure(.resourceLimitExceeded, tolerance,
                    "Original trim/box separation exhausted its existing cell/depth ceiling.")
            }
            let baseDepth = cell.depth
            let encloser = CertifiedSurfaceParameterCurveEncloser(
                maximumSubdivisionDepth: maximumDepth - baseDepth,
                consumeWork: { depth in try consumeWork(baseDepth + depth) },
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth,
                remainingSourceDepth: remainingSourceDepth)
            let bounds = try encloser.enclosures(for: curve,
                fromNormalizedFraction: cell.lower, toNormalizedFraction: cell.upper,
                maximumWidth: Double.greatestFiniteMagnitude, tolerance: tolerance)
            guard !bounds.isEmpty else {
                throw failure(.classificationFailure, tolerance,
                    "Original trim/box separation returned empty source coverage.")
            }
            var separated = true
            for bound in bounds {
                try consumeWork(cell.depth)
                if bound.u.upper < box.u.lower || bound.u.lower > box.u.upper
                    || bound.v.upper < box.v.lower || bound.v.lower > box.v.upper { continue }
                separated = false
                // This nonempty original parameter interval has its entire image
                // inside the box, so the box contains an actual trim boundary.
                if bound.u.lower >= box.u.lower, bound.u.upper <= box.u.upper,
                   bound.v.lower >= box.v.lower, bound.v.upper <= box.v.upper { return false }
            }
            if separated { continue }
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            guard cell.depth < maximumDepth, middle > cell.lower, middle < cell.upper,
                  pending.count < 131_072 else {
                throw failure(.resourceLimitExceeded, tolerance,
                    "Original trim/box contact cannot be excluded within caller admission.")
            }
            pending.append(Cell(lower: middle, upper: cell.upper, depth: cell.depth + 1))
            pending.append(Cell(lower: cell.lower, upper: middle, depth: cell.depth + 1))
        }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
        _ message: String) -> KernelError {
        KernelError(phase: .classification, code: code, tolerance: tolerance, message: message)
    }
}
