import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

extension BSplineSurface3D {
    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterProjectionResult(of: point, options: options, tolerance: tolerance, using: &execution)
    }

    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterProjectionResult {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance, using: &execution)
        try point.validate()
        let uLower = uKnots[uDegree], uUpper = uKnots[uControlPointCount]
        let vLower = vKnots[vDegree], vUpper = vKnots[vControlPointCount]
        if let affine = try ExactAffineBSplineSurfacePatch(self, using: &execution) {
            return try affine.parameterProjectionResult(
                of: point,
                tolerance: tolerance
            , using: &execution)
        }
        let sourcePatches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: self,
            tolerance: tolerance
        , using: &execution)
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline inverse projection produced no bounded Bezier patches."
            )
        }
        let patches = try OriginalCoefficientAllocation.map(elements: sourcePatches, using: &execution) { patch, execution in
            try RationalBezierPointProjectionPatch(patch: patch, using: &execution)
        }
        var bestWitness = try initialWitness(
            patches: patches,
            point: point,
            tolerance: tolerance
        , using: &execution)
        var stack = try OriginalCoefficientAllocation.map(elements: patches.indices.reversed(), using: &execution) { index, _ in
            ProjectionCell(patch: patches[index], depth: 0, sourcePatchIndex: index)
        }
        var stackCapacity = stack.count
        var preparedOriginalPatches: [Int: RationalBezierSurfaceJetEncloser.PreparedPatch] = [:]
        var preparedCapacity = 0
        var remainingCells = options.maximumSubdivisionCells
        var remainingCandidates = options.maximumCandidateCount
        var candidates: [ProjectionCandidate] = []
        var candidateCapacity = 0
        var unresolvedResidual: Double?

        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw resourceLimit(
                    residual: bestWitness.residual,
                    tolerance: tolerance,
                    message: "B-spline inverse projection exceeded its subdivision cell budget."
                )
            }
            remainingCells -= 1
            try execution.visitGeometricCell(depth: cell.depth)
            let box = try cell.patch.boundingBox(tolerance: tolerance, using: &execution)
            let distanceLowerBound = boundingBoxDistanceLowerBound(
                point: point,
                box: box
            )
            guard distanceLowerBound <= tolerance.distance else { continue }
            let diameter = boundingBoxDiameterUpperBound(box)
            let uScale = max(1.0, abs(cell.patch.uLower), abs(cell.patch.uUpper))
            let vScale = max(1.0, abs(cell.patch.vLower), abs(cell.patch.vUpper))
            let uResolution = max(
                tolerance.relative * uScale,
                Double.ulpOfOne * uScale * 128.0
            )
            let vResolution = max(
                tolerance.relative * vScale,
                Double.ulpOfOne * vScale * 128.0
            )
            let requiresSubdivision = cell.depth < options.maximumSubdivisionDepth
                && diameter > tolerance.distance * 0.25
                && (
                    cell.patch.uUpper - cell.patch.uLower > uResolution
                        || cell.patch.vUpper - cell.patch.vLower > vResolution
                )
            if requiresSubdivision {
                for child in try cell.patch.subdivided(using: &execution).reversed() {
                    try execution.consumeWork(1)
                    try OriginalCoefficientAllocation.reserveAppend(to: &stack, capacity: &stackCapacity, using: &execution)
                    stack.append(ProjectionCell(patch: child, depth: cell.depth + 1, sourcePatchIndex: cell.sourcePatchIndex))
                }
                continue
            }
            let localRefined = try refine(
                u: midpoint(cell.patch.uLower, cell.patch.uUpper),
                v: midpoint(cell.patch.vLower, cell.patch.vUpper),
                point: point,
                uBounds: (cell.patch.uLower, cell.patch.uUpper),
                vBounds: (cell.patch.vLower, cell.patch.vUpper),
                options: options,
                tolerance: tolerance
            , using: &execution)
            if localRefined.residual < bestWitness.residual {
                bestWitness = localRefined
            }
            let mayContainProjection = localRefined.residual <= tolerance.distance
                || localRefined.residual - diameter <= tolerance.distance
            if mayContainProjection {
                let canonical = try refine(
                    u: localRefined.u,
                    v: localRefined.v,
                    point: point,
                    uBounds: (uLower, uUpper),
                    vBounds: (vLower, vUpper),
                    options: options,
                    tolerance: tolerance
                , using: &execution)
                if canonical.residual < bestWitness.residual {
                    bestWitness = canonical
                }
                if canonical.residual <= tolerance.distance {
                    if isUPeriodic || isVPeriodic {
                        // Rank at a witness does not rule out another root in its leaf.
                        _ = try normal(u: canonical.u, v: canonical.v, tolerance: tolerance, using: &execution)
                        let encloser = RationalBezierSurfaceJetEncloser()
                        let prepared: RationalBezierSurfaceJetEncloser.PreparedPatch
                        if let cached = preparedOriginalPatches[cell.sourcePatchIndex] {
                            prepared = cached
                        } else {
                            prepared = try encloser.prepare(sourcePatches[cell.sourcePatchIndex], tolerance: tolerance, using: &execution)
                            if preparedOriginalPatches.count == preparedCapacity {
                                let next = preparedCapacity == 0 ? 1 : try exactScalarCount(preparedCapacity, 2, multiply: true)
                                try OriginalCoefficientAllocation.reserve(count: next,
                                    of: (Int, RationalBezierSurfaceJetEncloser.PreparedPatch).self, using: &execution)
                                preparedOriginalPatches.reserveCapacity(next)
                                preparedCapacity = next
                            }
                            preparedOriginalPatches[cell.sourcePatchIndex] = prepared
                        }
                        let sourceJet = try encloser.enclosure(of: prepared,
                            u: ScalarInterval(lower: cell.patch.uLower, upper: cell.patch.uUpper),
                            v: ScalarInterval(lower: cell.patch.vLower, upper: cell.patch.vUpper),
                            tolerance: tolerance, using: &execution)
                        let difference = sourceJet + .constant(.origin - point)
                        let squaredDistance = difference.dot(difference)
                        let uu = squaredDistance.secondDerivativeUU
                        let uv = squaredDistance.secondDerivativeUV
                        let vv = squaredDistance.secondDerivativeVV
                        let determinant = uu * vv - uv * uv
                        guard uu.lower > 0, vv.lower > 0, determinant.lower > 0 else {
                            throw resourceLimit(residual: canonical.residual, tolerance: tolerance,
                                message: "Periodic inverse projection could not certify a unique root throughout a remaining Bezier leaf.")
                        }
                    }
                    let candidate = ProjectionCandidate(projection: canonical)
                    if let index = try duplicateCandidateIndex(
                        candidate,
                        in: candidates,
                        uBounds: (uLower, uUpper),
                        vBounds: (vLower, vUpper),
                        tolerance: tolerance
                    , using: &execution) {
                        if canonical.residual < candidates[index].projection.residual {
                            candidates[index] = candidate
                        }
                    } else {
                        guard remainingCandidates > 0 else {
                            throw resourceLimit(
                                residual: canonical.residual,
                                tolerance: tolerance,
                                message: "B-spline inverse projection exceeded its distinct-candidate budget."
                            )
                        }
                        remainingCandidates -= 1
                        try OriginalCoefficientAllocation.reserveAppend(to: &candidates, capacity: &candidateCapacity, using: &execution)
                        candidates.append(candidate)
                    }
                    continue
                }
            }
            if localRefined.residual - diameter <= tolerance.distance {
                unresolvedResidual = min(
                    unresolvedResidual ?? localRefined.residual,
                    localRefined.residual
                )
            }
        }

        if let unresolvedResidual {
            throw resourceLimit(
                residual: unresolvedResidual,
                tolerance: tolerance,
                message: "B-spline inverse projection could not certify all remaining control-hull candidates."
            )
        }
        let uniqueCandidates = try deduplicated(
            candidates,
            sourcePatches: patches,
            tolerance: tolerance
        , using: &execution)
        guard let selected = try uniqueCandidates.min(by: { try execution.consumeWork(1); return projectionOrder($0, $1) }) else {
            return .outsideTolerance(residual: bestWitness.residual)
        }
        guard uniqueCandidates.count == 1 else {
            throw KernelError(
                phase: .geometry,
                code: .ambiguousSelection,
                residual: selected.projection.residual,
                tolerance: tolerance,
                message: "B-spline inverse projection has multiple distinct parameter solutions."
            )
        }
        let projection = try SurfaceParameterProjection(
            u: selected.projection.u,
            v: selected.projection.v,
            point: selected.projection.point,
            residual: selected.projection.residual,
            iterations: selected.projection.iterations
        )
        return .projected(try representativeProjection(projection, target: point,
            requiringInverseTolerance: true, tolerance: tolerance, using: &execution))
    }

    private func initialWitness(
        patches: [RationalBezierPointProjectionPatch],
        point: Point3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> RefinedProjection {
        try execution.consumeWork(1)
        var result: RefinedProjection?
        for patch in patches {
            try execution.consumeWork(1)
            let u = midpoint(patch.uLower, patch.uUpper)
            let v = midpoint(patch.vLower, patch.vUpper)
            let surfacePoint = try self.point(u: u, v: v, tolerance: tolerance, using: &execution)
            let candidate = RefinedProjection(
                u: u,
                v: v,
                point: surfacePoint,
                residual: outwardLength(surfacePoint - point),
                iterations: 0
            )
            if candidate.residual < (result?.residual ?? .infinity) {
                result = candidate
            }
        }
        guard let result else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline inverse projection could not construct an initial residual witness."
            )
        }
        return result
    }

    private func refine(
        u initialU: Double,
        v initialV: Double,
        point: Point3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> RefinedProjection {
        try execution.consumeWork(1)
        var u = initialU
        var v = initialV
        var iterations = 0
        var damping = max(tolerance.relative, Double.ulpOfOne.squareRoot())
        let uResolution = max(
            (uBounds.upper - uBounds.lower) * tolerance.relative,
            Double.ulpOfOne * max(1.0, abs(uBounds.lower), abs(uBounds.upper)) * 128.0
        )
        let vResolution = max(
            (vBounds.upper - vBounds.lower) * tolerance.relative,
            Double.ulpOfOne * max(1.0, abs(vBounds.lower), abs(vBounds.upper)) * 128.0
        )
        for iteration in 0..<options.maximumIterations {
            try execution.consumeWork(1)
            iterations = iteration + 1
            let geometry = try surfaceDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
            let residual = geometry.position - point
            let gradientU = residual.dot(geometry.tangentU)
            let gradientV = residual.dot(geometry.tangentV)
            let residualLength = outwardLength(residual)
            let gradientScale = max(
                1.0,
                max(geometry.tangentU.length, geometry.tangentV.length)
            )
            let stationarityTolerance = max(
                tolerance.distance * tolerance.relative * gradientScale,
                Double.ulpOfOne * gradientScale * 128.0
            )
            let hessianUU = geometry.tangentU.dot(geometry.tangentU)
                + residual.dot(geometry.secondDerivativeUU)
            let hessianUV = geometry.tangentU.dot(geometry.tangentV)
                + residual.dot(geometry.secondDerivativeUV)
            let hessianVV = geometry.tangentV.dot(geometry.tangentV)
                + residual.dot(geometry.secondDerivativeVV)
            let scale = max(
                1.0,
                max(abs(hessianUU), max(abs(hessianUV), abs(hessianVV)))
            )
            // A small spatial gradient alone does not resolve parameters on a small surface.
            // Use the undamped correction and the same axis resolutions as candidate dedup;
            // this is numerical stopping, not a root existence or uniqueness certificate.
            let determinant = hessianUU * hessianVV - hessianUV * hessianUV
            if residualLength <= tolerance.distance,
               hypot(gradientU, gradientV) <= stationarityTolerance,
               hessianUU > 0.0, hessianVV > 0.0,
               determinant.isFinite, determinant > Double.ulpOfOne * scale * scale {
                let deltaU = (hessianVV * gradientU - hessianUV * gradientV) / determinant
                let deltaV = (hessianUU * gradientV - hessianUV * gradientU) / determinant
                if deltaU.isFinite, deltaV.isFinite {
                    let nextU = min(max(u - deltaU, uBounds.lower), uBounds.upper)
                    let nextV = min(max(v - deltaV, vBounds.lower), vBounds.upper)
                    if abs(nextU - u) <= uResolution, abs(nextV - v) <= vResolution {
                        break
                    }
                }
            }
            var accepted = false
            var acceptedU = u
            var acceptedV = v
            var acceptedResidual = residualLength
            for _ in 0..<12 {
                try execution.consumeWork(1)
                let diagonalDamping = damping * scale
                let a = hessianUU + diagonalDamping
                let d = hessianVV + diagonalDamping
                let determinant = a * d - hessianUV * hessianUV
                if determinant.isFinite,
                   abs(determinant) > Double.ulpOfOne * scale * scale {
                    let deltaU = (d * gradientU - hessianUV * gradientV) / determinant
                    let deltaV = (a * gradientV - hessianUV * gradientU) / determinant
                    let nextU = min(max(u - deltaU, uBounds.lower), uBounds.upper)
                    let nextV = min(max(v - deltaV, vBounds.lower), vBounds.upper)
                    let nextPoint = try self.point(u: nextU, v: nextV, tolerance: tolerance, using: &execution)
                    let nextResidual = outwardLength(nextPoint - point)
                    if nextResidual < acceptedResidual {
                        accepted = true
                        acceptedU = nextU
                        acceptedV = nextV
                        acceptedResidual = nextResidual
                        damping = max(damping * 0.25, Double.ulpOfOne)
                        break
                    }
                }
                damping *= 8.0
            }
            guard accepted else { break }
            u = acceptedU
            v = acceptedV
            // A heavily damped step may be tiny while the undamped correction is unresolved.
            // The next existing-budget iteration applies the conditioning-aware stopping test.
        }
        let projectedPoint = try self.point(u: u, v: v, tolerance: tolerance, using: &execution)
        return RefinedProjection(
            u: u,
            v: v,
            point: projectedPoint,
            residual: outwardLength(projectedPoint - point),
            iterations: iterations
        )
    }

    private func deduplicated(
        _ candidates: [ProjectionCandidate],
        sourcePatches: [RationalBezierPointProjectionPatch],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [ProjectionCandidate] {
        try execution.consumeWork(1)
        guard let first = sourcePatches.first else { return [] }
        var uLower = first.uLower, uUpper = first.uUpper
        var vLower = first.vLower, vUpper = first.vUpper
        for patch in sourcePatches.dropFirst() {
            try execution.consumeWork(1)
            if patch.uLower < uLower { uLower = patch.uLower }
            if uUpper < patch.uUpper { uUpper = patch.uUpper }
            if patch.vLower < vLower { vLower = patch.vLower }
            if vUpper < patch.vUpper { vUpper = patch.vUpper }
        }
        let ordered = try orderedCandidates(candidates, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: candidates.count, of: ProjectionCandidate.self, using: &execution)
        var result: [ProjectionCandidate] = []; result.reserveCapacity(candidates.count)
        for candidate in ordered {
            try execution.consumeWork(1)
            if let index = try duplicateCandidateIndex(candidate, in: result,
                uBounds: (uLower, uUpper), vBounds: (vLower, vUpper), tolerance: tolerance, using: &execution) {
                if candidate.projection.residual < result[index].projection.residual {
                    result[index] = candidate
                }
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    /// Bottom-up stable merge retains the existing residual/u/v ordering and left-first ties.
    private func orderedCandidates(_ candidates: [ProjectionCandidate],
        using execution: inout OriginalQueryExecution) throws -> [ProjectionCandidate] {
        var ordered = try OriginalCoefficientAllocation.map(elements: candidates, using: &execution) { value, _ in value }
        guard ordered.count > 1 else { return ordered }
        var scratch = try OriginalCoefficientAllocation.map(elements: candidates, using: &execution) { value, _ in value }
        var width = 1
        while width < ordered.count {
            var start = 0
            while start < ordered.count {
                let middle = start + min(width, ordered.count - start)
                let end = middle + min(width, ordered.count - middle)
                var left = start, right = middle, output = start
                while left < middle || right < end {
                    try execution.consumeWork(1)
                    let takeRight: Bool
                    if left == middle { takeRight = true }
                    else if right == end { takeRight = false }
                    else {
                        try execution.consumeWork(1)
                        takeRight = projectionOrder(ordered[right], ordered[left])
                    }
                    if takeRight { scratch[output] = ordered[right]; right += 1 }
                    else { scratch[output] = ordered[left]; left += 1 }
                    output += 1
                }
                start = end
            }
            swap(&ordered, &scratch)
            if width > ordered.count / 2 { break }
            width *= 2
        }
        return ordered
    }

    private func projectionOrder(
        _ first: ProjectionCandidate,
        _ second: ProjectionCandidate
    ) -> Bool {
        if first.projection.residual != second.projection.residual {
            return first.projection.residual < second.projection.residual
        }
        if first.projection.u != second.projection.u {
            return first.projection.u < second.projection.u
        }
        return first.projection.v < second.projection.v
    }

    private func duplicateCandidateIndex(
        _ candidate: ProjectionCandidate,
        in candidates: [ProjectionCandidate],
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Int? {
        try execution.consumeWork(1)
        let uResolution = max(
            (uBounds.upper - uBounds.lower) * tolerance.relative,
            Double.ulpOfOne
                * max(1.0, abs(uBounds.lower), abs(uBounds.upper)) * 128.0
        )
        let vResolution = max(
            (vBounds.upper - vBounds.lower) * tolerance.relative,
            Double.ulpOfOne
                * max(1.0, abs(vBounds.lower), abs(vBounds.upper)) * 128.0
        )
        return try candidates.firstIndex { existing in
            try execution.consumeWork(1)
            return parameterDistance(existing.projection.u, candidate.projection.u, direction: .u) <= uResolution
                && parameterDistance(existing.projection.v, candidate.projection.v, direction: .v) <= vResolution
        }
    }

    private func parameterDistance(_ a: Double, _ b: Double, direction: SurfaceParameterDirection) -> Double {
        let distance = abs(a - b)
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic else { return distance }
        let knots = direction == .u ? uKnots : vKnots
        let degree = direction == .u ? uDegree : vDegree
        let count = direction == .u ? uControlPointCount : vControlPointCount
        return min(distance, abs(knots[count] - knots[degree] - distance))
    }

    private func boundingBoxDistanceLowerBound(
        point: Point3D,
        box: BoundingBox3D
    ) -> Double {
        let x = axisDistanceLowerBound(
            value: point.x,
            lower: box.minimum.x,
            upper: box.maximum.x
        )
        let y = axisDistanceLowerBound(
            value: point.y,
            lower: box.minimum.y,
            upper: box.maximum.y
        )
        let z = axisDistanceLowerBound(
            value: point.z,
            lower: box.minimum.z,
            upper: box.maximum.z
        )
        let squared = max(
            0.0,
            ((x * x).nextDown + (y * y).nextDown + (z * z).nextDown).nextDown
        )
        return sqrt(squared).nextDown
    }

    private func axisDistanceLowerBound(
        value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        if value < lower { return max(0.0, (lower - value).nextDown) }
        if value > upper { return max(0.0, (value - upper).nextDown) }
        return 0.0
    }

    private func boundingBoxDiameterUpperBound(_ box: BoundingBox3D) -> Double {
        let size = box.size
        let x = abs(size.x).nextUp
        let y = abs(size.y).nextUp
        let z = abs(size.z).nextUp
        return sqrt((x * x + y * y + z * z).nextUp).nextUp
    }

    private func outwardLength(_ value: Vector3D) -> Double {
        value.length.nextUp
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func resourceLimit(
        residual: Double?,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private struct ProjectionCell: Sendable {
        let patch: RationalBezierPointProjectionPatch
        let depth: Int
        let sourcePatchIndex: Int
    }

    private struct ProjectionCandidate: Sendable {
        let projection: RefinedProjection
    }

    private struct RefinedProjection: Sendable {
        let u: Double
        let v: Double
        let point: Point3D
        let residual: Double
        let iterations: Int
    }
}
