import CADCore

/// Exact affine graph of two original planes with authored parameter directions.
struct OriginalAuthoredPlaneIntersectionGraph: Sendable {
    let constants: [ExactRationalCoefficient]
    let slopes: [ExactRationalCoefficient]

    private struct Usage: RationalAlgebraAdmitting {
        let admission: SurfaceSurfaceQueryAdmission
        mutating func visitExactCell(depth: Int) throws {
            guard depth == 0 else {
                throw GeometryConversionError.invalidInput("An authored plane graph uses rational coefficients only.")
            }
            try admission.step()
        }
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else {
                throw GeometryConversionError.invalidInput("Original plane work count cannot be negative.")
            }
            for _ in 0..<count { try admission.step() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try admission.reserve(count: count, stride: MemoryLayout<UInt32>.stride)
        }
    }

    private struct Vector {
        let x: ExactRationalCoefficient
        let y: ExactRationalCoefficient
        let z: ExactRationalCoefficient
        subscript(_ index: Int) -> ExactRationalCoefficient {
            switch index { case 0: x; case 1: y; default: z }
        }
    }

    static func prepare(first: Surface3D, second: Surface3D,
        parameterBox: SurfaceIntersectionParameterBox,
        freeParameter: SurfaceIntersectionParameterCoordinate,
        admission: SurfaceSurfaceQueryAdmission) throws -> Self? {
        guard case .plane(let a) = first, case .plane(let b) = second,
            let au = a.uDirection, let bu = b.uDirection else { return nil }
        var usage = Usage(admission: admission)
        func vector(_ value: Vector3D, usage: inout Usage) throws -> Vector {
            try .init(x: .originalDouble(value.x, usage: &usage),
                y: .originalDouble(value.y, usage: &usage),
                z: .originalDouble(value.z, usage: &usage))
        }
        func cross(_ a: Vector, _ b: Vector, usage: inout Usage) throws -> Vector {
            try .init(x: a.y.multiplied(by: b.z, usage: &usage)
                    .subtracting(a.z.multiplied(by: b.y, usage: &usage), usage: &usage),
                y: a.z.multiplied(by: b.x, usage: &usage)
                    .subtracting(a.x.multiplied(by: b.z, usage: &usage), usage: &usage),
                z: a.x.multiplied(by: b.y, usage: &usage)
                    .subtracting(a.y.multiplied(by: b.x, usage: &usage), usage: &usage))
        }
        let u1 = try vector(au, usage: &usage), u2 = try vector(bu, usage: &usage)
        let n1 = try vector(a.normal, usage: &usage), n2 = try vector(b.normal, usage: &usage)
        let v1 = try cross(n1, u1, usage: &usage), v2 = try cross(n2, u2, usage: &usage)
        let o1 = try vector(.init(x: a.origin.x, y: a.origin.y, z: a.origin.z), usage: &usage)
        let o2 = try vector(.init(x: b.origin.x, y: b.origin.y, z: b.origin.z), usage: &usage)
        try admission.reserve(count: 4, stride: MemoryLayout<Vector>.stride)
        let bases = [u1, v1, u2, v2]
        try admission.reserve(count: 4, stride: MemoryLayout<ExactRationalCoefficient>.stride)
        var lower: [ExactRationalCoefficient] = []; lower.reserveCapacity(4)
        try admission.reserve(count: 4, stride: MemoryLayout<ExactRationalCoefficient>.stride)
        var widths: [ExactRationalCoefficient] = []; widths.reserveCapacity(4)
        for index in 0..<4 {
            try admission.step()
            guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
                throw GeometryConversionError.invalidInput("An original plane chart coordinate is invalid.")
            }
            let interval = parameterBox.interval(for: coordinate)
            guard interval.lower.isFinite, interval.upper.isFinite, interval.lower < interval.upper else {
                throw GeometryConversionError.invalidInput("An original affine graph requires positive finite source spans.")
            }
            let start = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &usage)
            lower.append(start)
            widths.append(try .originalDouble(interval.upper, usage: &usage)
                .subtracting(start, usage: &usage))
        }
        let free = freeParameter.rawValue
        guard (0..<4).contains(free) else {
            throw GeometryConversionError.invalidInput("An original affine graph free coordinate is invalid.")
        }
        try admission.reserve(count: 3, stride: MemoryLayout<Int>.stride)
        var dependent: [Int] = []; dependent.reserveCapacity(3)
        for index in 0..<4 where index != free { dependent.append(index) }
        try admission.reserve(count: 15, stride: MemoryLayout<ExactRationalCoefficient>.stride)
        var matrix = [ExactRationalCoefficient](repeating: .zero, count: 15)
        for row in 0..<3 {
            try admission.step()
            var origin = try o1[row].subtracting(o2[row], usage: &usage)
            for column in 0..<4 {
                let offset = try bases[column][row].multiplied(by: lower[column], usage: &usage)
                origin = try column < 2 ? origin.adding(offset, usage: &usage)
                    : origin.subtracting(offset, usage: &usage)
                let coefficient = try bases[column][row].multiplied(by: widths[column], usage: &usage)
                let directed = column < 2 ? coefficient : coefficient.negated
                if column == free { matrix[row * 5 + 4] = directed.negated }
                else if let target = dependent.firstIndex(of: column) { matrix[row * 5 + target] = directed }
            }
            matrix[row * 5 + 3] = origin.negated
        }
        for column in 0..<3 {
            try admission.step()
            var pivot: Int?
            for row in column..<3 {
                try admission.step()
                if !matrix[row * 5 + column].isZero { pivot = row; break }
            }
            guard let pivot else { return nil }
            if pivot != column {
                for entry in column..<5 { matrix.swapAt(column * 5 + entry, pivot * 5 + entry) }
            }
            let divisor = matrix[column * 5 + column]
            for entry in column..<5 {
                matrix[column * 5 + entry] = try matrix[column * 5 + entry].divided(by: divisor, usage: &usage)
            }
            for row in 0..<3 where row != column {
                try admission.step()
                let multiplier = matrix[row * 5 + column]
                for entry in column..<5 {
                    let correction = try multiplier.multiplied(by: matrix[column * 5 + entry], usage: &usage)
                    matrix[row * 5 + entry] = try matrix[row * 5 + entry].subtracting(correction, usage: &usage)
                }
            }
        }
        try admission.reserve(count: 8, stride: MemoryLayout<ExactRationalCoefficient>.stride)
        var constants = [ExactRationalCoefficient](repeating: .zero, count: 4)
        var slopes = [ExactRationalCoefficient](repeating: .zero, count: 4)
        slopes[free] = .one
        for row in 0..<3 {
            constants[dependent[row]] = matrix[row * 5 + 3]
            slopes[dependent[row]] = matrix[row * 5 + 4]
        }
        return Self(constants: constants, slopes: slopes)
    }

    func bounds(at fraction: Double, admission: SurfaceSurfaceQueryAdmission) throws -> [OutwardScalarInterval]? {
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
            throw GeometryConversionError.invalidInput("An original affine graph gauge must lie in the closed source chart.")
        }
        var usage = Usage(admission: admission)
        let t = try ExactRationalCoefficient.originalDouble(fraction, usage: &usage)
        try admission.reserve(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
        var result: [OutwardScalarInterval] = []; result.reserveCapacity(4)
        for index in 0..<4 {
            let value = try constants[index].adding(slopes[index].multiplied(by: t, usage: &usage), usage: &usage)
            guard !value.isNegative,
                !(try value.subtracting(.one, usage: &usage)).isPositive else { return nil }
            let enclosure = try value.outwardInterval(usage: &usage)
            guard let retained = enclosure.intersection(with: .init(lower: 0, upper: 1)) else {
                throw GeometryConversionError.invalidInput("An exact admitted plane parameter lost its closed enclosure.")
            }
            result.append(retained)
        }
        return result
    }

    func fullGraphBounds(admission: SurfaceSurfaceQueryAdmission) throws -> [OutwardScalarInterval]? {
        guard let first = try bounds(at: 0, admission: admission),
            let last = try bounds(at: 1, admission: admission) else { return nil }
        try admission.reserve(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
        var result: [OutwardScalarInterval] = []; result.reserveCapacity(4)
        for index in 0..<4 { try admission.step(); result.append(first[index].union(last[index])) }
        return result
    }

    func derivativeBounds(admission: SurfaceSurfaceQueryAdmission) throws -> [ScalarInterval] {
        var usage = Usage(admission: admission)
        try admission.reserve(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
        var result: [ScalarInterval] = []; result.reserveCapacity(4)
        for slope in slopes {
            try admission.step()
            let interval = try slope.outwardInterval(usage: &usage)
            result.append(try .init(lower: interval.lower, upper: interval.upper))
        }
        return result
    }
}
