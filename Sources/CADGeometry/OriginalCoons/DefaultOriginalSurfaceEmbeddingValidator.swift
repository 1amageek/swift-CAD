import CADCore

/// Certifies original chart injectivity and complete pair separation without a tensor conversion.
public struct DefaultOriginalSurfaceEmbeddingValidator: SourceBoundedOriginalSurfaceEmbeddingValidating {
    public init() {}

    struct Cell {
        let domain: SurfaceParameterBox
        let depth: Int
        let jet: OriginalSurfaceFirstOrderEnclosure
    }

    public func validate<B: RationalAlgebraAdmitting>(_ surface: Surface3D, over domain: SurfaceParameterBox,
        maximumLocalSubdivisionDepth: Int, maximumLocalCellCount: Int,
        maximumPairSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try validate(surface, over: domain, maximumLocalSubdivisionDepth: maximumLocalSubdivisionDepth,
            maximumLocalCellCount: maximumLocalCellCount, maximumPairSubdivisionDepth: maximumPairSubdivisionDepth,
            remainingSourceDepth: 20, tolerance: tolerance, usage: &usage)
    }

    public func validate<B: RationalAlgebraAdmitting>(_ surface: Surface3D, over domain: SurfaceParameterBox,
        maximumLocalSubdivisionDepth: Int, maximumLocalCellCount: Int,
        maximumPairSubdivisionDepth: Int, remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try limits(localDepth: maximumLocalSubdivisionDepth, localCount: maximumLocalCellCount,
            pairDepth: maximumPairSubdivisionDepth, tolerance: tolerance)
        let prepared = try prepare(surface, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumPairSubdivisionDepth, tolerance: tolerance, usage: &usage)
        if case .bSpline(let original) = surface {
            try OriginalSplineSurfaceContinuityAdmission().validate(original, tolerance: tolerance, usage: &usage)
        }
        if case .procedural(.originalBoundaryCorrected(let original)) = surface {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Final Loft embedding consumes
            // original C0 boundary authority. Unsupported original traversal
            // families require their true join producer before publication;
            // whole derivative hulls cannot authorize a position jump.
            guard original.hasOriginalPositionContinuity else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original corrected embedding requires complete original boundary position continuity.")
            }
        }
        if case .procedural(.originalPlaneDerivative(let original)) = surface {
            guard original.hasOriginalPositionContinuity else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original plane derivative embedding requires complete original boundary position continuity.")
            }
        }
        try domain.validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
        if domain.u.lower == 0, domain.u.upper == 1, domain.v.lower == 0, domain.v.upper == 1,
           let image = try exactBilinearImage(surface, usage: &usage),
           try OriginalBilinearEmbeddingCertificate.proven(image, usage: &usage) != nil { return }

        let hasOriginalBoundaryAtlas: Bool
        switch surface {
        case .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative): hasOriginalBoundaryAtlas = true
        default: hasOriginalBoundaryAtlas = false
        }
        if hasOriginalBoundaryAtlas {
            let originalWhole = try query(prepared, box: domain, maximumDepth: maximumPairSubdivisionDepth,
                maximumSpanCount: maximumLocalCellCount, remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, usage: &usage)
            if try monotone(originalWhole, usage: &usage) { return }
            if let rational = try OriginalCoonsRationalDifferentialAtlas.prepared(surface,
                maximumSpanCount: maximumLocalCellCount, tolerance: tolerance, usage: &usage),
               try OriginalCoonsRationalEmbeddingProof().proves(rational, over: domain,
                maximumDepth: maximumLocalSubdivisionDepth, maximumCells: maximumLocalCellCount,
                tolerance: tolerance, usage: &usage) { return }
        }

        try RationalAlgebraStorage.retain(1, of: (SurfaceParameterBox, Int).self, usage: &usage)
        var pending = [(domain, 0)]
        var cells: [Cell] = []
        var localVisits = 0
        while let (box, depth) = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: depth)
            guard localVisits < maximumLocalCellCount else {
                throw exhausted(tolerance, "Original embedding exhausted its original local-cell allowance.")
            }
            localVisits += 1
            let jet = try query(prepared, box: box, maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumLocalCellCount, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, usage: &usage)
            if try monotone(jet, usage: &usage) {
                let words = MemoryLayout<Cell>.stride / 4 + (MemoryLayout<Cell>.stride % 4 == 0 ? 0 : 1)
                try usage.retainExactStorage(max(64, words))
                cells.append(Cell(domain: box, depth: depth, jet: jet))
            } else {
                guard depth < maximumLocalSubdivisionDepth else {
                    throw exhausted(tolerance, "Original chart has unresolved injectivity at its original local-depth limit.")
                }
                let children = try split(box, tolerance: tolerance, usage: &usage)
                try RationalAlgebraStorage.retain(children.count, of: (SurfaceParameterBox, Int).self, usage: &usage)
                pending.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        for first in cells.indices {
            for second in cells.indices where second > first {
                try usage.visitExactCell(depth: max(cells[first].depth, cells[second].depth))
                if try separated(cells[first].jet, cells[second].jet, tolerance: tolerance, usage: &usage) { continue }
                let hull = try union(cells[first].domain, cells[second].domain)
                let whole = try query(prepared, box: hull, maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumLocalCellCount, remainingSourceDepth: remainingSourceDepth,
                    tolerance: tolerance, usage: &usage)
                if try monotone(whole, usage: &usage) { continue }
                try separatedPairs(first: prepared, firstBox: cells[first].domain,
                    second: prepared, secondBox: cells[second].domain,
                    initialDepth: max(cells[first].depth, cells[second].depth),
                    maximumDepth: maximumPairSubdivisionDepth, maximumSpanCount: maximumLocalCellCount, remainingSourceDepth: remainingSourceDepth, sameChart: true,
                    tolerance: tolerance, usage: &usage)
            }
        }
    }

    public func validateSeparation<B: RationalAlgebraAdmitting>(first: Surface3D, firstDomain: SurfaceParameterBox,
        second: Surface3D, secondDomain: SurfaceParameterBox, maximumSubdivisionDepth: Int, maximumSpanCount: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try validateSeparation(first: first, firstDomain: firstDomain, second: second, secondDomain: secondDomain,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: 20, tolerance: tolerance, usage: &usage)
    }

    public func validateSeparation<B: RationalAlgebraAdmitting>(first: Surface3D, firstDomain: SurfaceParameterBox,
        second: Surface3D, secondDomain: SurfaceParameterBox, maximumSubdivisionDepth: Int, maximumSpanCount: Int,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try limits(localDepth: maximumSubdivisionDepth, localCount: 1,
            pairDepth: maximumSubdivisionDepth, tolerance: tolerance)
        let a = try prepare(first, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
        let b = try prepare(second, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
        for surface in [first, second] { if case .bSpline(let original) = surface {
            try OriginalSplineSurfaceContinuityAdmission().validate(original, tolerance: tolerance, usage: &usage)
        } }
        try firstDomain.validateAssumingSurfaceValidated(for: first, tolerance: tolerance)
        try secondDomain.validateAssumingSurfaceValidated(for: second, tolerance: tolerance)
        try separatedPairs(first: a, firstBox: firstDomain, second: b, secondBox: secondDomain,
            initialDepth: 0, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth, sameChart: false,
            tolerance: tolerance, usage: &usage)
    }

    func separatedPairs<B: RationalAlgebraAdmitting>(first: PreparedSurfaceDifferentialEncloser,
        firstBox: SurfaceParameterBox, second: PreparedSurfaceDifferentialEncloser,
        secondBox: SurfaceParameterBox, initialDepth: Int, maximumDepth: Int, maximumSpanCount: Int, remainingSourceDepth: Int, sameChart: Bool,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try RationalAlgebraStorage.retain(1, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &usage)
        var pending = [(firstBox, secondBox, initialDepth)]
        while let (aBox, bBox, depth) = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: depth)
            let a = try query(first, box: aBox, maximumDepth: maximumDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, usage: &usage)
            let b = try query(second, box: bBox, maximumDepth: maximumDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, usage: &usage)
            if try separated(a, b, tolerance: tolerance, usage: &usage) { continue }
            if sameChart {
                let whole = try query(first, box: union(aBox, bBox), maximumDepth: maximumDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
                    tolerance: tolerance, usage: &usage)
                if try monotone(whole, usage: &usage) { continue }
            }
            guard depth < maximumDepth else {
                throw exhausted(tolerance, "Original complete surface pair remains unresolved at its original subdivision limit.")
            }
            let splitFirst = max(aBox.u.width, aBox.v.width) >= max(bBox.u.width, bBox.v.width)
            let children = try split(splitFirst ? aBox : bBox, tolerance: tolerance, usage: &usage)
            try RationalAlgebraStorage.retain(children.count, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &usage)
            for child in children { pending.append(splitFirst ? (child, bBox, depth + 1) : (aBox, child, depth + 1)) }
        }
    }

    func exactBilinearImage<B: RationalAlgebraAdmitting>(_ source: Surface3D, usage: inout B) throws -> BSplineSurface3D? {
        switch source {
        case .bSpline(let native): return native
        case .procedural(.originalCoons(let original)): return try original.exactBilinearImage(usage: &usage)
        default: return nil
        }
    }

    func prepare<B: RationalAlgebraAdmitting>(_ surface: Surface3D, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B)
        throws -> PreparedSurfaceDifferentialEncloser {
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original embedding source depth must be nonnegative.")
        }
        func storage(_ bytes: Int) throws { try retainNativeBytes(bytes, usage: &usage) }
        return try withoutActuallyEscaping(storage) { admittedStorage in
            try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: admittedStorage)
        }
    }

    private func retainNativeBytes<B: RationalAlgebraAdmitting>(_ bytes: Int, usage: inout B) throws {
        let rounded = bytes.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
        guard bytes >= 0, !rounded.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original embedding native storage conversion overflows.")
        }
        try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
    }

    func query<B: RationalAlgebraAdmitting>(_ prepared: PreparedSurfaceDifferentialEncloser,
        box: SurfaceParameterBox, maximumDepth: Int, maximumSpanCount: Int, remainingSourceDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> OriginalSurfaceFirstOrderEnclosure {
        try usage.consumeExactWork(9)
        if case .procedural(.originalCoons(let original)) = prepared.surface {
            return try original.preparedFirstOrder(over: box, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumDepth, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
        }
        if case .procedural(.originalBoundaryCorrected(let original)) = prepared.surface {
            return try original.preparedFirstOrder(over: box, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumDepth, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
        }
        if case .procedural(.originalPlaneDerivative(let original)) = prepared.surface {
            return try original.preparedFirstOrder(over: box, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumDepth, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
        }
        func storage(_ bytes: Int) throws { try retainNativeBytes(bytes, usage: &usage) }
        return try withoutActuallyEscaping(storage) { admittedStorage in
            try .init(prepared.intervalJet(overClosedBox: box, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: admittedStorage))
        }
    }

    func separated<B: RationalAlgebraAdmitting>(_ a: OriginalSurfaceFirstOrderEnclosure, _ b: OriginalSurfaceFirstOrderEnclosure,
        tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
        try usage.consumeExactWork(12)
        func excludes(_ delta: OutwardScalarInterval) -> Bool {
            delta.lower > tolerance.distance || delta.upper < -tolerance.distance
        }
        if excludes(a.x.value - b.x.value) { return true }
        if excludes(a.y.value - b.y.value) { return true }
        return excludes(a.z.value - b.z.value)
    }

    func monotone<B: RationalAlgebraAdmitting>(_ jet: OriginalSurfaceFirstOrderEnclosure,
        usage: inout B) throws -> Bool {
        try monotone(count: 1, jetAt: { _ in jet }, boundaryAt: nil, usage: &usage)
    }

    @available(*, deprecated, message: "Borrow one or two original first-order jets directly.")
    func monotone<B: RationalAlgebraAdmitting>(_ jets: [OriginalSurfaceFirstOrderEnclosure],
        boundaries: [SurfaceParameterBoundary]? = nil, usage: inout B) throws -> Bool {
        if let boundaries, boundaries.count != jets.count {
            throw GeometryConversionError.invalidInput("Original monotonicity boundary count differs from its jet count.")
        }
        return try monotone(count: jets.count, jetAt: { jets[$0] },
            boundaryAt: boundaries.map { values in { values[$0] } }, usage: &usage)
    }

    func monotone<B: RationalAlgebraAdmitting>(first: OriginalSurfaceFirstOrderEnclosure,
        second: OriginalSurfaceFirstOrderEnclosure, firstBoundary: SurfaceParameterBoundary,
        secondBoundary: SurfaceParameterBoundary, usage: inout B) throws -> Bool {
        try monotone(count: 2, jetAt: { $0 == 0 ? first : second },
            boundaryAt: { $0 == 0 ? firstBoundary : secondBoundary }, usage: &usage)
    }

    private func monotone<B: RationalAlgebraAdmitting>(count: Int,
        jetAt: (Int) -> OriginalSurfaceFirstOrderEnclosure,
        boundaryAt: ((Int) -> SurfaceParameterBoundary)?, usage: inout B) throws -> Bool {
        func differential(_ jet: OriginalSurfaceFirstOrderEnclosure, at index: Int) -> (u: Vector, v: Vector) {
            let u = Vector(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
            let v = Vector(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV)
            guard let boundaryAt else { return (u, v) }
            let boundary = boundaryAt(index)
            let fixedU = boundary == .uLower || boundary == .uUpper
            let upper = boundary == .uUpper || boundary == .vUpper
            let sign = (upper == (index == 0)) ? 1.0 : -1.0
            return (fixedU ? v : u, (fixedU ? u : v).scaled(sign))
        }
        guard count > 0 else { return false }
        let candidate = jetAt(0)
        try usage.consumeExactWork(48)
        let directions = differential(candidate, at: 0)
        let a = directions.u.midpoint, b = directions.v.midpoint
        let aa = a.dot(a), ab = a.dot(b), bb = b.dot(b), determinant = aa * bb - ab * ab
        guard determinant.isFinite, determinant > 0 else { return false }
        // Stored finite projection coefficients are candidates. All success
        // inequalities below enclose their complete original derivative law.
        let first = (a * bb - b * ab) * (1 / determinant)
        let second = (b * aa - a * ab) * (1 / determinant)
        guard first.isFinite, second.isFinite else { return false }
        for index in 0..<count {
            let jet = jetAt(index)
            try usage.consumeExactWork(80)
            let directions = differential(jet, at: index)
            let j11 = directions.u.projected(first), j12 = directions.v.projected(first)
            let j21 = directions.u.projected(second), j22 = directions.v.projected(second)
            let symmetric = (j12 + j21) * .exact(0.5)
            let squared = symmetric * symmetric
            let positive = j11 * j22 - squared
            guard j11.lower > 0, j22.lower > 0, positive.lower > 0 else { return false }
        }
        return true
    }

    struct Vector {
        let x: OutwardScalarInterval, y: OutwardScalarInterval, z: OutwardScalarInterval
        var midpoint: Vector3D { .init(x: x.midpoint, y: y.midpoint, z: z.midpoint) }
        func scaled(_ scalar: Double) -> Self { .init(x: x * .exact(scalar), y: y * .exact(scalar), z: z * .exact(scalar)) }
        func projected(_ axis: Vector3D) -> OutwardScalarInterval {
            x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
        }
    }

    func union(_ a: SurfaceParameterBox, _ b: SurfaceParameterBox) throws -> SurfaceParameterBox {
        try .init(u: .init(lower: min(a.u.lower, b.u.lower), upper: max(a.u.upper, b.u.upper)),
            v: .init(lower: min(a.v.lower, b.v.lower), upper: max(a.v.upper, b.v.upper)))
    }

    func split<B: RationalAlgebraAdmitting>(_ box: SurfaceParameterBox, tolerance: ModelingTolerance,
        usage: inout B) throws -> [SurfaceParameterBox] {
        try RationalAlgebraStorage.retain(2, of: SurfaceParameterBox.self, usage: &usage)
        let alongU = box.u.width >= box.v.width, range = alongU ? box.u : box.v
        let middle = range.lower / 2 + range.upper / 2
        guard middle > range.lower, middle < range.upper else {
            throw exhausted(tolerance, "Original subdivision has no representable interior parameter station.")
        }
        let a = try ScalarInterval(lower: range.lower, upper: middle)
        let b = try ScalarInterval(lower: middle, upper: range.upper)
        return alongU ? [.init(u: a, v: box.v), .init(u: b, v: box.v)]
            : [.init(u: box.u, v: a), .init(u: box.u, v: b)]
    }

    func limits(localDepth: Int, localCount: Int, pairDepth: Int, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard localDepth >= 0, localCount > 0, pairDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original embedding requires positive caller capacities and nonnegative depth limits.")
        }
    }

    func exhausted(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
