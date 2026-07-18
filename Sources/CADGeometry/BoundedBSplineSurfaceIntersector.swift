import Foundation
import CADCore

struct BoundedBSplineSurfaceIntersector {
    private struct DomainBounds: Sendable {
        let firstU: (lower: Double, upper: Double)
        let firstV: (lower: Double, upper: Double)
        let secondU: (lower: Double, upper: Double)
        let secondV: (lower: Double, upper: Double)

        var spans: [Double] {
            [
                firstU.upper - firstU.lower,
                firstV.upper - firstV.lower,
                secondU.upper - secondU.lower,
                secondV.upper - secondV.lower,
            ]
        }

        func actual(_ normalized: [Double]) -> [Double] {
            [
                interpolate(firstU, normalized[0]),
                interpolate(firstV, normalized[1]),
                interpolate(secondU, normalized[2]),
                interpolate(secondV, normalized[3]),
            ]
        }

        func normalized(_ actual: [Double]) -> [Double] {
            [
                fraction(firstU, actual[0]),
                fraction(firstV, actual[1]),
                fraction(secondU, actual[2]),
                fraction(secondV, actual[3]),
            ]
        }

        private func interpolate(_ bounds: (lower: Double, upper: Double), _ fraction: Double) -> Double {
            bounds.lower + (bounds.upper - bounds.lower) * fraction
        }

        private func fraction(_ bounds: (lower: Double, upper: Double), _ value: Double) -> Double {
            (value - bounds.lower) / (bounds.upper - bounds.lower)
        }
    }

    private struct PairSample: Sendable {
        let normalized: [Double]
        let actual: [Double]
        let firstPoint: Point3D
        let secondPoint: Point3D
        let point: Point3D
        let residual: Double
    }

    private struct PatchPair: Sendable {
        let first: RationalBezierSurfacePatch3D
        let second: RationalBezierSurfacePatch3D
    }

