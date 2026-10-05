import CADCore
import CADGeometry
import CADIR
import CADTopology
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

public struct MassPropertyEvaluator: MassPropertyMeasuring {
    private let tolerance: ModelingTolerance
    private let momentMeasurer: any BRepVolumeMomentMeasuring
    private let attributes: any ProductAttributeResolving
    public init(tolerance: ModelingTolerance,
        momentMeasurer: any BRepVolumeMomentMeasuring = DefaultBRepVolumeMomentMeasurer(),
        attributes: any ProductAttributeResolving = ProductAttributeResolver()) {
        self.tolerance = tolerance; self.momentMeasurer = momentMeasurer; self.attributes = attributes
    }
    public func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, reference: Point3D = .origin) throws -> MassPropertyMeasurement {
        try measure(components, in: document, options: options,
            modelLengthUnit: document.document.units.length, reference: reference)
    }
    public func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, modelLengthUnit: LengthUnit,
        reference: Point3D = .origin) throws -> MassPropertyMeasurement {
        try tolerance.validate(); try reference.validate()
        guard !components.isEmpty, options.absoluteAccuracy.isFinite, options.absoluteAccuracy > 0,
            options.relativeAccuracy.isFinite, options.relativeAccuracy >= 0,
            options.maximumWork > 0, options.maximumWork <= 262_144,
            options.maximumSubdivisionDepth >= 0, options.maximumSubdivisionDepth <= 32,
            components.count <= options.maximumWork else {
            throw failure("Mass composition requires components admitted by the original work/depth ceilings.")
        }
        var remainingWork = options.maximumWork
        var retainedMoments: [BodyID: BRepVolumeMoments] = [:]
        let resolved: ResolvedProductAttributes?
        if components.contains(where: { $0.densityKilogramsPerCubicMeter == nil }) {
            guard remainingWork > 0 else { throw budgetFailure() }
            let standard = ProductAttributeLimits.standard
            let result = try attributes.resolve(document, limits: ProductAttributeLimits(
                maximumRecords: min(standard.maximumRecords, remainingWork),
                maximumTargets: min(standard.maximumTargets, remainingWork),
                maximumDepth: standard.maximumDepth,
                maximumTextBytes: standard.maximumTextBytes, maximumWork: remainingWork))
            guard result.consumedWork >= 0, result.consumedWork <= remainingWork else { throw budgetFailure() }
            remainingWork -= result.consumedWork
            resolved = result
        } else { resolved = nil }
        let scale = modelLengthUnit.metersPerUnit
        var mass = Bounds.exact(0)
        var first = Array(repeating: Bounds.exact(0), count: 3)
        var second = Array(repeating: Array(repeating: Bounds.exact(0), count: 3), count: 3)
        for component in components {
            try Task.checkCancellation(); try component.placement.validate(tolerance: tolerance)
            guard remainingWork > 0 else { throw budgetFailure() }
            remainingWork -= 1
            guard document.brep.bodies[component.bodyID] != nil else { throw failure("Mass component body is missing.") }
            let density: Double
            if let supplied = component.densityKilogramsPerCubicMeter { density = supplied }
            else {
                guard let resolved else { throw failure("Mass composition lost requested effective density authority.") }
                guard resolved.values.count <= remainingWork else { throw budgetFailure() }
                remainingWork -= resolved.values.count
                let matching = resolved.values.filter { $0.key.topology == .body(component.bodyID) }
                guard matching.count == 1, let properties = matching.first?.value else { throw failure("Mass body requires one resolved physical-property owner.") }
                if case .density(let value) = properties.properties[.density]?.value { density = value.kilogramsPerCubicMeter }
                else { throw failure("Mass body has no resolved physical density.") }
            }
            guard density.isFinite, density >= 0 else { throw failure("Density must be finite and nonnegative in kilograms per cubic metre.") }
            let moments: BRepVolumeMoments
            if let retained = retainedMoments[component.bodyID] { moments = retained }
            else {
                guard remainingWork > 0 else { throw budgetFailure() }
                let request = BRepVolumeMomentOptions(absoluteAccuracy: options.absoluteAccuracy,
                    relativeAccuracy: options.relativeAccuracy, maximumWork: remainingWork,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth)
                if let certificate = document.validatedBRep {
                    guard certificate.tolerance == tolerance, certificate.validationLevel != .modeling else {
                        throw failure("Mass integration requires the original exact receipt at the configured tolerance.")
                    }
                    moments = try momentMeasurer.moments(of: component.bodyID, in: certificate, options: request)
                } else {
                    moments = try momentMeasurer.moments(of: component.bodyID, in: document.brep,
                        options: request, tolerance: tolerance)
                }
                guard moments.consumedWork > 0, moments.consumedWork <= remainingWork else { throw budgetFailure() }
                remainingWork -= moments.consumedWork
                retainedMoments[component.bodyID] = moments
            }
            let coefficients = moments.enclosures.map { Bounds($0) }
            let basisX: Vector3D, basisY: Vector3D, basisZ: Vector3D, offset: Vector3D
            let jacobian: Bounds
            if let affine = component.affinePlacement {
                try affine.validate()
                basisX = affine.basisX; basisY = affine.basisY; basisZ = affine.basisZ; offset = affine.translation
                let originalDeterminant = try affine.originalDeterminantBounds(consumeWork: {
                    try Task.checkCancellation()
                    guard remainingWork > 0 else { throw budgetFailure() }
                    remainingWork -= 1
                })
                let determinant = Bounds(originalDeterminant)
                guard determinant.lower > 0 || determinant.upper < 0 else {
                    throw failure("Original affine determinant enclosure cannot define a positive material volume scale.")
                }
                jacobian = determinant.lower > 0 ? determinant : -determinant
            } else {
                let placement = component.placement
                basisX = placement.basisX; basisY = placement.basisY; basisZ = placement.basisZ; offset = placement.translation
                jacobian = .exact(1)
            }
            let materialDensity = Bounds.exact(density)*jacobian
            let m = coefficients[0] * materialDensity * power(scale,3)
            let sourceFirst = (1...3).map { coefficients[$0] * materialDensity * power(scale,4) }
            let sourceSecond = [[coefficients[4],coefficients[7],coefficients[8]],
                [coefficients[7],coefficients[5],coefficients[9]], [coefficients[8],coefficients[9],coefficients[6]]].map { row in row.map { $0 * materialDensity * power(scale,5) } }
            let rotation = [[basisX.x,basisY.x,basisZ.x],[basisX.y,basisY.y,basisZ.y],[basisX.z,basisY.z,basisZ.z]]
            let translation = [offset.x,offset.y,offset.z].map { Bounds.exact($0)*Bounds.exact(scale) }
            var rotatedFirst = Array(repeating: Bounds.exact(0), count: 3)
            for i in 0..<3 { for j in 0..<3 { rotatedFirst[i] = rotatedFirst[i] + .exact(rotation[i][j]) * sourceFirst[j] } }
            for i in 0..<3 {
                first[i] = first[i] + rotatedFirst[i] + translation[i] * m
                for j in 0..<3 {
                    var value = Bounds.exact(0)
                    for a in 0..<3 { for b in 0..<3 { value = value + .exact(rotation[i][a]) * sourceSecond[a][b] * .exact(rotation[j][b]) } }
                    value = value + translation[i] * rotatedFirst[j] + translation[j] * rotatedFirst[i]
                        + translation[i] * translation[j] * m
                    second[i][j] = second[i][j] + value
                }
            }
            mass = mass + m
        }
        guard mass.lower > 0 else { throw failure("Mass enclosure must prove positive total mass to define a centroid.") }
        let centers = try first.map { try $0.divided(by: mass) }
        let referenceValues = [reference.x,reference.y,reference.z]
        var centeredSecond = second
        for i in 0..<3 { for j in 0..<3 {
            centeredSecond[i][j] = second[i][j] - .exact(referenceValues[i]) * first[j] - .exact(referenceValues[j]) * first[i]
                + .exact(referenceValues[i]) * .exact(referenceValues[j]) * mass
        } }
        let trace = centeredSecond[0][0] + centeredSecond[1][1] + centeredSecond[2][2]
        var inertia = Array(repeating: Array(repeating: Bounds.exact(0), count: 3), count: 3)
        for i in 0..<3 { for j in 0..<3 { inertia[i][j] = i == j ? trace-centeredSecond[i][j] : -centeredSecond[i][j] } }
        let eigen = try principalAxes(inertia)
        let result = MassPropertyMeasurement(requestedIntegrationAccuracy: options, modelLengthUnit: modelLengthUnit, consumedWork: options.maximumWork-remainingWork, mass: try mass.interval(), firstMoments: try first.map { try $0.interval() },
            secondMoments: try second.map { row in try row.map { try $0.interval() } },
            centroid: Point3D(x:centers[0].midpoint,y:centers[1].midpoint,z:centers[2].midpoint),
            centroidBounds: try centers.map { try $0.interval() },
            inertiaAtReference: try inertia.map { row in try row.map { try $0.interval() } }, inertiaReference: reference,
            principalMoments: eigen.moments, principalAxes: eigen.axes,
            principalFrameOrthogonalityError: eigen.frameError, principalAxisResidualBounds: eigen.residuals)
        try result.validate()
        return result
    }
    private func power(_ x: Double, _ n: Int) -> Bounds { var value = Bounds.exact(1); for _ in 0..<n { value = value * .exact(x) }; return value }
    private func principalAxes(_ input: [[Bounds]]) throws
        -> (moments: [ScalarInterval], axes: [Vector3D], frameError: Double, residuals: [ScalarInterval]) {
        var matrix = input.map { $0.map(\.midpoint) }
        var vectors = [[1.0,0,0],[0,1,0],[0,0,1]]
        for _ in 0..<32 {
            let pairs = [(0,1),(0,2),(1,2)]
            guard let pair = pairs.max(by: { abs(matrix[$0.0][$0.1]) < abs(matrix[$1.0][$1.1]) }) else { break }
            let p = pair.0, q = pair.1
            if abs(matrix[p][q]) <= Double.ulpOfOne * max(1, max(abs(matrix[p][p]),abs(matrix[q][q]))) { break }
            let angle = atan2(2*matrix[p][q],matrix[q][q]-matrix[p][p])/2
            let c = cos(angle), s = sin(angle)
            var rotation = [[1.0,0,0],[0,1,0],[0,0,1]]
            rotation[p][p]=c; rotation[q][q]=c; rotation[p][q]=s; rotation[q][p] = -s
            func product(_ a:[[Double]],_ b:[[Double]]) -> [[Double]] {
                (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0+a[i][$1]*b[$1][j] } } }
            }
            let transpose = (0..<3).map { i in (0..<3).map { j in rotation[j][i] } }
            matrix = product(product(transpose,matrix),rotation); vectors = product(vectors,rotation)
        }
        // Bound the original tensor directly. This proof does not assume that
        // floating-point Jacobi rotations were exact or exactly orthogonal.
        var gramSquared = 0.0, reconstructionSquared = 0.0
        func absoluteUpper(_ value: Bounds) -> Double { max(abs(value.lower),abs(value.upper)) }
        for i in 0..<3 { for j in 0..<3 {
            var gram = Bounds.exact(i == j ? -1 : 0)
            var reconstruction = Bounds.exact(0)
            for k in 0..<3 {
                gram = gram + .exact(vectors[k][i]) * .exact(vectors[k][j])
                reconstruction = reconstruction + .exact(vectors[i][k]) * .exact(matrix[k][k]) * .exact(vectors[j][k])
            }
            let g = absoluteUpper(gram), r = absoluteUpper(input[i][j]-reconstruction)
            gramSquared = (gramSquared+(g*g).nextUp).nextUp
            reconstructionSquared = (reconstructionSquared+(r*r).nextUp).nextUp
        } }
        let frameError = gramSquared.squareRoot().nextUp
        guard frameError.isFinite, frameError < 1 else {
            throw failure("Principal inertia candidate frame failed the original Gram-defect bound.")
        }
        let polarDenominator = (1 + max(0,(1-frameError).nextDown).squareRoot().nextDown).nextDown
        let frameCorrection = (frameError/polarDenominator).nextUp
        let frameNorm = (1+frameError).nextUp.squareRoot().nextUp
        let largestMoment = (0..<3).map { abs(matrix[$0][$0]) }.max()!.nextUp
        let correction = ((frameCorrection*largestMoment).nextUp*(frameNorm+1).nextUp).nextUp
        let error = (reconstructionSquared.squareRoot().nextUp+correction).nextUp
        guard error.isFinite else { throw failure("Principal inertia arithmetic is nonfinite.") }
        let order = (0..<3).sorted { matrix[$0][$0] < matrix[$1][$1] }
        let moments = try order.map { try ScalarInterval(lower:(matrix[$0][$0]-error).nextDown,upper:(matrix[$0][$0]+error).nextUp) }
        let axes = order.map { Vector3D(x:vectors[0][$0],y:vectors[1][$0],z:vectors[2][$0]) }
        let residuals = try order.map { k -> ScalarInterval in
            var squared = 0.0
            for i in 0..<3 {
                var residual = Bounds.exact(-matrix[k][k]) * .exact(vectors[i][k])
                for j in 0..<3 { residual = residual + input[i][j] * .exact(vectors[j][k]) }
                let upper = absoluteUpper(residual)
                squared = (squared+(upper*upper).nextUp).nextUp
            }
            return try ScalarInterval(lower: 0, upper: squared.squareRoot().nextUp)
        }
        return (moments,axes,frameError,residuals)
    }
    private func budgetFailure() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Mass composition exhausted its original shared work allowance.")
    }
    private func failure(_ message:String) -> KernelError { KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,message:message) }
    private struct Bounds {
        let lower:Double;let upper:Double
        init(_ interval:ScalarInterval){lower=interval.lower;upper=interval.upper}
        init(lower:Double,upper:Double){self.lower=lower;self.upper=upper}
        static func exact(_ value:Double)->Self{Self(lower:value,upper:value)}
        var midpoint:Double{lower+(upper-lower)/2}
        static prefix func -(_ a:Self)->Self{Self(lower:-a.upper,upper:-a.lower)}
        static func +(_ a:Self,_ b:Self)->Self{Self(lower:(a.lower+b.lower).nextDown,upper:(a.upper+b.upper).nextUp)}
        static func -(_ a:Self,_ b:Self)->Self{a + -b}
        static func *(_ a:Self,_ b:Self)->Self{
            let values=[a.lower*b.lower,a.lower*b.upper,a.upper*b.lower,a.upper*b.upper]
            return Self(lower:values.min()!.nextDown,upper:values.max()!.nextUp)
        }
        func divided(by b:Self)throws->Self{
            guard b.lower>0 || b.upper<0 else {throw GeometryError.invalidDistance(b.lower)}
            return self * Self(lower:(1/b.upper).nextDown,upper:(1/b.lower).nextUp)
        }
        func interval()throws->ScalarInterval{try ScalarInterval(lower:lower,upper:upper)}
    }
}
