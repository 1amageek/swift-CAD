import CADCore

public struct BSplineSurfaceEmbeddingValidator: Sendable {
    public var maximumLocalSubdivisionDepth: Int
    public var maximumCellCount: Int
    public var maximumPairSubdivisionDepth: Int
    public var maximumPairCellCount: Int

    public init(
        maximumLocalSubdivisionDepth: Int = 14,
        maximumCellCount: Int = 65_536,
        maximumPairSubdivisionDepth: Int = 24,
        maximumPairCellCount: Int = 262_144
    ) {
        self.maximumLocalSubdivisionDepth = maximumLocalSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        self.maximumPairSubdivisionDepth = maximumPairSubdivisionDepth
        self.maximumPairCellCount = maximumPairCellCount
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard maximumLocalSubdivisionDepth >= 0,
              maximumCellCount > 0,
              maximumPairSubdivisionDepth >= 0,
              maximumPairCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface embedding limits must be positive."
            )
        }
        guard surface.uDegree > 0, surface.vDegree > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A globally embedded B-spline surface requires positive parameter degrees."
            )
        }
        let bounds = try retainedBounds(
            surface: surface,
            uDomain: uDomain,
            vDomain: vDomain,
            tolerance: tolerance
        )
        var cells = try clippedPatches(
            surface: surface,
            bounds: bounds,
            tolerance: tolerance
        ).map { Cell(patch: $0, depth: 0) }
        guard cells.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested B-spline surface domain contains no non-degenerate knot span."
            )
        }

        try certifyLocalInjectivity(
            cells: &cells,
            surface: surface,
            tolerance: tolerance
        )
        try certifySeparatedCells(
            cells,
            surface: surface,
            tolerance: tolerance
        )
    }

    private struct RetainedBounds: Sendable {
        let uLower: Double
        let uUpper: Double
        let vLower: Double
        let vUpper: Double
    }

    private struct Cell: Sendable {
        let patch: RationalBezierSurfacePatch3D
        let depth: Int
    }

    private struct ProjectionAxes: Sendable {
        let first: Vector3D
        let second: Vector3D
    }

    private struct PairCell: Sendable {
        let difference: RationalBezierSurfaceSurfaceDifferencePatch
        let depth: Int
    }

    private func retainedBounds(
        surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> RetainedBounds {
        guard case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain,
              try surface.uDomain.containsSpan(
                  from: uLower,
                  to: uUpper,
                  tolerance: tolerance
              ),
              try surface.vDomain.containsSpan(
                  from: vLower,
                  to: vUpper,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface embedding requires contained closed parameter domains."
            )
        }
        return RetainedBounds(
            uLower: uLower,
            uUpper: uUpper,
            vLower: vLower,
            vUpper: vUpper
        )
    }

    private func clippedPatches(
        surface: BSplineSurface3D,
        bounds: RetainedBounds,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierSurfacePatch3D] {
        let parameterTolerance = max(
            tolerance.relative * max(
                abs(bounds.uLower),
                abs(bounds.uUpper),
                abs(bounds.vLower),
                abs(bounds.vUpper),
                1.0
            ),
            Double.ulpOfOne * 256.0
        )
        return try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance)
            .compactMap { patch in
                let uLower = max(patch.uLower, bounds.uLower)
                let uUpper = min(patch.uUpper, bounds.uUpper)
                let vLower = max(patch.vLower, bounds.vLower)
                let vUpper = min(patch.vUpper, bounds.vUpper)
                guard uUpper - uLower > parameterTolerance,
                      vUpper - vLower > parameterTolerance else {
                    return nil
                }
                return try patch.trimmed(
                    uFrom: uLower,
                    uTo: uUpper,
                    vFrom: vLower,
                    vTo: vUpper,
                    tolerance: tolerance
                )
            }
    }

    private func certifyLocalInjectivity(
        cells: inout [Cell],
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        while true {
            guard cells.count <= maximumCellCount else {
                throw resourceLimit(
                    residual: Double(cells.count),
                    tolerance: tolerance,
                    message: "B-spline surface embedding exhausted its local cell budget."
                )
            }
            if let index = cells.indices.first(where: {
                projectionProvesInjective(patches: [cells[$0].patch]) == false
            }) {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    surface: surface,
                    tolerance: tolerance
                )
                try subdivide(
                    indexes: [index],
                    cells: &cells,
                    tolerance: tolerance
                )
                continue
            }
            guard let unresolved = firstUnresolvedTouchingRegion(in: cells) else {
                return
            }
            for index in unresolved {
                try rejectSampledSingularity(
                    in: cells[index].patch,
                    surface: surface,
                    tolerance: tolerance
                )
            }
            try subdivide(
                indexes: unresolved,
                cells: &cells,
                tolerance: tolerance
            )
        }
    }

    private func rejectSampledSingularity(
        in patch: RationalBezierSurfacePatch3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        for uFraction in [0.0, 0.5, 1.0] {
            for vFraction in [0.0, 0.5, 1.0] {
                let sample = parameter(
                    in: patch,
                    uFraction: uFraction,
                    vFraction: vFraction
                )
                do {
                    _ = try surface.normal(
                        u: sample.x,
                        v: sample.y,
                        tolerance: tolerance
                    )
                } catch let error as KernelError where error.code == .singularSystem {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: error.residual,
                        tolerance: tolerance,
                        message: "The B-spline surface contains a sampled singular parameter in the retained domain."
                    )
                }
            }
        }
    }

    private func firstUnresolvedTouchingRegion(in cells: [Cell]) -> [Int]? {
        guard cells.count > 1 else { return nil }
        for firstIndex in 0..<(cells.count - 1) {
            for secondIndex in (firstIndex + 1)..<cells.count {
                let first = cells[firstIndex].patch
                let second = cells[secondIndex].patch
                guard touches(first, second) else { continue }
                let uLower = min(first.uLower, second.uLower)
                let uUpper = max(first.uUpper, second.uUpper)
                let vLower = min(first.vLower, second.vLower)
                let vUpper = max(first.vUpper, second.vUpper)
                let regionIndexes = cells.indices.filter { index in
                    hasPositiveAreaIntersection(
                        cells[index].patch,
                        uLower: uLower,
                        uUpper: uUpper,
                        vLower: vLower,
                        vUpper: vUpper
                    )
                }
                let regionPatches = regionIndexes.map { cells[$0].patch }
                if projectionProvesInjective(patches: regionPatches) == false {
                    return regionIndexes
                }
            }
        }
        return nil
    }

    private func subdivide(
        indexes: [Int],
        cells: inout [Cell],
        tolerance: ModelingTolerance
    ) throws {
        let uniqueIndexes = Array(Set(indexes)).sorted(by: >)
        guard uniqueIndexes.isEmpty == false else {
            throw resourceLimit(
                residual: 0.0,
                tolerance: tolerance,
                message: "B-spline surface embedding found an empty unresolved region."
            )
        }
        for index in uniqueIndexes {
            let cell = cells[index]
            guard cell.depth < maximumLocalSubdivisionDepth else {
                throw resourceLimit(
                    residual: Double(cell.depth),
                    tolerance: tolerance,
                    message: "B-spline surface embedding could not certify local injectivity within the subdivision limit."
                )
            }
            let children = try cell.patch.subdivided().map {
                Cell(patch: $0, depth: cell.depth + 1)
            }
            cells.remove(at: index)
            cells.insert(contentsOf: children, at: index)
        }
    }

    private func projectionProvesInjective(
        patches: [RationalBezierSurfacePatch3D]
    ) -> Bool {
        guard patches.isEmpty == false else { return false }
        let bounds = patches.map(RationalBezierSurfaceDifferentialBounds.init)
        for axes in projectionCandidates(from: bounds) {
            var firstSign: Int?
            var secondSign: Int?
            var determinantSign: Int?
            var isConsistent = true
            for bound in bounds {
                guard let currentFirstSign = bound
                    .tangentUProjection(along: axes.first).sign,
                      let currentSecondSign = bound
                    .tangentVProjection(along: axes.second).sign,
                      let currentDeterminantSign = bound
                    .normalProjection(along: axes.first.cross(axes.second)).sign else {
                    isConsistent = false
                    break
                }
                if let firstSign, firstSign != currentFirstSign {
                    isConsistent = false
                    break
                }
                if let secondSign, secondSign != currentSecondSign {
                    isConsistent = false
                    break
                }
                if let determinantSign, determinantSign != currentDeterminantSign {
                    isConsistent = false
                    break
                }
                firstSign = currentFirstSign
                secondSign = currentSecondSign
                determinantSign = currentDeterminantSign
            }
            if isConsistent,
               let firstSign,
               let secondSign,
               let determinantSign,
               firstSign * secondSign * determinantSign > 0 {
                return true
            }
        }
        return false
    }

    private func projectionCandidates(
        from bounds: [RationalBezierSurfaceDifferentialBounds]
    ) -> [ProjectionAxes] {
        var candidates = [
            ProjectionAxes(first: .unitX, second: .unitY),
            ProjectionAxes(first: .unitY, second: .unitX),
            ProjectionAxes(first: .unitX, second: .unitZ),
            ProjectionAxes(first: .unitZ, second: .unitX),
            ProjectionAxes(first: .unitY, second: .unitZ),
            ProjectionAxes(first: .unitZ, second: .unitY),
        ]
        var accumulatedU = Vector3D.zero
        var accumulatedV = Vector3D.zero
        for bound in bounds {
            if let axes = tangentProjectionAxes(
                tangentU: bound.representativeTangentU,
                tangentV: bound.representativeTangentV
            ) {
                candidates.append(axes)
                accumulatedU = accumulatedU + axes.first
                accumulatedV = accumulatedV + axes.second
            }
        }
        if let aggregate = tangentProjectionAxes(
            tangentU: accumulatedU,
            tangentV: accumulatedV
        ) {
            candidates.append(aggregate)
        }
        return candidates
    }

    private func tangentProjectionAxes(
        tangentU: Vector3D,
        tangentV: Vector3D
    ) -> ProjectionAxes? {
        guard let first = unit(tangentU),
              let normal = unit(tangentU.cross(tangentV)),
              let second = unit(normal.cross(first)) else {
            return nil
        }
        return ProjectionAxes(first: first, second: second)
    }

    private func unit(_ vector: Vector3D) -> Vector3D? {
        let length = vector.length
        guard length.isFinite, length > Double.leastNormalMagnitude else {
            return nil
        }
        let result = vector / length
        return result.isFinite ? result : nil
    }

    private func certifySeparatedCells(
        _ cells: [Cell],
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        guard cells.count > 1 else { return }
        var visitedPairCells = 0
        for firstIndex in 0..<(cells.count - 1) {
            for secondIndex in (firstIndex + 1)..<cells.count {
                let first = cells[firstIndex].patch
                let second = cells[secondIndex].patch
                guard touches(first, second) == false else { continue }
                try rejectSampledCoincidence(
                    first: first,
                    second: second,
                    surface: surface,
                    tolerance: tolerance
                )
                var pending = [PairCell(
                    difference: try RationalBezierSurfaceSurfaceDifferencePatch(
                        first: first,
                        second: second,
                        tolerance: tolerance
                    ),
                    depth: 0
                )]
                while let pair = pending.popLast() {
                    visitedPairCells += 1
                    guard visitedPairCells <= maximumPairCellCount else {
                        throw resourceLimit(
                            residual: Double(visitedPairCells),
                            tolerance: tolerance,
                            message: "B-spline surface embedding exhausted its separated-cell pair budget."
                        )
                    }
                    if pair.difference.excludesZero() {
                        continue
                    }
                    guard pair.depth < maximumPairSubdivisionDepth else {
                        throw resourceLimit(
                            residual: Double(pair.depth),
                            tolerance: tolerance,
                            message: "B-spline surface embedding could not exclude a global self-intersection within the subdivision limit."
                        )
                    }
                    let parameterIndex = widestParameterIndex(pair.difference)
                    pending.append(contentsOf: pair.difference
                        .subdivided(parameterIndex: parameterIndex)
                        .map { PairCell(difference: $0, depth: pair.depth + 1) })
                }
            }
        }
    }

    private func rejectSampledCoincidence(
        first: RationalBezierSurfacePatch3D,
        second: RationalBezierSurfacePatch3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        let fractions = [0.0, 0.5, 1.0]
        for firstU in fractions {
            for firstV in fractions {
                let firstParameter = parameter(
                    in: first,
                    uFraction: firstU,
                    vFraction: firstV
                )
                let firstPoint = try surface.point(
                    u: firstParameter.x,
                    v: firstParameter.y,
                    tolerance: tolerance
                )
                for secondU in fractions {
                    for secondV in fractions {
                        let secondParameter = parameter(
                            in: second,
                            uFraction: secondU,
                            vFraction: secondV
                        )
                        let secondPoint = try surface.point(
                            u: secondParameter.x,
                            v: secondParameter.y,
                            tolerance: tolerance
                        )
                        let residual = (firstPoint - secondPoint).length
                        guard residual > tolerance.distance else {
                            throw KernelError(
                                phase: .geometry,
                                code: .singularGeometry,
                                residual: residual,
                                tolerance: tolerance,
                                message: "Distinct B-spline surface parameters coincide within modeling tolerance."
                            )
                        }
                    }
                }
            }
        }
    }

    private func parameter(
        in patch: RationalBezierSurfacePatch3D,
        uFraction: Double,
        vFraction: Double
    ) -> Point2D {
        let uSpan = patch.uUpper - patch.uLower
        let vSpan = patch.vUpper - patch.vLower
        let u = patch.uLower + uSpan * uFraction
        let v = patch.vLower + vSpan * vFraction
        return Point2D(
            x: u,
            y: v
        )
    }

    private func widestParameterIndex(
        _ difference: RationalBezierSurfaceSurfaceDifferencePatch
    ) -> Int {
        let widths = [
            difference.firstUUpper - difference.firstULower,
            difference.firstVUpper - difference.firstVLower,
            difference.secondUUpper - difference.secondULower,
            difference.secondVUpper - difference.secondVLower,
        ]
        return widths.indices.max { first, second in
            if widths[first] != widths[second] {
                return widths[first] < widths[second]
            }
            return first > second
        } ?? 0
    }

    private func touches(
        _ first: RationalBezierSurfacePatch3D,
        _ second: RationalBezierSurfacePatch3D
    ) -> Bool {
        max(first.uLower, second.uLower) <= min(first.uUpper, second.uUpper)
            && max(first.vLower, second.vLower) <= min(first.vUpper, second.vUpper)
    }

    private func hasPositiveAreaIntersection(
        _ patch: RationalBezierSurfacePatch3D,
        uLower: Double,
        uUpper: Double,
        vLower: Double,
        vUpper: Double
    ) -> Bool {
        max(patch.uLower, uLower) < min(patch.uUpper, uUpper)
            && max(patch.vLower, vLower) < min(patch.vUpper, vUpper)
    }

    private func resourceLimit(
        residual: Double,
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
}
