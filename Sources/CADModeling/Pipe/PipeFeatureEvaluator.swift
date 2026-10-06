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
        // Circle symmetry is established by the original correspondence proof;
        // the authored law survives the nested Sweep like every other section.
        let twist = pipe.twist
        _ = try value(twist, .angle)
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
        let sourceBudget = try CurvedSweepSourceBudget(tolerance: tolerance)
        let admission = try sourceBudget.conversionAdmission()
        let wholeSpans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission).pathSpans(from: segments, allowsClosed: chain.isClosed)
        let spans = chain.isClosed && start == 0 && end == 1
            ? wholeSpans
            : try extended(
                try cut(wholeSpans, from: max(start, 0), to: min(end, 1), featureID: feature.id, tolerance: tolerance, admission: admission),
                before: -min(start, 0), after: max(end, 1) - 1, featureID: feature.id, tolerance: tolerance
            )
        let pathInvocation = try OriginalSweepInvocation(pathSpans: spans,
            pathIsClosed: chain.isClosed && start == 0 && end == 1, sourceBudget: sourceBudget)
        let pose = try OriginalPipeStartPose(span: spans[0], featureID: feature.id,
            tolerance: tolerance, admission: admission)
        let tangent = pose.tangent
        let sections: [Profile]
        var retainedSection: ResolvedModelingSection?
        if let custom = pipe.profile {
            let resolved = try ResolvedModelingSection.resolve(custom, context: context, featureID: feature.id, sourceBudget: sourceBudget)
            let placement = PipeCustomSectionPlacement(tolerance: tolerance)
            if wall == nil {
                let region = try placement.placedRegion(resolved, featureID: feature.id,
                    origin: pose.origin, tangent: tangent, angle: angle, admission: admission)
                retainedSection = .constructedRegion(region)
                sections = [region.profile]
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Hollow custom sections still
                // need retained original placed offset/join laws for every ring.
                // The existing facade offset is a bounded construction candidate;
                // it must not close complete original-region Pipe support.
                if case .face = resolved {
                    throw failure(.unsupportedCapability, feature.id, tolerance,
                        "Hollow original face Pipe requires retained offset region laws.")
                }
                sections = try placement.placed(resolved.profileFacade(), featureID: feature.id,
                    origin: pose.origin, tangent: tangent, angle: angle, wall: wall,
                    admission: admission)
            }
        } else if let radius {
            sections = [try profile(
                featureID: feature.id, origin: pose.origin, normal: tangent,
                radius: radius, wall: wall, vertexCount: pipe.vertexCount, angle: angle, tolerance: tolerance
            )]
        } else {
            throw failure(.invalidInput, feature.id, tolerance, "A pipe has either a diameter or a custom profile.")
        }
        let invocation = try OriginalSweepInvocation(section: retainedSection,
            pathSpans: pathInvocation.pathSpans, pathIsClosed: pathInvocation.pathIsClosed,
            sourceBudget: sourceBudget)
        let pathID = featureEvaluationStageID(featureID: feature.id, domain: .pipePath, ordinal: 0)
        var staged = context
        let curveBytes = spans.count.multipliedReportingOverflow(by: MemoryLayout<EvaluatedCurve>.stride)
        guard !curveBytes.overflow else {
            throw failure(.resourceLimitExceeded, feature.id, tolerance, "Original Pipe staging capacity overflows.")
        }
        try admission.chargeStorage(bytes: curveBytes.partialValue)
        var stagedPaths: [EvaluatedCurve] = []
        stagedPaths.reserveCapacity(spans.count)
        for span in spans {
            let original = try span.originalChart.persistentCurve(tolerance: tolerance, admission: admission)
            let prepared = try PreparedCurveDifferentialEncloser(curve: original, tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
            try admission.chargeStorage(bytes: 33 * (MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride))
            var parameters: [Double] = [], points: [Point3D] = []
            parameters.reserveCapacity(33); points.reserveCapacity(33)
            for index in 0...32 {
                try admission.chargeWork()
                let parameter = Double(index) / 32
                let owners = try prepared.closedNativeJets(over: ScalarInterval(lower: parameter, upper: parameter),
                    tolerance: tolerance, maximumSpanCount: admission.maximumSpanCount,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) })
                var x: OutwardScalarInterval?, y: OutwardScalarInterval?, z: OutwardScalarInterval?
                func append(_ value: OutwardScalarInterval, to hull: inout OutwardScalarInterval?) {
                    hull = hull.map { .init(lower: min($0.lower, value.lower), upper: max($0.upper, value.upper)) } ?? value
                }
                for owner in owners.spans {
                    try admission.chargeWork()
                    append(owner.jet.x.value, to: &x); append(owner.jet.y.value, to: &y); append(owner.jet.z.value, to: &z)
                }
                guard let x, let y, let z, x.isFinite, y.isFinite, z.isFinite else {
                    throw failure(.resourceLimitExceeded, feature.id, tolerance, "Original Pipe staging has no complete finite position bound.")
                }
                let point = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
                let error = IntervalVector3DBounds(x: x - .exact(point.x), y: y - .exact(point.y), z: z - .exact(point.z)).lengthUpperBound
                guard error <= tolerance.distance else {
                    throw failure(.resourceLimitExceeded, feature.id, tolerance, "Original Pipe staging uncertainty exceeds its distance allowance.")
                }
                parameters.append(parameter); points.append(point)
            }
            stagedPaths.append(EvaluatedCurve(sourceFeatureID: pathID, source: .generatedFeature,
                kind: .spline, points: points, exactCurve: original,
                exactParameterDomain: .closed(0, 1), exactPointParameters: parameters))
        }
        staged.curves[pathID] = stagedPaths
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
                                               context: staged, originalInvocation: invocation)
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
            let result = try sweep.evaluateValidated(feature: sweepNode(id, operation: operation, targets: targets), context: context, originalInvocation: invocation).result
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

    /// Retains the original inverse-length law at both selected fractions.
    private func cut(
        _ spans: [ExactBSplineCurveSpan], from start: Double, to end: Double,
        featureID: FeatureID, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission
    ) throws -> [ExactBSplineCurveSpan] {
        guard start > 0 || end < 1 else { return spans }
        if let span = spans.onlyElement, case .affine = span.originalChart.mapping,
           try isOriginalConstantSpeedLine(span.originalChart.curve, depth: 0, admission: admission) {
            let chart = try span.originalChart.admittingConstruction(admission)
                .restricted(from: start, to: end, in: .closed(0, 1), tolerance: tolerance)
            try admission.chargeStorage(bytes: MemoryLayout<ExactBSplineCurveSpan>.stride)
            return [try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission)
                .normalizedConstructionSpan(from: chart)]
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Production Pipe fraction cuts on
        // general original paths require a retained monotone inverse arc-length
        // endpoint expression. Quadrature and an inverse midpoint cannot define
        // the original trim; complete only when the original receipt survives
        // conversion, moving-frame construction and final publication.
        throw failure(.unsupportedCapability, featureID, tolerance,
            "Pipe fraction cuts require retained original inverse arc-length boundaries.")
    }

    private func isOriginalConstantSpeedLine(_ curve: Curve3D, depth: Int,
        admission: GeometryConversionAdmission) throws -> Bool {
        guard depth <= admission.remainingSourceDepth else {
            throw GeometryConversionError.resourceLimitExceeded("Original Pipe line source nesting exhausted.")
        }
        try admission.chargeWork()
        switch curve {
        case .line, .analytic(.line): return true
        case .rigidImage(let image):
            return try isOriginalConstantSpeedLine(image.source, depth: depth + 1, admission: admission)
        case .affineImage(let image):
            return try isOriginalConstantSpeedLine(image.source, depth: depth + 1, admission: admission)
        case .originalAffineWord(let image):
            return try isOriginalConstantSpeedLine(image.source, depth: depth + 1, admission: admission)
        case .parameterImage(let image):
            return try isOriginalConstantSpeedLine(image.source, depth: depth + 1, admission: admission)
        default: return false
        }
    }

    /// Original portions stay retained until extension length/tangent sources exist.
    private func extended(
        _ spans: [ExactBSplineCurveSpan], before: Double, after: Double,
        featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> [ExactBSplineCurveSpan] {
        guard before > 0 || after > 0 else { return spans }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Production Pipe tangent extensions
        // need an original total-length and endpoint-tangent expression, including
        // nonrepresentable length values. Generated line endpoints from numeric
        // quadrature do not retain that law. Complete only when source-bound
        // extension jets and published correspondence consume that same receipt.
        throw failure(.unsupportedCapability, featureID, tolerance,
            "Pipe tangent extensions require original length and tangent expressions.")
    }

    // Deprecated candidate-only numeric helpers have no production caller.
    // Retained until the original inverse-length receipt replaces their former
    // path; neither helper can authorize an original endpoint or output geometry.
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
