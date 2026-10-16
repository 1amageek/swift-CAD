import CADCore
import CADGeometry

/// Proves repeated edge uses against the original periodic chart laws.
package struct PeriodicFaceSeamValidator {
    package init() {}

    private func rootExecution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }

    package func validateRepeatedEdgeUses(in loop: Loop, on surface: Surface3D,
        tolerance: ModelingTolerance) throws {
        var execution = try rootExecution()
        try validateRepeatedEdgeUses(in: loop, on: surface, tolerance: tolerance,
            maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
    }

    package func validateRepeatedEdgeUses(in loop: Loop, on surface: Surface3D,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws {
        if let edgeID = try invalidRepeatedEdge(in: loop, on: surface, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) {
            throw TopologyError.duplicateTopologyReference(
                "Loop \(loop.id) contains repeated edge \(edgeID) that is not an original periodic seam.")
        }
    }

    package func certifiesRepeatedEdgeUses(in loop: Loop, on surface: Surface3D,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try rootExecution()
        return try certifiesRepeatedEdgeUses(in: loop, on: surface, tolerance: tolerance,
            maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
    }

    package func certifiesRepeatedEdgeUses(in loop: Loop, on surface: Surface3D,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try invalidRepeatedEdge(in: loop, on: surface, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) == nil
    }

    private func invalidRepeatedEdge(in loop: Loop, on surface: Surface3D,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int?,
        using execution: inout OriginalQueryExecution) throws -> EdgeID? {
        try tolerance.validate()
        for index in loop.coedges.indices {
            try execution.consumeWork(1)
            let first = loop.coedges[index]
            var appearedEarlier = false
            for earlier in 0..<index {
                try execution.consumeWork(1)
                if loop.coedges[earlier].edgeID == first.edgeID { appearedEarlier = true; break }
            }
            if appearedEarlier { continue }
            var second: Coedge?
            var count = 1
            for later in (index + 1)..<loop.coedges.count {
                try execution.consumeWork(1)
                if loop.coedges[later].edgeID == first.edgeID {
                    count += 1; second = loop.coedges[later]
                }
            }
            if count == 1 { continue }
            guard count == 2, let second, first.orientation != second.orientation,
                let a = first.surfaceParameterCurve, let b = second.surfaceParameterCurve,
                try certifiesOppositeSeamCurves(a, b, on: surface, tolerance: tolerance,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) else {
                return first.edgeID
            }
        }
        return nil
    }

    package func certifiesOppositeSeamCurves(_ firstCurve: SurfaceParameterCurve,
        _ secondCurve: SurfaceParameterCurve, on surface: Surface3D,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try rootExecution()
        return try certifiesOppositeSeamCurves(firstCurve, secondCurve, on: surface,
            tolerance: tolerance, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
    }

    package func certifiesOppositeSeamCurves(_ firstCurve: SurfaceParameterCurve,
        _ secondCurve: SurfaceParameterCurve, on surface: Surface3D,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> Bool {
        try OriginalPeriodicSeamProof.proves(first: firstCurve, second: secondCurve,
            on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }
}
