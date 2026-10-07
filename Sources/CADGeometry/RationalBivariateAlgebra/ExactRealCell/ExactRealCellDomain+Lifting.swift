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
   let origin = ExactRealCellSample(field:context.field,coordinates:[],depth:a.depth)
   try ExactCellAccess.storage(1,ExactRealCellRecord<Base>.self,&a)
   var records = [ExactRealCellRecord(sample:origin,parent:-1,branch:0,dimension:0,signs:[],stack:-1)]
   var stacks: [ExactRealCellStack<Base>] = []
   try ExactCellAccess.storage(1,Int.self,&a)
   var leaves = [0]
   for level in levels {
    var next: [Int] = []
    for parent in leaves {
     let prefix = records[parent].sample, field = prefix.field
     let rootDomain = try ExactRealRootDomain(field:field,using:&a), p=rootDomain.polynomials
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
      if let degree = try p.degree(of:law,in:0,using:&a), degree > 0 {
       try ExactCellAccess.storage(1,Int.self,&a); active.append(index)
       product = try p.multiplying(product,law,using:&a)
      }
     }
     let union = try rootDomain.bind(product,using:&a)
     let all = try rootDomain.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
     let rootSet = try rootDomain.isolate(union,in:all,limits:.init(maximumRoots:limits.maximumRootsPerStack),using:&a)
     try ExactCellAccess.storage(rootSet.roots.count,ExactRealRoot<Field>.self,&a)
     var roots = rootSet.roots
     if roots.count > 1 { for index in 1..<roots.count {
      while true {
       guard case .finite(let hi) = roots[index-1].isolation.upper, case .finite(let lo) = roots[index].isolation.lower else { throw ExactRealCellFailure.invalidCoverage }
       if try field.compare(hi,lo,using:&a) == .less { break }
       try ExactCellAccess.storage(2,Int.self,&a)
       for slot in [index-1,index] {
        guard case .finite(let l) = roots[slot].isolation.lower, case .finite(let h) = roots[slot].isolation.upper else { throw ExactRealCellFailure.invalidCoverage }
        let width = try field.dividing(field.subtracting(h,l,using:&a),field.integer(2,using:&a),using:&a)
        if try field.sign(of:width,using:&a) == .positive { roots[slot] = try rootDomain.refine(roots[slot],maximumWidth:width,using:&a) }
       }
      }
     } }
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
        let extensionValue = try field.adjoin(root,using:&a); childField=extensionValue.domain; value=extensionValue.generator
       }
      } else {
       let one = try field.integer(1,using:&a)
       if roots.isEmpty { value = try field.integer(0,using:&a) }
       else if ordinal == 0 {
        guard case .finite(let lo) = roots[0].isolation.lower else { throw ExactRealCellFailure.invalidCoverage }
        value = try field.subtracting(lo,one,using:&a)
       } else if ordinal == roots.count {
        guard case .finite(let hi) = roots[ordinal-1].isolation.upper else { throw ExactRealCellFailure.invalidCoverage }
        value = try field.adding(hi,one,using:&a)
       } else {
        guard case .finite(let hi) = roots[ordinal-1].isolation.upper, case .finite(let lo) = roots[ordinal].isolation.lower else { throw ExactRealCellFailure.invalidCoverage }
        value = try field.dividing(field.adding(hi,lo,using:&a),field.integer(2,using:&a),using:&a)
       }
      }
      if try !inside(value,field:childField,domain:source.domains[level.axis],&a) { continue }
      guard records.count < limits.maximumStoredCells else { throw ExactRealCellFailure.cellLimit }
      try ExactCellAccess.storage(ExactCellAccess.add(prefix.coordinates.count,1),Field.Value.self,&a)
      var coordinates: [Field.Value] = []; coordinates.reserveCapacity(prefix.coordinates.count+1)
      for earlier in prefix.coordinates { coordinates.append(try childField.importing(earlier,using:&a)) }; coordinates.append(value)
      let sample = ExactRealCellSample(field:childField,coordinates:coordinates,depth:a.depth)
      var truth: [ExactSign] = []
      if level.axis+1 == source.variableCount {
       try ExactCellAccess.storage(source.polynomials.count,ExactSign.self,&a)
       for law in source.polynomials { truth.append(try childField.sign(of:evaluate(law,at:sample,&a),using:&a)) }
      }
      try ExactCellAccess.storage(1,ExactRealCellRecord<Base>.self,&a); try ExactCellAccess.storage(1,Int.self,&a)
      children[branch]=records.count; next.append(records.count)
      records.append(.init(sample:sample,parent:parent,branch:branch,dimension:try ExactCellAccess.add(records[parent].dimension,section ? 0:1),signs:truth,stack:-1))
     }
     try ExactCellAccess.storage(1,ExactRealCellStack<Base>.self,&a)
     records[parent].stack=stacks.count
     stacks.append(.init(axis:level.axis,parent:parent,rootSet:rootSet,specialized:specialized,coefficientSigns:signs,activeLawIndices:active,children:children))
    }; leaves=next
   }
   if source.variableCount == 0 {
    try ExactCellAccess.storage(source.polynomials.count,ExactSign.self,&a)
    var truth: [ExactSign] = []
    for law in source.polynomials { truth.append(try context.field.sign(of:evaluate(law,at:origin,&a),using:&a)) }
    records[0] = .init(sample:origin,parent:-1,branch:0,dimension:0,signs:truth,stack:-1)
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
