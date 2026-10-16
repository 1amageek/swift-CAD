import HashTreeCollections
import CADCore
import CADGeometry

/// Admission for requested typed storage owned by original parameter queries.
package enum OriginalParameterQueryStorage {
  package static func reserve<Element, A: ExactScalarAdmission & ~Copyable>(
    _ capacity: Int, in values: inout [Element],
    using execution: inout A
  ) throws {
    guard capacity >= 0 else {
      throw failure()
    }
    guard capacity > values.capacity else { return }
    let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
    guard !bytes.overflow else { throw failure() }
    try execution.retainStorage(bytes: bytes.partialValue)
    values.reserveCapacity(capacity)
  }

  package static func append<Element, A: ExactScalarAdmission & ~Copyable>(
    _ element: Element, to values: inout [Element],
    using execution: inout A
  ) throws {
    if values.count == values.capacity {
      let doubled = values.capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else { throw failure() }
      try reserve(max(1, doubled.partialValue), in: &values, using: &execution)
    }
    values.append(element)
  }

  package static func map<Values: Sequence, Output, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A,
    transform: (Values.Element, inout A) throws -> Output
  ) throws -> [Output] {
    var result: [Output] = []
    try reserve(values.underestimatedCount, in: &result, using: &execution)
    for value in values {
      try CurrentTaskCancellationChecker().checkCancellation()
      try execution.consumeWork(1)
      let mapped = try transform(value, &execution)
      try append(mapped, to: &result, using: &execution)
    }
    return result
  }

  /// Sorts admitted storage with a fixed pure comparator using the same core.
  package static func sort<Element, A: ExactScalarAdmission & ~Copyable>(
    _ values: inout [Element],
    using execution: inout A, less: (Element, Element) -> Bool
  ) throws {
    try sort(&values, using: &execution, comparing: { left, right, execution in less(left, right) })
  }

  /// Sorts admitted uniquely owned storage without an auxiliary merge buffer.
  package static func sort<Element, A: ExactScalarAdmission & ~Copyable>(
    _ values: inout [Element],
    using execution: inout A,
    comparing: (Element, Element, inout A) throws -> Bool
  ) throws {
    func sift(_ root: Int, _ count: Int, _ storage: inout [Element]) throws {
      var parent = root
      while parent < count / 2 {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
        var child = parent * 2 + 1
        if child + 1 < count, try comparing(storage[child], storage[child + 1], &execution) {
          child += 1
        }
        if try !comparing(storage[parent], storage[child], &execution) { return }
        storage.swapAt(parent, child)
        parent = child
      }
    }
    guard values.count > 1 else { return }
    for root in stride(from: values.count / 2 - 1, through: 0, by: -1) {
      try sift(root, values.count, &values)
    }
    for end in stride(from: values.count - 1, through: 1, by: -1) {
      try execution.consumeWork(1)
      values.swapAt(0, end)
      try sift(0, end, &values)
    }
  }

  package static func append<Element, A: ExactScalarAdmission & ~Copyable>(
    contentsOf elements: [Element],
    to values: inout [Element], using execution: inout A
  ) throws {
    let count = values.count.addingReportingOverflow(elements.count)
    guard !count.overflow else { throw failure() }
    try reserve(count.partialValue, in: &values, using: &execution)
    for element in elements {
      try execution.consumeWork(1)
      values.append(element)
    }
  }

  @discardableResult
  package static func insert<Element: Hashable, A: ExactScalarAdmission & ~Copyable>(
    _ element: Element,
    in values: inout Set<Element>, using execution: inout A
  ) throws -> Bool {
    try execution.consumeWork(1)
    guard !values.contains(element) else { return false }
    if values.count == values.capacity {
      let doubled = values.capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else { throw failure() }
      let capacity = max(1, doubled.partialValue)
      let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
      guard !bytes.overflow else { throw failure() }
      try execution.retainStorage(bytes: bytes.partialValue)
      values.reserveCapacity(capacity)
    }
    values.insert(element)
    return true
  }

  package static func set<Key: Hashable, Value, A: ExactScalarAdmission & ~Copyable>(
    _ value: Value,
    for key: Key, in values: inout [Key: Value], using execution: inout A
  ) throws {
    try execution.consumeWork(1)
    if values[key] == nil, values.count == values.capacity {
      let doubled = values.capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else { throw failure() }
      let capacity = max(1, doubled.partialValue)
      let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
      guard !bytes.overflow else { throw failure() }
      try execution.retainStorage(bytes: bytes.partialValue)
      values.reserveCapacity(capacity)
    }
    values[key] = value
  }

  package static func set<Key: Hashable, Value, A: ExactScalarAdmission & ~Copyable>(
    _ value: Value, for key: Key, in values: inout PersistentMap<Key, Value>,
    using execution: inout A
  ) throws {
    try execution.consumeWork(1)
    try execution.retainStorage(bytes: MemoryLayout<(Key, Value)>.stride)
    values[key] = value
  }

  package static func repeated<Element, A: ExactScalarAdmission & ~Copyable>(
    _ value: Element,
    count: Int, using execution: inout A
  ) throws -> [Element] {
    guard count >= 0 else { throw failure() }
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
    guard !bytes.overflow else { throw failure() }
    try execution.retainStorage(bytes: bytes.partialValue)
    try execution.consumeWork(count)
    return Array(repeating: value, count: count)
  }

  package static func contains<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, predicate: (Values.Element, inout A) throws -> Bool
  ) throws -> Bool {
    for value in values {
      try execution.consumeWork(1)
      if try predicate(value, &execution) { return true }
    }
    return false
  }

  package static func compactMap<Values: Sequence, Output, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, transform: (Values.Element, inout A) throws -> Output?
  ) throws -> [Output] {
    var result: [Output] = []
    for value in values {
      try execution.consumeWork(1)
      if let transformed = try transform(value, &execution) {
        try append(transformed, to: &result, using: &execution)
      }
    }
    return result
  }

  package static func filter<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, predicate: (Values.Element, inout A) throws -> Bool
  ) throws -> [Values.Element] {
    var result: [Values.Element] = []
    for value in values {
      try execution.consumeWork(1)
      if try predicate(value, &execution) { try append(value, to: &result, using: &execution) }
    }
    return result
  }

  package static func reduce<Values: Sequence, Result, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    initial: Result, using execution: inout A,
    combine: (Result, Values.Element, inout A) throws -> Result
  ) throws -> Result {
    var result = initial
    for value in values {
      try execution.consumeWork(1)
      result = try combine(result, value, &execution)
    }
    return result
  }

  package static func ordered<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, less: (Values.Element, Values.Element) -> Bool
  ) throws -> [Values.Element] {
    var result = try map(values, using: &execution) { value, execution in value }
    try sort(&result, using: &execution, less: less)
    return result
  }

  package static func allSatisfy<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, predicate: (Values.Element, inout A) throws -> Bool
  ) throws -> Bool {
    for value in values {
      try execution.consumeWork(1)
      if try !predicate(value, &execution) { return false }
    }
    return true
  }

  package static func firstIndex<Element, A: ExactScalarAdmission & ~Copyable>(
    _ values: [Element],
    using execution: inout A, predicate: (Element, inout A) throws -> Bool
  ) throws -> Int? {
    for index in values.indices {
      try execution.consumeWork(1)
      if try predicate(values[index], &execution) { return index }
    }
    return nil
  }

  package static func first<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ values: Values,
    using execution: inout A, predicate: (Values.Element, inout A) throws -> Bool
  ) throws -> Values.Element? {
    for value in values {
      try execution.consumeWork(1)
      if try predicate(value, &execution) { return value }
    }
    return nil
  }

  package static func extrema<
    Values: Sequence, Value: Comparable, A: ExactScalarAdmission & ~Copyable
  >(
    _ values: Values, using execution: inout A,
    projection: (Values.Element, inout A) throws -> Value
  ) throws -> (lower: Value, upper: Value)? {
    var result: (lower: Value, upper: Value)?
    for value in values {
      try execution.consumeWork(1)
      let projected = try projection(value, &execution)
      if let current = result {
        result = (min(current.lower, projected), max(current.upper, projected))
      } else {
        result = (projected, projected)
      }
    }
    return result
  }

  package static func values<Element, A: ExactScalarAdmission & ~Copyable>(
    count: Int, using execution: inout A,
    _ initialize: (inout A) throws -> [Element]
  ) throws -> [Element] {
    guard count >= 0 else { throw failure() }
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
    guard !bytes.overflow else { throw failure() }
    try execution.retainStorage(bytes: bytes.partialValue)
    return try initialize(&execution)
  }

  package static func materialize<Elements: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ elements: Elements, using execution: inout A
  ) throws -> [Elements.Element] {
    var result: [Elements.Element] = []
    try reserve(elements.underestimatedCount, in: &result, using: &execution)
    for element in elements {
      try execution.consumeWork(1)
      try append(element, to: &result, using: &execution)
    }
    return result
  }

  package static func optionalMap<Element, Result, A: ExactScalarAdmission & ~Copyable>(
    _ element: Element?, using execution: inout A,
    _ transform: (Element, inout A) throws -> Result
  ) throws -> Result? {
    try execution.consumeWork(1)
    guard let element else { return nil }
    return try transform(element, &execution)
  }

  package static func flatMap<
    Elements: Sequence, Result: Sequence, A: ExactScalarAdmission & ~Copyable
  >(
    _ elements: Elements, using execution: inout A,
    _ transform: (Elements.Element, inout A) throws -> Result
  ) throws -> [Result.Element] {
    var result: [Result.Element] = []
    for element in elements {
      try execution.consumeWork(1)
      for value in try transform(element, &execution) {
        try execution.consumeWork(1)
        try append(value, to: &result, using: &execution)
      }
    }
    return result
  }

  package static func set<Elements: Sequence, A: ExactScalarAdmission & ~Copyable>(
    _ elements: Elements, using execution: inout A
  ) throws -> Set<Elements.Element>
  where Elements.Element: Hashable {
    var result: Set<Elements.Element> = []
    for element in elements { try insert(element, in: &result, using: &execution) }
    return result
  }

  package static func concatenated<Element, A: ExactScalarAdmission & ~Copyable>(
    _ first: [Element], _ second: [Element], using execution: inout A
  ) throws -> [Element] {
    let count = first.count.addingReportingOverflow(second.count)
    guard !count.overflow else { throw failure() }
    var result: [Element] = []
    try reserve(count.partialValue, in: &result, using: &execution)
    try append(contentsOf: first, to: &result, using: &execution)
    try append(contentsOf: second, to: &result, using: &execution)
    return result
  }

  private static func failure() -> KernelError {
    KernelError(
      phase: .classification, code: .resourceLimitExceeded, tolerance: nil,
      message: "Original parameter query typed byte request overflowed.")
  }
}
