import CADCore

struct OriginalAffineDeterminantBounds {
    static func bounds<A: ExactScalarAdmission & ~Copyable>(of source: AffineTransform3D, using execution: inout A) throws -> ScalarInterval {
        try execution.consumeWork(1);try source.validate()
            func vector(_ value:Vector3D) throws -> [ExactRationalCoefficient] {
                try OriginalCoefficientAllocation.reserve(count: 3, of: ExactRationalCoefficient.self, using: &execution)
                return try [.originalDouble(value.x,usage: &execution),.originalDouble(value.y,usage: &execution),.originalDouble(value.z,usage: &execution)]
            }
            let x = try vector(source.basisX),y = try vector(source.basisY),z = try vector(source.basisZ)
            var determinant = ExactRationalCoefficient.zero
            for axis in 0..<3 {
                let b = (axis+1)%3,c = (axis+2)%3
                let cross = try y[b].multiplied(by:z[c],usage: &execution)
                    .subtracting(y[c].multiplied(by:z[b],usage: &execution),usage: &execution)
                determinant = try determinant.adding(x[axis].multiplied(by:cross,usage: &execution),usage: &execution)
            }
            guard !determinant.isZero else {
                throw GeometryConversionError.invalidInput("Original affine columns are exactly singular.")
            }
            let interval = try determinant.outwardInterval(usage: &execution)
            guard interval.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Exact original affine determinant exceeds finite interval representation.")
            }
            try execution.checkpoint()
            return try .init(lower:interval.lower,upper:interval.upper)
    }
}
