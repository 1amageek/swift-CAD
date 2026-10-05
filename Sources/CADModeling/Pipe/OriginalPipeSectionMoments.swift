import CADCore
import CADGeometry

/// Whole original Green moments and an admitted planar centroid candidate.
package struct OriginalPipeSectionMoments: Sendable {
    private typealias I = OutwardScalarInterval
    private struct Moment {
        let area: I
        let x: I
        let y: I
        var uncertainty: Double { max(area.width, max(x.width, y.width)) }
        static let zero = Moment(area: .exact(0), x: .exact(0), y: .exact(0))
        static func + (a: Self, b: Self) -> Self {
            Self(area: a.area + b.area, x: a.x + b.x, y: a.y + b.y)
        }
        func multiplied(by sign: Double) -> Self {
            Self(area: area * .exact(sign), x: x * .exact(sign), y: y * .exact(sign))
        }
    }
    private struct Cell {
        let loop: Int
        let source: Int
        let interval: ScalarInterval
        let depth: Int
        let moment: Moment
    }
    private let arcLength: any CurveArcLengthResolving

    package init(arcLength: any CurveArcLengthResolving = DefaultCurveArcLengthResolver()) {
        self.arcLength = arcLength
    }

    package func centroid(loops: [[ExactBSplineCurveSpan]], plane: Plane3D,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> Point3D {
        guard !loops.isEmpty, loops.allSatisfy({ !$0.isEmpty }) else {
            throw failure(tolerance, "Original section moments require complete boundary loops.")
        }
        let n = plane.normal
        // Copy/sign changes preserve exact original plane incidence. A rounded
        // cross-product coefficient cannot define the original projection plane.
        let u: Vector3D, v: Vector3D
        if abs(n.z) >= max(abs(n.x), abs(n.y)) {
            u = Vector3D(x: n.z, y: 0, z: -n.x)
            v = Vector3D(x: 0, y: n.z, z: -n.y)
        } else if abs(n.x) >= abs(n.y) {
            u = Vector3D(x: -n.y, y: n.x, z: 0)
            v = Vector3D(x: -n.z, y: 0, z: n.x)
        } else {
            u = Vector3D(x: n.y, y: -n.x, z: 0)
            v = Vector3D(x: 0, y: -n.z, z: n.y)
        }
        func dot(_ a: Vector3D, _ b: Vector3D) -> I {
            .exact(a.x) * .exact(b.x) + .exact(a.y) * .exact(b.y) + .exact(a.z) * .exact(b.z)
        }
        let uu = dot(u, u), uv = dot(u, v), vv = dot(v, v)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite, determinant.lower > 0 else {
            throw failure(tolerance, "Original section projection has no positive Gram determinant.")
        }
        let spanCount = loops.reduce(0) { $0 + $1.count }
        let limits = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        guard spanCount <= admission.maximumSpanCount, spanCount <= limits.maximumCertificationBoxes else {
            throw failure(tolerance, "Original section moments exceed existing source cell admission.")
        }
        var remainingCells = limits.maximumCertificationBoxes - spanCount
        try retain(spanCount, of: (any CurveArcLengthParameterization).self, admission: admission, tolerance: tolerance)
        var sources: [any CurveArcLengthParameterization] = []
        sources.reserveCapacity(spanCount)
        try retain(spanCount, of: Cell.self, admission: admission, tolerance: tolerance)
        var cells: [Cell] = []
        cells.reserveCapacity(spanCount)
        let whole = try ScalarInterval(lower: 0, upper: 1)
        for (loopIndex, loop) in loops.enumerated() {
            for span in loop {
                try admission.chargeWork()
                let original = try span.originalChart.persistentCurve(tolerance: tolerance, admission: admission)
                let source = try arcLength.parameterization(of: original, over: whole,
                    options: CurveArcLengthOptions(absoluteAccuracy: tolerance.distance, relativeAccuracy: 0),
                    tolerance: tolerance, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    maximumAlgebraicDepth: admission.maximumAlgebraicDepth,
                    consumeWork: { try admission.visit(depth: $0) },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) })
                let index = sources.count
                sources.append(source)
                cells.append(Cell(loop: loopIndex, source: index, interval: whole, depth: 0,
                    moment: try integrate(source, over: whole, origin: plane.origin, u: u, v: v,
                        tolerance: tolerance, admission: admission)))
            }
        }
        var capacity = spanCount
        try retain(loops.count, of: Moment.self, admission: admission, tolerance: tolerance)
        var sums = Array(repeating: Moment.zero, count: loops.count)
        while true {
            try admission.chargeWork()
            for index in sums.indices { try admission.chargeWork(); sums[index] = .zero }
            var largest = 0
            for index in cells.indices {
                try admission.chargeWork()
                sums[cells[index].loop] = sums[cells[index].loop] + cells[index].moment
                if cells[index].moment.uncertainty > cells[largest].moment.uncertainty { largest = index }
            }
            var total = Moment.zero
            var oriented = true
            for index in sums.indices {
                try admission.chargeWork()
                let sum = sums[index]
                let sign: Double
                if sum.area.lower > 0 { sign = index == 0 ? 1 : -1 }
                else if sum.area.upper < 0 { sign = index == 0 ? -1 : 1 }
                else { oriented = false; break }
                total = total + sum.multiplied(by: sign)
            }
            if oriented, total.area.lower > 0,
               let x = total.x.divided(by: total.area),
               let y = (-total.y).divided(by: total.area),
               let a = (vv * x - uv * y).divided(by: determinant),
               let b = (uu * y - uv * x).divided(by: determinant) {
                let px = I.exact(plane.origin.x) + .exact(u.x) * a + .exact(v.x) * b
                let py = I.exact(plane.origin.y) + .exact(u.y) * a + .exact(v.y) * b
                let pz = I.exact(plane.origin.z) + .exact(u.z) * a + .exact(v.z) * b
                let point = Point3D(x: px.midpoint, y: py.midpoint, z: pz.midpoint)
                let error = IntervalVector3DBounds(x: px - .exact(point.x),
                    y: py - .exact(point.y), z: pz - .exact(point.z)).lengthUpperBound
                if error.isFinite, error <= tolerance.distance * 0.125 { return point }
            }
            let old = cells[largest]
            guard remainingCells >= 2 else {
                throw failure(tolerance, "Original section moments exhausted their source cell allowance.")
            }
            remainingCells -= 2
            let middle = old.interval.lower + old.interval.width * 0.5
            guard old.depth < admission.maximumSubdivisionDepth,
                  middle > old.interval.lower, middle < old.interval.upper else {
                throw failure(tolerance, "Original section moments exhausted their retained refinement depth.")
            }
            if cells.count == capacity {
                let next = capacity.multipliedReportingOverflow(by: 2)
                guard !next.overflow else { throw failure(tolerance, "Original moment cell capacity overflowed.") }
                let admittedCapacity = min(next.partialValue, limits.maximumCertificationBoxes)
                try retain(admittedCapacity, of: Cell.self, admission: admission, tolerance: tolerance)
                cells.reserveCapacity(admittedCapacity)
                capacity = admittedCapacity
            }
            let left = try ScalarInterval(lower: old.interval.lower, upper: middle)
            let right = try ScalarInterval(lower: middle, upper: old.interval.upper)
            try admission.visit(depth: old.depth + 1)
            cells[largest] = Cell(loop: old.loop, source: old.source, interval: left, depth: old.depth + 1,
                moment: try integrate(sources[old.source], over: left, origin: plane.origin, u: u, v: v,
                    tolerance: tolerance, admission: admission))
            try admission.visit(depth: old.depth + 1)
            cells.append(Cell(loop: old.loop, source: old.source, interval: right, depth: old.depth + 1,
                moment: try integrate(sources[old.source], over: right, origin: plane.origin, u: u, v: v,
                    tolerance: tolerance, admission: admission)))
        }
    }

    private func integrate(_ source: any CurveArcLengthParameterization,
        over interval: ScalarInterval, origin: Point3D, u: Vector3D, v: Vector3D,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> Moment {
        try admission.chargeWork()
        func projected(_ p: CoordinateEnclosure3D, _ direction: Vector3D, position: Bool) -> I {
            let x = I(lower: p.x.lower, upper: p.x.upper) - .exact(position ? origin.x : 0)
            let y = I(lower: p.y.lower, upper: p.y.upper) - .exact(position ? origin.y : 0)
            let z = I(lower: p.z.lower, upper: p.z.upper) - .exact(position ? origin.z : 0)
            return x * .exact(direction.x) + y * .exact(direction.y) + z * .exact(direction.z)
        }
        func fields(_ jet: CurveDifferentialEnclosure) -> (value: Moment, derivative: Moment) {
            let x = projected(jet.position, u, position: true), y = projected(jet.position, v, position: true)
            let dx = projected(jet.firstDerivative, u, position: false), dy = projected(jet.firstDerivative, v, position: false)
            let ddx = projected(jet.secondDerivative, u, position: false), ddy = projected(jet.secondDerivative, v, position: false)
            return (Moment(area: x * dy - y * dx, x: x * x * dy, y: y * y * dx),
                Moment(area: x * ddy - y * ddx,
                    x: .exact(2) * x * dx * dy + x * x * ddy,
                    y: .exact(2) * y * dy * dx + y * y * ddx))
        }
        let whole = fields(try source.differentialEnclosure(over: interval))
        let width = I.exact(interval.upper) - .exact(interval.lower)
        guard try source.hasSmoothNativeInterval(over: interval) else {
            return Moment(area: whole.value.area * width, x: whole.value.x * width, y: whole.value.y * width)
        }
        let middle = interval.lower + interval.width * 0.5
        // The actual representable station need not be the exact mathematical midpoint.
        // Integrate the chosen constant derivative analytically over both sides.
        let point = fields(try source.differentialEnclosure(over: ScalarInterval(lower: middle, upper: middle))).value
        let left = I.exact(middle) - .exact(interval.lower), right = I.exact(interval.upper) - .exact(middle)
        func integral(_ value: I, _ derivative: I) -> I {
            let slope = derivative.midpoint
            let radius = (derivative - .exact(slope)).absoluteUpperBound
            let linear = .exact(slope) * (right * right - left * left) * .exact(0.5)
            let error = (.exact(radius) * (right * right + left * left) * .exact(0.5)).upper
            return value * width + linear + I(lower: -error, upper: error)
        }
        return Moment(area: integral(point.area, whole.derivative.area),
            x: integral(point.x, whole.derivative.x), y: integral(point.y, whole.derivative.y))
    }

    private func retain<T>(_ count: Int, of: T.Type, admission: GeometryConversionAdmission,
        tolerance: ModelingTolerance) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else { throw failure(tolerance, "Original moment storage overflowed.") }
        try admission.chargeStorage(bytes: bytes.partialValue)
    }

    private func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
