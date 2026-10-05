import CADCore
import CADGeometry
import CADTopology

/// Validates sewing value invariants using original endpoint enclosures.
package struct OriginalSewingPatchValidator: Sendable {
    let maximumSpanCount: Int
    let maximumSubdivisionDepth: Int
    let remainingSourceDepth: Int
    let maximumAlgebraicDepth: Int
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: (@Sendable (Int) throws -> Void)?

    package func validate(_ patch: BRepSewingFacePatch, tolerance: ModelingTolerance) throws {
        try step()
        try tolerance.validate()
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
            !patch.stableID.isEmpty, !patch.loops.isEmpty else {
            throw failure(.invalidInput, tolerance, "Bounded sewing patch requires original source and supported caller capabilities.")
        }
        try validateParents(patch.parentSubshapeIDs, tolerance: tolerance)
        let support = try PreparedSurfaceDifferentialEncloser(surface: patch.surface,
            tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { try step() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        var outerCount = 0
        for loopIndex in patch.loops.indices {
            try step()
            let loop = patch.loops[loopIndex]
            guard !loop.stableID.isEmpty, loop.edges.count >= 2 else {
                throw failure(.invalidInput, tolerance, "A sewing loop requires a stable identity and ordered edges.")
            }
            if loop.role == .outer { outerCount += 1 }
            for previous in 0..<loopIndex {
                guard try !sameIdentity(loop.stableID, patch.loops[previous].stableID) else {
                    throw failure(.invalidInput, tolerance, "Sewing patch repeats an original loop identity.")
                }
            }
            for index in loop.edges.indices {
                try step()
                let edge = loop.edges[index]
                for previous in 0..<index {
                    guard try !sameIdentity(edge.stableID, loop.edges[previous].stableID) else {
                        throw failure(.invalidInput, tolerance, "Sewing loop repeats an original edge identity.")
                    }
                }
                try validate(edge, support: support, tolerance: tolerance)
                let next = loop.edges[index == loop.edges.count - 1 ? 0 : index + 1]
                guard endpointDistance(edge.endPoint, next.startPoint) <= tolerance.distance else {
                    throw failure(.topologyFailure, tolerance, "Original sewing loop endpoints do not close in their declared order.")
                }
            }
        }
        guard outerCount == 1 else {
            throw failure(.invalidInput, tolerance, "Original sewing patch requires exactly one outer loop.")
        }
    }

    private func validate(_ edge: BRepSewingEdge, support: PreparedSurfaceDifferentialEncloser,
        tolerance: ModelingTolerance) throws {
        try step()
        guard !edge.stableID.isEmpty, edge.startParameter.isFinite, edge.endParameter.isFinite,
            abs(edge.endParameter - edge.startParameter) > max(tolerance.angle, Double.ulpOfOne) else {
            throw failure(.invalidInput, tolerance, "Original sewing edge has invalid identity or native trim.")
        }
        try edge.startPoint.validate(); try edge.endPoint.validate()
        try validateParents(edge.parentSubshapeIDs, tolerance: tolerance)
        try validateParents(edge.startVertexParentSubshapeIDs, tolerance: tolerance)
        try validateParents(edge.endVertexParentSubshapeIDs, tolerance: tolerance)
        let curve = try PreparedCurveDifferentialEncloser(curve: edge.curve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { try step() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        guard try edge.curve.parameterDomain.containsSpan(from: edge.startParameter,
            to: edge.endParameter, tolerance: tolerance) else {
            throw failure(.invalidInput, tolerance, "Original sewing edge trim exceeds its authored domain.")
        }
        if edge.startPoint.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance) {
            let kind = try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
                .kind(curve: edge.curve, from: edge.startParameter, to: edge.endParameter, tolerance: tolerance)
            guard kind != .open else {
                throw failure(.topologyFailure, tolerance, "Coincident sewing endpoints require original closed or singular geometry.")
            }
        }
        try edge.surfaceParameterCurve.validate(on: support.surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        for endpoint in 0..<2 {
            try step()
            let parameter = endpoint == 0 ? edge.startParameter : edge.endParameter
            let position = endpoint == 0 ? edge.startPoint : edge.endPoint
            let span = try ScalarInterval(lower: parameter, upper: parameter)
            let original = try curve.closedNativeJets(over: span, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() },
                consumeStorage: consumeStorage)
            guard let first = original.spans.first else {
                throw failure(.topologyFailure, tolerance, "Original sewing endpoint has no owning source law.")
            }
            var jet = first.jet
            for owner in original.spans.dropFirst() { try step(); jet = jet.union(owner.jet) }
            guard residual(jet.x.value, jet.y.value, jet.z.value, to: position) <= tolerance.distance else {
                throw failure(.topologyFailure, tolerance, "Original sewing endpoint enclosure exceeds modeling distance.")
            }
            let fraction = Double(endpoint)
            let uv = try edge.surfaceParameterCurve.originalParameterBounds(
                over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() },
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            let hosted = try support.positionBounds(over: uv, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() }, consumeStorage: consumeStorage)
            guard residual(hosted.x, hosted.y, hosted.z, to: position) <= tolerance.distance else {
                throw failure(.topologyFailure, tolerance, "Original sewing pcurve endpoint enclosure exceeds modeling distance.")
            }
        }
    }

    private func validateParents(_ parents: [SubshapeID], tolerance: ModelingTolerance) throws {
        for parent in parents {
            try step()
            guard parent.isValid else {
                throw failure(.invalidInput, tolerance, "Original sewing ancestry contains an invalid identity.")
            }
        }
    }

    private func sameIdentity(_ first: String, _ second: String) throws -> Bool {
        for _ in first.utf8 { try step() }
        for _ in second.utf8 { try step() }
        return first == second
    }

    private func residual(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
        _ z: OutwardScalarInterval, to point: Point3D) -> Double {
        let dx = x - .exact(point.x), dy = y - .exact(point.y), dz = z - .exact(point.z)
        return IntervalVector3DBounds(x: dx, y: dy, z: dz).lengthUpperBound
    }

    private func endpointDistance(_ first: Point3D, _ second: Point3D) -> Double {
        residual(.exact(first.x), .exact(first.y), .exact(first.z), to: second)
    }

    private func step() throws { try Task.checkCancellation(); try consumeWork(0) }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
        _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
