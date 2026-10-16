import HashTreeCollections
#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A planar face read as a profile: its plane with the face's outward normal, and its loops, the
/// outer one counterclockwise about that normal and the holes clockwise, each edge as the exact
/// segment it is, using exact conics and certified native-curve conversion.
package struct FaceSectionProfileResolver: Sendable {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    package func profile(for reference: FaceSectionReference, context: EvaluationContext, featureID: FeatureID) throws -> Profile {
        try resolve(for: reference, context: context, featureID: featureID).profile
    }

    package func resolve(for reference: FaceSectionReference, context: EvaluationContext,
        featureID: FeatureID, sourceBudget: CurvedSweepSourceBudget? = nil) throws -> ResolvedFaceSection {
        let owner = try sourceBudget ?? CurvedSweepSourceBudget(tolerance: context.tolerance)
        var execution = try owner.execution()
        return try resolve(for: reference, context: context, featureID: featureID, using: &execution)
    }

    package func resolve(for reference: FaceSectionReference, context: EvaluationContext,
        featureID: FeatureID, using execution: inout OriginalQueryExecution) throws -> ResolvedFaceSection {
        let tolerance = context.tolerance
        let model = context.brep
        let bodyID = try context.bodyID(generatedBy: reference.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let resolved = try subshapeResolver.topologyReference(
            for: reference.face, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        )
        guard case let .face(faceID) = resolved, scope.references.contains(.face(faceID)), let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: reference.face.subshapeID,
                              tolerance: tolerance, message: "A face section did not resolve to a face of its body.")
        }
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "A face section is a planar face.")
        }
        let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
        let normal = face.orientation == .forward ? planeNormal : planeNormal * -1
        var outer: ProfileLoop?
        var outerSource: OriginalFaceSectionLoop?
        var inner: [ProfileLoop] = []
        var innerSources: [OriginalFaceSectionLoop] = []
        try retain(face.loops.count, of: ProfileLoop.self, using: &execution)
        try retain(face.loops.count, of: OriginalFaceSectionLoop.self, using: &execution)
        inner.reserveCapacity(face.loops.count)
        innerSources.reserveCapacity(face.loops.count)
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A face section's loop is missing.") }
            try retain(loop.coedges.count, of: OriginalFaceSectionSegment.self, using: &execution)
            var originalSegments: [OriginalFaceSectionSegment] = []
            originalSegments.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID],
                      let trim = edge.trim else { throw TopologyError.missingReference("Original face boundary trim is missing.") }
                originalSegments.append(try OriginalFaceSectionSegment(edgeID: edge.id, curve: curve,
                    startParameter: coedge.orientation == .forward ? trim.startParameter : trim.endParameter,
                    endParameter: coedge.orientation == .forward ? trim.endParameter : trim.startParameter,
                    tolerance: tolerance, using: &execution))
            }
            let counterclockwise = try OriginalPlanarLoopOrientation().counterclockwise(originalSegments,
                origin: plane.origin, normal: normal, tolerance: tolerance, using: &execution)
            var segments: [ProfileBoundarySegment] = []
            var segmentCapacity = 0
            for (index, coedge) in loop.coedges.enumerated() {
                let pieces = try self.segments(of: coedge, original: originalSegments[index], model: model,
                    featureID: featureID, tolerance: tolerance, using: &execution)
                let (required, overflow) = segments.count.addingReportingOverflow(pieces.count)
                guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Face section segment capacity overflowed.") }
                if required > segmentCapacity {
                    let (doubled, doubledOverflow) = segmentCapacity.multipliedReportingOverflow(by: 2)
                    let capacity = doubledOverflow ? required : max(required, max(1, doubled))
                    try retain(capacity, of: ProfileBoundarySegment.self, using: &execution)
                    try execution.consumeWork(segments.count)
                    segments.reserveCapacity(capacity)
                    segmentCapacity = capacity
                }
                for piece in pieces {
                    try execution.consumeWork(1)
                    segments.append(piece)
                }
            }
            if counterclockwise != (loop.role == .outer) {
                for index in 0..<(originalSegments.count / 2) {
                    try execution.consumeWork(1)
                    let other = originalSegments.count - 1 - index
                    let first = originalSegments[index].reversed()
                    originalSegments[index] = originalSegments[other].reversed()
                    originalSegments[other] = first
                }
                if originalSegments.count % 2 == 1 {
                    try execution.consumeWork(1)
                    let middle = originalSegments.count / 2
                    originalSegments[middle] = originalSegments[middle].reversed()
                }
                segments = try reversed(segments, tolerance: tolerance, using: &execution)
            }
            let originalLoop = OriginalFaceSectionLoop(loopID: loopID, role: loop.role, segments: originalSegments)
            let profileLoop = ProfileLoop(vertices: try samples(of: segments,
                tolerance: tolerance, using: &execution), boundarySegments: segments)
            if loop.role == .outer {
                guard outer == nil else {
                    throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                      message: "A face section has more than one outer loop.")
                }
                outer = profileLoop
                outerSource = originalLoop
            } else {
                inner.append(profileLoop)
                innerSources.append(originalLoop)
            }
        }
        guard let outer, let outerSource else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A face section needs an outer loop.")
        }
        let profile = Profile(
            sourceFeatureID: reference.featureID,
            plane: .plane(Plane3D(origin: plane.origin, normal: normal)),
            outerLoop: outer,
            innerLoops: inner
        )
        let (loopCount, overflow) = innerSources.count.addingReportingOverflow(1)
        guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Face section loop capacity overflowed.") }
        try retain(loopCount, of: OriginalFaceSectionLoop.self, using: &execution)
        var sources: [OriginalFaceSectionLoop] = []
        sources.reserveCapacity(loopCount)
        sources.append(outerSource)
        for source in innerSources { try execution.consumeWork(1); sources.append(source) }
        return ResolvedFaceSection(faceID: faceID, profile: profile, loops: sources)
    }

    /// The segment a coedge runs along, in the coedge's direction.
    private func segments(of coedge: Coedge, original: OriginalFaceSectionSegment,
        model: BRepModel, featureID: FeatureID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [ProfileBoundarySegment] {
        try execution.consumeWork(1)
        guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
              let first = model.vertices[edge.startVertexID]?.point, let last = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("A face section's edge is missing.")
        }
        let forward = coedge.orientation == .forward
        let (start, end) = forward ? (first, last) : (last, first)
        try execution.retainStorage(bytes: MemoryLayout<ProfileBoundarySegment>.stride)
        switch curve {
        case .line, .analytic(.line):
            return [.line(ProfileLineSegment(start: start, end: end))]
        case let .circle(circle):
            let sweep = (trim.endParameter - trim.startParameter) * (forward ? 1 : -1)
            return [.circularArc(ProfileCircularArcSegment(
                center: circle.center, normal: circle.normal, radius: circle.radius, start: start, end: end, sweepAngle: sweep
            ))]
        case let .analytic(.circle(center, circleNormal, radius)):
            let sweep = (trim.endParameter - trim.startParameter) * (forward ? 1 : -1)
            return [.circularArc(ProfileCircularArcSegment(
                center: center, normal: circleNormal, radius: radius, start: start, end: end, sweepAngle: sweep
            ))]
        default:
            let pieces = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, using: &execution)
                .sectionSpans(sourceOwner: original.source,
                    lower: min(original.startParameter, original.endParameter),
                    upper: max(original.startParameter, original.endParameter), using: &execution)
            try retain(pieces.count, of: ProfileBoundarySegment.self, using: &execution)
            let directed = original.startParameter < original.endParameter
            return try pieces.indices.map { index in
                try execution.consumeWork(1)
                let piece = pieces[directed ? index : pieces.count - 1 - index].curve
                let result: BSplineCurve3D
                if directed { result = piece }
                else {
                    try admitReversal(piece, using: &execution)
                    result = try piece.reversed(tolerance: tolerance)
                }
                return .spline(ProfileSplineSegment(curve: result))
            }
        }
    }

    /// Compatibility display points only; no sample supplies source winding authority.
    private func samples(of segments: [ProfileBoundarySegment], tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        var pointCount = 0
        for segment in segments {
            try execution.consumeWork(1)
            let count: Int
            switch segment { case .line: count = 1; case .circularArc, .spline: count = 8 }
            let (next, overflow) = pointCount.addingReportingOverflow(count)
            guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Face presentation station count overflowed.") }
            pointCount = next
        }
        try retain(pointCount, of: Point3D.self, using: &execution)
        var points: [Point3D] = []
        points.reserveCapacity(pointCount)
        for segment in segments {
            switch segment {
            case let .line(line):
                try execution.consumeWork(1)
                points.append(line.start)
            case let .circularArc(arc):
                let radial = arc.start - arc.center
                guard arc.normal.length.isFinite, arc.normal.length > 0 else {
                    throw GeometryConversionError.invalidInput("A circular facade requires a finite nonzero original normal.")
                }
                let normal = arc.normal * (1 / arc.normal.length)
                let axis = normal.cross(radial)
                for index in 0..<8 {
                    try execution.consumeWork(1)
                    let angle = arc.sweepAngle * Double(index) / 8
                    points.append(arc.center + radial * cos(angle) + axis * sin(angle))
                }
            case let .spline(spline):
                guard case let .closed(lower, upper) = spline.curve.domain else {
                    throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: .standard,
                                      message: "A face section's spline edge has no bounded domain.")
                }
                let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(spline.curve),
                    tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                    using: &execution)
                for index in 0..<8 {
                    try execution.consumeWork(1)
                    let station = lower * (1 - Double(index) / 8) + upper * (Double(index) / 8)
                    let receipt = try prepared.closedNativeJets(over: ScalarInterval(lower: station, upper: station),
                        tolerance: tolerance, maximumSpanCount: execution.effectiveLimits.maximumSpans,
                        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                        using: &execution)
                    guard let first = receipt.spans.first else {
                        throw GeometryConversionError.invalidInput("A facade station has no candidate native owner.")
                    }
                    var x = first.jet.x.value
                    var y = first.jet.y.value
                    var z = first.jet.z.value
                    for owner in receipt.spans.dropFirst() {
                        try execution.consumeWork(1)
                        x = .init(lower: min(x.lower, owner.jet.x.value.lower), upper: max(x.upper, owner.jet.x.value.upper))
                        y = .init(lower: min(y.lower, owner.jet.y.value.lower), upper: max(y.upper, owner.jet.y.value.upper))
                        z = .init(lower: min(z.lower, owner.jet.z.value.lower), upper: max(z.upper, owner.jet.z.value.upper))
                    }
                    points.append(Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint))
                }
            }
        }
        return points
    }

    private func reversed(_ segments: [ProfileBoundarySegment], tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [ProfileBoundarySegment] {
        try retain(segments.count, of: ProfileBoundarySegment.self, using: &execution)
        return try segments.reversed().map { segment in
            try execution.consumeWork(1)
            switch segment {
            case let .line(line):
                return .line(ProfileLineSegment(start: line.end, end: line.start))
            case let .circularArc(arc):
                return .circularArc(ProfileCircularArcSegment(
                    center: arc.center, normal: arc.normal, radius: arc.radius, start: arc.end, end: arc.start, sweepAngle: -arc.sweepAngle
                ))
            case let .spline(spline):
                try admitReversal(spline.curve, using: &execution)
                return .spline(ProfileSplineSegment(curve: try spline.curve.reversed(tolerance: tolerance)))
            }
        }
    }

    private func admitReversal(_ curve: BSplineCurve3D,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(curve.knots.count + 2 * curve.controlPointCount)
        try execution.retainStorage(bytes: curve.knots.count * MemoryLayout<Double>.stride
            + curve.controlPointCount * (MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride))
    }

    private func retain<Value>(_ count: Int, of: Value.Type,
        using execution: inout OriginalQueryExecution) throws {
        let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
        guard count >= 0, !overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Face section payload size overflowed.")
        }
        try execution.retainStorage(bytes: bytes)
    }
}
