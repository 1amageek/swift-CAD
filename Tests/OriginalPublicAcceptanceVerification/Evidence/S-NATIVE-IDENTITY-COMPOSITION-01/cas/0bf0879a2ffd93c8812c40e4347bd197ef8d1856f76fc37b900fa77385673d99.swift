#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain: ExactRealCellProducing {
 public func decompose<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealCellSource<Base>,
  limits: ExactRealCellLimits, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellPartition<Base> {
  let source = copy source
  return try ExactCellAccess.run(&admission,inherited:source.depth) { a in
   try require(source,&a)
   for domain in source.domains { try a.consumeWork(1); if domain.isEmpty {
    return try partition(source,levels:[],records:[],stacks:[],leaves:[],&a)
   } }
   let levels = try projection(source,&a)
   guard limits.maximumStoredCells > 0 else { throw ExactRealCellFailure.cellLimit }
   try a.visitCell(axis: .value, depth: a.depth.value)
   let origin = ExactRealCellSample(field:context.field,coordinates:[],depth:a.depth)
   try ExactCellAccess.storage(1,ExactRealCellRecord<Base>.self,&a)
   var records = [ExactRealCellRecord(sample:origin,parent:-1,branch:0,dimension:0,projectionSigns:[],signs:[],stack:-1)]
   var stacks: [ExactRealCellStack<Base>] = []
   try ExactCellAccess.storage(1,Int.self,&a)
   var leaves = [0]
   for level in levels {
    typealias RootDomain = ExactRealRootDomain<Field>
    typealias RootSet = ExactRealRootSet<Field>
    try ExactCellAccess.storage(1, (Polynomial, RootSet)?.self, &a)
    var originalRootDomain: RootDomain? = nil
    var previousOriginalRoots: (Polynomial, RootSet)? = nil
    var next: [Int] = []
    for parent in leaves {
     let prefix = records[parent].sample, field = prefix.field
     let usesOriginalField = field.extensionLevel == context.field.extensionLevel
     let rootDomain: RootDomain
     if usesOriginalField {
      if let retained = originalRootDomain { rootDomain = retained }
      else {
       let created = try RootDomain(field:field,using:&a)
       originalRootDomain = created; rootDomain = created
      }
     } else { rootDomain = try RootDomain(field:field,using:&a) }
     let p=rootDomain.polynomials
     var specialized: [ExactRealRootSource<Field>] = [], signs: [[ExactSign]] = [], active: [Int] = []
     try ExactCellAccess.storage(level.laws.count,ExactRealRootSource<Field>.self,&a)
     try ExactCellAccess.storage(level.laws.count,[ExactSign].self,&a)
     var product = try p.constant(field.integer(1,using:&a),using:&a)
     for index in level.laws.indices {
      let law = try specialize(level.laws[index],prefix:prefix,axis:level.axis,into:p,&a)
      specialized.append(try rootDomain.bind(law,using:&a))
      var coefficientSigns: [ExactSign] = []
      try ExactCellAccess.storage(level.coefficients[index].count,ExactSign.self,&a)
      for coefficient in level.coefficients[index] {
       coefficientSigns.append(try field.sign(of:evaluate(coefficient,at:prefix,&a),using:&a))
      }; signs.append(coefficientSigns)
      if let degree = try p.degree(of:law,in:0,using:&a), degree > 0, index < level.cutLawCount {
       try ExactCellAccess.storage(1,Int.self,&a); active.append(index)
       product=try adjoiningRootCuts(law,to:product,polynomials:p,using:&a)
      }
     }
     let union = try rootDomain.bind(product,using:&a)
     let rootSet: RootSet
     if usesOriginalField, let previous = previousOriginalRoots,
        try p.equals(product, previous.0, using:&a) {
      try ExactCellAccess.admit(previous.1.depth, &a)
      try a.checkpoint()
      guard previous.1.roots.count <= limits.maximumRootsPerStack else { throw ExactRealRootFailure.resultLimit }
      rootSet = previous.1
     } else {
      rootSet = try isolateRootUnion(union,laws:specialized,active:active,domain:rootDomain,limits:.init(maximumRoots:limits.maximumRootsPerStack),using:&a)
      if usesOriginalField { previousOriginalRoots = (product, rootSet) }
     }
     try ExactCellAccess.storage(rootSet.roots.count,ExactRealRoot<Field>.self,&a)
     var roots = rootSet.roots
     try ExactCellAccess.storage(max(0, roots.count - 1), ExactRealRootSeparation<Field>.self, &a)
     var separations: [ExactRealRootSeparation<Field>] = []
     if roots.count > 1 { for index in 1..<roots.count {
      let separation = try rootDomain.separate(roots[index - 1], roots[index], using: &a)
      roots[index - 1] = separation.left; roots[index] = separation.right
      separations.append(separation)
     } }
     let conditions = try parentConditions(level, parent: records[parent], &a)
     let multiplicities = try originalMultiplicities(rootSet, specialized: specialized, cutLawCount: level.cutLawCount, &a)
     try ExactCellAccess.storage(specialized.count, Int.self, &a)
     var effectiveDegrees: [Int] = []; effectiveDegrees.reserveCapacity(specialized.count)
     for law in specialized { effectiveDegrees.append(try p.degree(of: law.original, in: 0, using: &a) ?? -1) }
     let branches = try ExactCellAccess.add(ExactCellAccess.multiply(roots.count,2),1)
     try ExactCellAccess.storage(branches,Int.self,&a)
     var children = Array(repeating:-1,count:branches)
     for branch in 0..<branches {
      try a.consumeWork(1)
      let section = branch & 1 == 1, ordinal=branch/2
      var childField = field, value: Field.Value
      if section {
       let root = roots[ordinal]
       var linear: Field.Value? = nil
       for law in specialized {
        if try p.degree(of:law.original,in:0,using:&a) == 1 && rootDomain.sign(of:law,at:root,using:&a) == .zero {
         var constant = try field.integer(0,using:&a), leading=constant
         for term in law.original.terms { try a.consumeWork(1); if term.powers[0] == 0 { constant=term.coefficient } else { leading=term.coefficient } }
         linear = try field.dividing(field.negated(constant,using:&a),leading,using:&a); break
        }
       }
       if let linear { value=linear } else {
        var definingRoot = root
        var definingDegree = try p.degree(of: root.source.original, in: 0, using:&a) ?? 0
        var definingLaw: ExactRealRootSource<Field>? = nil
        for law in specialized {
         try a.consumeWork(1)
         if let degree = try p.degree(of: law.original, in:0, using:&a), degree > 1, degree < definingDegree,
            try rootDomain.sign(of:law,at:root,using:&a) == .zero {
          definingLaw = law; definingDegree = degree
         }
        }
        if let definingLaw {
         // L2 owns the selected computational factor, which may be smaller than
         // the full union. It proves the factor-relative common defining law.
         definingRoot = try rootDomain.refine(root,usingVanishingLaw:definingLaw,using:&a)
        }
        let extensionValue = try field.adjoin(definingRoot,using:&a); childField=extensionValue.domain; value=extensionValue.generator
       }
      } else {
       let one = try field.integer(1,using:&a)
       if roots.isEmpty { value = try field.integer(0,using:&a) }
       else if ordinal == 0 {
        guard case .finite(let lo) = roots[0].isolation.lower else { throw ExactRealCellFailure.invalidCoverage }
        value = try field.subtracting(lo,one,using:&a)
       } else if ordinal == roots.count {
        guard case .finite(let hi) = roots[ordinal - 1].isolation.upper else { throw ExactRealCellFailure.invalidCoverage }
        value = try field.adding(hi, one, using: &a)
       } else {
        guard separations.indices.contains(ordinal - 1) else { throw ExactRealCellFailure.invalidCoverage }
        value = separations[ordinal - 1].value
       }
      }
      if try !inside(value,field:childField,domain:source.domains[level.axis],&a) { continue }
      guard records.count < limits.maximumStoredCells else { throw ExactRealCellFailure.cellLimit }
      try a.visitCell(axis: .value, depth: a.depth.value)
      try ExactCellAccess.storage(ExactCellAccess.add(prefix.coordinates.count,1),Field.Value.self,&a)
      var coordinates: [Field.Value] = []; coordinates.reserveCapacity(prefix.coordinates.count+1)
      for earlier in prefix.coordinates { coordinates.append(try childField.importing(earlier,using:&a)) }; coordinates.append(value)
      let sample = ExactRealCellSample(field:childField,coordinates:coordinates,depth:a.depth)
      try ExactCellAccess.storage(level.laws.count,ExactSign.self,&a)
      var projectionSigns: [ExactSign] = []
      for law in level.laws { projectionSigns.append(try childField.sign(of:evaluate(law,at:sample,&a),using:&a)) }
      var truth: [ExactSign] = []
      if level.axis+1 == source.variableCount {
       try ExactCellAccess.storage(source.polynomials.count,ExactSign.self,&a)
       for law in source.polynomials { truth.append(try childField.sign(of:evaluate(law,at:sample,&a),using:&a)) }
      }
      try ExactCellAccess.storage(1,ExactRealCellRecord<Base>.self,&a); try ExactCellAccess.storage(1,Int.self,&a)
      children[branch]=records.count; next.append(records.count)
      records.append(.init(sample:sample,parent:parent,branch:branch,dimension:try ExactCellAccess.add(records[parent].dimension,section ? 0:1),projectionSigns:projectionSigns,signs:truth,stack:-1))
     }
     try ExactCellAccess.storage(1,ExactRealCellStack<Base>.self,&a)
     records[parent].stack=stacks.count
     stacks.append(.init(axis:level.axis,parent:parent,rootSet:rootSet,specialized:specialized,coefficientSigns:signs,effectiveDegrees:effectiveDegrees,parentConditionSigns:conditions,rootMultiplicities:multiplicities,separations:separations,activeLawIndices:active,children:children))
    }; leaves=next
   }
   if source.variableCount == 0 {
    try ExactCellAccess.storage(source.polynomials.count,ExactSign.self,&a)
    var truth: [ExactSign] = []
    for law in source.polynomials { truth.append(try context.field.sign(of:evaluate(law,at:origin,&a),using:&a)) }
    records[0] = .init(sample:origin,parent:-1,branch:0,dimension:0,projectionSigns:[],signs:truth,stack:-1)
   }
   return try partition(source,levels:levels,records:records,stacks:stacks,leaves:leaves,&a)
  }
 }
 func partition(_ source: ExactRealCellSource<Base>, levels: [ExactRealCellProjectionLevel<Base>], records: [ExactRealCellRecord<Base>],
  stacks: [ExactRealCellStack<Base>], leaves: [Int], _ a: inout ExactCellBorrowedAdmission) throws -> ExactRealCellPartition<Base> {
  try ExactCellAccess.owner((ExactRealCellSource<Base>,[ExactRealCellProjectionLevel<Base>],[ExactRealCellRecord<Base>],[ExactRealCellStack<Base>],[Int],ExactScalarDepth).self,&a)
  return .init(owner:.init(source:source,levels:levels,records:records,stacks:stacks,leaves:leaves,depth:a.depth))
 }
}
