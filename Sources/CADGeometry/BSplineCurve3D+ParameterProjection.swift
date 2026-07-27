import CADCore
import Foundation

extension BSplineCurve3D {
    func parameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()
        let searchCurve: BSplineCurve3D
        if let range = options.parameterRange {
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
        let patches = sourcePatches.map(RationalBezierCurvePointProjectionPatch.init(patch:))
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
                        tolerance: tolerance
                    ) {
                        if canonical.residual < candidates[index].residual {
                            candidates[index] = canonical
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
                abs($0.parameter - candidate.parameter) <= resolution
            }) {
                if candidate.residual < result[index].residual {
                    result[index] = candidate
                }
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
        tolerance: ModelingTolerance
    ) -> Int? {
        let scale = max(1.0, abs(lower), abs(upper), upper - lower)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        return candidates.firstIndex {
            abs($0.parameter - candidate.parameter) <= resolution
        }
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
