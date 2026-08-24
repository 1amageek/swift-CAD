import CADCore
import Foundation

extension BSplineSurface3D {
    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()
        guard case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline inverse projection requires finite parameter domains."
            )
        }
        if let affine = ExactAffineBSplineSurfacePatch(self) {
            return try affine.parameterProjectionResult(
                of: point,
                tolerance: tolerance
            )
        }
        let sourcePatches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: self,
            tolerance: tolerance
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline inverse projection produced no bounded Bezier patches."
            )
        }
        let patches = sourcePatches.map(RationalBezierPointProjectionPatch.init(patch:))
        var bestWitness = try initialWitness(
            patches: patches,
            point: point,
            tolerance: tolerance
        )
        var stack = patches.reversed().map { ProjectionCell(patch: $0, depth: 0) }
        var remainingCells = options.maximumSubdivisionCells
        var remainingCandidates = options.maximumCandidateCount
        var candidates: [ProjectionCandidate] = []
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
            let box = try cell.patch.boundingBox(tolerance: tolerance)
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
                for child in cell.patch.subdivided().reversed() {
                    stack.append(ProjectionCell(patch: child, depth: cell.depth + 1))
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
            )
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
                )
                if canonical.residual < bestWitness.residual {
                    bestWitness = canonical
                }
                if canonical.residual <= tolerance.distance {
                    let candidate = ProjectionCandidate(projection: canonical)
                    if let index = duplicateCandidateIndex(
                        candidate,
                        in: candidates,
                        uBounds: (uLower, uUpper),
                        vBounds: (vLower, vUpper),
                        tolerance: tolerance
                    ) {
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
        let uniqueCandidates = deduplicated(
            candidates,
            sourcePatches: patches,
            tolerance: tolerance
        )
        guard let selected = uniqueCandidates.min(by: projectionOrder) else {
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
        return .projected(try SurfaceParameterProjection(
            u: selected.projection.u,
            v: selected.projection.v,
            point: selected.projection.point,
            residual: selected.projection.residual,
            iterations: selected.projection.iterations
        ))
    }

    private func initialWitness(
        patches: [RationalBezierPointProjectionPatch],
        point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> RefinedProjection {
        var result: RefinedProjection?
        for patch in patches {
            let u = midpoint(patch.uLower, patch.uUpper)
            let v = midpoint(patch.vLower, patch.vUpper)
            let surfacePoint = try self.point(u: u, v: v, tolerance: tolerance)
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
    ) throws -> RefinedProjection {
        var u = initialU
        var v = initialV
        var iterations = 0
        var damping = max(tolerance.relative, Double.ulpOfOne.squareRoot())
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let geometry = try surfaceDerivatives(atU: u, v: v, tolerance: tolerance)
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
            if residualLength <= tolerance.distance,
               hypot(gradientU, gradientV) <= stationarityTolerance {
                break
            }
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
            var accepted = false
            var acceptedU = u
            var acceptedV = v
            var acceptedResidual = residualLength
            for _ in 0..<12 {
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
                    let nextPoint = try self.point(u: nextU, v: nextV, tolerance: tolerance)
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
            let parameterChange = hypot(acceptedU - u, acceptedV - v)
            u = acceptedU
            v = acceptedV
            if parameterChange <= max(tolerance.relative, Double.ulpOfOne * 64.0) {
                break
            }
        }
        let projectedPoint = try self.point(u: u, v: v, tolerance: tolerance)
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
    ) -> [ProjectionCandidate] {
        guard let uLower = sourcePatches.map(\.uLower).min(),
              let uUpper = sourcePatches.map(\.uUpper).max(),
              let vLower = sourcePatches.map(\.vLower).min(),
              let vUpper = sourcePatches.map(\.vUpper).max() else {
            return []
        }
        let baseUResolution = max(
            (uUpper - uLower) * tolerance.relative,
            Double.ulpOfOne * max(1.0, max(abs(uLower), abs(uUpper))) * 128.0
        )
        let baseVResolution = max(
            (vUpper - vLower) * tolerance.relative,
            Double.ulpOfOne * max(1.0, max(abs(vLower), abs(vUpper))) * 128.0
        )
        let ordered = candidates.sorted(by: projectionOrder)
        var result: [ProjectionCandidate] = []
        for candidate in ordered {
            if let index = result.firstIndex(where: { existing in
                abs(existing.projection.u - candidate.projection.u) <= max(
                    baseUResolution,
                    Double.ulpOfOne * max(1.0, abs(candidate.projection.u)) * 128.0
                ) && abs(existing.projection.v - candidate.projection.v) <= max(
                    baseVResolution,
                    Double.ulpOfOne * max(1.0, abs(candidate.projection.v)) * 128.0
                )
            }) {
                if candidate.projection.residual < result[index].projection.residual {
                    result[index] = candidate
                }
            } else {
                result.append(candidate)
            }
        }
        return result
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
    ) -> Int? {
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
        return candidates.firstIndex { existing in
            abs(existing.projection.u - candidate.projection.u) <= uResolution
                && abs(existing.projection.v - candidate.projection.v) <= vResolution
        }
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
