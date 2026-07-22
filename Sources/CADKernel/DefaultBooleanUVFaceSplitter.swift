import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultBooleanUVFaceSplitter: BooleanUVFaceSplitting {
    private struct ContactProjectionCacheKey: Hashable {
        let curve: Curve3D
        let point: Point3D
    }

    private enum ContactProjectionCacheEntry {
        case parameter(Double)
        case noIntersection
    }

    private let facePointContainment: any FacePointContainmentTesting

    public init(
        facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
    ) {
        self.facePointContainment = facePointContainment
    }

    public func splitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph {
        try intersectionGraph.validate(in: model, tolerance: tolerance)
        var splits: [BooleanFaceSplit] = []
        var containmentCache: [FacePointContainmentCacheKey: Bool] = [:]
        var containmentPreparationCache = FacePointContainmentPreparationCache()
        var contactProjectionCache: [
            ContactProjectionCacheKey: ContactProjectionCacheEntry
        ] = [:]
        for pair in intersectionGraph.facePairs {
            guard let targetFace = model.faces[pair.targetFaceID],
                  let toolFace = model.faces[pair.toolFaceID],
                  let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
                  let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean UV splitting references missing face geometry."
                )
            }
            guard let targetPlane = planeGeometry(targetSurface),
                  let toolPlane = planeGeometry(toolSurface) else {
                if let curvedSplit = try curvedSplit(
                    pair: pair,
                    intersectionGraph: intersectionGraph,
                    targetSurface: targetSurface,
                    toolSurface: toolSurface,
                    model: model,
                    containmentCache: &containmentCache,
                    containmentPreparationCache: &containmentPreparationCache,
                    contactProjectionCache: &contactProjectionCache,
                    tolerance: tolerance
                ) {
                    splits.append(curvedSplit)
                }
                continue
            }
            let lineDirection = targetPlane.normal.cross(toolPlane.normal)
            let contacts = contacts(for: pair, in: intersectionGraph)
            if lineDirection.length <= tolerance.angle {
                let separation = abs((toolPlane.origin - targetPlane.origin).dot(targetPlane.normal))
                if separation <= tolerance.distance,
                   contacts.contains(where: { if case .coincident = $0.geometry { return true }; return false }) {
                    splits.append(try split(
                        facePair: pair,
                        geometries: [.coincident],
                        tolerance: tolerance
                    ))
                }
                continue
            }
            let points = try clippedPoints(
                contacts: contacts,
                pair: pair,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                model: model,
                containmentCache: &containmentCache,
                containmentPreparationCache: &containmentPreparationCache,
                tolerance: tolerance
            )
            guard points.isEmpty == false else { continue }
            let direction = try lineDirection.normalized(tolerance: tolerance.distance)
            let ordered = points.sorted {
                vector($0.point).dot(direction) < vector($1.point).dot(direction)
            }
            guard let first = ordered.first, let last = ordered.last else { continue }
            if (first.point - last.point).length <= tolerance.distance {
                splits.append(try split(
                    facePair: pair,
                    geometries: [.tangent(first)],
                    tolerance: tolerance
                ))
            } else {
                splits.append(try split(
                    facePair: pair,
                    geometries: [.transverseSegment(start: first, end: last)],
                    tolerance: tolerance
                ))
            }
        }
        let graph = BooleanUVSplitGraph(splits: splits)
        try graph.validate(intersectionGraph: intersectionGraph, model: model, tolerance: tolerance)
        return graph
    }

    private func planeGeometry(_ surface: Surface3D) -> (origin: Point3D, normal: Vector3D)? {
        switch surface {
        case let .plane(plane):
            return (plane.origin, plane.normal)
        case let .analytic(.plane(origin, normal)):
            return (origin, normal)
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private func contacts(
        for pair: BooleanFacePairCandidate,
        in graph: BooleanIntersectionGraph
    ) -> [BooleanBoundaryContact] {
        graph.boundaryContacts.filter { contact in
            (contact.curveFaceID == pair.targetFaceID && contact.surfaceFaceID == pair.toolFaceID)
                || (contact.curveFaceID == pair.toolFaceID && contact.surfaceFaceID == pair.targetFaceID)
        }
    }

    private func curvedSplit(
        pair: BooleanFacePairCandidate,
        intersectionGraph: BooleanIntersectionGraph,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        model: BRepModel,
        containmentCache: inout [FacePointContainmentCacheKey: Bool],
        containmentPreparationCache: inout FacePointContainmentPreparationCache,
        contactProjectionCache: inout [
            ContactProjectionCacheKey: ContactProjectionCacheEntry
        ],
        tolerance: ModelingTolerance
    ) throws -> BooleanFaceSplit? {
        let intersections = intersectionGraph.faceIntersections.filter { $0.facePair == pair }
        guard intersections.isEmpty == false else { return nil }
        if intersections.contains(where: {
            if case .coincident = $0.geometry { return true }
            return false
        }) {
            guard intersections.count == 1 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A coincident face pair cannot also contain discrete intersections."
                )
            }
            return try split(
                facePair: pair,
                geometries: [.coincident],
                tolerance: tolerance
            )
        }

        let pairContacts = contacts(for: pair, in: intersectionGraph)
        let contactPoints = pairContacts.flatMap { contact -> [Point3D] in
            guard case let .points(points) = contact.geometry else { return [] }
            return points.map(\.point)
        }
        var geometries: [BooleanFaceSplitComponentGeometry] = []
        for intersection in intersections {
            switch intersection.geometry {
            case .coincident:
                break
            case let .point(point):
                guard try contains(
                    point.point,
                    faceID: pair.targetFaceID,
                    surface: targetSurface,
                    model: model,
                    cache: &containmentCache,
                    preparationCache: &containmentPreparationCache,
                    tolerance: tolerance
                ), try contains(
                    point.point,
                    faceID: pair.toolFaceID,
                    surface: toolSurface,
                    model: model,
                    cache: &containmentCache,
                    preparationCache: &containmentPreparationCache,
                    tolerance: tolerance
                ) else {
                    continue
                }
                geometries.append(.tangent(try booleanUVPoint(
                    point.point,
                    targetSurface: targetSurface,
                    toolSurface: toolSurface,
                    inheritedResidual: point.residual,
                    tolerance: tolerance
                )))
            case let .curve(curveIntersection):
                let clipped = try clip(
                    curveIntersection,
                    at: contactPoints,
                    pair: pair,
                    targetSurface: targetSurface,
                    toolSurface: toolSurface,
                    model: model,
                    containmentCache: &containmentCache,
                    containmentPreparationCache: &containmentPreparationCache,
                    contactProjectionCache: &contactProjectionCache,
                    tolerance: tolerance
                )
                switch clipped {
                case .empty:
                    break
                case let .closed(value):
                    geometries.append(.closedCurve(value))
                case let .trimmed(values):
                    geometries.append(contentsOf: values.map(BooleanFaceSplitComponentGeometry.trimmedCurve))
                }
            }
        }
        guard geometries.isEmpty == false else { return nil }
        return try split(
            facePair: pair,
            geometries: geometries,
            tolerance: tolerance
        )
    }

    private func split(
        facePair: BooleanFacePairCandidate,
        geometries: [BooleanFaceSplitComponentGeometry],
        tolerance: ModelingTolerance
    ) throws -> BooleanFaceSplit {
        guard geometries.isEmpty == false,
              Set(geometries).count == geometries.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean face split requires unique geometric components."
            )
        }
        let sorted = geometries.map { geometry in
            (geometry: geometry, key: componentSortKey(geometry))
        }.sorted { lhs, rhs in
            lhs.key.lexicographicallyPrecedes(rhs.key)
        }
        for index in 1..<sorted.count where sorted[index - 1].key == sorted[index].key {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Boolean split components have indistinguishable deterministic geometry keys."
            )
        }
        return BooleanFaceSplit(
            facePair: facePair,
            components: sorted.enumerated().map { ordinal, record in
                BooleanFaceSplitComponent(
                    id: BooleanFaceSplitComponentID(ordinal: ordinal),
                    geometry: record.geometry
                )
            }
        )
    }

    private func componentSortKey(
        _ geometry: BooleanFaceSplitComponentGeometry
    ) -> [Double] {
        switch geometry {
        case let .transverseSegment(start, end):
            return [0.0] + orderedPointKey(start.point, end.point)
        case let .closedCurve(curve):
            let points = curve.samples.map(\.uvPoint.point)
            let minimum = points.min(by: lexicographicPointOrder) ?? .origin
            let maximum = points.max(by: lexicographicPointOrder) ?? .origin
            let count = Double(max(points.count, 1))
            let centroid = Point3D(
                x: points.reduce(0.0) { $0 + $1.x } / count,
                y: points.reduce(0.0) { $0 + $1.y } / count,
                z: points.reduce(0.0) { $0 + $1.z } / count
            )
            return [1.0, Double(points.count)]
                + pointKey(minimum)
                + pointKey(maximum)
                + pointKey(centroid)
                + points.sorted(by: lexicographicPointOrder).flatMap(pointKey)
        case let .trimmedCurve(chain):
            let midpoint = Point3D(
                x: (chain.start.point.x + chain.end.point.x) * 0.5,
                y: (chain.start.point.y + chain.end.point.y) * 0.5,
                z: (chain.start.point.z + chain.end.point.z) * 0.5
            )
            return [2.0, Double(chain.segments.count)]
                + orderedPointKey(chain.start.point, chain.end.point)
                + pointKey(midpoint)
                + chain.segments.flatMap {
                    [$0.startParameter, $0.endParameter]
                }
        case let .tangent(point):
            return [3.0] + pointKey(point.point)
        case .coincident:
            return [4.0]
        }
    }

    private func orderedPointKey(_ first: Point3D, _ second: Point3D) -> [Double] {
        if lexicographicPointOrder(first, second) {
            return pointKey(first) + pointKey(second)
        }
        return pointKey(second) + pointKey(first)
    }

    private func lexicographicPointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        pointKey(lhs).lexicographicallyPrecedes(pointKey(rhs))
    }

    private func pointKey(_ point: Point3D) -> [Double] {
        [point.x, point.y, point.z]
    }

    private func clip(
        _ intersection: SurfaceSurfaceIntersectionCurve,
        at contactPoints: [Point3D],
        pair: BooleanFacePairCandidate,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        model: BRepModel,
        containmentCache: inout [FacePointContainmentCacheKey: Bool],
        containmentPreparationCache: inout FacePointContainmentPreparationCache,
        contactProjectionCache: inout [
            ContactProjectionCacheKey: ContactProjectionCacheEntry
        ],
        tolerance: ModelingTolerance
    ) throws -> CurvedClipResult {
        let curve = intersection.curve
        var contacts: [ClipContact] = []
        for point in contactPoints {
            let key = ContactProjectionCacheKey(curve: curve, point: point)
            if let cached = contactProjectionCache[key] {
                if case let .parameter(parameter) = cached {
                    contacts.append(ClipContact(parameter: parameter, point: point))
                }
                continue
            }
            do {
                let projection = try curve.parameterProjection(of: point, tolerance: tolerance)
                contactProjectionCache[key] = .parameter(projection.parameter)
                contacts.append(ClipContact(
                    parameter: projection.parameter,
                    point: point
                ))
            } catch let error as KernelError where error.code == .intersectionFailure {
                contactProjectionCache[key] = .noIntersection
                continue
            }
        }
        contacts = deduplicatedContacts(
            contacts,
            domain: curve.parameterDomain,
            tolerance: tolerance
        )
        if contacts.count < 2 {
            switch curve.parameterDomain {
            case let .periodic(period):
                return try completeClosedClip(
                    intersection,
                    lowerParameter: 0.0,
                    upperParameter: period,
                    pair: pair,
                    targetSurface: targetSurface,
                    toolSurface: toolSurface,
                    model: model,
                    containmentCache: &containmentCache,
                    containmentPreparationCache: &containmentPreparationCache,
                    tolerance: tolerance
                )
            case let .closed(lower, upper):
                let start = try curve.point(at: lower, tolerance: tolerance)
                let end = try curve.point(at: upper, tolerance: tolerance)
                if start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) {
                    return try completeClosedClip(
                        intersection,
                        lowerParameter: lower,
                        upperParameter: upper,
                        pair: pair,
                        targetSurface: targetSurface,
                        toolSurface: toolSurface,
                        model: model,
                        containmentCache: &containmentCache,
                        containmentPreparationCache: &containmentPreparationCache,
                        tolerance: tolerance
                    )
                }
            case .unbounded:
                break
            }
        }

        var boundaries = contacts.map(\.parameter)
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            boundaries.append(contentsOf: [lower, upper])
        case .periodic, .unbounded:
            break
        }
        boundaries = deduplicatedParameters(
            boundaries,
            domain: curve.parameterDomain,
            tolerance: tolerance
        ).sorted()
        guard boundaries.count >= 2 else { return .empty }

        var intervals = Array(zip(boundaries, boundaries.dropFirst()))
        if case let .periodic(period) = curve.parameterDomain,
           let first = boundaries.first,
           let last = boundaries.last {
            intervals.append((last, first + period))
        }
        var result: [TrimmedIntervalRecord] = []
        for (intervalOrdinal, interval) in intervals.enumerated() {
            let (lower, upper) = interval
            guard upper - lower > tolerance.angle else { continue }
            let midpoint = lower + (upper - lower) * 0.5
            let midpointPoint = try curve.point(at: midpoint, tolerance: tolerance)
            guard try contains(
                midpointPoint,
                faceID: pair.targetFaceID,
                surface: targetSurface,
                model: model,
                cache: &containmentCache,
                preparationCache: &containmentPreparationCache,
                tolerance: tolerance
            ), try contains(
                midpointPoint,
                faceID: pair.toolFaceID,
                surface: toolSurface,
                model: model,
                cache: &containmentCache,
                preparationCache: &containmentPreparationCache,
                tolerance: tolerance
            ) else {
                continue
            }
            let startContact = try contactPoint(
                at: lower,
                contacts: contacts,
                domain: curve.parameterDomain,
                tolerance: tolerance
            )
            let endContact = try contactPoint(
                at: upper,
                contacts: contacts,
                domain: curve.parameterDomain,
                tolerance: tolerance
            )
            let startPoint: Point3D
            if let startContact {
                startPoint = startContact
            } else {
                startPoint = try curve.point(at: lower, tolerance: tolerance)
            }
            let endPoint: Point3D
            if let endContact {
                endPoint = endContact
            } else {
                endPoint = try curve.point(at: upper, tolerance: tolerance)
            }
            result.append(TrimmedIntervalRecord(
                ordinal: intervalOrdinal,
                segment: try BooleanTrimmedFaceIntersection(
                    intersection: intersection,
                    startParameter: lower,
                    endParameter: upper,
                    start: try booleanUVPoint(
                        startPoint,
                        atCurveParameter: lower,
                        intersection: intersection,
                        targetSurface: targetSurface,
                        toolSurface: toolSurface,
                        tolerance: tolerance
                    ),
                    end: try booleanUVPoint(
                        endPoint,
                        atCurveParameter: upper,
                        intersection: intersection,
                        targetSurface: targetSurface,
                        toolSurface: toolSurface,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                )
            ))
        }
        guard result.isEmpty == false else { return .empty }
        return .trimmed(try trimmedChains(
            result,
            intervalCount: intervals.count,
            domain: curve.parameterDomain,
            tolerance: tolerance
        ))
    }

    private func trimmedChains(
        _ records: [TrimmedIntervalRecord],
        intervalCount: Int,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> [BooleanTrimmedFaceIntersectionChain] {
        var remaining = records
        var result: [BooleanTrimmedFaceIntersectionChain] = []
        if case .closed = domain,
           remaining.count >= 2,
           remaining.first?.ordinal == 0,
           remaining.last?.ordinal == intervalCount - 1 {
            let first = remaining.removeFirst().segment
            let last = remaining.removeLast().segment
            result.append(try BooleanTrimmedFaceIntersectionChain(
                segments: [last, first],
                tolerance: tolerance
            ))
        }
        result.append(contentsOf: try remaining.map {
            try BooleanTrimmedFaceIntersectionChain(
                segments: [$0.segment],
                tolerance: tolerance
            )
        })
        return result
    }

    private func completeClosedClip(
        _ intersection: SurfaceSurfaceIntersectionCurve,
        lowerParameter: Double,
        upperParameter: Double,
        pair: BooleanFacePairCandidate,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        model: BRepModel,
        containmentCache: inout [FacePointContainmentCacheKey: Bool],
        containmentPreparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> CurvedClipResult {
        let sampleCount = 32
        var samples: [BooleanCurveUVSample] = []
        var containedSampleCount = 0
        for index in 0..<sampleCount {
            let parameter = lowerParameter
                + (upperParameter - lowerParameter) * Double(index) / Double(sampleCount)
            let point = try intersection.curve.point(at: parameter, tolerance: tolerance)
            let isContained = try contains(
                point,
                faceID: pair.targetFaceID,
                surface: targetSurface,
                model: model,
                cache: &containmentCache,
                preparationCache: &containmentPreparationCache,
                tolerance: tolerance
            ) && contains(
                point,
                faceID: pair.toolFaceID,
                surface: toolSurface,
                model: model,
                cache: &containmentCache,
                preparationCache: &containmentPreparationCache,
                tolerance: tolerance
            )
            if isContained { containedSampleCount += 1 }
            samples.append(try BooleanCurveUVSample(
                curveParameter: parameter,
                uvPoint: booleanUVPoint(
                    point,
                    atCurveParameter: parameter,
                    intersection: intersection,
                    targetSurface: targetSurface,
                    toolSurface: toolSurface,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ))
        }
        guard containedSampleCount > 0 else { return .empty }
        // This path has fewer than two distinct clip parameters. One contained
        // sample is therefore an isolated shared-boundary contact, not a finite
        // face interval.
        if containedSampleCount == 1 {
            return .empty
        }
        guard containedSampleCount == sampleCount else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Trim boundary contacts are incomplete for a partially contained closed intersection."
            )
        }
        return .closed(try BooleanClosedFaceIntersection(
            intersection: intersection,
            samples: samples,
            tolerance: tolerance
        ))
    }

    private func deduplicatedParameters(
        _ parameters: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let canonical: [Double]
        if case let .periodic(period) = domain {
            canonical = parameters.map { parameter in
                let remainder = parameter.truncatingRemainder(dividingBy: period)
                return remainder >= 0.0 ? remainder : remainder + period
            }
        } else {
            canonical = parameters
        }
        let threshold = max(tolerance.angle, tolerance.distance)
        var result: [Double] = []
        for parameter in canonical.sorted() {
            if result.last.map({ abs($0 - parameter) <= threshold }) != true {
                result.append(parameter)
            }
        }
        if case let .periodic(period) = domain,
           let first = result.first,
           let last = result.last,
           first + period - last <= threshold {
            result.removeLast()
        }
        return result
    }

    private func deduplicatedContacts(
        _ contacts: [ClipContact],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> [ClipContact] {
        let canonical = contacts.map { contact in
            ClipContact(
                parameter: canonicalParameter(contact.parameter, domain: domain),
                point: contact.point
            )
        }.sorted { lhs, rhs in
            if lhs.parameter != rhs.parameter {
                return lhs.parameter < rhs.parameter
            }
            return lexicographicPointOrder(lhs.point, rhs.point)
        }
        let threshold = max(tolerance.angle, tolerance.distance)
        var result: [ClipContact] = []
        for contact in canonical {
            if let last = result.last,
               abs(last.parameter - contact.parameter) <= threshold {
                continue
            }
            result.append(contact)
        }
        if case let .periodic(period) = domain,
           let first = result.first,
           let last = result.last,
           first.parameter + period - last.parameter <= threshold {
            result.removeLast()
        }
        return result
    }

    private func contactPoint(
        at parameter: Double,
        contacts: [ClipContact],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Point3D? {
        let canonical = canonicalParameter(parameter, domain: domain)
        let threshold = max(tolerance.angle, tolerance.distance)
        let matches = contacts.filter {
            abs($0.parameter - canonical) <= threshold
        }
        guard matches.count <= 1 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean trim parameter resolved to multiple canonical boundary contacts."
            )
        }
        return matches.first?.point
    }

    private func canonicalParameter(
        _ parameter: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return parameter }
        let remainder = parameter.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func booleanUVPoint(
        _ point: Point3D,
        atCurveParameter parameter: Double,
        intersection: SurfaceSurfaceIntersectionCurve,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVPoint {
        let target = try intersection.surfaceParameter(
            on: .first,
            atCurveParameter: parameter,
            tolerance: tolerance
        )
        let tool = try intersection.surfaceParameter(
            on: .second,
            atCurveParameter: parameter,
            tolerance: tolerance
        )
        let targetPoint = try targetSurface.point(
            u: target.u,
            v: target.v,
            tolerance: tolerance
        )
        let toolPoint = try toolSurface.point(
            u: tool.u,
            v: tool.v,
            tolerance: tolerance
        )
        let residual = max(
            intersection.maximumResidual,
            (point - targetPoint).length,
            (point - toolPoint).length
        )
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Boolean UV split pcurves disagree with their intersection curve."
            )
        }
        return try BooleanUVPoint(
            point: point,
            targetU: target.u,
            targetV: target.v,
            toolU: tool.u,
            toolV: tool.v,
            residual: residual,
            tolerance: tolerance
        )
    }

    private func booleanUVPoint(
        _ point: Point3D,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        inheritedResidual: Double,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVPoint {
        let target = try targetSurface.parameterProjection(of: point, tolerance: tolerance)
        let tool = try toolSurface.parameterProjection(of: point, tolerance: tolerance)
        return try BooleanUVPoint(
            point: point,
            targetU: target.u,
            targetV: target.v,
            toolU: tool.u,
            toolV: tool.v,
            residual: max(inheritedResidual, target.residual, tool.residual),
            tolerance: tolerance
        )
    }

    private func clippedPoints(
        contacts: [BooleanBoundaryContact],
        pair: BooleanFacePairCandidate,
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        model: BRepModel,
        containmentCache: inout [FacePointContainmentCacheKey: Bool],
        containmentPreparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> [BooleanUVPoint] {
        var points: [BooleanUVPoint] = []
        for contact in contacts {
            guard case let .points(intersections) = contact.geometry else { continue }
            for intersection in intersections {
                guard try contains(
                    intersection.point,
                    faceID: pair.targetFaceID,
                    surface: targetSurface,
                    model: model,
                    cache: &containmentCache,
                    preparationCache: &containmentPreparationCache,
                    tolerance: tolerance
                ), try contains(
                    intersection.point,
                    faceID: pair.toolFaceID,
                    surface: toolSurface,
                    model: model,
                    cache: &containmentCache,
                    preparationCache: &containmentPreparationCache,
                    tolerance: tolerance
                ) else {
                    continue
                }
                let target = try targetSurface.parameterProjection(of: intersection.point, tolerance: tolerance)
                let tool = try toolSurface.parameterProjection(of: intersection.point, tolerance: tolerance)
                let point = try BooleanUVPoint(
                    point: intersection.point,
                    targetU: target.u,
                    targetV: target.v,
                    toolU: tool.u,
                    toolV: tool.v,
                    residual: max(intersection.residual, target.residual, tool.residual),
                    tolerance: tolerance
                )
                if points.contains(where: { ($0.point - point.point).length <= tolerance.distance }) == false {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func contains(
        _ point: Point3D,
        faceID: FaceID,
        surface: Surface3D,
        model: BRepModel,
        cache: inout [FacePointContainmentCacheKey: Bool],
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        _ = surface
        let key = FacePointContainmentCacheKey(faceID: faceID, point: point)
        if let cached = cache[key] {
            return cached
        }
        let result: Bool
        if let defaultTester = facePointContainment as? DefaultFacePointContainmentTester {
            result = try defaultTester.contains(
                point,
                on: faceID,
                in: model,
                preparationCache: &preparationCache,
                tolerance: tolerance
            )
        } else {
            result = try facePointContainment.contains(
                point,
                on: faceID,
                in: model,
                tolerance: tolerance
            )
        }
        cache[key] = result
        return result
    }

    private func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private enum CurvedClipResult {
        case empty
        case closed(BooleanClosedFaceIntersection)
        case trimmed([BooleanTrimmedFaceIntersectionChain])
    }

    private struct ClipContact {
        let parameter: Double
        let point: Point3D
    }

    private struct TrimmedIntervalRecord {
        let ordinal: Int
        let segment: BooleanTrimmedFaceIntersection
    }

    private struct FacePointContainmentCacheKey: Hashable {
        let faceID: FaceID
        let point: Point3D
    }
}
