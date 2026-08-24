import CADCore

extension SurfaceLiftCurve3D {
    /// Returns a certified enclosure of a bounded lift interval.
    ///
    /// Exact intersection truth is preferred. Otherwise the implementation
    /// uses convex-hull bounds for rational supports or a proven global speed
    /// bound; no sampled point cloud is accepted as a bounding certificate.
    package func boundingBox(
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
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
        if let exact = try parameterCurve.exactIntersectionBoundingBox(
            tolerance: tolerance
        ) {
            return exact
        }
        let bounder = SurfaceLiftDifferentialBounder()
        if supportsIntervalLocalParameterBounds(parameterCurve) {
            let localCurve = try parameterCurve.subcurve(
                fromNormalizedFraction: interval.lower,
                toNormalizedFraction: interval.upper,
                tolerance: tolerance
            )
            if let parameters = try bounder.parameterBounds(
                localCurve,
                tolerance: tolerance
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
                        tolerance: tolerance
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
        if let rationalSupport = try bounder.bSplineSupportBounds(
            lift: self,
            interval: interval,
            tolerance: tolerance
        ) {
            return rationalSupport
        }
        guard let speed = try bounder.firstDerivativeMagnitude(
            lift: self,
            interval: interval,
            tolerance: tolerance
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
            tolerance: tolerance
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
    ) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV, .polyline, .bSpline:
            return true
        case let .sameParameterImage(image):
            return supportsIntervalLocalParameterBounds(image.source)
        case let .periodicTranslation(base, _, _):
            return supportsIntervalLocalParameterBounds(base)
        case .harmonic, .sphericalGreatCircle, .certifiedImplicit,
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
