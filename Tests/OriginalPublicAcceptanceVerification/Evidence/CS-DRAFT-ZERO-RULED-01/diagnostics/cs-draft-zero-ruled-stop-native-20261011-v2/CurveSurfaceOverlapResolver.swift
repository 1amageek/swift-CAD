import CADCore
@testable import CADGeometry
@testable import DerivativeLiftPlanePort
import enum DerivativeLiftPlanePort.GeometryExactScalarFailure
import struct CADGeometry.CurveSurfaceIntersectionResult
import protocol CADGeometry.CurveSurfaceIntersectionResolving
import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

struct CurveSurfaceOverlapResolver {
    private struct Candidate {
        let range: ScalarInterval
        let deviation: Double
        var isoparametric: OverlapIsoparametricCorrespondence? = nil
        var graph: OverlapRegularGraphCorrespondence? = nil
    }

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                 tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector) throws -> CurveSurfaceIntersectionResult {
        if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true) { return exact }
        if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true) { return native }
        if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return original }
        if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return affine }
        if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return coons }
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        let range = try DefaultCurveSurfaceSearchRangeResolver().curveRange(curve: curve, surface: surface,
                                                                          requestedRange: options.curveRange, tolerance: tolerance)
        guard range.width.isFinite, range.width > 0, try curve.parameterDomain.containsSpan(from: range.lower, to: range.upper, tolerance: tolerance) else {
            throw failure(.invalidInput, "Continuous intersection queries require a positive interval in the curve domain.", tolerance)
        }
        let support = try proofSupport(surface, tolerance: tolerance)
        var rawOptions = options
        rawOptions.curveRange = range
        rawOptions.surfaceURange = nil
        rawOptions.surfaceVRange = nil
        var points: [CurveSurfaceIntersection] = []
        var candidates: [Candidate] = []
        var graphBudget = OverlapProofBudget(options: options, tolerance: tolerance)

        if case .bSpline(let spline) = curve, case .bSpline(let target) = surface,
           let certificate = try OverlapIsoparametricMembershipCertifier().certificate(
               curve: spline, surface: target, range: range, options: options, tolerance: tolerance, budget: &graphBudget) {
            candidates.append(Candidate(range: range, deviation: certificate.deviation,
                isoparametric: certificate.correspondence))
        } else if case .bSpline(let spline) = curve, case .bSpline(let target) = surface,
                  !spline.isPeriodic, !target.isUPeriodic, !target.isVPeriodic,
                  ExactAffineBSplineSurfacePatch(target) == nil {
            let result = try OverlapRegularGraphCertifier().resolve(curve: spline, surface: target,
                range: range, options: options, tolerance: tolerance, budget: &graphBudget)
            for graph in result.graphs {
                candidates.append(Candidate(range: graph.range, deviation: graph.maximumDeviation, graph: graph))
            }
            for excluded in result.excluded {
                var discreteOptions = rawOptions
                discreteOptions.curveRange = excluded
                points.append(contentsOf: try intersector.intersections(curve: curve, surface: support,
                    options: discreteOptions, tolerance: tolerance))
            }
        } else if case .bSpline(let spline) = curve {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: spline, intersecting: range, tolerance: tolerance)
            guard spans.count <= options.maximumSubdivisionCells else {
                throw failure(.resourceLimitExceeded, "Overlap source spans exceed the cell budget.", tolerance)
            }
            for span in spans {
                try CurrentTaskCancellationChecker().checkCancellation()
                let lower = max(span.lower, range.lower), upper = min(span.upper, range.upper)
                guard upper > lower else { continue }
                let interval = try ScalarInterval(lower: lower, upper: upper)
                let degree = span.controlPoints.count - 1
                let piece = BSplineCurve3D(degree: degree,
                    knots: Array(repeating: span.lower, count: degree + 1) + Array(repeating: span.upper, count: degree + 1),
                    controlPoints: span.controlPoints, weights: span.weights)
                var pieceOptions = rawOptions
                pieceOptions.curveRange = interval
                do {
                    points.append(contentsOf: try intersector.intersections(curve: .bSpline(piece), surface: support,
                                                                          options: pieceOptions, tolerance: tolerance))
                } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Non-isoparametric free-surface
                    // coincidence without retained hosting provenance has no proof here.
                    // intersectionResult may succeed only after its complete correspondence
                    // and whole-span membership certificate are implemented.
                    if case .unsupported = CanonicalAnalyticSurface(support) {
                        throw failure(.unsupportedCapability, "Rational overlap on this free surface has no membership certificate.", tolerance)
                    }
                    let bound = try OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
                        .deviation(of: span, on: CanonicalAnalyticSurface(support))
                    guard bound <= tolerance.distance else {
                        throw failure(.intersectionFailure, "A non-discrete rational span has no certified overlap distance bound at this tolerance.", tolerance)
                    }
                    candidates.append(Candidate(range: interval, deviation: bound))
                }
                try checkCount(points.count + candidates.count, options: options, tolerance: tolerance)
            }
        } else {
            do {
                if case .periodic(let period) = curve.parameterDomain {
                    var fundamentalOptions = rawOptions
                    fundamentalOptions.curveRange = try ScalarInterval(lower: 0, upper: period)
                    let fundamental = try intersector.intersections(curve: curve, surface: support,
                                                                   options: fundamentalOptions, tolerance: tolerance)
                    for event in fundamental {
                        let lowerCycle = ceil((range.lower - event.curveParameter) / period)
                        let upperCycle = floor((range.upper - event.curveParameter) / period)
                        guard lowerCycle.isFinite, upperCycle.isFinite,
                              abs(lowerCycle) <= 9_007_199_254_740_991, abs(upperCycle) <= 9_007_199_254_740_991,
                              upperCycle - lowerCycle < Double(options.maximumCandidateCount) else {
                            throw failure(.resourceLimitExceeded, "Periodic overlap boundary events exceed the finite cycle budget.", tolerance)
                        }
                        var cycle = lowerCycle
                        while cycle <= upperCycle {
                            try CurrentTaskCancellationChecker().checkCancellation()
                            points.append(try CurveSurfaceIntersection(point: event.point,
                                curveParameter: event.curveParameter + cycle * period,
                                surfaceU: event.surfaceU, surfaceV: event.surfaceV, kind: event.kind,
                                residual: event.residual, iterations: event.iterations))
                            try checkCount(points.count, options: options, tolerance: tolerance)
                            cycle += 1
                        }
                    }
                } else {
                    points = try intersector.intersections(curve: curve, surface: support, options: rawOptions, tolerance: tolerance)
                }
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                let bound = try membershipBound(curve: curve, surface: surface, support: support,
                                                range: range, options: options, tolerance: tolerance)
                candidates.append(Candidate(range: range, deviation: bound))
            }
        }

        var admitted: [Candidate] = []
        for candidate in candidates {
            let clipping = try clip(candidate, curve: curve, surface: surface, options: options,
                                    tolerance: tolerance, intersector: intersector, budget: &graphBudget)
            admitted.append(contentsOf: clipping.candidates)
            points.append(contentsOf: clipping.points)
            try checkCount(points.count + admitted.count, options: options, tolerance: tolerance)
        }
        let merged = try merge(admitted)
        var uniquePoints: [CurveSurfaceIntersection] = []
        for event in points.sorted(by: { $0.curveParameter < $1.curveParameter }) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let candidate = candidates.first { $0.range.contains(event.curveParameter) }
            let correspondence = candidate?.isoparametric
            guard !merged.contains(where: { $0.range.contains(event.curveParameter) }),
                  try contains(curve: curve, surface: surface, parameter: event.curveParameter, options: options,
                               tolerance: tolerance, isoparametric: correspondence, graph: candidate?.graph, budget: &graphBudget) else { continue }
            if let last = uniquePoints.last, last.curveParameter == event.curveParameter { continue }
            let endpoint: CurveSurfaceOverlapEndpoint
            if let graph = candidate?.graph {
                endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: event.curveParameter,
                    uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                    graph: graph, budget: &graphBudget)
            } else {
                endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: event.curveParameter,
                    uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                    isoparametric: correspondence)
            }
            uniquePoints.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: endpoint.curveParameter,
                surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v, kind: event.kind,
                residual: endpoint.residual, iterations: event.iterations))
        }
        let overlaps = try merged.map {
            if let graph = $0.graph {
                return try CurveSurfaceOverlap(curve: curve, surface: surface, range: $0.range, deviation: $0.deviation,
                    options: options, tolerance: tolerance, graph: graph, budget: &graphBudget)
            }
            return try CurveSurfaceOverlap(curve: curve, surface: surface, range: $0.range, deviation: $0.deviation,
                                    options: options, tolerance: tolerance, isoparametric: $0.isoparametric)
        }
        try checkCount(uniquePoints.count + overlaps.count, options: options, tolerance: tolerance)
        return CurveSurfaceIntersectionResult(points: uniquePoints, overlaps: overlaps)
    }

    /// Resolves retained original incidence without the legacy overlap ledger.
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector,
        invocation: CurveSurfaceQueryInvocation) throws -> CurveSurfaceIntersectionResult {
        if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation, retainingRelations: true) { return exact }
        if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation, retainingRelations: true) { return native }
        if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return original }
        if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return affine }
        if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return coons }
        try options.validate(tolerance: tolerance)
        try invocation.consumeFixedWork()
        guard case .bSpline(let spline) = curve, case .plane(let plane) = surface,
            plane.uDirection != nil else {
            let points = try intersector.intersections(curve: curve, surface: surface, options: options,
                tolerance: tolerance, maximumSpanCount: invocation.maximumSpanCount,
                maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
                remainingSourceDepth: invocation.remainingSourceDepth,
                consumeWork: invocation.consume, consumeStorage: invocation.consumeStorage,
                maximumAlgebraicDepth: invocation.maximumAlgebraicDepth)
            try invocation.reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride)
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
        let contacts = try OriginalNativePlaneContactProducer().contacts(source: spline,
            over: interval, plane: plane, tolerance: tolerance, invocation: invocation)
        // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted richer route
        // composes retained base-native/authored-U plane components. Periodic
        // translated carriers and general support coincidence still need their
        // original complete sector producers; this branch adds no authority to
        // numerical ranges or legacy overlap counters.
        let preparedPlane = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            remainingSourceDepth: invocation.remainingSourceDepth,
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
            consumeWork: invocation.consumeFixedWork, consumeStorage: invocation.consumeStorage,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth)
        typealias Clip = OriginalNativePlaneContactProducer.Overlap.ClipResult
        try invocation.reserve(count: contacts.overlaps.count, stride: MemoryLayout<Clip>.stride)
        var clips: [Clip] = []; clips.reserveCapacity(contacts.overlaps.count)
        var pointCount = contacts.isolated.count
        var sectorCount = 0
        for overlap in contacts.overlaps {
            try invocation.consumeFixedWork()
            let clip = try overlap.clipped(uRange: options.surfaceURange,
                vRange: options.surfaceVRange, invocation: invocation)
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
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride)
        var sectors: [Sector] = []; sectors.reserveCapacity(sectorCount)
        for clip in clips {
            for sector in clip.sectors { try invocation.consumeFixedWork(); sectors.append(sector) }
        }
        try invocation.reserve(count: pointCount, stride: MemoryLayout<Contact>.stride)
        var events: [Contact] = []; events.reserveCapacity(pointCount)
        func admit(_ contact: Contact) throws {
            for sector in sectors {
                if try sector.hasEndpoint(contact, invocation: invocation) { return }
            }
            if try contact.nativeKnotStation(invocation: invocation) != nil {
                for index in events.indices {
                    if let combined = try events[index].mergingNativeKnotEvent(contact, invocation: invocation) {
                        events[index] = combined
                        return
                    }
                }
            }
            events.append(contact)
        }
        for contact in contacts.isolated { try admit(contact) }
        for clip in clips { for contact in clip.isolated { try admit(contact) } }
        try invocation.reserve(count: events.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride)
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<CurveSurfaceOverlap>.stride)
        var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(events.count)
        var overlaps: [CurveSurfaceOverlap] = []; overlaps.reserveCapacity(sectorCount)
        for contact in events {
            if let event = try intersector.publishOriginalNativePlaneContact(contact,
                preparedPlane: preparedPlane, options: options, tolerance: tolerance, invocation: invocation) {
                points.append(event)
            }
        }
        let width = max(Double.leastNonzeroMagnitude,
            interval.upper * 0.5 - interval.lower * 0.5)
        guard width.isFinite, width > 0 else {
            throw failure(.resourceLimitExceeded, "Original plane overlap has no finite localization width.", tolerance)
        }
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride)
        var component: [Sector] = []; component.reserveCapacity(sectorCount)
        func publishComponent() throws {
            guard !component.isEmpty else { return }
            let prepared = try OriginalNativePlaneContactProducer.Overlap.PreparedSector.joining(component,
                maximumParameterWidth: width, invocation: invocation)
            try invocation.reserve(count: 1, stride: MemoryLayout<OriginalNativePlaneOverlapCorrespondence>.stride)
            overlaps.append(try .init(original: .init(sector: prepared, preparedPlane: preparedPlane,
                options: options, tolerance: tolerance, invocation: invocation, maximumParameterWidth: width)))
            component.removeAll(keepingCapacity: true)
        }
        for sector in sectors {
            if let preceding = component.last, try !preceding.joins(sector, invocation: invocation) {
                try publishComponent()
            }
            component.append(sector)
        }
        try publishComponent()
        try invocation.reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride)
        return .init(points: points, overlaps: overlaps)
    }

    private func membershipBound(curve: Curve3D, surface: Surface3D, support: Surface3D,
                                 range: ScalarInterval, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> Double {
        if try OverlapSourceMembershipResolver().isExactSource(surface, of: curve, tolerance: tolerance) {
            return tolerance.distance
        }
        if case .plane(let plane) = CanonicalAnalyticSurface(support) {
            return try OverlapPlanarMembershipCertifier().deviation(of: curve, over: range, on: plane, tolerance: tolerance)
        }
        if let rational = try AnalyticCurveBSplineBuilder().boundedCurve(curve: curve, interval: range,
            maximumSpanCount: options.maximumCandidateCount, tolerance: tolerance) {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: rational, tolerance: tolerance)
            let proof = OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
            var bound = 0.0
            for span in spans {
                try CurrentTaskCancellationChecker().checkCancellation()
                bound = max(bound, try proof.deviation(of: span, on: CanonicalAnalyticSurface(support)))
            }
            guard bound <= tolerance.distance else {
                throw failure(.intersectionFailure, "The continuous analytic candidate cannot meet the whole-span distance bound.", tolerance)
            }
            return bound
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Unretained non-affine free-surface coincidence
        // has no whole-span proof in intersectionResult. Completion requires certified
        // membership and complete overlap-domain isolation before this branch can succeed.
        throw failure(.unsupportedCapability, "This continuous curve-surface domain has no whole-span membership certificate.", tolerance)
    }

    private func proofSupport(_ surface: Surface3D, tolerance: ModelingTolerance) throws -> Surface3D {
        if case .bSpline(let spline) = surface, let affine = ExactAffineBSplineSurfacePatch(spline) {
            let normal = try affine.uDirection.cross(affine.vDirection).normalized(tolerance: tolerance.distance)
            return .plane(Plane3D(origin: affine.origin, normal: normal))
        }
        return surface
    }

    private func clip(_ candidate: Candidate, curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                      tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector,
                      budget: inout OverlapProofBudget) throws -> (candidates: [Candidate], points: [CurveSurfaceIntersection]) {
        let boundaries = try OverlapChartBoundaryResolver().boundaries(curve: curve, surface: surface, options: options,
            tolerance: tolerance, isoparametric: candidate.isoparametric, regularGraph: candidate.graph, budget: &budget)
        var cuts = [candidate.range.lower, candidate.range.upper]
        for boundary in boundaries {
            try CurrentTaskCancellationChecker().checkCancellation()
            switch boundary {
            case .certifiedSourceParameter(let parameter):
                if candidate.range.contains(parameter) { cuts.append(parameter) }
            case let .plane(plane, parameterPlaneSource):
                var boundaryOptions = options
                boundaryOptions.curveRange = candidate.range
                boundaryOptions.surfaceURange = nil
                boundaryOptions.surfaceVRange = nil
                let source = parameterPlaneSource ?? curve
                let result = try resolve(curve: source, surface: plane, options: boundaryOptions,
                                         tolerance: tolerance, intersector: intersector)
                cuts.append(contentsOf: result.points.map({ $0.curveParameter }))
                for overlap in result.overlaps { cuts.append(overlap.curveRange.lower); cuts.append(overlap.curveRange.upper) }
            }
            try checkCount(cuts.count, options: options, tolerance: tolerance)
        }
        cuts.sort()
        var unique: [Double] = []
        for cut in cuts where unique.last != cut { unique.append(cut) }
        var regions: [Candidate] = []
        for index in 0..<(unique.count - 1) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let lower = unique[index], upper = unique[index + 1]
            guard upper > lower else { continue }
            let middle = lower + (upper - lower) * 0.5
            guard middle > lower, middle < upper else {
                throw failure(.classificationFailure, "An overlap clipping cell has no representable interior parameter.", tolerance)
            }
            // Each cut came from a complete boundary result. An open connected
            // cell has no boundary crossing, so one membership test classifies it.
            if try contains(curve: curve, surface: surface, parameter: middle, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric, graph: candidate.graph, budget: &budget) {
                regions.append(Candidate(range: try ScalarInterval(lower: lower, upper: upper), deviation: candidate.deviation,
                                         isoparametric: candidate.isoparametric, graph: candidate.graph))
            }
        }
        var points: [CurveSurfaceIntersection] = []
        for cut in unique where !regions.contains(where: { $0.range.contains(cut) }) {
            if try contains(curve: curve, surface: surface, parameter: cut, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric, graph: candidate.graph, budget: &budget) {
                let endpoint: CurveSurfaceOverlapEndpoint
                if let graph = candidate.graph {
                    endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: cut,
                        uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance, graph: graph, budget: &budget)
                } else {
                    endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: cut,
                        uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                        isoparametric: candidate.isoparametric)
                }
                points.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: cut,
                    surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v,
                    kind: .tangent, residual: endpoint.residual, iterations: 0))
            }
        }
        return (regions, points)
    }

    private func contains(curve: Curve3D, surface: Surface3D, parameter: Double,
                          options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
                          isoparametric: OverlapIsoparametricCorrespondence? = nil,
                          graph: OverlapRegularGraphCorrespondence? = nil, budget: inout OverlapProofBudget) throws -> Bool {
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let coordinates: SurfaceParameter
        if let graph {
            coordinates = try graph.parameter(at: parameter, budget: &budget)
        } else if let isoparametric {
            coordinates = isoparametric.parameter(at: parameter)
        } else if case let .surfaceLift(lift) = curve, lift.surface == surface {
            coordinates = try lift.parameterCurve.parameter(atNormalizedFraction: parameter, tolerance: tolerance)
        } else {
            switch try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
            case .projected(let projection): coordinates = SurfaceParameter(u: projection.u, v: projection.v)
            case .outsideTolerance:
                if case .bSpline(let spline) = surface, ExactAffineBSplineSurfacePatch(spline) != nil { return false }
                throw failure(.intersectionFailure, "A certified overlap candidate failed target membership verification.", tolerance)
            }
        }
        let resolver = SurfaceParameterRangeResolver()
        return resolver.resolvedParameter(coordinates.u, domain: surface.uDomain, requestedRange: options.surfaceURange, tolerance: tolerance) != nil
            && resolver.resolvedParameter(coordinates.v, domain: surface.vDomain, requestedRange: options.surfaceVRange, tolerance: tolerance) != nil
    }

    private func merge(_ candidates: [Candidate]) throws -> [Candidate] {
        var result: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.range.lower < $1.range.lower }) {
            if let previous = result.last, candidate.range.lower <= previous.range.upper,
               previous.isoparametric == candidate.isoparametric,
               sameGraph(previous.graph, candidate.graph) {
                result[result.count - 1] = Candidate(range: try ScalarInterval(lower: previous.range.lower,
                    upper: max(previous.range.upper, candidate.range.upper)), deviation: max(previous.deviation, candidate.deviation),
                    isoparametric: previous.isoparametric, graph: previous.graph)
            } else { result.append(candidate) }
        }
        return result
    }

    private func sameGraph(_ first: OverlapRegularGraphCorrespondence?, _ second: OverlapRegularGraphCorrespondence?) -> Bool {
        switch (first, second) {
        case (.none, .none): return true
        case let (.some(first), .some(second)): return first.sharesAuthority(with: second)
        default: return false
        }
    }

    private func checkCount(_ count: Int, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws {
        guard count <= options.maximumCandidateCount else { throw failure(.resourceLimitExceeded, "Continuous intersection results exceed the candidate budget.", tolerance) }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
