public enum BooleanFaceSplitComponentGeometry: Codable, Hashable, Sendable {
    case transverseSegment(start: BooleanUVPoint, end: BooleanUVPoint)
    case closedCurve(BooleanClosedFaceIntersection)
    case trimmedCurve(BooleanTrimmedFaceIntersectionChain)
    case tangent(BooleanUVPoint)
    case coincident
}


// The synthesized equality binds every large payload pair in one frame,
// which overflows 512 KB worker stacks in unoptimized builds, so the
// dispatch below binds payloads only inside per-case helpers.
extension BooleanFaceSplitComponentGeometry {
    public static func == (
        lhs: BooleanFaceSplitComponentGeometry,
        rhs: BooleanFaceSplitComponentGeometry
    ) -> Bool {
        switch (lhs, rhs) {
        case (.transverseSegment, .transverseSegment):
            return equalsTransverseSegment(lhs, rhs)
        case (.closedCurve, .closedCurve):
            return equalsClosedCurve(lhs, rhs)
        case (.trimmedCurve, .trimmedCurve):
            return equalsTrimmedCurve(lhs, rhs)
        case (.tangent, .tangent):
            return equalsTangent(lhs, rhs)
        case (.coincident, .coincident):
            return true
        default:
            return false
        }
    }

    @inline(never)
    private static func equalsTransverseSegment(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .transverseSegment(ls, le) = lhs,
              case let .transverseSegment(rs, re) = rhs else { return false }
        return ls == rs && le == re
    }

    @inline(never)
    private static func equalsClosedCurve(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .closedCurve(l) = lhs, case let .closedCurve(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsTrimmedCurve(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .trimmedCurve(l) = lhs, case let .trimmedCurve(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsTangent(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .tangent(l) = lhs, case let .tangent(r) = rhs else { return false }
        return l == r
    }
}
