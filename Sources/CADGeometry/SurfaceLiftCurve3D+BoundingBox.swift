import CADCore

extension SurfaceLiftCurve3D {
    /// Returns a certified enclosure of a bounded lift interval.
    ///
    /// Interval-local UV certificates are preferred over whole-intersection
    /// bounds. Other representations use exact truth, rational support hulls,
    /// or a proven speed bound; sampled point clouds are not certificates.
    package func boundingBox(
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(over: interval, tolerance: tolerance, using: &execution)
    }

    package func boundingBox(over interval: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard interval.lower >= -tolerance.relative,
              interval.upper <= 1.0 + tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface-lift bounding interval must lie in the normalized curve domain."
            )
        }
        if case .originalAffineWord(let image) = parameterCurve {
            let original = try image.source.boundingBox(over: image.mappedRange(interval), tolerance: tolerance, using: &execution)
            let sourceBounds = IntervalVector3DBounds(
                x: .init(lower: original.minimum.x, upper: original.maximum.x),
                y: .init(lower: original.minimum.y, upper: original.maximum.y),
                z: .init(lower: original.minimum.z, upper: original.maximum.z))
            let bounds = try OriginalAffineWordJetTransport.position(image.target.preparedWord,
                bounds: sourceBounds, using: &execution)
            return try .init(minimum: .init(x: bounds.x.lower, y: bounds.y.lower, z: bounds.z.lower),
                maximum: .init(x: bounds.x.upper, y: bounds.y.upper, z: bounds.z.upper))
        }
        if case .originalImage(let image) = parameterCurve {
            let original = try image.source.boundingBox(over: image.mappedRange(interval), tolerance: tolerance, using: &execution)
            try execution.retainStorage(count: 16, stride: MemoryLayout<Point3D>.stride)
            try execution.consumeWork(8)
            let points = [original.minimum, original.maximum,
                Point3D(x: original.minimum.x, y: original.minimum.y, z: original.maximum.z),
                Point3D(x: original.minimum.x, y: original.maximum.y, z: original.minimum.z),
                Point3D(x: original.maximum.x, y: original.minimum.y, z: original.minimum.z),
                Point3D(x: original.maximum.x, y: original.maximum.y, z: original.minimum.z),
                Point3D(x: original.maximum.x, y: original.minimum.y, z: original.maximum.z),
                Point3D(x: original.minimum.x, y: original.maximum.y, z: original.maximum.z)]
            return try BoundingBox3D(points: points.map(image.targetImage.transform.applying(to:)))
                .expanded(by: tolerance.distance)
        }
        let bounder = SurfaceLiftDifferentialBounder()
        if try supportsIntervalLocalParameterBounds(parameterCurve, using: &execution) {
            // A position box is only as tight as its interval, so a cell is widened only as far
            // as a pcurve trim needs (wider than the relative tolerance), not to the derivative
            // certificates' minimum width: a closest-point search refining toward a root must see
            // its boxes shrink.
            let minimumWidth = (4.0 * tolerance.relative).nextUp
            let containingInterval: ScalarInterval
            if interval.width >= minimumWidth {
                containingInterval = interval
            } else {
                let upper = min(1.0, max(interval.midpoint + minimumWidth * 0.5, minimumWidth))
                containingInterval = try ScalarInterval(lower: upper - minimumWidth, upper: upper)
            }
            let localCurve = try parameterCurve.subcurveForParameterBounds(
                fromNormalizedFraction: containingInterval.lower,
                toNormalizedFraction: containingInterval.upper,
                tolerance: tolerance, using: &execution
            )
            if let parameters = try bounder.parameterBounds(
                localCurve,
                tolerance: tolerance, using: &execution
            ) {
                let u = try intervalInsideDomain(
                    parameters.u,
                    domain: surface.uDomain,
                    tolerance: tolerance
                )
                let v = try intervalInsideDomain(
                    parameters.v,
                    domain: surface.vDomain,
                    tolerance: tolerance
                )
                let enclosure = try DefaultSurfaceDifferentialEncloser()
                    .enclosure(
                        of: surface,
                        over: SurfaceParameterBox(u: u, v: v),
                        tolerance: tolerance, using: &execution
                    ).position
                return try BoundingBox3D(
                    minimum: Point3D(
                        x: enclosure.x.lower,
                        y: enclosure.y.lower,
                        z: enclosure.z.lower
                    ),
                    maximum: Point3D(
                        x: enclosure.x.upper,
                        y: enclosure.y.upper,
                        z: enclosure.z.upper
                    )
                )
            }
        }
        if let exact = try parameterCurve.exactIntersectionBoundingBox(
            tolerance: tolerance, using: &execution
        ) {
            return exact
        }
        if let rationalSupport = try bounder.bSplineSupportBounds(
            lift: self,
            interval: interval,
            tolerance: tolerance, using: &execution
        ) {
            return rationalSupport
        }
        guard let speed = try bounder.firstDerivativeMagnitude(
            lift: self,
            interval: interval,
            tolerance: tolerance, using: &execution
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A bounded surface lift has no finite first-derivative certificate within the requested proof budget."
            )
        }
        let middle = interval.lower + interval.width * 0.5
        let center = try point(
            atNormalizedFraction: middle,
            tolerance: tolerance, using: &execution
        )
        let radius = (speed.nextUp * (interval.width * 0.5).nextUp)
            .nextUp
        guard radius.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A surface-lift bounding certificate exceeded finite arithmetic."
            )
        }
        return try BoundingBox3D(
            minimum: Point3D(
                x: center.x - radius,
                y: center.y - radius,
                z: center.z - radius
            ),
            maximum: Point3D(
                x: center.x + radius,
                y: center.y + radius,
                z: center.z + radius
            )
        ).expanded(by: tolerance.distance)
    }

    private func supportsIntervalLocalParameterBounds(
        _ curve: SurfaceParameterCurve
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch curve {
        case .affine, .constantU, .constantV, .polyline, .bSpline, .originalBSplineContinuation, .certifiedImplicit:
            return true
        case let .offsetSurfaceImage(image):
            return try supportsIntervalLocalParameterBounds(image.source, using: &execution)
        case let .periodicTranslation(base, _, _):
            return try supportsIntervalLocalParameterBounds(base, using: &execution)
        case .originalImage, .originalAffineWord, .harmonic, .sphericalGreatCircle,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            return false
        }
    }

    private func intervalInsideDomain(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let lower: Double
        let upper: Double
        switch domain {
        case let .closed(domainLower, domainUpper):
            lower = max(interval.lower, domainLower)
            upper = min(interval.upper, domainUpper)
        case .periodic, .unbounded:
            lower = interval.lower
            upper = interval.upper
        }
        guard lower < upper else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A surface-lift parameter enclosure collapsed at the support domain boundary."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }
}
