import CADCore

/// Borrows one caller allowance without creating an independent work ceiling.
package struct SurfaceSurfaceQueryAdmission: Sendable {
    package let maximumSpanCount: Int
    package let maximumSubdivisionDepth: Int
    package let remainingSourceDepth: Int
    package let maximumAlgebraicDepth: Int?
    let usesCallerAccounting: Bool
    private let consumeWork: @Sendable () throws -> Void
    package var usesCallerStorageAccounting: Bool { consumeStorage != nil }
    private let consumeStorage: (@Sendable (Int) throws -> Void)?

    package init(maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Surface-pair admission requires positive spans and nonnegative original depths.")
        }
        usesCallerAccounting = true
        self.maximumSpanCount = maximumSpanCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
    }

    /// Historical enclosure defaults; no new cumulative work allowance.
    package static var legacy: Self {
        Self(maximumSpanCount: 262_144, maximumSubdivisionDepth: 32,
            remainingSourceDepth: Int.max, uncheckedWork: { try Task.checkCancellation() })
    }

    private init(maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, uncheckedWork: @escaping @Sendable () throws -> Void) {
        usesCallerAccounting = false
        self.maximumSpanCount = maximumSpanCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        maximumAlgebraicDepth = nil
        consumeWork = uncheckedWork
        consumeStorage = nil
    }

    package func descendingSource() throws -> Self {
        try step()
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original intersection support exhausted its source depth.")
        }
        if usesCallerAccounting {
            return try Self(maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1,
                consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        return Self(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth - 1, uncheckedWork: consumeWork)
    }

    package func step() throws {
        try Task.checkCancellation()
        try consumeWork()
    }

    /// Byte admission is distinct from source recursion depth and visit count.
    package func reserve(count: Int, stride: Int) throws {
        try step()
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original intersection retained-byte accounting overflowed.")
        }
        try consumeStorage?(bytes.partialValue)
    }

    func algebraAdmission() -> OriginalGeometryValidationAdmission {
        OriginalGeometryValidationAdmission(consumeWork: { _ in try self.step() },
            consumeStorage: usesCallerStorageAccounting ? { try self.retain(bytes: $0) } : nil,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    func prepare(_ surface: Surface3D, tolerance: ModelingTolerance) throws -> PreparedSurfaceDifferentialEncloser {
        try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { try step() }, consumeStorage: usesCallerStorageAccounting ? { try retain(bytes: $0) } : nil,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    private func retain(bytes: Int) throws {
        try Task.checkCancellation()
        guard bytes >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original intersection retained-byte admission cannot be negative.")
        }
        try consumeStorage?(bytes)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Preparation and native/analytic query
    // storage now forward this caller byte admission. Procedural query scratch
    // producers still explicitly refuse until their actual allocation owners
    // accept it; the full bounded SSI domain is not complete.
    func intervalJet(_ surface: PreparedSurfaceDifferentialEncloser,
        over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        try surface.intervalJet(overClosedBox: box, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() },
            consumeStorage: usesCallerStorageAccounting ? { try retain(bytes: $0) } : nil)
    }
    func positionBounds(_ surface: PreparedSurfaceDifferentialEncloser,
        at parameter: SurfaceParameter, tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
        try parameter.validate(); try step()
        return try positionBounds(surface, over: .init(
            u: .init(lower: parameter.u, upper: parameter.u),
            v: .init(lower: parameter.v, upper: parameter.v)), tolerance: tolerance)
    }

    func positionBounds(_ surface: PreparedSurfaceDifferentialEncloser,
        over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
        try step()
        return try surface.positionBounds(over: box, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() },
            consumeStorage: usesCallerStorageAccounting ? { try retain(bytes: $0) } : nil)
    }

    func numericalSample(_ surface: PreparedSurfaceDifferentialEncloser, at parameter: SurfaceParameter,
        tolerance: ModelingTolerance) throws -> (position: Point3D, derivativeU: Vector3D, derivativeV: Vector3D,
            secondUU: Vector3D, secondUV: Vector3D, secondVV: Vector3D) {
        try surface.numericalSample(at: parameter, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: { try step() },
            consumeStorage: usesCallerStorageAccounting ? { try retain(bytes: $0) } : nil)
    }
}