    func intersections(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        if first == second {
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: 0.0,
                tolerance: tolerance
            ))]
        }
        let domains = try domainBounds(first: first, second: second, tolerance: tolerance)
        let decomposer = BSplineSurfaceBezierDecomposer()
        let firstPatches = try decomposer.surfacePatches(surface: first, tolerance: tolerance)
        let secondPatches = try decomposer.surfacePatches(surface: second, tolerance: tolerance)
        var seeds: [PairSample] = []
        var unresolvedPairs: [PatchPair] = []
        var remainingSeedAttempts = options.maximumSeedCount
        for firstPatch in firstPatches {
            for secondPatch in secondPatches {
                try collectSeeds(
                    pair: PatchPair(first: firstPatch, second: secondPatch),
                    depth: 0,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingSeedAttempts: &remainingSeedAttempts,
                    seeds: &seeds,
                    unresolvedPairs: &unresolvedPairs
                )
            }
        }
        seeds.sort { lexicographicallyPrecedes($0.normalized, $1.normalized) }
        guard seeds.isEmpty == false else {
            if unresolvedPairs.isEmpty { return [] }
            throw unresolvedControlHulls(tolerance: tolerance)
        }

        var components: [[PairSample]] = []
        var remainingPointCount = min(max(options.maximumSeedCount * 64, 4_096), 65_536)
        for seed in seeds {
            if try isRepresented(seed, by: components, tolerance: tolerance) {
                continue
            }
            let component = try marchedComponent(
                from: seed,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            if component.count >= 2 {
                components.append(component)
            }
        }
        for pair in unresolvedPairs {
            guard try isRepresented(pair, by: components, tolerance: tolerance) else {
                throw unresolvedControlHulls(tolerance: tolerance)
            }
        }
        components = consolidatedComponents(components, tolerance: tolerance)
        return try components.map {
            try intersectionCurve(
                samples: $0,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func collectSeeds(
        pair: PatchPair,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingSeedAttempts: inout Int,
        seeds: inout [PairSample],
        unresolvedPairs: inout [PatchPair]
    ) throws {
        let firstBox = try pair.first.boundingBox()
        let secondBox = try pair.second.boundingBox()
        guard firstBox.intersects(secondBox, tolerance: tolerance.distance) else { return }
        if ConvexHullSeparation3D.provesSeparated(
            first: pair.first.controlPoints.flatMap { $0 },
            second: pair.second.controlPoints.flatMap { $0 },
            tolerance: tolerance.distance
        ) {
            return
        }
        if depth < options.maximumSubdivisionDepth {
            if depth.isMultiple(of: 2) {
                for child in try pair.first.subdivided() {
                    try collectSeeds(
                        pair: PatchPair(first: child, second: pair.second),
                        depth: depth + 1,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingSeedAttempts: &remainingSeedAttempts,
                        seeds: &seeds,
                        unresolvedPairs: &unresolvedPairs
                    )
                }
            } else {
                for child in try pair.second.subdivided() {
                    try collectSeeds(
                        pair: PatchPair(first: pair.first, second: child),
                        depth: depth + 1,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingSeedAttempts: &remainingSeedAttempts,
                        seeds: &seeds,
                        unresolvedPairs: &unresolvedPairs
                    )
                }
            }
            return
        }
        let actualSeed = [
            midpoint(pair.first.uLower, pair.first.uUpper),
            midpoint(pair.first.vLower, pair.first.vUpper),
            midpoint(pair.second.uLower, pair.second.uUpper),
            midpoint(pair.second.vLower, pair.second.vUpper),
        ]
        let normalizedSeed = domains.normalized(actualSeed)
        let constraints = normalizedPatchBounds(pair, domains: domains)
        let candidateSeeds = [normalizedSeed] + (0..<16).map { mask in
            constraints.indices.map { index in
                mask & (1 << index) == 0
                    ? constraints[index].lower
                    : constraints[index].upper
            }
        }
        guard remainingSeedAttempts > 0 else {
            throw resourceLimit(tolerance: tolerance, message: "Bounded surface intersection exceeded its seed limit.")
        }
        remainingSeedAttempts -= 1
        var convergedSeedCount = 0
        for candidate in candidateSeeds {
            guard let sample = try closestIntersectionSample(
                seed: candidate,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                continue
            }
            convergedSeedCount += 1
            if seeds.contains(where: { normalizedDistance($0.normalized, sample.normalized) <= 1.0e-8 }) == false {
                seeds.append(sample)
            }
        }
        guard convergedSeedCount > 0 else {
            unresolvedPairs.append(pair)
            return
        }
    }

    private func closestIntersectionSample(
        seed: [Double],
        constraints: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> PairSample? {
        var parameters = seed
        for _ in 0..<options.maximumIterations {
            let sample = try pairSample(
                normalized: parameters,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            if sample.residual <= tolerance.distance * 0.1 {
                return sample
            }
            let columns = try jacobianColumns(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
            var rightHandSide = Array(repeating: 0.0, count: 4)
            let difference = sample.firstPoint - sample.secondPoint
            for row in 0..<4 {
                rightHandSide[row] = -columns[row].dot(difference)
                for column in 0..<4 {
                    matrix[row][column] = columns[row].dot(columns[column])
                }
            }
            let maximumDiagonal = (0..<4).map { matrix[$0][$0] }.max() ?? 1.0
            let damping = max(maximumDiagonal * 1.0e-10, 1.0e-14)
            for index in 0..<4 {
                matrix[index][index] += damping
            }
            guard let delta = SmallLinearSystem4.solve(
                matrix: matrix,
                rightHandSide: rightHandSide
            ) else {
                return nil
            }
            for index in 0..<4 {
                parameters[index] = min(
                    max(parameters[index] + delta[index], constraints[index].lower),
                    constraints[index].upper
                )
            }
            if delta.map(abs).max() ?? 0.0 <= 1.0e-13 {
                break
            }
        }
        let final = try pairSample(
            normalized: parameters,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        return final.residual <= tolerance.distance ? final : nil
    }

    private func marchedComponent(
        from seed: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        let tangent = try intersectionTangent(
            sample: seed,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        let forward = try march(
            from: seed,
            initialTangent: tangent,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        let reverse = try march(
            from: seed,
            initialTangent: tangent.map { -$0 },
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        let combined = Array(reverse.dropFirst().reversed()) + forward
        return try refined(
            combined,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
    }

    private func march(
        from seed: PairSample,
        initialTangent: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        var result = [seed]
        var current = seed
        var tangent = initialTangent
        let baseStep = max(
            1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
            1.0 / 256.0
        )
        while true {
            guard result.count < 16_384 else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: "Surface intersection marching exceeded its component length limit."
                )
            }
            guard remainingPointCount > 0 else {
                throw resourceLimit(tolerance: tolerance, message: "Surface intersection marching exceeded its point limit.")
            }
            var step = baseStep
            var corrected: PairSample?
            var reachesBoundary = false
            for _ in 0..<8 {
                let boundaryScale = scaleToUnitBoundary(
                    from: current.normalized,
                    direction: tangent,
                    requestedStep: step
                )
                reachesBoundary = boundaryScale < step
                let predictor = zip(current.normalized, tangent).map {
                    $0.0 + $0.1 * boundaryScale
                }
                corrected = try pseudoArclengthCorrection(
                    predictor: predictor,
                    tangent: tangent,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance
                )
                if corrected != nil { break }
                step *= 0.5
            }
            guard let next = corrected else {
                if isOnUnitBoundary(current.normalized) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Pseudo-arclength correction failed at the marching seed."
                )
            }
            if (next.point - current.point).length <= tolerance.distance * 0.1 {
                if isOnUnitBoundary(next.normalized) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: (next.point - current.point).length,
                    tolerance: tolerance,
                    message: "Surface intersection marching stagnated before reaching a component boundary."
                )
            }
            remainingPointCount -= 1
            result.append(next)
            if result.count > 12,
               (next.point - seed.point).length <= tolerance.distance * 2.0 {
                result[result.count - 1] = seed
                break
            }
            if reachesBoundary || isOnUnitBoundary(next.normalized) {
                break
            }
            var nextTangent = try intersectionTangent(
                sample: next,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            if dot(nextTangent, tangent) < 0.0 {
                nextTangent = nextTangent.map { -$0 }
            }
            tangent = nextTangent
            current = next
        }
        return result
    }

    private func pseudoArclengthCorrection(
        predictor: [Double],
        tangent: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> PairSample? {
        var parameters = predictor.map { min(max($0, 0.0), 1.0) }
        for _ in 0..<options.maximumIterations {
            let sample = try pairSample(
                normalized: parameters,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let gauge = dot(zip(parameters, predictor).map { $0.0 - $0.1 }, tangent)
            if sample.residual <= tolerance.distance * 0.1,
               abs(gauge) <= 1.0e-10 {
                return sample
            }
            let columns = try jacobianColumns(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let difference = sample.firstPoint - sample.secondPoint
            let matrix = [
                columns.map(\.x),
                columns.map(\.y),
                columns.map(\.z),
                tangent,
            ]
            let rhs = [-difference.x, -difference.y, -difference.z, -gauge]
            guard let delta = SmallLinearSystem4.solve(matrix: matrix, rightHandSide: rhs) else {
                return nil
            }
            for index in 0..<4 {
                parameters[index] = min(max(parameters[index] + delta[index], 0.0), 1.0)
            }
        }
        let final = try pairSample(
            normalized: parameters,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        return final.residual <= tolerance.distance ? final : nil
    }

    private func refined(
        _ samples: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        guard samples.count >= 2 else { return samples }
        var result = [samples[0]]
        for index in 1..<samples.count {
            try refineSegment(
                firstSample: samples[index - 1],
                secondSample: samples[index],
                depth: 0,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount,
                result: &result
            )
        }
        return result
    }

    private func refineSegment(
        firstSample: PairSample,
        secondSample: PairSample,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int,
        result: inout [PairSample]
    ) throws {
        let residual = try linearSegmentResidual(
            firstSample: firstSample,
            secondSample: secondSample,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        if residual <= tolerance.distance * 0.5 {
            result.append(secondSample)
            return
        }
        let difference = zip(secondSample.normalized, firstSample.normalized).map { $0.0 - $0.1 }
        guard let tangent = normalized(difference) else {
            return
        }
        let predictor = zip(firstSample.normalized, secondSample.normalized).map {
            ($0.0 + $0.1) * 0.5
        }
        guard let middle = try pseudoArclengthCorrection(
            predictor: predictor,
            tangent: tangent,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Surface intersection midpoint correction failed."
            )
        }
        guard depth < 18,
              remainingPointCount > 0 else {
            throw resourceLimit(tolerance: tolerance, message: "Surface intersection residual refinement exceeded its limit.")
        }
        remainingPointCount -= 1
        try refineSegment(
            firstSample: firstSample,
            secondSample: middle,
            depth: depth + 1,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
        try refineSegment(
            firstSample: middle,
            secondSample: secondSample,
            depth: depth + 1,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
    }

    private func linearSegmentResidual(
        firstSample: PairSample,
        secondSample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximum = 0.0
        for fraction in [0.25, 0.5, 0.75] {
            let normalizedParameters = zip(
                firstSample.normalized,
                secondSample.normalized
            ).map {
                $0.0 + ($0.1 - $0.0) * fraction
            }
            let actual = domains.actual(normalizedParameters)
            let curvePoint = interpolated(
                firstSample.point,
                secondSample.point,
                fraction: fraction
            )
            let firstPoint = try first.point(
                u: actual[0],
                v: actual[1],
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                u: actual[2],
                v: actual[3],
                tolerance: tolerance
            )
            maximum = max(
                maximum,
                (curvePoint - firstPoint).length,
                (curvePoint - secondPoint).length
            )
        }
        return maximum
    }

    private func intersectionCurve(
        samples: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let points = samples.map(\.point)
        let firstParameters = samples.map { Point2D(x: $0.actual[0], y: $0.actual[1]) }
        let secondParameters = samples.map { Point2D(x: $0.actual[2], y: $0.actual[3]) }
        let knots = degreeOneKnots(controlPointCount: points.count)
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: knots,
            controlPoints: points
        ))
        let firstPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: firstParameters
        ))
        let secondPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: secondParameters
        ))
        try firstPcurve.validate(on: firstSurface, tolerance: tolerance)
        try secondPcurve.validate(on: secondSurface, tolerance: tolerance)
        let maximumResidual = try verifiedResidual(
            points: points,
            firstParameters: firstParameters,
            secondParameters: secondParameters,
            first: first,
            second: second,
            tolerance: tolerance
        )
        let firstAnchor = try firstSurface.parameterProjection(of: points[0], tolerance: tolerance)
        let secondAnchor = try secondSurface.parameterProjection(of: points[0], tolerance: tolerance)
        return .curve(try SurfaceSurfaceIntersectionCurve(
            curve: curve,
            kind: .transverse,
            firstSurfaceParameterCurve: firstPcurve,
            secondSurfaceParameterCurve: secondPcurve,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            maximumResidual: maximumResidual,
            tolerance: tolerance
        ))
    }

    private func verifiedResidual(
        points: [Point3D],
        firstParameters: [Point2D],
        secondParameters: [Point2D],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximumResidual = 0.0
        for index in 1..<points.count {
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let curvePoint = interpolated(points[index - 1], points[index], fraction: fraction)
                let firstUV = interpolated(firstParameters[index - 1], firstParameters[index], fraction: fraction)
                let secondUV = interpolated(secondParameters[index - 1], secondParameters[index], fraction: fraction)
                let firstPoint = try first.point(u: firstUV.x, v: firstUV.y, tolerance: tolerance)
                let secondPoint = try second.point(u: secondUV.x, v: secondUV.y, tolerance: tolerance)
                maximumResidual = max(
                    maximumResidual,
                    (curvePoint - firstPoint).length,
                    (curvePoint - secondPoint).length
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Bounded surface intersection failed residual verification."
            )
        }
        return maximumResidual
    }

    private func pairSample(
        normalized: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> PairSample {
        let actual = domains.actual(normalized)
        let firstPoint = try first.point(u: actual[0], v: actual[1], tolerance: tolerance)
        let secondPoint = try second.point(u: actual[2], v: actual[3], tolerance: tolerance)
        return PairSample(
            normalized: normalized,
            actual: actual,
            firstPoint: firstPoint,
            secondPoint: secondPoint,
            point: interpolated(firstPoint, secondPoint, fraction: 0.5),
            residual: (firstPoint - secondPoint).length
        )
    }

    private func jacobianColumns(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> [Vector3D] {
        let firstGeometry = try first.differentialGeometry(
            atU: sample.actual[0],
            v: sample.actual[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: sample.actual[2],
            v: sample.actual[3],
            tolerance: tolerance
        )
        let spans = domains.spans
        return [
            firstGeometry.tangentU * spans[0],
            firstGeometry.tangentV * spans[1],
            secondGeometry.tangentU * -spans[2],
            secondGeometry.tangentV * -spans[3],
        ]
    }

    private func intersectionTangent(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let firstGeometry = try first.differentialGeometry(
            atU: sample.actual[0],
            v: sample.actual[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: sample.actual[2],
            v: sample.actual[3],
            tolerance: tolerance
        )
        let normalSeparation = firstGeometry.normal.cross(secondGeometry.normal).length
        guard normalSeparation > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                residual: normalSeparation,
                tolerance: tolerance,
                message: "Bounded surface marching currently requires a transverse intersection."
            )
        }
        let columns = try jacobianColumns(
            sample: sample,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        let cofactors = [
            -determinant(columns[1], columns[2], columns[3]),
            determinant(columns[0], columns[2], columns[3]),
            -determinant(columns[0], columns[1], columns[3]),
            determinant(columns[0], columns[1], columns[2]),
        ]
        guard let tangent = normalized(cofactors) else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                residual: cofactors.map(abs).max(),
                tolerance: tolerance,
                message: "Bounded surface marching currently requires a transverse intersection."
            )
        }
        return tangent
    }

    private func domainBounds(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> DomainBounds {
        DomainBounds(
            firstU: try closedBounds(first.uDomain, tolerance: tolerance),
            firstV: try closedBounds(first.vDomain, tolerance: tolerance),
            secondU: try closedBounds(second.uDomain, tolerance: tolerance),
            secondV: try closedBounds(second.vDomain, tolerance: tolerance)
        )
    }

    private func normalizedPatchBounds(
        _ pair: PatchPair,
        domains: DomainBounds
    ) -> [(lower: Double, upper: Double)] {
        let lower = domains.normalized([
            pair.first.uLower,
            pair.first.vLower,
            pair.second.uLower,
            pair.second.vLower,
        ])
        let upper = domains.normalized([
            pair.first.uUpper,
            pair.first.vUpper,
            pair.second.uUpper,
            pair.second.vUpper,
        ])
        return lower.indices.map { (lower[$0], upper[$0]) }
    }

    private func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(lower, upper) = domain,
              upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded surface marching requires closed parameter domains."
            )
        }
        return (lower, upper)
    }

    private func isRepresented(
        _ seed: PairSample,
        by components: [[PairSample]],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for component in components {
            for index in 1..<component.count {
                if pointSegmentDistance(
                    seed.point,
                    component[index - 1].point,
                    component[index].point
                ) <= tolerance.distance * 2.0 {
                    return true
                }
            }
        }
        return false
    }

    private func consolidatedComponents(
        _ source: [[PairSample]],
        tolerance: ModelingTolerance
    ) -> [[PairSample]] {
        var merged = source
        var didMerge = true
        while didMerge {
            didMerge = false
            outer: for firstIndex in merged.indices {
                guard firstIndex + 1 < merged.count else { continue }
                for secondIndex in (firstIndex + 1)..<merged.count {
                    guard let joined = continuouslyJoined(
                        merged[firstIndex],
                        merged[secondIndex],
                        tolerance: tolerance
                    ) else {
                        continue
                    }
                    merged[firstIndex] = joined
                    merged.remove(at: secondIndex)
                    didMerge = true
                    break outer
                }
            }
        }

        var unique: [[PairSample]] = []
        for component in merged {
            if unique.contains(where: {
                representsSameLocus(component, $0, tolerance: tolerance)
            }) == false {
                unique.append(component)
            }
        }
        return unique
    }

    private func continuouslyJoined(
        _ first: [PairSample],
        _ second: [PairSample],
        tolerance: ModelingTolerance
    ) -> [PairSample]? {
        guard first.count >= 2, second.count >= 2 else { return nil }
        let firstVariants = [first, Array(first.reversed())]
        let secondVariants = [second, Array(second.reversed())]
        for left in firstVariants {
            for right in secondVariants {
                guard let leftEnd = left.last,
                      let rightStart = right.first,
                      (leftEnd.point - rightStart.point).length <= tolerance.distance * 4.0,
                      normalizedDistance(leftEnd.normalized, rightStart.normalized) <= 1.0e-6,
                      let incoming = unitDirection(
                          from: left[left.count - 2].point,
                          to: leftEnd.point,
                          tolerance: tolerance
                      ),
                      let outgoing = unitDirection(
                          from: rightStart.point,
                          to: right[1].point,
                          tolerance: tolerance
                      ),
                      incoming.dot(outgoing) >= 0.95 else {
                    continue
                }
                return left + Array(right.dropFirst())
            }
        }
        return nil
    }

    private func unitDirection(
        from start: Point3D,
        to end: Point3D,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        let direction = end - start
        let length = direction.length
        guard length > tolerance.distance * 0.1 else { return nil }
        return direction / length
    }

    private func representsSameLocus(
        _ first: [PairSample],
        _ second: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        samples(first, lieOn: second, tolerance: tolerance)
            && samples(second, lieOn: first, tolerance: tolerance)
    }

    private func samples(
        _ samples: [PairSample],
        lieOn component: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        guard component.count >= 2 else { return false }
        return samples.allSatisfy { sample in
            (1..<component.count).contains { index in
                pointSegmentDistance(
                    sample.point,
                    component[index - 1].point,
                    component[index].point
                ) <= tolerance.distance * 8.0
            }
        }
    }

    private func isRepresented(
        _ pair: PatchPair,
        by components: [[PairSample]],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let firstBox = try pair.first.boundingBox()
        let secondBox = try pair.second.boundingBox()
        return components.contains { component in
            component.contains { sample in
                firstBox.contains(sample.point, tolerance: tolerance.distance)
                    && secondBox.contains(sample.point, tolerance: tolerance.distance)
            }
        }
    }

    private func pointSegmentDistance(_ point: Point3D, _ start: Point3D, _ end: Point3D) -> Double {
        let direction = end - start
        let squaredLength = direction.dot(direction)
        guard squaredLength > Double.ulpOfOne else { return (point - start).length }
        let fraction = min(max((point - start).dot(direction) / squaredLength, 0.0), 1.0)
        return (point - (start + direction * fraction)).length
    }

    private func scaleToUnitBoundary(
        from parameters: [Double],
        direction: [Double],
        requestedStep: Double
    ) -> Double {
        var result = requestedStep
        for index in 0..<4 {
            if direction[index] > 0.0 {
                result = min(result, (1.0 - parameters[index]) / direction[index])
            } else if direction[index] < 0.0 {
                result = min(result, -parameters[index] / direction[index])
            }
        }
        return max(result, 0.0)
    }

    private func isOnUnitBoundary(_ values: [Double]) -> Bool {
        values.contains { $0 <= 1.0e-10 || $0 >= 1.0 - 1.0e-10 }
    }

    private func determinant(_ first: Vector3D, _ second: Vector3D, _ third: Vector3D) -> Double {
        first.dot(second.cross(third))
    }

    private func normalized(_ values: [Double]) -> [Double]? {
        let length = sqrt(values.reduce(0.0) { $0 + $1 * $1 })
        guard length.isFinite, length > 1.0e-12 else { return nil }
        return values.map { $0 / length }
    }

    private func dot(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private func normalizedDistance(_ first: [Double], _ second: [Double]) -> Double {
        sqrt(zip(first, second).reduce(0.0) { partial, pair in
            let difference = pair.0 - pair.1
            return partial + difference * difference
        })
    }

    private func lexicographicallyPrecedes(_ first: [Double], _ second: [Double]) -> Bool {
        for index in first.indices where first[index] != second[index] {
            return first[index] < second[index]
        }
        return false
    }

    private func degreeOneKnots(controlPointCount: Int) -> [Double] {
        [0.0, 0.0]
            + (1..<(controlPointCount - 1)).map(Double.init)
            + [Double(controlPointCount - 1), Double(controlPointCount - 1)]
    }

    private func interpolated(_ first: Point2D, _ second: Point2D, fraction: Double) -> Point2D {
        Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func interpolated(_ first: Point3D, _ second: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            z: first.z + (second.z - first.z) * fraction
        )
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func resourceLimit(tolerance: ModelingTolerance, message: String) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private func unresolvedControlHulls(tolerance: ModelingTolerance) -> KernelError {
        resourceLimit(
            tolerance: tolerance,
            message: "Overlapping Bezier control hulls remain unresolved at the bounded surface subdivision limit."
        )
    }
}
