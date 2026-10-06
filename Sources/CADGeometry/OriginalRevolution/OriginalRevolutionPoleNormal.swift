import CADCore

/// Closed one-sided original Rodrigues normal after its exact endpoint factor.
package struct OriginalRevolutionPoleNormal: Sendable {
    package let surface:OriginalRevolutionSurface3D
    package let atEnd:Bool
    package let radialOrder:Int
    package let axialDerivativeOrder:Int?
    private let inwardGenerator:OriginalCurveRootSpan3D
    private let tolerance:ModelingTolerance

    package init<B:RationalAlgebraAdmitting>(surface:OriginalRevolutionSurface3D,atEnd:Bool,
        maximumSubdivisionDepth:Int,tolerance:ModelingTolerance,usage:inout B) throws {
        try usage.consumeExactWork(1)
        try surface.validate(tolerance:tolerance)
        guard maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              surface.hasOriginalAxisEndpoint(atEnd:atEnd) else {
            throw GeometryConversionError.invalidInput("Original revolution normal requires an admitted depth and original axis-endpoint witness.")
        }
        guard case .bSpline(let source) = surface.generator.source,
              let index = surface.generator.nativeSpanIndex else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Analytic angular and transformed
            // root traversal needs its original scalar derivative algebra before
            // revolution pole consumers may publish a factored closed normal.
            throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
                message:"Original revolution normal needs the retained owning scalar germ producer for this source family.")
        }
        let endpoint = atEnd ? surface.generator.end : surface.generator.start
        func zero(_ polynomial:ExactBivariatePolynomial) throws -> Bool {
            switch endpoint {
            case .algebraic(let root):
                return try root.sign(of:polynomial,maximumSubdivisionDepth:maximumSubdivisionDepth,usage:&usage) == .zero
            case .authored(let value):
                return try polynomial.evaluated(atU:.originalDouble(value,usage:&usage),v:.zero,usage:&usage).isZero
            }
        }
        let original = try OriginalRationalCurvePolynomial(source:source,spanIndex:index,tolerance:tolerance,usage:&usage)
        let derivatives = try OriginalRationalCurveDerivativeLaw(original:original,throughOrder:source.degree,usage:&usage)
        let raw = surface.axisDirection
        let dx = try ExactRationalCoefficient.originalDouble(raw.x,usage:&usage)
        let dy = try ExactRationalCoefficient.originalDouble(raw.y,usage:&usage)
        let dz = try ExactRationalCoefficient.originalDouble(raw.z,usage:&usage)
        var radial:Int?,axial:Int?
        for order in 1...source.degree {
            let q = derivatives.numerators[order]
            if radial == nil {
                try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
                let cross = try [
                    q[1].scaled(by:dz,usage:&usage).subtracting(q[2].scaled(by:dy,usage:&usage),usage:&usage),
                    q[2].scaled(by:dx,usage:&usage).subtracting(q[0].scaled(by:dz,usage:&usage),usage:&usage),
                    q[0].scaled(by:dy,usage:&usage).subtracting(q[1].scaled(by:dx,usage:&usage),usage:&usage)]
                var allZero = true
                for value in cross { if try !zero(value) { allZero = false } }
                if !allZero { radial = order }
            }
            if axial == nil {
                let dot = try q[0].scaled(by:dx,usage:&usage)
                    .adding(q[1].scaled(by:dy,usage:&usage),usage:&usage)
                    .adding(q[2].scaled(by:dz,usage:&usage),usage:&usage)
                if try !zero(dot) { axial = order-1 }
            }
            if radial != nil, axial != nil { break }
        }
        // With a positive denominator, transverse and axial displacement
        // numerators have degree at most p. A finite germ cannot first appear
        // after p; all p zero derivative germs prove a constant coordinate.
        guard let radial else {
            throw KernelError(phase:.geometry,code:.singularGeometry,tolerance:tolerance,
                message:"The original revolution generator is exactly entirely axial on its owning rational span.")
        }
        self.surface = surface;self.atEnd = atEnd;radialOrder = radial;axialDerivativeOrder = axial
        inwardGenerator = atEnd ? surface.generator.reversed() : surface.generator
        self.tolerance = tolerance
    }

    package func panelBounds<B:RationalAlgebraAdmitting>(over box:SurfaceParameterBox,
        tolerance:ModelingTolerance,storageByteStride:Int,usage:inout B) throws -> OriginalSurfacePoleNormalPanel {
        try usage.consumeExactWork(1)
        guard storageByteStride > 0,tolerance == self.tolerance,box.u.lower.isFinite,box.u.upper.isFinite,
              box.v.lower.isFinite,box.v.upper.isFinite,box.v.lower >= 0,box.v.upper <= 1,
              case let .closed(uLower,uUpper) = surface.uDomain,
              box.u.lower >= uLower,box.u.upper <= uUpper,
              (atEnd ? box.v.upper == 1 : box.v.lower == 0) else {
            throw GeometryConversionError.invalidInput("Original revolution pole panel must own its retained exact endpoint.")
        }
        let inwardUpper = atEnd
            ? min(1,(OutwardScalarInterval.exact(1) - .exact(box.v.lower)).upper)
            : box.v.upper
        let range = try ScalarInterval(lower:0,upper:inwardUpper)
        let order = max(radialOrder+1,(axialDerivativeOrder ?? -1)+2)
        // Preparation has proved one raw native owning span. This fixed query
        // uses its cache, with no recursive source owner or renewed root solver.
        let jet = try inwardGenerator.intervalTaylorJet(over:range,throughOrder:order,tolerance:tolerance,
            storageByteStride:storageByteStride,usage:&usage, maximumSpanCount:1, remainingSourceDepth:0)
        let raw = surface.axisDirection
        let sourceAxis = IntervalVector3DBounds(x:.exact(raw.x),y:.exact(raw.y),z:.exact(raw.z))
        guard let axis = try sourceAxis.normalized(consumeWork: { try usage.consumeExactWork(1) }) else {
            throw GeometryConversionError.resourceLimitExceeded("Original revolution raw axis has no finite normalization.")
        }
        func coefficient(_ order:Int) throws -> IntervalVector3DBounds {
            try .init(x:jet.x.coefficient(order,0),y:jet.y.coefficient(order,0),z:jet.z.coefficient(order,0))
        }
        func radial(_ q:IntervalVector3DBounds)->IntervalVector3DBounds { q-axis*q.dot(axis) }
        let rf = radial(try coefficient(radialOrder)),rdf = radial(try coefficient(radialOrder+1))
        let rpf = rf * .exact(Double(radialOrder))
        let rpdf = radial(try coefficient(radialOrder+1)) * .exact(Double(radialOrder+1))
        let lowerOrder = min(radialOrder+(axialDerivativeOrder ?? radialOrder-1),2*radialOrder-1)
        let s = OutwardScalarInterval(lower:range.lower,upper:range.upper)
        func power(_ exponent:Int) throws -> OutwardScalarInterval {
            var value = OutwardScalarInterval.exact(1)
            if exponent > 0 { for _ in 0..<exponent {
                try usage.consumeExactWork(1)
                value = value*s
            } }
            return value
        }
        func scaled(_ value:IntervalVector3DBounds,_ derivative:IntervalVector3DBounds,_ exponent:Int)
            throws -> (IntervalVector3DBounds,IntervalVector3DBounds) {
            let p = try power(exponent)
            let dp: OutwardScalarInterval
            if exponent == 0 { dp = .exact(0) }
            else { dp = try power(exponent-1) * .exact(Double(exponent)) }
            return (value*p,derivative*p+value*dp)
        }
        let radialPair = try scaled(axis * rf.dot(rpf),axis * (rdf.dot(rpf)+rf.dot(rpdf)),2*radialOrder-1-lowerOrder)
        var field = radialPair.0 * .exact(-1)
        var derivative = radialPair.1 * .exact(-1)
        if let m = axialDerivativeOrder {
            let af = try coefficient(m+1).dot(axis) * .exact(Double(m+1))
            let adf = try coefficient(m+2).dot(axis) * .exact(Double(m+2))
            let axialPair = try scaled(rf*af,rdf*af+rf*adf,radialOrder+m-lowerOrder)
            field = field+axialPair.0;derivative = derivative+axialPair.1
        }
        // At the upper pole F(v) = -P(1-v), hence F'(v) = P'(1-v).
        // Only the field changes sign; the signed V derivative does not.
        if atEnd { field = field * .exact(-1) }
        let angle = SurfaceIntervalJet.parameterU(box.u)
        let cosine = try CanonicalSphereAngularPhase.harmonic(of: angle, cosine: true,
            consumeWork: { try usage.consumeExactWork(1) })
        let sine = try CanonicalSphereAngularPhase.harmonic(of: angle, cosine: false,
            consumeWork: { try usage.consumeExactWork(1) })
        func rotated(_ value:IntervalVector3DBounds)->IntervalVector3DBounds {
            let axial = axis*value.dot(axis),radial = value-axial
            return axial+radial*cosine.value+axis.cross(radial)*sine.value
        }
        let radialField = field - axis * field.dot(axis)
        let normal = rotated(field)
        // The authored radian unit carries the original symbolic full-turn
        // phase gain. Its U derivative is not a unit-gain numeric rotation.
        let du = radialField * cosine.derivativeU + axis.cross(radialField) * sine.derivativeU
        let dv = rotated(derivative)
        let low = normal.lengthLowerBound
        guard low.isFinite,low > 0 else {
            throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
                message:"Original factored revolution normal needs a smaller owning angular or radial panel.")
        }
        func storage(_ bytes: Int) throws {
            let rounded = bytes.addingReportingOverflow(storageByteStride - 1)
            guard bytes >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original revolution fixed-jet storage conversion overflows.")
            }
            try usage.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        let original = try withoutActuallyEscaping(storage) { admittedStorage in
            try surface.intervalJet(over: box, tolerance: tolerance,
                consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: admittedStorage,
                maximumSpanCount: 1,
                maximumSubdivisionDepth: min(32, surface.generator.maximumSubdivisionDepth),
                remainingSourceDepth: 0)
        }
        func magnitude(_ key:(SurfaceIntervalJet) -> OutwardScalarInterval)->Double {
            IntervalVector3DBounds(x:key(original.x),y:key(original.y),z:key(original.z)).lengthUpperBound
        }
        let bounds = SurfaceTessellationDifferentialBounds(tangentUMagnitudeUpperBound:magnitude({ $0.derivativeU }),
            tangentVMagnitudeUpperBound:magnitude({ $0.derivativeV }),secondDerivativeUUMagnitudeUpperBound:magnitude({ $0.secondDerivativeUU }),
            secondDerivativeUVMagnitudeUpperBound:magnitude({ $0.secondDerivativeUV }),secondDerivativeVVMagnitudeUpperBound:magnitude({ $0.secondDerivativeVV }),
            unitNormalDerivativeUMagnitudeUpperBound:(du.lengthUpperBound/low).nextUp,
            unitNormalDerivativeVMagnitudeUpperBound:(dv.lengthUpperBound/low).nextUp)
        try usage.consumeExactWork(16)
        guard normal.lengthUpperBound.isFinite,
              bounds.tangentUMagnitudeUpperBound.isFinite,bounds.tangentVMagnitudeUpperBound.isFinite,
              bounds.secondDerivativeUUMagnitudeUpperBound.isFinite,
              bounds.secondDerivativeUVMagnitudeUpperBound.isFinite,
              bounds.secondDerivativeVVMagnitudeUpperBound.isFinite,
              bounds.unitNormalDerivativeUMagnitudeUpperBound.isFinite,
              bounds.unitNormalDerivativeVMagnitudeUpperBound.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original revolution normal factors exceed finite whole-panel arithmetic.")
        }
        return .init(surface:.procedural(.originalRevolution(surface)),parameters:box,normalField:normal,
            tolerance:tolerance,differentialBounds:bounds)
    }
}
