import CADCore

/// Original directed face boundaries sealed to one complete Native parameter receipt.
public final class OriginalNativeBoundaryDomain: Sendable {
    public enum Source: Sendable {
        case curveSurface(OriginalNativeCurveSurfaceRelation)
        case firstSurface(OriginalNativeSurfaceSurfaceRelations)
        case secondSurface(OriginalNativeSurfaceSurfaceRelations)

        public var surface: BSplineSurface3D {
            switch self {
            case .curveSurface(let raw): return raw.surface
            case .firstSurface(let raw): return raw.firstSurface
            case .secondSurface(let raw): return raw.secondSurface
            }
        }
        package var variableCount: Int {
            switch self { case .curveSurface: return 3; case .firstSurface, .secondSurface: return 4 }
        }
        package var uAxis: Int {
            switch self { case .curveSurface: return 1; case .firstSurface: return 0; case .secondSurface: return 2 }
        }
        package var domains: [OriginalRationalParameterDomain] {
            switch self {
            case .curveSurface(let raw): return raw.requestedDomains
            case .firstSurface(let raw), .secondSurface(let raw): return raw.requestedDomains
            }
        }
        package var nativeDomains: [OriginalRationalParameterDomain] {
            switch self {
            case .curveSurface(let raw): return raw.nativeDomains
            case .firstSurface(let raw), .secondSurface(let raw): return raw.nativeDomains
            }
        }
    }
    public enum Selection: Equatable, Sendable { case closed, strictInterior, boundary }
    public struct SpanReference: Equatable, Sendable {
        public let loopOrdinal: Int
        public let curveOrdinal: Int
        public let segmentOrdinal: Int
    }
    package struct Loop: Sendable {
        package let isInner: Bool
        package let curves: [SurfaceParameterCurve]
        package init(isInner: Bool, curves: [SurfaceParameterCurve]) {
            self.isInner = isInner; self.curves = curves
        }
    }
    public let source: Source
    package let loops: [Loop]

    /// Only a face issuer can establish topology/source authority before sealing this domain.
    package init<A: ExactScalarAdmission & ~Copyable>(source: Source, loops: [Loop], usage: inout A) throws {
        try intersectionAlgebraStep(&usage)
        var hasOuter = false
        for loop in loops {
            try intersectionAlgebraStep(&usage)
            if !loop.isInner { hasOuter = true; break }
        }
        guard !loops.isEmpty, hasOuter else {
            throw GeometryConversionError.invalidInput("Original face clipping requires its complete outer and inner loop cover.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic and pole-chart boundary domains need their
        // original lifted chart/seam authority before this Native face clipping entry can succeed.
        // A finite polygon or a guessed periodic translation is not that complete authority.
        guard !source.surface.isUPeriodic, !source.surface.isVPeriodic else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                tolerance: Self.tolerance(source), message: "Original boundary clipping requires a nonperiodic source chart.")
        }
        let bytes = 2 * MemoryLayout<UInt>.stride + MemoryLayout<Source>.stride + MemoryLayout<[Loop]>.stride
        try RationalAlgebraStorage.retainBytes(bytes, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.source = source; self.loops = loops
    }
    package static func tolerance(_ source: Source) -> ModelingTolerance {
        switch source {
        case .curveSurface(let raw): return raw.certificationTolerance
        case .firstSurface(let raw), .secondSurface(let raw): return raw.certificationTolerance
        }
    }
}
