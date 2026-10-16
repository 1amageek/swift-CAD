import CADCore

struct CurveSurfaceOverlapResolver {
    /// Resolves retained original incidence without the legacy overlap ledger.
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector,
        using execution: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult {
        if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true, using: &execution) { return exact }
        if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true, using: &execution) { return native }
        if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, using: &execution) { return original }
        if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, using: &execution) { return affine }
        if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, using: &execution) { return coons }
        try options.validate(tolerance: tolerance)
        execution.context = execution.context.at(stage: .source)
        try execution.consumeWork(1)
        guard case .bSpline(let spline) = curve, case .plane(let plane) = surface,
            plane.uDirection != nil else {
            let points = try intersector.intersections(curve: curve, surface: surface, options: options,
                tolerance: tolerance, using: &execution)
            try reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride, using: &execution)
            return .init(points: points, overlaps: [])
        }
        let interval: ScalarInterval
        if let requested = options.curveRange { interval = requested }
        else {
            guard case .closed(let lower, let upper) = spline.domain else {
                throw failure(.invalidInput, "Original plane overlaps require an authored base-native range.", tolerance)
            }
            interval = try .init(lower: lower, upper: upper)
        }
        guard interval.lower.isFinite, interval.upper.isFinite, interval.lower < interval.upper,
            spline.degree <= options.maximumPolynomialDegree else {
            throw failure(.invalidInput, "Original plane overlaps require a finite positive range and admitted source degree.", tolerance)
        }
        execution.context = execution.context.at(stage: .relation)
        let contacts = try OriginalNativePlaneContactProducer().contacts(source: spline,
            over: interval, plane: plane, tolerance: tolerance, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted richer route
        // composes retained base-native/authored-U plane components. Periodic
        // translated carriers and general support coincidence still need their
        // original complete sector producers; this branch adds no authority to
        // numerical ranges or legacy overlap counters.
        let preparedPlane = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        typealias Clip = OriginalNativePlaneContactProducer.Overlap.ClipResult
        try reserve(count: contacts.overlaps.count, stride: MemoryLayout<Clip>.stride, using: &execution)
        var clips: [Clip] = []; clips.reserveCapacity(contacts.overlaps.count)
        var pointCount = contacts.isolated.count
        var sectorCount = 0
        for overlap in contacts.overlaps {
            try execution.consumeWork(1)
            let clip = try overlap.clipped(uRange: options.surfaceURange,
                vRange: options.surfaceVRange, using: &execution)
            let points = pointCount.addingReportingOverflow(clip.isolated.count)
            let sectors = sectorCount.addingReportingOverflow(clip.sectors.count)
            guard !points.overflow, !sectors.overflow else {
                throw failure(.resourceLimitExceeded, "Original plane overlap result count overflows.", tolerance)
            }
            pointCount = points.partialValue; sectorCount = sectors.partialValue
            let total = pointCount.addingReportingOverflow(sectorCount)
            guard !total.overflow else {
                throw failure(.resourceLimitExceeded, "Original plane overlap result count overflows.", tolerance)
            }
            try checkCount(total.partialValue, options: options, tolerance: tolerance)
            clips.append(clip)
        }
        try checkCount(pointCount, options: options, tolerance: tolerance)
        typealias Sector = OriginalNativePlaneContactProducer.Overlap.Sector
        typealias Contact = OriginalNativePlaneContactProducer.Isolated
        try reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride, using: &execution)
        var sectors: [Sector] = []; sectors.reserveCapacity(sectorCount)
        for clip in clips {
            for sector in clip.sectors { try execution.consumeWork(1); sectors.append(sector) }
        }
        try reserve(count: pointCount, stride: MemoryLayout<Contact>.stride, using: &execution)
        var events: [Contact] = []; events.reserveCapacity(pointCount)
        func admit(_ contact: Contact) throws {
            for sector in sectors {
                if try sector.hasEndpoint(contact, using: &execution) { return }
            }
            if try contact.nativeKnotStation(using: &execution) != nil {
                for index in events.indices {
                    if let combined = try events[index].mergingNativeKnotEvent(contact, using: &execution) {
                        events[index] = combined
                        return
                    }
                }
            }
            events.append(contact)
        }
        for contact in contacts.isolated { try admit(contact) }
        for clip in clips { for contact in clip.isolated { try admit(contact) } }
        try reserve(count: events.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride, using: &execution)
        try reserve(count: sectorCount, stride: MemoryLayout<CurveSurfaceOverlap>.stride, using: &execution)
        var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(events.count)
        var overlaps: [CurveSurfaceOverlap] = []; overlaps.reserveCapacity(sectorCount)
        for contact in events {
            if let event = try intersector.publishOriginalNativePlaneContact(contact,
                preparedPlane: preparedPlane, options: options, tolerance: tolerance, using: &execution) {
                points.append(event)
            }
        }
        let width = max(Double.leastNonzeroMagnitude,
            interval.upper * 0.5 - interval.lower * 0.5)
        guard width.isFinite, width > 0 else {
            throw failure(.resourceLimitExceeded, "Original plane overlap has no finite localization width.", tolerance)
        }
        try reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride, using: &execution)
        var component: [Sector] = []; component.reserveCapacity(sectorCount)
        func publishComponent() throws {
            guard !component.isEmpty else { return }
            let prepared = try OriginalNativePlaneContactProducer.Overlap.PreparedSector.joining(component,
                maximumParameterWidth: width, using: &execution)
            try reserve(count: 1, stride: MemoryLayout<OriginalNativePlaneOverlapCorrespondence>.stride, using: &execution)
            overlaps.append(try .init(original: .init(sector: prepared, preparedPlane: preparedPlane,
                options: options, tolerance: tolerance, budget: execution.budget, contributions: try execution.retainActiveContributionHandles(), limits: execution.effectiveLimits,
                context: execution.context, maximumParameterWidth: width), using: &execution))
            component.removeAll(keepingCapacity: true)
        }
        for sector in sectors {
            if let preceding = component.last, try !preceding.joins(sector, using: &execution) {
                try publishComponent()
            }
            component.append(sector)
        }
        try publishComponent()
        try reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride, using: &execution)
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return .init(points: points, overlaps: overlaps)
    }

    private func checkCount(_ count: Int, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws {
        guard count <= options.maximumCandidateCount else { throw failure(.resourceLimitExceeded, "Continuous intersection results exceed the candidate budget.", tolerance) }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
    private func reserve(count: Int, stride: Int,
        using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0 else { throw ExactScalarFailure.invalidSource }
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: bytes.partialValue)
    }
}
