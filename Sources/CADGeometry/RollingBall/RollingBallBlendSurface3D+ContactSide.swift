import CADCore

extension RollingBallBlendSurface3D {
    /// Certifies the side containing the minor section, relative to the source
    /// UV chart and forward contact direction. This is not solid admission.
    public func crossSectionLiesOnLeft(
        of role: SurfaceIntersectionSurfaceRole,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        try validate(using: &execution)
        guard maximumSubdivisionDepth > 0, maximumSubdivisionDepth <= 64,
              maximumCellCount > 0 else {
            throw failure(.invalidInput, "Contact-side certification requires positive bounded budgets.")
        }
        let contact = role == .first ? firstContact : secondContact
        let other = role == .first ? secondContact : firstContact
        let contactEncloser = try PreparedCurveDifferentialEncloser(curve: contact, tolerance: tolerance, using: &execution)
        let otherEncloser = try PreparedCurveDifferentialEncloser(curve: other, tolerance: tolerance, using: &execution)
        try execution.retainStorage(bytes: MemoryLayout<(ScalarInterval, Int)>.stride)
        var stackCapacity = 1
        var stack: [(ScalarInterval, Int)] = [(try ScalarInterval(lower: 0, upper: 1), 0)]
        var remaining = maximumCellCount
        var side: Bool?
        while let (interval, depth) = stack.popLast() {
            guard remaining > 0 else {
                throw failure(.resourceLimitExceeded, "Contact-side certification exceeded its cell budget.")
            }
            remaining -= 1
            try execution.visitGeometricCell(depth: depth)
            do {
                let sign = try execution.withGeometricDepthOffset(depth) { execution in
                    let rail = try contactEncloser.thirdOrderIntervalJet(over: interval, tolerance: tolerance, using: &execution)
                    let opposite = try otherEncloser.thirdOrderIntervalJet(over: interval, tolerance: tolerance, using: &execution)
                    let normal = try contactNormal(of: contact, over: interval, using: &execution)
                    try execution.consumeWork(1)
                    return rail.differentiatedUThroughSecondOrder().cross(opposite + (-rail)).dot(normal).value
                }
                if sign.lower > 0 || sign.upper < 0 {
                    let left = sign.lower > 0
                    guard side == nil || side == left else {
                        throw failure(.intersectionFailure, "The blend crosses both sides of its source contact.")
                    }
                    side = left
                    continue
                }
            } catch {
                guard OriginalQueryFailure.classification(of: error)?.code == .singularSystem else {
                    throw error
                }
                // An inconclusive interval is subdivided, never accepted.
            }
            let middle = interval.midpoint
            guard depth < maximumSubdivisionDepth,
                  middle > interval.lower, middle < interval.upper else {
                throw failure(.resourceLimitExceeded, "Contact-side certification exceeded its subdivision depth.")
            }
            let required = stack.count.addingReportingOverflow(2)
            guard required.overflow == false else { throw ExactScalarFailure.countOverflow }
            if required.partialValue > stackCapacity {
                let doubled = stackCapacity.multipliedReportingOverflow(by: 2)
                guard doubled.overflow == false else { throw ExactScalarFailure.countOverflow }
                stackCapacity = max(required.partialValue, doubled.partialValue)
                try execution.retainStorage(count: stackCapacity, stride: MemoryLayout<(ScalarInterval, Int)>.stride)
                stack.reserveCapacity(stackCapacity)
            }
            try execution.consumeWork(2)
            stack.append((try ScalarInterval(lower: middle, upper: interval.upper), depth + 1))
            stack.append((try ScalarInterval(lower: interval.lower, upper: middle), depth + 1))
        }
        guard let side else {
            throw failure(.intersectionFailure, "The blend has no certified contact side.")
        }
        return side
    }

    private func contactNormal(of contact: Curve3D, over interval: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try execution.consumeWork(1)
        if case let .rigidImage(image) = contact {
            let normal = try contactNormal(of: image.source, over: interval, using: &execution)
            let transformed = SurfaceIntervalVectorJet.constant(image.transform.basisX) * normal.x
                + .constant(image.transform.basisY) * normal.y
                + .constant(image.transform.basisZ) * normal.z
            return image.transform.basisX.dot(image.transform.basisY.cross(image.transform.basisZ)) < 0
                ? -transformed : transformed
        }
        guard case let .surfaceLift(lift) = contact else {
            throw failure(.unsupportedCapability, "Contact-side certification requires retained source-surface charts.")
        }
        let bounder = SurfaceLiftDifferentialBounder()
        let containing = try bounder.certificationInterval(containing: interval, tolerance: tolerance, using: &execution)
        let pcurve = try lift.parameterCurve.subcurveForParameterBounds(
            fromNormalizedFraction: containing.lower, toNormalizedFraction: containing.upper, tolerance: tolerance, using: &execution)
        guard let parameters = try bounder.parameterBounds(pcurve, tolerance: tolerance, using: &execution) else {
            throw failure(.unsupportedCapability, "The contact chart has no certified local UV enclosure.")
        }
        let box = try SurfaceParameterBox(
            u: bounder.nondegenerateRange(parameters.u, domain: lift.surface.uDomain, tolerance: tolerance, using: &execution),
            v: bounder.nondegenerateRange(parameters.v, domain: lift.surface.vDomain, tolerance: tolerance, using: &execution))
        let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(of: lift.surface, over: box, tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        return jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
    }
    public func crossSectionLiesOnLeft(
        of role: SurfaceIntersectionSurfaceRole,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int
    ) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try crossSectionLiesOnLeft(of: role, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumCellCount: maximumCellCount, using: &execution)
    }

}
