import CADCore
import Foundation

struct ProceduralSurfaceParameterProjector: Sendable {
    private struct Cell: Sendable {
        let u: ClosedRange<Double>
        let v: ClosedRange<Double>
        let uDepth: Int
        let vDepth: Int
    }

    private struct Witness: Sendable {
        let u: Double
        let v: Double
        let point: Point3D
        let residual: Double
        let iterations: Int
    }

    private struct ProjectionInterval {
        let lower: Double
        let upper: Double

        init(lower: Double, upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        func adding(_ other: ProjectionInterval) -> ProjectionInterval {
            ProjectionInterval(
                lower: lower + other.lower,
                upper: upper + other.upper
            )
        }

        func multiplied(by other: ProjectionInterval) -> ProjectionInterval {
            let products = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return ProjectionInterval(
                lower: products.min() ?? -.infinity,
                upper: products.max() ?? .infinity
            )
        }
    }

    func parameterProjectionResult(
        of point: Point3D,
        on offset: OffsetSurface3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance: tolerance)
        try offset.validate(tolerance: tolerance)
        try point.validate()
        if let equivalent = try offset.exactChartPreservingSurface(
            tolerance: tolerance
        ) {
            return try equivalent.parameterProjectionResult(
                of: point,
                options: options,
                tolerance: tolerance
            )
        }
        if let cone = flattenedCone(offset) {
            return try coneProjectionResult(
                of: point,
                offset: offset,
                cone: cone,
                tolerance: tolerance
            )
        }
        guard let uBounds = finiteBounds(offset.uDomain),
              let vBounds = finiteBounds(offset.vDomain) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A non-analytic procedural surface requires finite or periodic parameter domains for certified inverse projection."
            )
        }
        return try boundedProjectionResult(
            of: point,
            on: .procedural(.offset(offset)),
            uBounds: uBounds,
            vBounds: vBounds,
            options: options,
            tolerance: tolerance
        )
    }

    func parameterProjectionResult(
        of point: Point3D,
        on ruled: RuledSurface3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance: tolerance)
        try ruled.validate(tolerance: tolerance)
        try point.validate()
        let surface = Surface3D.procedural(.ruled(ruled))
        guard let uBounds = finiteBounds(surface.uDomain),
              let vBounds = finiteBounds(surface.vDomain) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A ruled surface requires finite parameter domains for certified inverse projection."
            )
        }
        return try boundedProjectionResult(
            of: point,
            on: surface,
            uBounds: uBounds,
            vBounds: vBounds,
            options: options,
            tolerance: tolerance
        )
    }

    func closestProjection(
        of point: Point3D,
        on offset: OffsetSurface3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try options.validate(tolerance: tolerance)
        try offset.validate(tolerance: tolerance)
        try point.validate()
        guard try offset.exactChartPreservingSurface(tolerance: tolerance) == nil else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytically reducible offset must use its closed-form closest-point projection."
            )
        }
        return try closestProjection(
            of: point,
            on: .procedural(.offset(offset)),
            options: options,
            tolerance: tolerance
        )
    }

    func closestProjection(
        of point: Point3D,
        on ruled: RuledSurface3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try options.validate(tolerance: tolerance)
        try ruled.validate(tolerance: tolerance)
        try point.validate()
        return try closestProjection(
            of: point,
            on: .procedural(.ruled(ruled)),
            options: options,
            tolerance: tolerance
        )
    }

    func closestProjection(
        of point: Point3D,
        on surface: Surface3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try options.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        try point.validate()
        guard let uBounds = finiteBounds(surface.uDomain),
              let vBounds = finiteBounds(surface.vDomain) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified closest-point projection requires finite or periodic parameter domains."
            )
        }

        var best = try refine(
            u: midpoint(uBounds),
            v: midpoint(vBounds),
            point: point,
            surface: surface,
            uBounds: uBounds,
            vBounds: vBounds,
            options: options,
            tolerance: tolerance
        )
        var remainingCells = options.maximumSubdivisionCells
        var stack = [Cell(u: uBounds, v: vBounds, uDepth: 0, vDepth: 0)]
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw resourceLimit(
                    residual: best.residual,
                    tolerance: tolerance,
                    message: "Certified closest-point projection exceeded its subdivision cell budget."
                )
            }
            remainingCells -= 1
            let enclosure: SurfaceDifferentialEnclosure
            do {
                enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
                    of: surface,
                    over: try parameterBox(cell),
                    tolerance: tolerance
                )
            } catch let error as KernelError where error.code == .singularSystem {
                guard hasSubdivisionCapacity(
                    cell,
                    maximumDepth: options.maximumSubdivisionDepth
                ) else {
                    throw resourceLimit(
                        residual: best.residual,
                        tolerance: tolerance,
                        message: "Certified closest-point projection could not enclose a regular parameter cell."
                    )
                }
                stack.append(contentsOf: try subdivided(
                    cell,
                    surface: surface,
                    maximumDepth: options.maximumSubdivisionDepth,
                    tolerance: tolerance
                ).reversed())
                continue
            }
            let lowerBound = distanceLowerBound(from: point, to: enclosure.position)
            if lowerBound + tolerance.distance >= best.residual {
                continue
            }
            guard mayContainClosestPoint(
                to: point,
                enclosure: enclosure,
                cell: cell,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                uBounds: uBounds,
                vBounds: vBounds
            ) else {
                continue
            }
            let witness = try refine(
                u: midpoint(cell.u),
                v: midpoint(cell.v),
                point: point,
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options,
                tolerance: tolerance
            )
            if witnessOrder(witness, best) {
                best = witness
            }
            if lowerBound + tolerance.distance >= best.residual {
                continue
            }
            guard hasSubdivisionCapacity(
                cell,
                maximumDepth: options.maximumSubdivisionDepth
            ) else {
                throw resourceLimit(
                    residual: best.residual - lowerBound,
                    tolerance: tolerance,
                    message: "Certified closest-point projection did not close its global distance bound."
                )
            }
            stack.append(contentsOf: try subdivided(
                cell,
                surface: surface,
                maximumDepth: options.maximumSubdivisionDepth,
                tolerance: tolerance
            ).reversed())
        }
        return try projection(best)
    }

    private func boundedProjectionResult(
        of point: Point3D,
        on surface: Surface3D,
        uBounds: ClosedRange<Double>,
        vBounds: ClosedRange<Double>,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        var best = try refine(
            u: midpoint(uBounds),
            v: midpoint(vBounds),
            point: point,
            surface: surface,
            uBounds: uBounds,
            vBounds: vBounds,
            options: options,
            tolerance: tolerance
        )
        var candidates: [Witness] = []
        var stack = [Cell(u: uBounds, v: vBounds, uDepth: 0, vDepth: 0)]
        var remainingCells = options.maximumSubdivisionCells
        var unresolvedResidual: Double?

        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw resourceLimit(
                    residual: best.residual,
                    tolerance: tolerance,
                    message: "Procedural surface projection exceeded its subdivision cell budget."
                )
            }
            remainingCells -= 1
            let enclosure: SurfaceDifferentialEnclosure
            do {
                enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
                    of: surface,
                    over: try parameterBox(cell),
                    tolerance: tolerance
                )
            } catch let error as KernelError where error.code == .singularSystem {
                if hasSubdivisionCapacity(
                    cell,
                    maximumDepth: options.maximumSubdivisionDepth
                ) {
                    stack.append(contentsOf: try subdivided(
                        cell,
                        surface: surface,
                        maximumDepth: options.maximumSubdivisionDepth,
                        tolerance: tolerance
                    ).reversed())
                    continue
                }
                throw resourceLimit(
                    residual: best.residual,
                    tolerance: tolerance,
                    message: "Procedural surface projection could not certify a regular interval frame."
                )
            }
            let lowerBound = distanceLowerBound(
                from: point,
                to: enclosure.position
            )
            guard lowerBound <= tolerance.distance else {
                continue
            }
            let diameter = enclosureDiameter(enclosure.position)
            let canSubdivide = hasSubdivisionCapacity(
                cell,
                maximumDepth: options.maximumSubdivisionDepth
            )
                && (
                    parameterWidthIsResolved(cell.u, tolerance: tolerance) == false
                        || parameterWidthIsResolved(cell.v, tolerance: tolerance) == false
                )
            if canSubdivide, diameter > tolerance.distance * 0.25 {
                stack.append(contentsOf: try subdivided(
                    cell,
                    surface: surface,
                    maximumDepth: options.maximumSubdivisionDepth,
                    tolerance: tolerance
                ).reversed())
                continue
            }

            let witness = try refine(
                u: midpoint(cell.u),
                v: midpoint(cell.v),
                point: point,
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options,
                tolerance: tolerance
            )
            if witness.residual < best.residual {
                best = witness
            }
            if witness.residual <= tolerance.distance {
                appendDistinct(
                    witness,
                    to: &candidates,
                    uDomain: surface.uDomain,
                    vDomain: surface.vDomain,
                    tolerance: tolerance
                )
            } else if lowerBound <= tolerance.distance {
                unresolvedResidual = min(
                    unresolvedResidual ?? witness.residual,
                    witness.residual
                )
            }
        }

        if let unresolvedResidual {
            throw resourceLimit(
                residual: unresolvedResidual,
                tolerance: tolerance,
                message: "Procedural surface projection left an unresolved certified candidate cell."
            )
        }
        guard let selected = candidates.min(by: witnessOrder) else {
            return .outsideTolerance(residual: best.residual)
        }
        guard candidates.count == 1 else {
            throw KernelError(
                phase: .geometry,
                code: .ambiguousSelection,
                residual: selected.residual,
                tolerance: tolerance,
                message: "Procedural surface projection has multiple distinct parameter solutions."
            )
        }
        return .projected(try projection(selected))
    }

    private func refine(
        u initialU: Double,
        v initialV: Double,
        point: Point3D,
        surface: Surface3D,
        uBounds: ClosedRange<Double>,
        vBounds: ClosedRange<Double>,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Witness {
        var u = initialU
        var v = initialV
        var iterations = 0
        var damping = max(tolerance.relative, Double.ulpOfOne.squareRoot())
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let derivatives = try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
            let residual = derivatives.position - point
            let gradientU = residual.dot(derivatives.tangentU)
            let gradientV = residual.dot(derivatives.tangentV)
            let residualLength = outwardLength(residual)
            let tangentScale = max(
                1.0,
                derivatives.tangentU.length,
                derivatives.tangentV.length
            )
            let stationarityTolerance = max(
                tolerance.distance * tolerance.relative * tangentScale,
                Double.ulpOfOne * tangentScale * 128.0
            )
            if residualLength <= tolerance.distance,
               hypot(gradientU, gradientV) <= stationarityTolerance {
                break
            }
            let hessianUU = derivatives.tangentU.dot(derivatives.tangentU)
                + residual.dot(derivatives.secondDerivativeUU)
            let hessianUV = derivatives.tangentU.dot(derivatives.tangentV)
                + residual.dot(derivatives.secondDerivativeUV)
            let hessianVV = derivatives.tangentV.dot(derivatives.tangentV)
                + residual.dot(derivatives.secondDerivativeVV)
            let scale = max(1.0, abs(hessianUU), abs(hessianUV), abs(hessianVV))
            var accepted: (u: Double, v: Double, residual: Double)?
            for _ in 0..<12 {
                let a = hessianUU + damping * scale
                let d = hessianVV + damping * scale
                let determinant = a * d - hessianUV * hessianUV
                if determinant.isFinite,
                   abs(determinant) > Double.ulpOfOne * scale * scale {
                    let deltaU = (d * gradientU - hessianUV * gradientV) / determinant
                    let deltaV = (a * gradientV - hessianUV * gradientU) / determinant
                    let nextU = min(max(u - deltaU, uBounds.lowerBound), uBounds.upperBound)
                    let nextV = min(max(v - deltaV, vBounds.lowerBound), vBounds.upperBound)
                    let nextPoint = try surface.point(
                        u: nextU,
                        v: nextV,
                        tolerance: tolerance
                    )
                    let nextResidual = outwardLength(nextPoint - point)
                    if nextResidual < residualLength {
                        accepted = (nextU, nextV, nextResidual)
                        damping = max(damping * 0.25, Double.ulpOfOne)
                        break
                    }
                }
                damping *= 8.0
            }
            guard let accepted else {
                break
            }
            let parameterChange = hypot(accepted.u - u, accepted.v - v)
            u = accepted.u
            v = accepted.v
            if parameterChange <= max(
                tolerance.relative,
                Double.ulpOfOne * 64.0
            ) {
                break
            }
        }
        let surfacePoint = try surface.point(u: u, v: v, tolerance: tolerance)
        return Witness(
            u: canonical(u, domain: surface.uDomain),
            v: canonical(v, domain: surface.vDomain),
            point: surfacePoint,
            residual: outwardLength(surfacePoint - point),
            iterations: iterations
        )
    }

    private func coneProjectionResult(
        of point: Point3D,
        offset: OffsetSurface3D,
        cone: (apex: Point3D, axis: Vector3D, halfAngle: Double, distance: Double),
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        let basis = try analyticOrthonormalBasis(cone.axis, tolerance: tolerance)
        let displacement = point - cone.apex
        let axial = displacement.dot(cone.axis)
        let planar = displacement - cone.axis * axial
        var candidates: [Witness] = []
        for sign in [-1.0, 1.0] {
            let v = (axial + sign * cone.distance * sin(cone.halfAngle))
                / cos(cone.halfAngle)
            guard v * sign > tolerance.distance else {
                continue
            }
            let radialCoefficient = v * sin(cone.halfAngle)
                + sign * cone.distance * cos(cone.halfAngle)
            let radialDirection = radialCoefficient >= 0.0 ? planar : -planar
            let u = radialDirection.length > tolerance.distance
                ? normalizedAngle(atan2(
                    radialDirection.dot(basis.v),
                    radialDirection.dot(basis.u)
                ))
                : 0.0
            let surfacePoint = try offset.point(u: u, v: v, tolerance: tolerance)
            let witness = Witness(
                u: u,
                v: v,
                point: surfacePoint,
                residual: outwardLength(surfacePoint - point),
                iterations: 0
            )
            if witness.residual <= tolerance.distance {
                appendDistinct(
                    witness,
                    to: &candidates,
                    uDomain: offset.uDomain,
                    vDomain: offset.vDomain,
                    tolerance: tolerance
                )
            }
        }
        guard let selected = candidates.min(by: witnessOrder) else {
            let residual = candidates.map(\.residual).min() ?? planar.length
            return .outsideTolerance(residual: residual)
        }
        guard candidates.count == 1 else {
            throw KernelError(
                phase: .geometry,
                code: .ambiguousSelection,
                residual: selected.residual,
                tolerance: tolerance,
                message: "Offset cone projection has multiple distinct parameter solutions."
            )
        }
        return .projected(try projection(selected))
    }

    private func flattenedCone(
        _ offset: OffsetSurface3D
    ) -> (apex: Point3D, axis: Vector3D, halfAngle: Double, distance: Double)? {
        var source = offset.source
        var distance = offset.distance
        while case let .procedural(.offset(nested)) = source {
            distance += nested.distance
            source = nested.source
        }
        guard case let .analytic(.cone(apex, axis, halfAngle)) = source else {
            return nil
        }
        return (apex, axis, halfAngle, distance)
    }

    private func finiteBounds(_ domain: ParameterDomain) -> ClosedRange<Double>? {
        switch domain {
        case let .closed(lower, upper):
            return lower ... upper
        case let .periodic(period):
            return 0.0 ... period
        case .unbounded:
            return nil
        }
    }

    private func parameterBox(_ cell: Cell) throws -> SurfaceParameterBox {
        SurfaceParameterBox(
            u: try ScalarInterval(
                lower: cell.u.lowerBound,
                upper: cell.u.upperBound
            ),
            v: try ScalarInterval(
                lower: cell.v.lowerBound,
                upper: cell.v.upperBound
            )
        )
    }

    private func subdivided(
        _ cell: Cell,
        surface: Surface3D,
        maximumDepth: Int,
        tolerance: ModelingTolerance
    ) throws -> [Cell] {
        let uMidpoint = midpoint(cell.u)
        let vMidpoint = midpoint(cell.v)
        let canSplitU = cell.uDepth < maximumDepth
            && uMidpoint > cell.u.lowerBound
            && uMidpoint < cell.u.upperBound
        let canSplitV = cell.vDepth < maximumDepth
            && vMidpoint > cell.v.lowerBound
            && vMidpoint < cell.v.upperBound
        guard canSplitU || canSplitV else {
            throw resourceLimit(
                residual: 0.0,
                tolerance: tolerance,
                message: "Procedural surface projection reached the representable parameter resolution."
            )
        }
        let splitU = canSplitU && (
            canSplitV == false
                || relativeWidth(cell.u, domain: surface.uDomain)
                    >= relativeWidth(cell.v, domain: surface.vDomain)
        )
        if splitU {
            return [
                Cell(
                    u: cell.u.lowerBound ... uMidpoint,
                    v: cell.v,
                    uDepth: cell.uDepth + 1,
                    vDepth: cell.vDepth
                ),
                Cell(
                    u: uMidpoint ... cell.u.upperBound,
                    v: cell.v,
                    uDepth: cell.uDepth + 1,
                    vDepth: cell.vDepth
                ),
            ]
        }
        return [
            Cell(
                u: cell.u,
                v: cell.v.lowerBound ... vMidpoint,
                uDepth: cell.uDepth,
                vDepth: cell.vDepth + 1
            ),
            Cell(
                u: cell.u,
                v: vMidpoint ... cell.v.upperBound,
                uDepth: cell.uDepth,
                vDepth: cell.vDepth + 1
            ),
        ]
    }

    private func hasSubdivisionCapacity(
        _ cell: Cell,
        maximumDepth: Int
    ) -> Bool {
        let uMidpoint = midpoint(cell.u)
        let vMidpoint = midpoint(cell.v)
        let canSplitU = cell.uDepth < maximumDepth
            && uMidpoint > cell.u.lowerBound
            && uMidpoint < cell.u.upperBound
        let canSplitV = cell.vDepth < maximumDepth
            && vMidpoint > cell.v.lowerBound
            && vMidpoint < cell.v.upperBound
        return canSplitU || canSplitV
    }

    private func relativeWidth(
        _ range: ClosedRange<Double>,
        domain: ParameterDomain
    ) -> Double {
        let width = range.upperBound - range.lowerBound
        switch domain {
        case let .closed(lower, upper):
            return width / max(upper - lower, Double.leastNormalMagnitude)
        case let .periodic(period):
            return width / max(period, Double.leastNormalMagnitude)
        case .unbounded:
            return width
        }
    }

    private func distanceLowerBound(
        from point: Point3D,
        to enclosure: CoordinateEnclosure3D
    ) -> Double {
        let x = axisDistance(
            point.x,
            lower: enclosure.x.lower,
            upper: enclosure.x.upper
        )
        let y = axisDistance(
            point.y,
            lower: enclosure.y.lower,
            upper: enclosure.y.upper
        )
        let z = axisDistance(
            point.z,
            lower: enclosure.z.lower,
            upper: enclosure.z.upper
        )
        return sqrt(max(0.0, x * x + y * y + z * z)).nextDown
    }

    private func mayContainClosestPoint(
        to point: Point3D,
        enclosure: SurfaceDifferentialEnclosure,
        cell: Cell,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        uBounds: ClosedRange<Double>,
        vBounds: ClosedRange<Double>
    ) -> Bool {
        let gradientU = distanceGradientInterval(
            point: point,
            position: enclosure.position,
            tangent: enclosure.tangentU
        )
        guard stationarityIsPossible(
            gradientU,
            range: cell.u,
            domain: uDomain,
            bounds: uBounds
        ) else {
            return false
        }
        let gradientV = distanceGradientInterval(
            point: point,
            position: enclosure.position,
            tangent: enclosure.tangentV
        )
        return stationarityIsPossible(
            gradientV,
            range: cell.v,
            domain: vDomain,
            bounds: vBounds
        )
    }

    private func distanceGradientInterval(
        point: Point3D,
        position: CoordinateEnclosure3D,
        tangent: CoordinateEnclosure3D
    ) -> ProjectionInterval {
        let displacementX = ProjectionInterval(
            lower: position.x.lower - point.x,
            upper: position.x.upper - point.x
        )
        let displacementY = ProjectionInterval(
            lower: position.y.lower - point.y,
            upper: position.y.upper - point.y
        )
        let displacementZ = ProjectionInterval(
            lower: position.z.lower - point.z,
            upper: position.z.upper - point.z
        )
        return displacementX.multiplied(by: ProjectionInterval(
            lower: tangent.x.lower,
            upper: tangent.x.upper
        )).adding(displacementY.multiplied(by: ProjectionInterval(
            lower: tangent.y.lower,
            upper: tangent.y.upper
        ))).adding(displacementZ.multiplied(by: ProjectionInterval(
            lower: tangent.z.lower,
            upper: tangent.z.upper
        )))
    }

    private func stationarityIsPossible(
        _ gradient: ProjectionInterval,
        range: ClosedRange<Double>,
        domain: ParameterDomain,
        bounds: ClosedRange<Double>
    ) -> Bool {
        if gradient.containsZero {
            return true
        }
        guard case .closed = domain else {
            return false
        }
        if range.lowerBound == bounds.lowerBound,
           gradient.upper >= 0.0 {
            return true
        }
        if range.upperBound == bounds.upperBound,
           gradient.lower <= 0.0 {
            return true
        }
        return false
    }

    private func axisDistance(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        if value < lower {
            return max(0.0, (lower - value).nextDown)
        }
        if value > upper {
            return max(0.0, (value - upper).nextDown)
        }
        return 0.0
    }

    private func enclosureDiameter(_ enclosure: CoordinateEnclosure3D) -> Double {
        hypot(
            enclosure.x.width,
            hypot(enclosure.y.width, enclosure.z.width)
        ).nextUp
    }

    private func parameterWidthIsResolved(
        _ range: ClosedRange<Double>,
        tolerance: ModelingTolerance
    ) -> Bool {
        let scale = max(1.0, abs(range.lowerBound), abs(range.upperBound))
        return range.upperBound - range.lowerBound <= max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
    }

    private func appendDistinct(
        _ candidate: Witness,
        to candidates: inout [Witness],
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) {
        let resolution = max(tolerance.relative * 64.0, Double.ulpOfOne * 256.0)
        if let index = candidates.firstIndex(where: { existing in
            parameterDistance(existing.u, candidate.u, domain: uDomain) <= resolution
                && parameterDistance(existing.v, candidate.v, domain: vDomain) <= resolution
        }) {
            if candidate.residual < candidates[index].residual {
                candidates[index] = candidate
            }
        } else {
            candidates.append(candidate)
        }
    }

    private func parameterDistance(
        _ first: Double,
        _ second: Double,
        domain: ParameterDomain
    ) -> Double {
        let direct = abs(first - second)
        guard case let .periodic(period) = domain else {
            return direct
        }
        return min(direct, abs(period - direct))
    }

    private func canonical(_ value: Double, domain: ParameterDomain) -> Double {
        guard case let .periodic(period) = domain else {
            return value
        }
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func midpoint(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * 0.5
    }

    private func outwardLength(_ vector: Vector3D) -> Double {
        vector.length.nextUp
    }

    private func witnessOrder(_ first: Witness, _ second: Witness) -> Bool {
        if first.residual != second.residual {
            return first.residual < second.residual
        }
        if first.u != second.u {
            return first.u < second.u
        }
        return first.v < second.v
    }

    private func projection(_ witness: Witness) throws -> SurfaceParameterProjection {
        try SurfaceParameterProjection(
            u: witness.u,
            v: witness.v,
            point: witness.point,
            residual: witness.residual,
            iterations: witness.iterations
        )
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
