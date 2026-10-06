import CADCore

struct OriginalAffineDeterminantBounds {
    private struct Usage:RationalAlgebraAdmitting {
        let consume:()throws->Void
        mutating func consumeExactWork(_ count:Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original affine work count is negative.") }
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation();try consume() }
        }
        mutating func retainExactStorage(_ count:Int) throws { try consumeExactWork(count) }
        mutating func visitExactCell(depth:Int) throws {
            throw GeometryConversionError.invalidInput("Original affine determinant has no subdivision cells.")
        }
    }
    static func bounds(of source:AffineTransform3D,consumeWork:()throws->Void) throws -> ScalarInterval {
        try consumeWork();try source.validate()
        return try withoutActuallyEscaping(consumeWork) { scoped in
            var usage = Usage(consume:scoped)
            func vector(_ value:Vector3D) throws -> [ExactRationalCoefficient] {
                try [.originalDouble(value.x,usage:&usage),.originalDouble(value.y,usage:&usage),.originalDouble(value.z,usage:&usage)]
            }
            let x = try vector(source.basisX),y = try vector(source.basisY),z = try vector(source.basisZ)
            var determinant = ExactRationalCoefficient.zero
            for axis in 0..<3 {
                let b = (axis+1)%3,c = (axis+2)%3
                let cross = try y[b].multiplied(by:z[c],usage:&usage)
                    .subtracting(y[c].multiplied(by:z[b],usage:&usage),usage:&usage)
                determinant = try determinant.adding(x[axis].multiplied(by:cross,usage:&usage),usage:&usage)
            }
            guard !determinant.isZero else {
                throw GeometryConversionError.invalidInput("Original affine columns are exactly singular.")
            }
            let interval = try determinant.outwardInterval(usage:&usage)
            guard interval.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Exact original affine determinant exceeds finite interval representation.")
            }
            return try .init(lower:interval.lower,upper:interval.upper)
        }
    }
}
