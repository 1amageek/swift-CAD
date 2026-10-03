import Foundation
import CADCore
import CADGeometry
import CADIR

/// A pipe as the sweep of its section along its path: the path is cut to the pipe's start and end
/// fractions of its length, or run on straight along its end tangents where they pass 0 or 1, the
/// circle or polygon, or the custom profile placed by `PipeCustomSectionPlacement` (hollow for a
/// wall: outward of the section when positive, inward when negative), is laid across the path's
/// start, turned by the pipe's angle and twisted along it, and both are handed to Sweep in a
/// context that holds
/// them under the pipe's own identity. Straight paths, single arcs and curved paths then take
/// Sweep's exact or certified routes, and a Boolean combines with the pipe's targets.
package struct PipeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sweep: PlanarSweepFeatureEvaluator
    private let resolver: ParameterResolving

    package init(sweep: PlanarSweepFeatureEvaluator, resolver: ParameterResolving = ParameterResolver()) {
        self.sweep = sweep
        self.resolver = resolver
    }

    package func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        let tolerance = context.tolerance
        try tolerance.validate()
        guard case let .pipe(pipe) = feature.operation else {
            throw failure(.invalidInput, feature.id, tolerance, "The pipe evaluator received another feature.")
        }
        try pipe.validate()
        func value(_ expression: CADExpression, _ kind: QuantityKind) throws -> Double {
            let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
            guard quantity.kind == kind, quantity.value.isFinite else {
                throw failure(.invalidInput, feature.id, tolerance, "A pipe's value has the wrong kind.")
            }
            return quantity.value
        }
        let radius = try pipe.diameter.map { try value($0, .length) / 2 }
        let wall = try pipe.thickness.map { try value($0, .length) }
        let angle = try value(pipe.angle, .angle)
        // A circle turns into itself, so only a polygon's or a custom profile's twist is swept.
        let twist = try value(pipe.twist, .angle) != 0 && (pipe.profile != nil || pipe.vertexCount > 0)
            ? pipe.twist : .constant(.angle(0, unit: .degree))
        let start = try value(pipe.start, .scalar)
        let end = try value(pipe.end, .scalar)
        let sectionAdmitted = radius.map { radius in radius > tolerance.distance && (wall.map { $0 > 0 || -$0 < radius } ?? true) } ?? true
        guard sectionAdmitted, wall.map({ abs($0) > tolerance.distance }) ?? true, start < end, start < 1, end > 0 else {
            throw failure(.invalidInput, feature.id, tolerance,
                "A pipe needs a positive diameter, a nonzero wall (inward thinner than its radius), and start < end with start below 1 and end above 0.")
        }
        guard let curves = context.curves[pipe.path.featureID], curves.isEmpty == false else {
            throw FeatureEvaluationError.missingInput("A pipe's path curve was not evaluated.")
        }
        let chain = try EvaluatedCurveChainBuilder(tolerance: tolerance).connectedSegments(from: curves, operationName: "Pipe path")
        let segments = chain.segments
        guard segments.allSatisfy({ $0.curve.exactCurve != nil }) else {
            throw failure(.invalidInput, feature.id, tolerance, "A pipe follows an exact path curve.")
        }
        // A closed path runs on into itself: it has no ends to extend past, and taken whole the
        // pipe closes into a ring.
        guard chain.isClosed == false || (start >= 0 && end <= 1) else {
            throw failure(.invalidInput, feature.id, tolerance, "A pipe along a closed path runs within it, from 0 to 1.")
        }
        let wholeSpans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).pathSpans(from: segments, allowsClosed: chain.isClosed)
        let spans = chain.isClosed && start == 0 && end == 1
            ? wholeSpans
            : try extended(
                try cut(wholeSpans, from: max(start, 0), to: min(end, 1), featureID: feature.id, tolerance: tolerance),
                before: -min(start, 0), after: max(end, 1) - 1, featureID: feature.id, tolerance: tolerance
            )
        let geometry = try spans[0].curve.differentialGeometry(at: try lower(of: spans[0].curve), tolerance: tolerance)
        let tangent = try geometry.firstDerivative.normalized(tolerance: tolerance.distance)
        let sections: [Profile]
        if let custom = pipe.profile {
            guard case let .profile(source, _) = try ResolvedModelingSection.resolve(custom, context: context, featureID: feature.id) else {
                throw failure(.invalidInput, feature.id, tolerance, "A pipe's custom profile is a region or a planar face.")
            }
            sections = try PipeCustomSectionPlacement(tolerance: tolerance).placed(
                source, featureID: feature.id, origin: geometry.position, tangent: tangent, angle: angle, wall: wall
            )
        } else if let radius {
            sections = [try profile(
                featureID: feature.id, origin: geometry.position, normal: tangent,
                radius: radius, wall: wall, vertexCount: pipe.vertexCount, angle: angle, tolerance: tolerance
            )]
        } else {
            throw failure(.invalidInput, feature.id, tolerance, "A pipe has either a diameter or a custom profile.")
        }
        let path = try ExactCompositeBSplineCurveBuilder().build(spans: spans.map(\.curve), tolerance: tolerance)
        guard case let .closed(pathLower, pathUpper) = path.domain else {
            throw failure(.invalidInput, feature.id, tolerance, "A pipe's path has no bounded domain.")
        }
        let parameters = (0...32).map { pathLower + (pathUpper - pathLower) * Double($0) / 32 }
        let pathID = featureEvaluationStageID(featureID: feature.id, domain: .pipePath, ordinal: 0)
        var staged = context
        staged.curves[pathID] = [EvaluatedCurve(
            sourceFeatureID: pathID, source: .generatedFeature, kind: .spline,
            points: try parameters.map { try path.point(at: $0, tolerance: tolerance) },
            exactCurve: .bSpline(path), exactParameterDomain: path.domain, exactPointParameters: parameters
        )]
        /// The sweep of one section along the path under `id`, combined by `operation` with
        /// `targets`.
        func sweepNode(_ id: FeatureID, operation: SweepBooleanOperation, targets: [SweepTargetReference]) -> FeatureNode {
            FeatureNode(id: id, name: feature.name, operation: .sweep(SweepFeature(
                sections: [.profile(ProfileReference(featureID: id))],
                path: SweepPathReference(featureID: pathID),
                targets: targets,
                options: SweepOptions(
                    twistAngle: twist,
                    endScale: pipe.endScale,
                    alignment: .normal,
                    booleanOperation: operation,
                    keepTools: pipe.keepTools,
                    resultKind: .solid,
                    approximationTolerance: pipe.approximationTolerance
                )
            )), inputs: feature.inputs, outputs: feature.outputs, isSuppressed: feature.isSuppressed)
        }
        guard sections.count > 1 else {
            staged.profiles[feature.id] = sections
            return try sweep.evaluateValidated(feature: sweepNode(feature.id, operation: pipe.booleanOperation, targets: pipe.targets),
                                               context: staged)
        }
        // A hollow custom section with holes: one ring per loop, swept in turn. Each ring after the
        // first joins the ones before (or, with a Boolean, works on the targets they left), so the
        // last sweep publishes one body.
        guard [.newBody, .union, .difference].contains(pipe.booleanOperation), pipe.keepTools == false else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a hollow pipe of a section with holes intersected
            // with or slicing its targets, or keeping its tools, would apply the Boolean to the
            // rings' union, which the staged sweeps do not build, so it is refused. Production
            // path: PipeFeatureEvaluator for a custom profile with holes and a thickness. Complete
            // only when the rings' union takes every Boolean, verified by intersecting such a pipe.
            throw failure(.unsupportedCapability, feature.id, tolerance,
                          "A hollow pipe of a section with holes makes a new body, or joins or cuts its targets without keeping its tools.")
        }
        var stages = FeatureEvaluationStages(staged)
        var previous: [SweepTargetReference] = pipe.targets
        for (index, ring) in sections.enumerated() {
            let last = index == sections.count - 1
            let id = last ? feature.id : featureEvaluationStageID(featureID: feature.id, domain: .pipeRing, ordinal: UInt64(index))
            var context = stages.context
            context.profiles[id] = [Profile(sourceFeatureID: id, plane: ring.plane, outerLoop: ring.outerLoop, innerLoops: ring.innerLoops)]
            let operation: SweepBooleanOperation
            let targets: [SweepTargetReference]
            if pipe.booleanOperation == .newBody {
                // The first ring stands alone; each next joins the body before it.
                (operation, targets) = index == 0 ? (.newBody, []) : (.union, previous)
            } else {
                (operation, targets) = (pipe.booleanOperation, previous)
            }
            let result = try sweep.evaluateValidated(feature: sweepNode(id, operation: operation, targets: targets), context: context).result
            if last {
                return try ValidatedFeatureEvaluation(validating: try stages.publish(result, featureID: feature.id), tolerance: tolerance)
            }
            stages.apply(result)
            previous = [SweepTargetReference(featureID: id)]
        }
        throw failure(.invalidInput, feature.id, tolerance, "A pipe has a section.")
    }

    /// The circle or regular polygon of `radius` across `normal` at `origin`, its first vertex (or
    /// seam) turned by `angle`, with the wall's hole when `wall` is given.
    private func profile(
        featureID: FeatureID, origin: Point3D, normal: Vector3D, radius: Double, wall: Double?,
        vertexCount: Int, angle: Double, tolerance: ModelingTolerance
    ) throws -> Profile {
        let seed: Vector3D = abs(normal.x) < 0.6 ? .unitX : .unitY
        let first = try normal.cross(seed).normalized(tolerance: tolerance.distance)
        let second = normal.cross(first)
        func point(_ r: Double, _ theta: Double) -> Point3D {
            origin + first * (r * cos(theta + angle)) + second * (r * sin(theta + angle))
        }
        func loop(_ r: Double, reversed: Bool) -> ProfileLoop {
            var segments: [ProfileBoundarySegment]
            var vertices: [Point3D]
            if vertexCount == 0 {
                // Two half circles, counterclockwise about the normal.
                let arcs = [(0.0, Double.pi), (Double.pi, 2 * Double.pi)]
                segments = arcs.map { lower, upper in
                    .circularArc(ProfileCircularArcSegment(
                        center: origin, normal: normal, radius: r, start: point(r, lower), end: point(r, upper), sweepAngle: Double.pi
                    ))
                }
                vertices = (0..<16).map { point(r, 2 * Double.pi * Double($0) / 16) }
            } else {
                vertices = (0..<vertexCount).map { point(r, 2 * Double.pi * Double($0) / Double(vertexCount)) }
                segments = vertices.indices.map { .line(ProfileLineSegment(start: vertices[$0], end: vertices[($0 + 1) % vertices.count])) }
            }
            guard reversed else { return ProfileLoop(vertices: vertices, boundarySegments: segments) }
            segments = segments.reversed().map { segment in
                switch segment {
                case let .line(line): .line(ProfileLineSegment(start: line.end, end: line.start))
                case let .circularArc(arc):
                    .circularArc(ProfileCircularArcSegment(
                        center: arc.center, normal: arc.normal, radius: arc.radius, start: arc.end, end: arc.start, sweepAngle: -arc.sweepAngle
                    ))
                case .spline: segment
                }
            }
            return ProfileLoop(vertices: vertices.reversed(), boundarySegments: segments)
        }
        // The wall keeps the section's shape, measured across the sides: a positive wall grows the
        // outside past the section (the hole is the section), a negative one hollows it.
        let across = vertexCount == 0 ? 1 : cos(Double.pi / Double(vertexCount))
        let (outer, inner): (Double, Double?) = switch wall {
        case let wall? where wall > 0: (radius + wall / across, radius)
        case let wall?: (radius, radius + wall / across)
        case nil: (radius, nil)
        }
        if let inner, inner <= tolerance.distance {
            throw failure(.invalidInput, featureID, tolerance, "A pipe's wall is as thick as its section.")
        }
        return Profile(
            sourceFeatureID: featureID,
            plane: .plane(Plane3D(origin: origin, normal: normal)),
            outerLoop: loop(outer, reversed: false),
            innerLoops: inner.map { [loop($0, reversed: true)] } ?? []
        )
    }

    /// The path spans between the `start` and `end` fractions of its length.
    private func cut(
        _ spans: [ExactBSplineCurveSpan], from start: Double, to end: Double, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> [ExactBSplineCurveSpan] {
        guard start > 0 || end < 1 else { return spans }
        let lengths = try spans.map { try length(of: $0.curve, tolerance: tolerance) }
        let total = lengths.reduce(0, +)
        let (from, to) = (start * total, end * total)
        var result: [ExactBSplineCurveSpan] = []
        var covered = 0.0
        for (span, spanLength) in zip(spans, lengths) {
            defer { covered += spanLength }
            let (spanStart, spanEnd) = (covered, covered + spanLength)
            guard spanEnd > from, spanStart < to else { continue }
            let (lower, upper) = (try self.lower(of: span.curve), try self.upper(of: span.curve))
            let a = from > spanStart ? try parameter(of: span.curve, atLength: from - spanStart, tolerance: tolerance) : lower
            let b = to < spanEnd ? try parameter(of: span.curve, atLength: to - spanStart, tolerance: tolerance) : upper
            guard b - a > tolerance.angle else { continue }
            result.append(a == lower && b == upper ? span
                : try ExactBSplineCurveSpan(curve: span.curve.trimmed(from: a, to: b, tolerance: tolerance), tolerance: tolerance))
        }
        guard result.isEmpty == false else {
            throw failure(.invalidInput, featureID, tolerance, "A pipe's start and end leave no path.")
        }
        return result
    }

    /// `spans` run on straight along their start tangent by `before` and their end tangent by
    /// `after`, each a fraction of the spans' length.
    private func extended(
        _ spans: [ExactBSplineCurveSpan], before: Double, after: Double, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> [ExactBSplineCurveSpan] {
        guard before > 0 || after > 0, let first = spans.first, let last = spans.last else { return spans }
        let total = try spans.reduce(0.0) { $0 + (try length(of: $1.curve, tolerance: tolerance)) }
        func line(from start: Point3D, to end: Point3D) throws -> ExactBSplineCurveSpan {
            try ExactBSplineCurveSpan(curve: BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [start, end], weights: [1, 1]),
                                      tolerance: tolerance)
        }
        /// Whether `span` is a straight segment along `direction`, which an extension then lengthens.
        func straight(_ span: ExactBSplineCurveSpan, along direction: Vector3D) -> Bool {
            let chord = span.endPoint - span.startPoint
            guard chord.length > tolerance.distance, chord.cross(direction).length <= tolerance.angle * chord.length else { return false }
            return span.curve.controlPoints.allSatisfy { ($0 - span.startPoint).cross(chord).length <= tolerance.distance * chord.length }
        }
        var result = spans
        if before > 0 {
            let at = try first.curve.differentialGeometry(at: try lower(of: first.curve), tolerance: tolerance)
            let tangent = try at.firstDerivative.normalized(tolerance: tolerance.distance)
            let from = at.position + tangent * (-before * total)
            // A straight first span runs back as one line, so a straight pipe stays one span.
            if straight(first, along: tangent) {
                result[0] = try line(from: from, to: first.endPoint)
            } else {
                result.insert(try line(from: from, to: at.position), at: 0)
            }
        }
        if after > 0, let tail = result.last {
            let at = try last.curve.differentialGeometry(at: try upper(of: last.curve), tolerance: tolerance)
            let tangent = try at.firstDerivative.normalized(tolerance: tolerance.distance)
            let to = at.position + tangent * (after * total)
            if straight(tail, along: tangent) {
                result[result.count - 1] = try line(from: tail.startPoint, to: to)
            } else {
                result.append(try line(from: at.position, to: to))
            }
        }
        return result
    }

    /// The arc length of `curve` over its whole domain, by composite Gauss–Legendre quadrature.
    private func length(of curve: BSplineCurve3D, from lower: Double? = nil, to upper: Double? = nil, tolerance: ModelingTolerance) throws -> Double {
        let a = try lower ?? self.lower(of: curve), b = try upper ?? self.upper(of: curve)
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        let pieces = 64
        var sum = 0.0
        for index in 0..<pieces {
            let left = a + (b - a) * Double(index) / Double(pieces), half = (b - a) / Double(2 * pieces)
            for (node, weight) in zip(nodes, weights) {
                sum += weight * half * (try curve.differentialGeometry(at: left + half * (1 + node), tolerance: tolerance)).firstDerivative.length
            }
        }
        return sum
    }

    /// The parameter where `curve` has run `target` of its length, by bisection.
    private func parameter(of curve: BSplineCurve3D, atLength target: Double, tolerance: ModelingTolerance) throws -> Double {
        var (low, high) = (try lower(of: curve), try upper(of: curve))
        let start = low
        for _ in 0..<60 {
            let middle = 0.5 * (low + high)
            if try length(of: curve, from: start, to: middle, tolerance: tolerance) < target { low = middle } else { high = middle }
        }
        return 0.5 * (low + high)
    }

    private func lower(of curve: BSplineCurve3D) throws -> Double {
        guard case let .closed(lower, _) = curve.domain else { throw FeatureEvaluationError.invalidGraph("A pipe's path span is unbounded.") }
        return lower
    }

    private func upper(of curve: BSplineCurve3D) throws -> Double {
        guard case let .closed(_, upper) = curve.domain else { throw FeatureEvaluationError.invalidGraph("A pipe's path span is unbounded.") }
        return upper
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
