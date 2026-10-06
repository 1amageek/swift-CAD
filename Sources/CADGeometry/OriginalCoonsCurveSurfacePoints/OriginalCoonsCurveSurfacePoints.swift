import CADCore

/// Complete original-source coverage and every isolated curve/Coons parameter tuple.
public final class OriginalCoonsCurveSurfacePoints: Sendable {
    public let curve: BSplineCurve3D
    public let surface: OriginalCoonsSurface3D
    public let certificationTolerance: ModelingTolerance
    public let nativeDomains: [OriginalRationalParameterDomain]
    public let requestedDomains: [OriginalRationalParameterDomain]
    public let effectiveDomains: [OriginalRationalParameterDomain]?
    public var count: Int { cellIndexes.count }
    public var coverageCellCount: Int { incidence?.partition.cells.count ?? 0 }
    package let source: OriginalCoonsIntersectionRelation
    package let incidence: OriginalRationalIntersectionIncidence?
    package let components: OriginalRationalParameterComponents?
    private let cellIndexes: [Int]
    private let parameterIsolations: [OriginalSingularFieldValueIsolation]
    private let parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]

    /// Mirrors retained instance payload; class headers are admitted separately.
    private struct StorageLayout {
        let curve: BSplineCurve3D
        let surface: OriginalCoonsSurface3D
        let tolerance: ModelingTolerance
        let native: [OriginalRationalParameterDomain]
        let requested: [OriginalRationalParameterDomain]
        let effective: [OriginalRationalParameterDomain]?
        let source: OriginalCoonsIntersectionRelation
        let incidence: OriginalRationalIntersectionIncidence?
        let components: OriginalRationalParameterComponents?
        let cells: [Int]
        let isolations: [OriginalSingularFieldValueIsolation]
        let localizations: [NativeCurveSurfaceScalarLocalization?]
    }

    static func admitStorage(usage: inout NativeCurveSurfacePointAllowance) throws {
        let headers = try rationalAlgebraCount(2, MemoryLayout<UInt>.stride, multiply: true)
        try usage.retainBytes(rationalAlgebraCount(headers, MemoryLayout<StorageLayout>.stride))
    }

    init(curve: BSplineCurve3D, source: OriginalCoonsIntersectionRelation,
        tolerance: ModelingTolerance, nativeDomains: [OriginalRationalParameterDomain],
        requestedDomains: [OriginalRationalParameterDomain], effectiveDomains: [OriginalRationalParameterDomain]?,
        incidence: OriginalRationalIntersectionIncidence?, components: OriginalRationalParameterComponents?, cellIndexes: [Int],
        parameterIsolations: [OriginalSingularFieldValueIsolation],
        parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]) {
        self.curve = curve; surface = source.coons.source; self.source = source
        certificationTolerance = tolerance; self.nativeDomains = nativeDomains
        self.requestedDomains = requestedDomains; self.effectiveDomains = effectiveDomains
        self.incidence = incidence; self.components = components; self.cellIndexes = cellIndexes
        self.parameterIsolations = parameterIsolations; self.parameterLocalizations = parameterLocalizations
    }

    public func point(at ordinal: Int) throws -> OriginalCoonsCurveSurfacePoint {
        guard cellIndexes.indices.contains(ordinal) else {
            throw GeometryConversionError.invalidInput("Original Coons point index is outside its complete receipt.")
        }
        return .init(owner: self, ordinal: ordinal)
    }

    public func owns(_ point: OriginalCoonsCurveSurfacePoint) -> Bool {
        point.owner === self && cellIndexes.indices.contains(point.ordinal)
    }

    package func isolation(at ordinal: Int, axis: Int) throws -> OriginalSingularFieldValueIsolation {
        guard cellIndexes.indices.contains(ordinal), (0..<3).contains(axis) else {
            throw GeometryConversionError.invalidInput("Original tuple access requires its retained owner and coordinate.")
        }
        return parameterIsolations[ordinal * 3 + axis]
    }

    package func coordinate(at ordinal: Int, axis: Int) throws -> OriginalAlgebraicCoordinate {
        let isolation = try isolation(at: ordinal, axis: axis)
        guard let incidence else {
            throw rationalAlgebraFailure("An original isolated tuple lost its complete partition owner.")
        }
        let cell = incidence.partition.cells[cellIndexes[ordinal]]
        return .init(original: isolation.original, inheritedDepth: isolation.sourceDepth,
            inheritedCoefficientDepth: max(cell.coefficientAdmissionDepth,
                parameterLocalizations[ordinal * 3 + axis]?.coefficientDepth ?? 0),
            certifiedBounds: (isolation.lower, isolation.upper))
    }
}
