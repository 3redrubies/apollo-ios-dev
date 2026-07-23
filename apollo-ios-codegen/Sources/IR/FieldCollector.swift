import GraphQLCompiler

public actor FieldCollector {

  typealias CollectedField = (String, GraphQLType, deprecationReason: String?)

  private var collectedFields: [
    GraphQLCompositeType: [String: (GraphQLType, deprecationReason: String?)]
  ] = [:]

  func collectFields(from selectionSet: CompilationResult.SelectionSet) {
    guard let type = selectionSet.parentType as? (any GraphQLInterfaceImplementingType) else { return }
    for case let .field(field) in selectionSet.selections {
      add(field: field, to: type)
    }
  }

  func add<T: Sequence>(
    fields: T,
    to type: any GraphQLInterfaceImplementingType
  ) where T.Element == CompilationResult.Field {
    for field in fields {
      add(field: field, to: type)
    }
  }

  func add(
    field: CompilationResult.Field,
    to type: any GraphQLInterfaceImplementingType
  ) {
    var fields = collectedFields[type] ?? [:]
    add(field, to: &fields)
    collectedFields.updateValue(fields, forKey: type)
  }

  private func add(
    _ field: CompilationResult.Field,
    to referencedFields: inout [String: (GraphQLType, deprecationReason: String?)]
  ) {
    let key = field.responseKey
    guard let existing = referencedFields[key] else {
      referencedFields[key] = (field.type, field.deprecationReason)
      return
    }
    // Two selections legitimately share a response key with differing underlying types (e.g. an
    // alias resolving to a different schema field). The IR is built concurrently
    // (ApolloCodegen.swift task group -> shared FieldCollector actor), so the first arrival for a
    // given key is nondeterministic. Choose the lexicographically-smallest type reference
    // (tie-broken on deprecationReason) so the stored value is a stable function of the candidate
    // set, independent of arrival order. Direction (min) is arbitrary but fixed; it preserves the
    // previously-emitted output for existing consumers.
    let incoming = (field.type, deprecationReason: field.deprecationReason)
    if Self.isOrderedBefore(incoming, existing) {
      referencedFields[key] = incoming
    }
  }

  private static func isOrderedBefore(
    _ lhs: (GraphQLType, deprecationReason: String?),
    _ rhs: (GraphQLType, deprecationReason: String?)
  ) -> Bool {
    let lRef = lhs.0.typeReference, rRef = rhs.0.typeReference
    if lRef != rRef { return lRef < rRef }
    switch (lhs.deprecationReason, rhs.deprecationReason) {  // same type: nil sorts before non-nil
    case (nil, nil): return false
    case (nil, _):   return true
    case (_, nil):   return false
    case let (l?, r?): return l < r
    }
  }

  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [(String, GraphQLType, deprecationReason: String?)] {
    var fields = collectedFields[type] ?? [:]

    for interface in type.interfaces {
      if let interfaceFields = collectedFields[interface] {
        fields.merge(interfaceFields) { field, _ in field }
      }
    }

    return fields.sorted { $0.0 < $1.0 }.map { ($0.key, $0.value.0, $0.value.deprecationReason )}
  }
}
