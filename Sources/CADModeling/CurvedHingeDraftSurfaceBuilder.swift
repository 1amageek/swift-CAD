#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry

/// Constructs exact common-apex cones or original cubic extrusion drafts with whole-law receipts.
package struct CurvedHingeDraftSurfaceBuilder {
    typealias Interval = OutwardScalarInterval
    typealias Jet = IntervalVectorDerivativeJet
    package static let maximumSpanCount = 4_096
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func surface(
        hinge: Curve3D, start: Double, end: Double,
        reference: Surface3D, referenceSign: Double,
        outward: Vector3D, angle: Double, reach: Double
    ) throws -> Surface3D {
        try construction(hinge: hinge, start: start, end: end, reference: reference,
                         referenceSign: referenceSign, outward: outward, angle: angle, reach: reach).surface
    }

    package struct Construction: Sendable {
        package let surface: Surface3D
        package let receipt: Receipt?
        fileprivate init(surface: Surface3D, receipt: Receipt?) {
            self.surface = surface
            self.receipt = receipt
        }
    }

    /// Only this producer can mint original-law authority. Consumers still prove incidence.
    package struct Receipt: Sendable {
        package let hinge: Curve3D
        package let reference: Surface3D
        package let start: Double
        package let end: Double
        package let referenceSign: Double
        package let outward: Vector3D
        package let angle: Double
        package let reach: Double
        package let tolerance: ModelingTolerance
        package let surface: Surface3D
        package let hingePcurve: SurfaceParameterCurve
        package let spans: [ClosedSpan]
        package let maximumPositionError: Double
        package let maximumRulingError: Double
        fileprivate init(hinge: Curve3D, reference: Surface3D, start: Double, end: Double,
                         referenceSign: Double, outward: Vector3D, angle: Double, reach: Double,
                         tolerance: ModelingTolerance, surface: Surface3D, hingePcurve: SurfaceParameterCurve,
                         spans: [ClosedSpan], maximumPositionError: Double, maximumRulingError: Double) {
            self.hinge = hinge; self.reference = reference; self.start = start; self.end = end
            self.referenceSign = referenceSign; self.outward = outward; self.angle = angle; self.reach = reach
            self.tolerance = tolerance; self.surface = surface; self.hingePcurve = hingePcurve
            self.spans = spans; self.maximumPositionError = maximumPositionError; self.maximumRulingError = maximumRulingError
        }

        package func validate(hinge: Curve3D, reference: Surface3D, start: Double, end: Double,
                              referenceSign: Double, output: Surface3D, tolerance: ModelingTolerance) throws {
            guard self.hinge == hinge, self.reference == reference, self.start == start, self.end == end,
                  self.referenceSign == referenceSign, self.surface == output, self.tolerance == tolerance else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "A cubic draft receipt does not belong to the original source and output.")
            }
        }
    }

    package struct ClosedSpan: Sendable {
        package let lower: Double
        package let upper: Double
    }

    package func construction(
        hinge: Curve3D, start: Double, end: Double,
        reference: Surface3D, referenceSign: Double,
        outward: Vector3D, angle: Double, reach: Double
    ) throws -> Construction {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        try hinge.validate(tolerance: tolerance)
        try reference.validate(tolerance: tolerance)
        try outward.validateUnitLength(tolerance: tolerance)
        guard start.isFinite, end.isFinite, start != end,
              try hinge.parameterDomain.containsSpan(from: start, to: end, tolerance: tolerance),
              referenceSign == 1 || referenceSign == -1,
              angle.isFinite, reach.isFinite, reach > tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A curved hinge draft requires a finite original trim, oriented reference and reach.")
        }
        let circle: Circle3D?
        switch hinge {
        case let .circle(value): circle = value
        case let .analytic(.circle(center, normal, radius)):
            circle = Circle3D(center: center, normal: normal, radius: radius)
        case let .analytic(.arc(center, normal, radius, _, _)):
            circle = Circle3D(center: center, normal: normal, radius: radius)
        default: circle = nil
        }
        if let circle,
           let cone = try cone(circle: circle, reference: reference, referenceSign: referenceSign,
                               outward: outward, tangent: tan(angle)) {
            return Construction(surface: cone, receipt: nil)
        }
        if let law = try OriginalLaw(hinge: hinge, reference: reference, start: start, end: end,
                                    referenceSign: referenceSign, outward: outward, angle: angle,
                                    reach: reach, tolerance: tolerance) {
            return try fitted(law: law, hinge: hinge, reference: reference, start: start, end: end,
                              referenceSign: referenceSign, outward: outward, angle: angle, reach: reach)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): General curved hinges do not yet have original
        // whole-range normal/ruling and adjacent-face authority. Production curved-reference
        // FaceDraftFeatureEvaluator dispatch reaches this refusal. Complete only when the
        // original ruled draft and all adjacent intersections are certified over their trims.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                          message: "A curved hinge draft has no original whole-range ruling certificate.")
    }

    /// Direct original polynomial coefficients, never a rounded extracted patch or a projection.
    struct OriginalLaw {
        enum Region: Equatable { case before, native, after }
        let curve: BSplineCurve3D
        let start: Double
        let end: Double
        let normalSign: Double
        let outward: Vector3D
        let tangent: Interval
        let carry: Interval
        let tolerance: ModelingTolerance

        init?(hinge: Curve3D, reference: Surface3D, start: Double, end: Double,
              referenceSign: Double, outward: Vector3D, angle: Double, reach: Double,
              tolerance: ModelingTolerance) throws {
            guard case let .bSpline(curve) = hinge, case let .bSpline(surface) = reference,
                  curve.degree == 3, curve.controlPoints.count == 4, curve.knots.count == 8,
                  curve.weights.allSatisfy({ $0 == 1 }), !curve.isPeriodic,
                  curve.knots.prefix(4).allSatisfy({ $0 == curve.knots[3] }),
                  curve.knots.suffix(4).allSatisfy({ $0 == curve.knots[4] }),
                  !surface.isUPeriodic, !surface.isVPeriodic,
                  surface.weights.flatMap({ $0 }).allSatisfy({ $0 == 1 }),
                  outward.y == 0, outward.z == 0, abs(outward.x) == 1 else { return nil }
            let rows: [[Point3D]]
            let knots: [Double]
            let alongU: Bool
            if surface.uDegree == 3, surface.vDegree == 1,
               surface.controlPoints.count == 2, surface.controlPoints.allSatisfy({ $0.count == 4 }),
               surface.vKnots.count == 4, surface.vKnots[0] == surface.vKnots[1], surface.vKnots[2] == surface.vKnots[3] {
                rows = surface.controlPoints; knots = surface.uKnots; alongU = true
            } else if surface.uDegree == 1, surface.vDegree == 3,
                      surface.controlPoints.count == 4, surface.controlPoints.allSatisfy({ $0.count == 2 }),
                      surface.uKnots.count == 4, surface.uKnots[0] == surface.uKnots[1], surface.uKnots[2] == surface.uKnots[3] {
                rows = [surface.controlPoints.map { $0[0] }, surface.controlPoints.map { $0[1] }]
                knots = surface.vKnots; alongU = false
            } else { return nil }
            guard knots == curve.knots, rows.contains(curve.controlPoints),
                  rows[0].allSatisfy({ $0.x == rows[0][0].x }),
                  rows[1].allSatisfy({ $0.x == rows[1][0].x }), rows[0][0].x != rows[1][0].x,
                  zip(rows[0], rows[1]).allSatisfy({ $0.y == $1.y && $0.z == $1.z }),
                  start >= curve.knots[3], start <= curve.knots[4],
                  end >= curve.knots[3], end <= curve.knots[4] else { return nil }
            if curve.controlPoints.allSatisfy({ $0 == curve.controlPoints[0] }) ||
                (start == curve.knots[3] && curve.controlPoints[0] == curve.controlPoints[1]) ||
                (end == curve.knots[4] && curve.controlPoints[2] == curve.controlPoints[3]) {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                                  message: "An original cubic draft hinge has a zero tangent.")
            }
            let rotation = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance)
            guard let tangent = rotation.sine.divided(by: rotation.cosine), tangent.isFinite else {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                                  message: "The original draft tangent is not finite.")
            }
            self.curve = curve; self.start = start; self.end = end; self.outward = outward
            self.normalSign = referenceSign * (rows[1][0].x > rows[0][0].x ? 1 : -1) * (alongU ? 1 : -1)
            self.tangent = tangent; self.carry = .exact(reach) * .exact(0.5); self.tolerance = tolerance
        }

        private func native(_ range: Interval) throws -> Jet {
            let width = Interval.exact(0.8) - .exact(0.2)
            let domain = Interval.exact(curve.knots[4]) - .exact(curve.knots[3])
            guard let nativeFraction = (range - .exact(0.2)).divided(by: width),
                  let fraction = (.exact(start) + (.exact(end) - .exact(start)) * nativeFraction - .exact(curve.knots[3])).divided(by: domain),
                  let scale = (.exact(end) - .exact(start)).divided(by: width * domain) else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "An original cubic parameter width is invalid.")
            }
            var controls = curve.controlPoints.map { [Interval.exact($0.x), .exact($0.y), .exact($0.z)] }
            var derivatives: [[Interval]] = []
            var factor = Interval.exact(1)
            for order in 0...5 {
                if order <= 3 {
                    var level = controls
                    while level.count > 1 {
                        level = zip(level, level.dropFirst()).map { a, b in
                            zip(a, b).map { $0 * (.exact(1) - fraction) + $1 * fraction }
                        }
                    }
                    derivatives.append(level[0].map { $0 * factor })
                    if order < 3 {
                        controls = zip(controls, controls.dropFirst()).map { a, b in
                            zip(a, b).map { ($1 - $0) * .exact(Double(3 - order)) }
                        }
                        factor = factor * scale
                    }
                } else { derivatives.append(Array(repeating: .exact(0), count: 3)) }
            }
            // The admitted original boundary has constant X; preserve that exact identity.
            return Jet(x: IntervalDerivativeJet(derivatives: [.exact(curve.controlPoints[0].x)] + Array(repeating: .exact(0), count: 5)),
                       y: IntervalDerivativeJet(derivatives: derivatives.map { $0[1] }),
                       z: IntervalDerivativeJet(derivatives: derivatives.map { $0[2] }))
        }

        private func unit(_ jet: Jet) -> Jet? {
            guard let length = jet.dot(jet).squareRoot(), let inverse = length.reciprocal() else { return nil }
            return jet.scaled(by: inverse)
        }

        func jets(over range: Interval, region: Region) throws -> (point: Jet, direction: Jet)? {
            let source: Jet
            let point: Jet
            switch region {
            case .native:
                source = try native(range); point = source
            case .before, .after:
                let endpoint = region == .before ? 0.2 : 0.8
                source = try native(.exact(endpoint))
                guard let derivative = source.differentiated(), let along = unit(derivative),
                      let speed = carry.divided(by: .exact(0.2)) else { return nil }
                let coefficients = (0...5).map { order -> [Interval] in
                    if order == 0 {
                        return zip(source.derivative(0), along.derivative(0)).map { $0 + $1 * speed * (range - .exact(endpoint)) }
                    }
                    return order == 1 ? along.derivative(0).map { $0 * speed } : Array(repeating: .exact(0), count: 3)
                }
                point = Jet(x: IntervalDerivativeJet(derivatives: coefficients.map { $0[0] }),
                            y: IntervalDerivativeJet(derivatives: coefficients.map { $0[1] }),
                            z: IntervalDerivativeJet(derivatives: coefficients.map { $0[2] }))
            }
            guard let derivative = source.differentiated(), let along = unit(derivative) else { return nil }
            let sign = normalSign * (end > start ? 1 : -1)
            var normal = Jet(x: .constant(.exact(0), order: 4),
                             y: along.z.scaled(by: .exact(sign)), z: along.y.scaled(by: .exact(-sign)))
            if region != .native { normal = .constant(normal.derivative(0), order: 4) }
            let across = Jet.constant([.exact(outward.x), .exact(0), .exact(0)], order: 4)
            return (point, normal.scaled(by: .constant(.exact(-1), order: 4)) + across.scaled(by: .constant(tangent, order: 4)))
        }
    }

    /// Uses the same verifier for emitted coefficients and independently perturbed candidates.
    static func error(controls: [Point3D], lowerJet: Jet, upperJet: Jet, wholeJet: Jet,
                      width: Interval) -> Double {
        guard controls.count == 4, controls.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              width.isFinite, width.lower > 0,
              lowerJet.derivative(0).allSatisfy({ $0.isFinite }), lowerJet.derivative(1).allSatisfy({ $0.isFinite }),
              upperJet.derivative(0).allSatisfy({ $0.isFinite }), upperJet.derivative(1).allSatisfy({ $0.isFinite }),
              wholeJet.derivative(4).allSatisfy({ $0.isFinite }) else { return .infinity }
        guard let third = width.divided(by: .exact(3)), let remainderFactor = Interval.exact(1).divided(by: .exact(384)) else { return .infinity }
        let ideal = [lowerJet.derivative(0),
                     zip(lowerJet.derivative(0), lowerJet.derivative(1)).map { $0 + $1 * third },
                     zip(upperJet.derivative(0), upperJet.derivative(1)).map { $0 - $1 * third }, upperJet.derivative(0)]
        var numeric = Interval.exact(0)
        for (point, enclosure) in zip(controls, ideal) {
            let residual = zip([point.x, point.y, point.z], enclosure).reduce(Interval.exact(0)) {
                $0 + .exact((.exact($1.0) - $1.1).absoluteUpperBound)
            }
            if residual.upper > numeric.upper { numeric = residual }
        }
        let fourth = wholeJet.derivative(4).reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) }
        return (numeric + fourth * width * width * width * width * remainderFactor).upper
    }

    private func fitted(law: OriginalLaw, hinge: Curve3D, reference: Surface3D, start: Double, end: Double,
                        referenceSign: Double, outward: Vector3D, angle: Double, reach: Double) throws -> Construction {
        let depths = [-0.05 * reach, 1.5 * reach]
        guard depths.allSatisfy({ $0.isFinite }), depths[0] < depths[1] else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "Cubic draft depths are not finite.")
        }
        let angular = try CertifiedRotationTrigonometry.evaluate(.exact(min(tolerance.angle, .pi / 2)), tolerance: tolerance).sine.lower
        var pending: [(Double, Double, OriginalLaw.Region)] = [(0.8, 1, .after), (0.2, 0.8, .native), (0, 0.2, .before)]
        var rows: [[Point3D]] = [[], []]
        var spans: [ClosedSpan] = []
        var maximumPositionError = 0.0, maximumRulingError = 0.0
        while let (a, b, region) = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            let width = Interval.exact(b) - .exact(a)
            var accepted = false
            if let all = try law.jets(over: Interval(lower: a, upper: b), region: region),
               let first = try law.jets(over: .exact(a), region: region),
               let last = try law.jets(over: .exact(b), region: region),
               let third = width.divided(by: .exact(3)) {
                var candidates: [[Point3D]] = []
                var positional = 0.0
                for row in 0..<2 {
                    let depth = IntervalDerivativeJet.constant(.exact(depths[row]), order: 4)
                    let atStart = first.point + first.direction.scaled(by: depth)
                    let atEnd = last.point + last.direction.scaled(by: depth)
                    let across = all.point + all.direction.scaled(by: depth)
                    let coefficients = [atStart.derivative(0),
                        zip(atStart.derivative(0), atStart.derivative(1)).map { $0 + $1 * third },
                        zip(atEnd.derivative(0), atEnd.derivative(1)).map { $0 - $1 * third }, atEnd.derivative(0)]
                    var points = coefficients.map { Point3D(x: $0[0].midpoint, y: $0[1].midpoint, z: $0[2].midpoint) }
                    if let previous = rows[row].last { points[0] = previous }
                    candidates.append(points)
                    positional = max(positional, Self.error(controls: points, lowerJet: atStart, upperJet: atEnd, wholeJet: across, width: width))
                }
                let depthWidth = Interval.exact(depths[1]) - .exact(depths[0])
                var directionControls: [Point3D] = []
                var divisionError = Interval.exact(0)
                for i in 0..<4 {
                    let first = candidates[0][i], last = candidates[1][i]
                    let differences = try zip([first.x, first.y, first.z], [last.x, last.y, last.z]).map { a, b -> Interval in
                        guard let result = (.exact(b) - Interval.exact(a)).divided(by: depthWidth), result.isFinite else {
                            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                                              message: "The stored cubic ruling difference is not certifiable.")
                        }
                        return result
                    }
                    let values = differences.map { $0.midpoint }
                    divisionError = divisionError.union(differences.enumerated().reduce(Interval.exact(0)) { $0 + .exact(($1.element - .exact(values[$1.offset])).absoluteUpperBound) })
                    directionControls.append(Point3D(x: values[0], y: values[1], z: values[2]))
                }
                let ruling = (Interval.exact(Self.error(controls: directionControls, lowerJet: first.direction,
                    upperJet: last.direction, wholeJet: all.direction, width: width)) + divisionError).upper
                // |D| >= 1 from the original orthogonal unit normal/X identity. A ball of this
                // radius about D lies within the requested angular cone and positive hemisphere.
                if positional.isFinite, ruling.isFinite, positional <= tolerance.distance / 8,
                   ruling < 1, ruling <= angular {
                    for row in 0..<2 { rows[row] += rows[row].isEmpty ? candidates[row] : Array(candidates[row].dropFirst()) }
                    spans.append(ClosedSpan(lower: a, upper: b)); accepted = true
                    maximumPositionError = max(maximumPositionError, positional)
                    maximumRulingError = max(maximumRulingError, ruling)
                }
            }
            if !accepted {
                let middle = a + (b - a) * 0.5
                guard middle > a, middle < b else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "The original cubic draft proof cannot subdivide further.")
                }
                pending.append((middle, b, region)); pending.append((a, middle, region))
            }
            guard spans.count + pending.count <= Self.maximumSpanCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "The original cubic draft exceeds its shared span allowance.")
            }
        }
        var knots = Array(repeating: spans[0].lower, count: 4)
        for (index, span) in spans.enumerated() { knots += Array(repeating: span.upper, count: index == spans.count - 1 ? 4 : 3) }
        let output = Surface3D.bSpline(BSplineSurface3D(uDegree: 3, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1], controlPoints: rows))
        try output.validate(tolerance: tolerance)
        let v = -depths[0] / (depths[1] - depths[0])
        let pcurve = SurfaceParameterCurve.constantV(v: v, uStart: 0.2, uEnd: 0.8)
        let receipt = Receipt(hinge: hinge, reference: reference, start: start, end: end,
                              referenceSign: referenceSign, outward: outward, angle: angle, reach: reach,
                              tolerance: tolerance, surface: output, hingePcurve: pcurve, spans: spans,
                              maximumPositionError: maximumPositionError, maximumRulingError: maximumRulingError)
        return Construction(surface: output, receipt: receipt)
    }

    /// Coaxial cylinders and equatorial spheres have radial normals on the complete circle.
    /// With the face normal on its axis, every original ruling reaches this same apex.
    private func cone(circle: Circle3D, reference: Surface3D, referenceSign: Double,
                      outward: Vector3D, tangent: Double) throws -> Surface3D? {
        // These identities are structural admission, not an angular or sampled approximation.
        guard circle.normal.cross(outward).length == 0, tangent.isFinite else { return nil }
        let support: (origin: Point3D, axis: Vector3D, radius: Double)?
        switch reference {
        case let .cylinder(value): support = (value.origin, value.axis, value.radius)
        case let .analytic(.cylinder(origin, axis, radius)): support = (origin, axis, radius)
        case let .analytic(.sphere(center, radius)):
            guard center == circle.center, radius == circle.radius else { return nil }
            support = nil
        default: return nil
        }
        if let support {
            guard support.axis.cross(circle.normal).length == 0,
                  (circle.center - support.origin).cross(support.axis).length == 0,
                  support.radius == circle.radius else { return nil }
        }
        let across = try outward.normalized(tolerance: tolerance.distance)
        let apex = circle.center + across * (referenceSign * circle.radius * tangent)
        let height = (circle.center - apex).length
        guard height > tolerance.distance else { return nil }
        return .analytic(.cone(apex: apex,
                               axis: try (circle.center - apex).normalized(tolerance: tolerance.distance),
                               halfAngle: atan2(circle.radius, height)))
    }
}
