import CADCore
import Foundation

extension BSplineCurve3D {
    package struct ParameterProjector: Sendable {
        fileprivate let curve: BSplineCurve3D
        fileprivate let globalLower: Double
        fileprivate let globalUpper: Double
        fileprivate let hasEquivalentEndpoints: Bool
        fileprivate let patches: [RationalBezierCurvePointProjectionPatch]
        fileprivate let options: CurveParameterProjectionOptions
        fileprivate let tolerance: ModelingTolerance

        package func project(_ point: Point3D) throws -> CurveParameterProjection {
            try curve.parameterProjection(of: point, using: self)
        }
    }

    func parameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()
        if let exactLinearProjection = try exactLinearParameterProjection(
            of: point,
            options: options,
            tolerance: tolerance
        ) {
            return exactLinearProjection
        }
        return try makeParameterProjector(
            options: options,
            tolerance: tolerance
        ).project(point)
    }

    private func exactLinearParameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection? {
        guard degree == 1,
              controlPoints.count == 2,
              case let .closed(domainLower, domainUpper) = domain else {
            return nil
        }
        let chord = controlPoints[1] - controlPoints[0]
        let squaredLength = chord.dot(chord)
        guard squaredLength > tolerance.distance * tolerance.distance else {
            return nil
        }
        let length = sqrt(squaredLength)
        let rawFraction = (point - controlPoints[0]).dot(chord) / squaredLength
        let weightScale = max(weights[0], weights[1]) / min(weights[0], weights[1])
        let parameterTolerance = max(
            domain.parameterResolution(tolerance: tolerance),
            tolerance.angle,
            tolerance.distance / length * (domainUpper - domainLower) * weightScale
        )
        guard rawFraction >= -tolerance.distance / length,
              rawFraction <= 1.0 + tolerance.distance / length else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Point projects outside the exact linear B-spline segment."
            )
        }
        let fraction = min(max(rawFraction, 0.0), 1.0)
        let denominator = (1.0 - fraction) * weights[1]
            + fraction * weights[0]
        guard denominator.isFinite,
              denominator > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Exact linear B-spline projection produced a singular rational parameter."
            )
        }
        let basisParameter = fraction * weights[0] / denominator
        var parameter = domainLower
            + (domainUpper - domainLower) * basisParameter
        let allowedLower = max(domainLower, options.parameterRange?.lower ?? domainLower)
        let allowedUpper = min(domainUpper, options.parameterRange?.upper ?? domainUpper)
        guard allowedUpper >= allowedLower,
              parameter >= allowedLower - parameterTolerance,
              parameter <= allowedUpper + parameterTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Exact linear B-spline projection lies outside the requested parameter range."
            )
        }
        parameter = min(max(parameter, allowedLower), allowedUpper)
        let projectedPoint = try pointAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
        let residual = (point - projectedPoint).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Point does not lie on the exact linear B-spline within tolerance."
            )
        }
        return try CurveParameterProjection(
            parameter: parameter,
            point: projectedPoint,
            residual: residual,
            iterations: 0
        )
    }

    package func makeParameterProjector(
        options: CurveParameterProjectionOptions = CurveParameterProjectionOptions(),
        tolerance: ModelingTolerance
    ) throws -> ParameterProjector {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        let searchCurve: BSplineCurve3D
        if let range = options.parameterRange,
           parameterRange(range, matches: domain, tolerance: tolerance) == false {
            searchCurve = try trimmed(
                from: range.lower,
                to: range.upper,
                tolerance: tolerance
            )
        } else {
            searchCurve = self
        }
        guard case let .closed(globalLower, globalUpper) = searchCurve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline inverse projection requires a bounded parameter domain."
            )
        }
        let hasEquivalentEndpoints = try searchCurve.pointAssumingValid(
            at: globalLower,
            tolerance: tolerance
        ).isApproximatelyEqual(
            to: searchCurve.pointAssumingValid(
                at: globalUpper,
                tolerance: tolerance
            ),
            tolerance: tolerance.distance
        )
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: searchCurve,
            tolerance: tolerance
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline inverse projection produced no bounded Bezier spans."
            )
        }
        return ParameterProjector(
            curve: searchCurve,
            globalLower: globalLower,
            globalUpper: globalUpper,
            hasEquivalentEndpoints: hasEquivalentEndpoints,
            patches: sourcePatches.map(
                RationalBezierCurvePointProjectionPatch.init(patch:)
            ),
            options: options,
            tolerance: tolerance
        )
    }

    private func parameterProjection(
        of point: Point3D,
        using projector: ParameterProjector
    ) throws -> CurveParameterProjection {
        try point.validate()
        let globalLower = projector.globalLower
        let globalUpper = projector.globalUpper
        let hasEquivalentEndpoints = projector.hasEquivalentEndpoints
        let patches = projector.patches
        let options = projector.options
        let tolerance = projector.tolerance
        var bestWitness = try initialWitness(
            patches: patches,
            point: point,
            tolerance: tolerance
        )
        var stack = patches.reversed().map { ProjectionCell(patch: $0, depth: 0) }
        var remainingCells = options.maximumSubdivisionCells
        var remainingCandidates = options.maximumCandidateCount
        var candidates: [RefinedProjection] = []
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
            let lowerBound = boundingBoxDistanceLowerBound(point: point, box: box)
            guard lowerBound <= tolerance.distance else { continue }
            let diameter = boundingBoxDiameterUpperBound(box)
            let parameterScale = max(
                1.0,
                abs(cell.patch.lower),
                abs(cell.patch.upper)
            )
            let parameterResolution = max(
                tolerance.relative * parameterScale,
                Double.ulpOfOne * parameterScale * 128.0
            )
            let requiresSubdivision = cell.depth < options.maximumSubdivisionDepth
                && diameter > tolerance.distance * 0.25
                && cell.patch.upper - cell.patch.lower > parameterResolution
            if requiresSubdivision {
                for child in cell.patch.subdivided().reversed() {
                    stack.append(ProjectionCell(patch: child, depth: cell.depth + 1))
                }
                continue
            }

            let local = try refine(
                initialParameter: midpoint(cell.patch.lower, cell.patch.upper),
                bounds: (cell.patch.lower, cell.patch.upper),
                point: point,
                options: options,
                tolerance: tolerance
            )
            if local.residual < bestWitness.residual {
                bestWitness = local
            }
            let mayContainProjection = local.residual <= tolerance.distance
                || local.residual - diameter <= tolerance.distance
            if mayContainProjection {
                let canonical = try refine(
                    initialParameter: local.parameter,
                    bounds: (globalLower, globalUpper),
                    point: point,
                    options: options,
                    tolerance: tolerance
                )
                if canonical.residual < bestWitness.residual {
                    bestWitness = canonical
                }
                if canonical.residual <= tolerance.distance {
                    if let index = duplicateCandidateIndex(
                        canonical,
                        in: candidates,
                        lower: globalLower,
                        upper: globalUpper,
                        hasEquivalentEndpoints: hasEquivalentEndpoints,
                        tolerance: tolerance
                    ) {
                        candidates[index] = preferredCandidate(
                            candidates[index],
                            canonical,
                            lower: globalLower,
                            upper: globalUpper,
                            hasEquivalentEndpoints: hasEquivalentEndpoints,
                            tolerance: tolerance
                        )
                    } else {
                        guard remainingCandidates > 0 else {
                            throw resourceLimit(
                                residual: canonical.residual,
                                tolerance: tolerance,
                                message: "B-spline inverse projection exceeded its distinct-candidate budget."
                            )
                        }
                        remainingCandidates -= 1
                        candidates.append(canonical)
                    }
                    continue
                }
            }
            if local.residual - diameter <= tolerance.distance {
                unresolvedResidual = min(
                    unresolvedResidual ?? local.residual,
                    local.residual
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
        let unique = deduplicated(
            candidates,
            lower: globalLower,
            upper: globalUpper,
            hasEquivalentEndpoints: hasEquivalentEndpoints,
            tolerance: tolerance
        )
        guard let selected = unique.min(by: projectionOrder) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: bestWitness.residual,
                tolerance: tolerance,
                message: "Point does not lie on the bounded B-spline curve within tolerance."
            )
        }
        guard unique.count == 1 else {
            throw KernelError(
                phase: .geometry,
                code: .ambiguousSelection,
                residual: selected.residual,
                tolerance: tolerance,
                message: "B-spline inverse projection has multiple distinct parameter solutions."
            )
        }
        return try CurveParameterProjection(
            parameter: selected.parameter,
            point: selected.point,
            residual: selected.residual,
            iterations: selected.iterations
        )
    }

    private func parameterRange(
        _ range: ScalarInterval,
        matches domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard case let .closed(lower, upper) = domain else { return false }
        let scale = max(1.0, abs(lower), abs(upper), upper - lower)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        return abs(range.lower - lower) <= resolution
            && abs(range.upper - upper) <= resolution
    }

    private func initialWitness(
        patches: [RationalBezierCurvePointProjectionPatch],
        point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> RefinedProjection {
        var result: RefinedProjection?
        for patch in patches {
            let parameter = midpoint(patch.lower, patch.upper)
            let curvePoint = try self.point(at: parameter, tolerance: tolerance)
            let candidate = RefinedProjection(
                parameter: parameter,
                point: curvePoint,
                residual: outwardLength(curvePoint - point),
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
        initialParameter: Double,
        bounds: (lower: Double, upper: Double),
        point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> RefinedProjection {
        var parameter = initialParameter
        var iterations = 0
        var damping = max(tolerance.relative, Double.ulpOfOne.squareRoot())
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let geometry = try differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            let offset = geometry.position - point
            let residual = outwardLength(offset)
            let gradient = offset.dot(geometry.firstDerivative)
            let derivativeScale = max(1.0, geometry.firstDerivative.length)
            let stationarityTolerance = max(
                tolerance.distance * tolerance.relative * derivativeScale,
                Double.ulpOfOne * derivativeScale * 128.0
            )
            if residual <= tolerance.distance,
               abs(gradient) <= stationarityTolerance {
                break
            }
            let hessian = geometry.firstDerivative.dot(geometry.firstDerivative)
                + offset.dot(geometry.secondDerivative)
            let scale = max(1.0, abs(hessian))
            var accepted = false
            var nextParameter = parameter
            for _ in 0..<12 {
                let denominator = hessian + damping * scale
                if denominator.isFinite,
                   abs(denominator) > Double.ulpOfOne * scale {
                    let candidateParameter = min(
                        max(parameter - gradient / denominator, bounds.lower),
                        bounds.upper
                    )
                    let candidatePoint = try self.pointAssumingValid(
                        at: candidateParameter,
                        tolerance: tolerance
                    )
                    if outwardLength(candidatePoint - point) < residual {
                        accepted = true
                        nextParameter = candidateParameter
                        damping = max(damping * 0.25, Double.ulpOfOne)
                        break
                    }
                }
                damping *= 8.0
            }
            guard accepted else { break }
            let change = abs(nextParameter - parameter)
            parameter = nextParameter
            if change <= max(tolerance.relative, Double.ulpOfOne * 64.0) {
                break
            }
        }
        let curvePoint = try self.pointAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
        return RefinedProjection(
            parameter: parameter,
            point: curvePoint,
            residual: outwardLength(curvePoint - point),
            iterations: iterations
        )
    }

    private func deduplicated(
        _ candidates: [RefinedProjection],
        lower: Double,
        upper: Double,
        hasEquivalentEndpoints: Bool,
        tolerance: ModelingTolerance
    ) -> [RefinedProjection] {
        let scale = max(1.0, abs(lower), abs(upper), upper - lower)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        let ordered = candidates.sorted(by: projectionOrder)
        var result: [RefinedProjection] = []
        for candidate in ordered {
            if let index = result.firstIndex(where: {
                parametersAreEquivalent(
                    $0.parameter,
                    candidate.parameter,
                    lower: lower,
                    upper: upper,
                    resolution: resolution,
                    hasEquivalentEndpoints: hasEquivalentEndpoints
                )
            }) {
                result[index] = preferredCandidate(
                    result[index],
                    candidate,
                    lower: lower,
                    upper: upper,
                    hasEquivalentEndpoints: hasEquivalentEndpoints,
                    tolerance: tolerance
                )
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    private func duplicateCandidateIndex(
        _ candidate: RefinedProjection,
        in candidates: [RefinedProjection],
        lower: Double,
        upper: Double,
        hasEquivalentEndpoints: Bool,
        tolerance: ModelingTolerance
    ) -> Int? {
        let scale = max(1.0, abs(lower), abs(upper), upper - lower)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        return candidates.firstIndex {
            parametersAreEquivalent(
                $0.parameter,
                candidate.parameter,
                lower: lower,
                upper: upper,
                resolution: resolution,
                hasEquivalentEndpoints: hasEquivalentEndpoints
            )
        }
    }

    private func parametersAreEquivalent(
        _ first: Double,
        _ second: Double,
        lower: Double,
        upper: Double,
        resolution: Double,
        hasEquivalentEndpoints: Bool
    ) -> Bool {
        if abs(first - second) <= resolution {
            return true
        }
        guard hasEquivalentEndpoints else { return false }
        return (abs(first - lower) <= resolution && abs(second - upper) <= resolution)
            || (abs(first - upper) <= resolution && abs(second - lower) <= resolution)
    }

    private func preferredCandidate(
        _ first: RefinedProjection,
        _ second: RefinedProjection,
        lower: Double,
        upper: Double,
        hasEquivalentEndpoints: Bool,
        tolerance: ModelingTolerance
    ) -> RefinedProjection {
        let scale = max(1.0, abs(lower), abs(upper), upper - lower)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        if hasEquivalentEndpoints {
            let firstIsLower = abs(first.parameter - lower) <= resolution
            let secondIsLower = abs(second.parameter - lower) <= resolution
            let firstIsUpper = abs(first.parameter - upper) <= resolution
            let secondIsUpper = abs(second.parameter - upper) <= resolution
            if firstIsLower && secondIsUpper { return first }
            if secondIsLower && firstIsUpper { return second }
        }
        return projectionOrder(first, second) ? first : second
    }

    private func projectionOrder(
        _ first: RefinedProjection,
        _ second: RefinedProjection
    ) -> Bool {
        if first.residual != second.residual {
            return first.residual < second.residual
        }
        return first.parameter < second.parameter
    }

    private func boundingBoxDistanceLowerBound(
        point: Point3D,
        box: BoundingBox3D
    ) -> Double {
        let x = axisDistanceLowerBound(value: point.x, lower: box.minimum.x, upper: box.maximum.x)
        let y = axisDistanceLowerBound(value: point.y, lower: box.minimum.y, upper: box.maximum.y)
        let z = axisDistanceLowerBound(value: point.z, lower: box.minimum.z, upper: box.maximum.z)
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

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func outwardLength(_ value: Vector3D) -> Double {
        value.length.nextUp
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
        let patch: RationalBezierCurvePointProjectionPatch
        let depth: Int
    }

    private struct RefinedProjection: Sendable {
        let parameter: Double
        let point: Point3D
        let residual: Double
        let iterations: Int
    }
}
