import CADCore

/// Exact equation of an original plane source, independent of its numeric normal.
package struct OriginalSupportingPlaneEquation: Sendable {
    package struct Vector: Sendable {
        package let x: ExactRationalCoefficient
        package let y: ExactRationalCoefficient
        package let z: ExactRationalCoefficient
        package init(x: ExactRationalCoefficient, y: ExactRationalCoefficient, z: ExactRationalCoefficient) {
            self.x = x; self.y = y; self.z = z
        }
        package var isZero: Bool { x.isZero && y.isZero && z.isZero }

        package static func original<B: RationalAlgebraAdmitting>(_ value: Point3D, usage: inout B) throws -> Self {
            try .init(x: .originalDouble(value.x, usage: &usage), y: .originalDouble(value.y, usage: &usage),
                z: .originalDouble(value.z, usage: &usage))
        }
        package static func original<B: RationalAlgebraAdmitting>(_ value: Vector3D, usage: inout B) throws -> Self {
            try .init(x: .originalDouble(value.x, usage: &usage), y: .originalDouble(value.y, usage: &usage),
                z: .originalDouble(value.z, usage: &usage))
        }
        package func subtracting<B: RationalAlgebraAdmitting>(_ value: Self, usage: inout B) throws -> Self {
            try .init(x: x.subtracting(value.x, usage: &usage), y: y.subtracting(value.y, usage: &usage),
                z: z.subtracting(value.z, usage: &usage))
        }
        package func scaled<B: RationalAlgebraAdmitting>(by value: ExactRationalCoefficient, usage: inout B) throws -> Self {
            try .init(x: x.multiplied(by: value, usage: &usage), y: y.multiplied(by: value, usage: &usage),
                z: z.multiplied(by: value, usage: &usage))
        }
        package func dot<B: RationalAlgebraAdmitting>(_ value: Self, usage: inout B) throws -> ExactRationalCoefficient {
            try x.multiplied(by: value.x, usage: &usage).adding(y.multiplied(by: value.y, usage: &usage), usage: &usage)
                .adding(z.multiplied(by: value.z, usage: &usage), usage: &usage)
        }
        package func cross<B: RationalAlgebraAdmitting>(_ value: Self, usage: inout B) throws -> Self {
            try .init(x: y.multiplied(by: value.z, usage: &usage).subtracting(z.multiplied(by: value.y, usage: &usage), usage: &usage),
                y: z.multiplied(by: value.x, usage: &usage).subtracting(x.multiplied(by: value.z, usage: &usage), usage: &usage),
                z: x.multiplied(by: value.y, usage: &usage).subtracting(y.multiplied(by: value.x, usage: &usage), usage: &usage))
        }
    }

    package let normal: Vector
    package let offset: ExactRationalCoefficient
    package init(normal: Vector, offset: ExactRationalCoefficient) {
        self.normal = normal; self.offset = offset
    }

    package func contains<B: RationalAlgebraAdmitting>(_ point: Point3D, usage: inout B) throws -> Bool {
        try normal.dot(.original(point, usage: &usage), usage: &usage).adding(offset, usage: &usage).isZero
    }
    package func polynomial<B: RationalAlgebraAdmitting>(_ fields: [ExactBivariatePolynomial],
        includeOffset: Bool, usage: inout B) throws -> ExactBivariatePolynomial {
        guard fields.count >= (includeOffset ? 4 : 3) else {
            throw GeometryConversionError.invalidInput("Original plane equation lost its homogeneous fields.")
        }
        var result = try fields[0].scaled(by: normal.x, usage: &usage)
            .adding(fields[1].scaled(by: normal.y, usage: &usage), usage: &usage)
            .adding(fields[2].scaled(by: normal.z, usage: &usage), usage: &usage)
        if includeOffset { result = try result.adding(fields[3].scaled(by: offset, usage: &usage), usage: &usage) }
        return result
    }
    package func pulledBack<B: RationalAlgebraAdmitting>(by transform: AffineTransform3D, usage: inout B) throws -> Self {
        try .init(normal: .init(x: normal.dot(.original(transform.basisX, usage: &usage), usage: &usage),
            y: normal.dot(.original(transform.basisY, usage: &usage), usage: &usage),
            z: normal.dot(.original(transform.basisZ, usage: &usage), usage: &usage)),
            offset: normal.dot(.original(transform.translation, usage: &usage), usage: &usage).adding(offset, usage: &usage))
    }
    package func pushedForward<B: RationalAlgebraAdmitting>(by transform: AffineTransform3D, usage: inout B) throws -> Self {
        try pushedForward(x: .original(transform.basisX, usage: &usage), y: .original(transform.basisY, usage: &usage),
            z: .original(transform.basisZ, usage: &usage), translation: .original(transform.translation, usage: &usage), usage: &usage)
    }
    private func pushedForward<B: RationalAlgebraAdmitting>(x: Vector, y: Vector, z: Vector,
        translation: Vector, usage: inout B) throws -> Self {
        let first = try y.cross(z, usage: &usage), second = try z.cross(x, usage: &usage), third = try x.cross(y, usage: &usage)
        let determinant = try x.dot(first, usage: &usage)
        guard !determinant.isZero else { throw GeometryConversionError.invalidInput("Original plane image has a singular exact cofactor.") }
        func component(_ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
            _ c: ExactRationalCoefficient) throws -> ExactRationalCoefficient {
            try a.multiplied(by: normal.x, usage: &usage).adding(b.multiplied(by: normal.y, usage: &usage), usage: &usage)
                .adding(c.multiplied(by: normal.z, usage: &usage), usage: &usage)
        }
        let target = try Vector(x: component(first.x, second.x, third.x),
            y: component(first.y, second.y, third.y), z: component(first.z, second.z, third.z))
        return try .init(normal: target, offset: offset.multiplied(by: determinant, usage: &usage)
            .subtracting(target.dot(translation, usage: &usage), usage: &usage))
    }

    package static func prepared<B: RationalAlgebraAdmitting>(source: Surface3D, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, usage: inout B) throws -> Self {
        try usage.consumeExactWork(1)
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original plane equation exhausted its retained source depth.")
        }
        let origin: Point3D, normal: Vector
        switch source {
        case .plane(let plane):
            origin = plane.origin
            let originalNormal = try Vector.original(plane.normal, usage: &usage)
            if let direction = plane.uDirection {
                let u = try Vector.original(direction, usage: &usage)
                // The authored chart retains tolerated nonorthogonality of N and U.
                normal = try u.cross(originalNormal.cross(u, usage: &usage), usage: &usage)
            } else {
                normal = originalNormal
            }
        case .analytic(.plane(let point, let direction)): origin = point; normal = try .original(direction, usage: &usage)
        case .procedural(.originalImage(let image)):
            let equation = try prepared(source: image.source, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                usage: &usage).pushedForward(by: image.transform, usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return equation
        case .procedural(.originalAffineWord(let image)):
            let original = try prepared(source: image.source, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1, usage: &usage)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Strict generated plane derivatives
            // require the original ordered-field equation for normalized word
            // coefficients. Rational getters must not replace it with midpoints.
            guard try image.preparedWord.originalNormalizedFrame(usage: &usage) == nil else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original plane projection needs its normalized ordered-field equation.")
            }
            func column(_ index: Int) throws -> Vector {
                try usage.consumeExactWork(3)
                return try .init(x: image.preparedWord.linearCoefficient(row: 0, column: index),
                    y: image.preparedWord.linearCoefficient(row: 1, column: index),
                    z: image.preparedWord.linearCoefficient(row: 2, column: index))
            }
            try usage.consumeExactWork(3)
            let translation = try Vector(x: image.preparedWord.translationCoefficient(row: 0),
                y: image.preparedWord.translationCoefficient(row: 1), z: image.preparedWord.translationCoefficient(row: 2))
            let equation = try original.pushedForward(x: column(0), y: column(1), z: column(2), translation: translation, usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return equation
        case .bSpline(let spline):
            guard let first = spline.controlPoints.first?.first else {
                throw GeometryConversionError.invalidInput("Original plane support is empty.")
            }
            origin = first
            let a = try Vector.original(first, usage: &usage)
            var direction: Vector?, selected: Vector?
            for row in spline.controlPoints {
                for point in row {
                    try usage.consumeExactWork(1)
                    let difference = try Vector.original(point, usage: &usage).subtracting(a, usage: &usage)
                    if let direction {
                        let cross = try direction.cross(difference, usage: &usage)
                        if !cross.isZero { selected = cross; break }
                    } else if !difference.isZero { direction = difference }
                }
                if selected != nil { break }
            }
            guard let selected else { throw GeometryConversionError.invalidInput("Original plane support has no nonzero exact cofactor.") }
            normal = selected
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Generated strict plane sources
            // consume this equation issuer. Remaining procedural plane families
            // need original exact transport before their projection can succeed.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original support plane has no exact equation transport.")
        }
        guard !normal.isZero else { throw GeometryConversionError.invalidInput("Original plane equation has zero normal.") }
        let equation = try Self(normal: normal, offset: normal.dot(.original(origin, usage: &usage), usage: &usage).negated)
        if case .bSpline(let spline) = source {
            for row in spline.controlPoints { for point in row {
                try usage.consumeExactWork(1)
                guard try equation.contains(point, usage: &usage) else {
                    throw GeometryConversionError.invalidInput("Original native support controls do not satisfy the exact plane equation.")
                }
            } }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return equation
    }
}
