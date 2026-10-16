import HashTreeCollections
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
        momentMeasurer: any BRepVolumeMomentMeasuring,
        attributes: any ProductAttributeResolving) {
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
        var execution = try DefaultBRepVolumeMomentMeasurer.originalExecution(options: options)
        return try measure(components, in: document, options: options,
            modelLengthUnit: modelLengthUnit, reference: reference, using: &execution)
    }

    public func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, reference: Point3D = .origin,
        using execution: inout OriginalQueryExecution) throws -> MassPropertyMeasurement {
        try measure(components, in: document, options: options,
            modelLengthUnit: document.document.units.length, reference: reference, using: &execution)
    }

    public func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, modelLengthUnit: LengthUnit,
        reference: Point3D = .origin, using execution: inout OriginalQueryExecution) throws -> MassPropertyMeasurement {
        try execution.checkpoint()
        try options.validate()
        let initialWork = execution.localWork
        let allocationPolicy = execution.effectiveAllocationPolicy
        let result = try execution.withAllocationScope(policy: allocationPolicy, workLimit: options.maximumWork) { execution in
            let requestContribution = try execution.makeContributionHandle(workLimit: options.maximumWork,
                allocationPolicy: execution.effectiveAllocationPolicy,
                executionLimits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                    remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth))
            return try execution.withContributionScope(requestContribution) { execution in
                try measureComponents(components, in: document, options: options,
                    modelLengthUnit: modelLengthUnit, reference: reference,
                    initialWork: initialWork, using: &execution)
            }
        }
        try execution.checkpoint()
        return result
    }

    private func measureComponents(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, modelLengthUnit: LengthUnit, reference: Point3D,
        initialWork: Int, using execution: inout OriginalQueryExecution) throws -> MassPropertyMeasurement {
        try tolerance.validate(); try reference.validate()
        guard !components.isEmpty, options.absoluteAccuracy.isFinite, options.absoluteAccuracy > 0,
            options.relativeAccuracy.isFinite, options.relativeAccuracy >= 0,
            options.maximumWork > 0, options.maximumWork <= 262_144,
            options.maximumSubdivisionDepth >= 0, options.maximumSubdivisionDepth <= 32,
            components.count <= options.maximumWork else {
            throw failure("Mass composition requires components admitted by the original work/depth ceilings.")
        }
        var remainingWork: Int { max(0, options.maximumWork - (execution.localWork - initialWork)) }
        var retainedMoments: [BodyID: BRepVolumeMoments] = [:]
        let resolved: ResolvedProductAttributes?
        if try OriginalParameterQueryStorage.contains(components, using: &execution, predicate: { component, execution in component.densityKilogramsPerCubicMeter == nil }) {
            guard remainingWork > 0 else { throw budgetFailure() }
            let standard = ProductAttributeLimits.standard
            let available = remainingWork
            let result = try attributes.resolve(document, limits: ProductAttributeLimits(
                maximumRecords: min(standard.maximumRecords, remainingWork),
                maximumTargets: min(standard.maximumTargets, remainingWork),
                maximumDepth: standard.maximumDepth,
                maximumTextBytes: standard.maximumTextBytes, maximumWork: available), using: &execution)
            guard result.consumedWork >= 0, result.consumedWork <= available else { throw budgetFailure() }
            resolved = result
        } else { resolved = nil }
        let scale = modelLengthUnit.metersPerUnit
        var mass = Bounds.exact(0)
        var first = try OriginalParameterQueryStorage.repeated(Bounds.exact(0), count: 3, using: &execution)
        var second = try zeroMatrix(using: &execution)
        for component in components {
            try execution.consumeWork(1)
            try component.placement.validate(tolerance: tolerance)
            guard remainingWork > 0 else { throw budgetFailure() }
            guard document.brep.bodies[component.bodyID] != nil else { throw failure("Mass component body is missing.") }
            let density: Double
            if let supplied = component.densityKilogramsPerCubicMeter { density = supplied }
            else {
                guard let resolved else { throw failure("Mass composition lost requested effective density authority.") }
                guard resolved.values.count <= remainingWork else { throw budgetFailure() }
                let matching = try OriginalParameterQueryStorage.filter(resolved.values, using: &execution) { value, execution in
                    value.key.topology == .body(component.bodyID)
                }
                guard matching.count == 1, let properties = matching.first?.value else { throw failure("Mass body requires one resolved physical-property owner.") }
                if case .density(let value) = properties.properties[.density]?.value { density = value.kilogramsPerCubicMeter }
                else { throw failure("Mass body has no resolved physical density.") }
            }
            guard density.isFinite, density >= 0 else { throw failure("Density must be finite and nonnegative in kilograms per cubic metre.") }
            let moments: BRepVolumeMoments
            if let retained = retainedMoments[component.bodyID] { moments = retained }
            else {
                guard remainingWork > 0 else { throw budgetFailure() }
                let available = remainingWork
                let request = BRepVolumeMomentOptions(absoluteAccuracy: options.absoluteAccuracy,
                    relativeAccuracy: options.relativeAccuracy, maximumWork: remainingWork,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth)
                if let certificate = document.validatedBRep {
                    guard certificate.tolerance == tolerance, certificate.validationLevel != .modeling else {
                        throw failure("Mass integration requires the original exact receipt at the configured tolerance.")
                    }
                    moments = try momentMeasurer.moments(of: component.bodyID, in: certificate, options: request, using: &execution)
                } else {
                    moments = try momentMeasurer.moments(of: component.bodyID, in: document.brep,
                        options: request, tolerance: tolerance, using: &execution)
                }
                guard moments.consumedWork > 0, moments.consumedWork <= available else { throw budgetFailure() }
                try OriginalParameterQueryStorage.set(moments, for: component.bodyID,
                    in: &retainedMoments, using: &execution)
            }
            let coefficients = try OriginalParameterQueryStorage.map(moments.enclosures, using: &execution) { value, execution in Bounds(value) }
            let basisX: Vector3D, basisY: Vector3D, basisZ: Vector3D, offset: Vector3D
            let jacobian: Bounds
            if let affine = component.affinePlacement {
                try affine.validate()
                basisX = affine.basisX; basisY = affine.basisY; basisZ = affine.basisZ; offset = affine.translation
                let originalDeterminant = try affine.originalDeterminantBounds(using: &execution)
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
            let m = try coefficients[0] * materialDensity * power(scale,3, using: &execution)
            let sourceFirst = try OriginalParameterQueryStorage.map(1...3, using: &execution) { index, execution in
                try coefficients[index] * materialDensity * power(scale,4, using: &execution)
            }
            let rawSecond = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                let x = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [coefficients[4],coefficients[7],coefficients[8]]
                }
                let y = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [coefficients[7],coefficients[5],coefficients[9]]
                }
                let z = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [coefficients[8],coefficients[9],coefficients[6]]
                }
                try execution.consumeWork(3); return [x,y,z]
            }
            let sourceSecond = try OriginalParameterQueryStorage.map(rawSecond, using: &execution) { row, execution in
                try OriginalParameterQueryStorage.map(row, using: &execution) { value, execution in
                    try value * materialDensity * power(scale,5, using: &execution)
                }
            }
            let rotation = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                let x = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [basisX.x,basisY.x,basisZ.x]
                }
                let y = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [basisX.y,basisY.y,basisZ.y]
                }
                let z = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                    try execution.consumeWork(3); return [basisX.z,basisY.z,basisZ.z]
                }
                try execution.consumeWork(3); return [x,y,z]
            }
            let offsetValues = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                try execution.consumeWork(3); return [offset.x,offset.y,offset.z]
            }
            let translation = try OriginalParameterQueryStorage.map(offsetValues, using: &execution) { value, execution in
                Bounds.exact(value)*Bounds.exact(scale)
            }
            var rotatedFirst = try OriginalParameterQueryStorage.repeated(Bounds.exact(0), count: 3, using: &execution)
            for i in 0..<3 { for j in 0..<3 {
                try execution.consumeWork(1)
                rotatedFirst[i] = rotatedFirst[i] + .exact(rotation[i][j]) * sourceFirst[j]
            } }
            for i in 0..<3 {
                try execution.consumeWork(1)
                first[i] = first[i] + rotatedFirst[i] + translation[i] * m
                for j in 0..<3 {
                    try execution.consumeWork(1)
                    var value = Bounds.exact(0)
                    for a in 0..<3 { for b in 0..<3 {
                        try execution.consumeWork(1)
                        value = value + .exact(rotation[i][a]) * sourceSecond[a][b] * .exact(rotation[j][b])
                    } }
                    value = value + translation[i] * rotatedFirst[j] + translation[j] * rotatedFirst[i]
                        + translation[i] * translation[j] * m
                    second[i][j] = second[i][j] + value
                }
            }
            mass = mass + m
        }
        guard mass.lower > 0 else { throw failure("Mass enclosure must prove positive total mass to define a centroid.") }
        let centers = try OriginalParameterQueryStorage.map(first, using: &execution) { value, execution in try value.divided(by: mass) }
        let referenceValues = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
            try execution.consumeWork(3); return [reference.x,reference.y,reference.z]
        }
        // The original accumulated tensor remains retained for result publication.
        var centeredSecond = try OriginalParameterQueryStorage.map(second, using: &execution) { row, execution in
            try OriginalParameterQueryStorage.materialize(row, using: &execution)
        }
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            centeredSecond[i][j] = second[i][j] - .exact(referenceValues[i]) * first[j] - .exact(referenceValues[j]) * first[i]
                + .exact(referenceValues[i]) * .exact(referenceValues[j]) * mass
        } }
        let trace = centeredSecond[0][0] + centeredSecond[1][1] + centeredSecond[2][2]
        var inertia = try zeroMatrix(using: &execution)
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            inertia[i][j] = i == j ? trace-centeredSecond[i][j] : -centeredSecond[i][j]
        } }
        let eigen = try principalAxes(inertia, using: &execution)
        let firstIntervals = try OriginalParameterQueryStorage.map(first, using: &execution) { value, execution in try value.interval() }
        let secondIntervals = try OriginalParameterQueryStorage.map(second, using: &execution) { row, execution in
            try OriginalParameterQueryStorage.map(row, using: &execution) { value, execution in try value.interval() }
        }
        let centroidIntervals = try OriginalParameterQueryStorage.map(centers, using: &execution) { value, execution in try value.interval() }
        let inertiaIntervals = try OriginalParameterQueryStorage.map(inertia, using: &execution) { row, execution in
            try OriginalParameterQueryStorage.map(row, using: &execution) { value, execution in try value.interval() }
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<MassPropertyMeasurement>.stride)
        let result = MassPropertyMeasurement(requestedIntegrationAccuracy: options, modelLengthUnit: modelLengthUnit,
            consumedWork: options.maximumWork-remainingWork, mass: try mass.interval(), firstMoments: firstIntervals,
            secondMoments: secondIntervals, centroid: Point3D(x:centers[0].midpoint,y:centers[1].midpoint,z:centers[2].midpoint),
            centroidBounds: centroidIntervals, inertiaAtReference: inertiaIntervals, inertiaReference: reference,
            principalMoments: eigen.moments, principalAxes: eigen.axes,
            principalFrameOrthogonalityError: eigen.frameError, principalAxisResidualBounds: eigen.residuals)
        try result.validate(using: &execution)
        // Only the scalar consumption field changes; the validated array owners are retained.
        return MassPropertyMeasurement(requestedIntegrationAccuracy: result.requestedIntegrationAccuracy,
            modelLengthUnit: result.modelLengthUnit, consumedWork: options.maximumWork-remainingWork,
            mass: result.mass, firstMoments: result.firstMoments, secondMoments: result.secondMoments,
            centroid: result.centroid, centroidBounds: result.centroidBounds,
            inertiaAtReference: result.inertiaAtReference, inertiaReference: result.inertiaReference,
            principalMoments: result.principalMoments, principalAxes: result.principalAxes,
            principalFrameOrthogonalityError: result.principalFrameOrthogonalityError,
            principalAxisResidualBounds: result.principalAxisResidualBounds)
    }
    private func zeroMatrix(using execution: inout OriginalQueryExecution) throws -> [[Bounds]] {
        try OriginalParameterQueryStorage.map(0..<3, using: &execution) { _, execution in
            try OriginalParameterQueryStorage.repeated(Bounds.exact(0), count: 3, using: &execution)
        }
    }
    private func identityMatrix(using execution: inout OriginalQueryExecution) throws -> [[Double]] {
        try OriginalParameterQueryStorage.map(0..<3, using: &execution) { i, execution in
            try OriginalParameterQueryStorage.map(0..<3, using: &execution) { j, execution in i == j ? 1.0 : 0.0 }
        }
    }
    private func power(_ x: Double, _ n: Int, using execution: inout OriginalQueryExecution) throws -> Bounds {
        var value = Bounds.exact(1)
        for _ in 0..<n { try execution.consumeWork(1); value = value * .exact(x) }
        return value
    }
    private func principalAxes(_ input: [[Bounds]], using execution: inout OriginalQueryExecution) throws
        -> (moments: [ScalarInterval], axes: [Vector3D], frameError: Double, residuals: [ScalarInterval]) {
        var matrix = try OriginalParameterQueryStorage.map(input, using: &execution) { row, execution in
            try OriginalParameterQueryStorage.map(row, using: &execution) { value, execution in value.midpoint }
        }
        var vectors = try identityMatrix(using: &execution)
        for _ in 0..<32 {
            try execution.consumeWork(1)
            let pairs = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                try execution.consumeWork(3); return [(0,1),(0,2),(1,2)]
            }
            var selected = pairs.first
            for candidate in pairs.dropFirst() {
                try execution.consumeWork(1)
                if let current = selected, abs(matrix[current.0][current.1]) < abs(matrix[candidate.0][candidate.1]) { selected = candidate }
            }
            guard let pair = selected else { break }
            let p = pair.0, q = pair.1
            if abs(matrix[p][q]) <= Double.ulpOfOne * max(1, max(abs(matrix[p][p]),abs(matrix[q][q]))) { break }
            let angle = atan2(2*matrix[p][q],matrix[q][q]-matrix[p][p])/2
            let c = cos(angle), s = sin(angle)
            var rotation = try identityMatrix(using: &execution)
            rotation[p][p]=c; rotation[q][q]=c; rotation[p][q]=s; rotation[q][p] = -s
            func product(_ a: [[Double]], _ b: [[Double]], using execution: inout OriginalQueryExecution) throws -> [[Double]] {
                try OriginalParameterQueryStorage.map(0..<3, using: &execution) { i, execution in
                    try OriginalParameterQueryStorage.map(0..<3, using: &execution) { j, execution in
                        try OriginalParameterQueryStorage.reduce(0..<3, initial: 0.0, using: &execution) { value, k, execution in value+a[i][k]*b[k][j] }
                    }
                }
            }
            let transpose = try OriginalParameterQueryStorage.map(0..<3, using: &execution) { i, execution in
                try OriginalParameterQueryStorage.map(0..<3, using: &execution) { j, execution in rotation[j][i] }
            }
            let leftProduct = try product(transpose,matrix, using: &execution)
            matrix = try product(leftProduct,rotation, using: &execution)
            vectors = try product(vectors,rotation, using: &execution)
        }
        // Bound the original tensor directly. This proof does not assume that
        // floating-point Jacobi rotations were exact or exactly orthogonal.
        var gramSquared = 0.0, reconstructionSquared = 0.0
        func absoluteUpper(_ value: Bounds) -> Double { max(abs(value.lower),abs(value.upper)) }
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            var gram = Bounds.exact(i == j ? -1 : 0)
            var reconstruction = Bounds.exact(0)
            for k in 0..<3 {
                try execution.consumeWork(1)
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
        let magnitudes = try OriginalParameterQueryStorage.map(0..<3, using: &execution) { i, execution in abs(matrix[i][i]) }
        let largestMoment = try OriginalParameterQueryStorage.extrema(magnitudes, using: &execution, projection: { value, execution in value })!.upper.nextUp
        let correction = ((frameCorrection*largestMoment).nextUp*(frameNorm+1).nextUp).nextUp
        let error = (reconstructionSquared.squareRoot().nextUp+correction).nextUp
        guard error.isFinite else { throw failure("Principal inertia arithmetic is nonfinite.") }
        var order = try OriginalParameterQueryStorage.materialize(0..<3, using: &execution)
        // The original stable ordering preserves source axes for equal candidate moments.
        for index in 1..<order.count {
            try execution.consumeWork(1)
            var cursor = index
            while cursor > 0 {
                try execution.consumeWork(1)
                guard matrix[order[cursor]][order[cursor]] < matrix[order[cursor-1]][order[cursor-1]] else { break }
                order.swapAt(cursor, cursor-1); cursor -= 1
            }
        }
        let moments = try OriginalParameterQueryStorage.map(order, using: &execution) { k, execution in
            try ScalarInterval(lower:(matrix[k][k]-error).nextDown,upper:(matrix[k][k]+error).nextUp)
        }
        let axes = try OriginalParameterQueryStorage.map(order, using: &execution) { k, execution in
            Vector3D(x:vectors[0][k],y:vectors[1][k],z:vectors[2][k])
        }
        let residuals = try OriginalParameterQueryStorage.map(order, using: &execution) { k, execution -> ScalarInterval in
            var squared = 0.0
            for i in 0..<3 {
                try execution.consumeWork(1)
                var residual = Bounds.exact(-matrix[k][k]) * .exact(vectors[i][k])
                for j in 0..<3 { try execution.consumeWork(1); residual = residual + input[i][j] * .exact(vectors[j][k]) }
                let upper = absoluteUpper(residual)
                squared = (squared+(upper*upper).nextUp).nextUp
            }
            return try ScalarInterval(lower: 0, upper: squared.squareRoot().nextUp)
        }
        try execution.checkpoint()
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
            let first = a.lower*b.lower, second = a.lower*b.upper
            let third = a.upper*b.lower, fourth = a.upper*b.upper
            var lower = first, upper = first
            if second < lower { lower = second }; if upper < second { upper = second }
            if third < lower { lower = third }; if upper < third { upper = third }
            if fourth < lower { lower = fourth }; if upper < fourth { upper = fourth }
            return Self(lower:lower.nextDown,upper:upper.nextUp)
        }
        func divided(by b:Self)throws->Self{
            guard b.lower>0 || b.upper<0 else {throw GeometryError.invalidDistance(b.lower)}
            return self * Self(lower:(1/b.upper).nextDown,upper:(1/b.lower).nextUp)
        }
        func interval()throws->ScalarInterval{try ScalarInterval(lower:lower,upper:upper)}
    }
}
