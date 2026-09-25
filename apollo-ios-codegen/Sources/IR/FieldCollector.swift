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
    let value = (field.type, deprecationReason: field.deprecationReason)
    if let existingValue = referencedFields[key], !Self.isOrdered(value, before: existingValue) {
      return
    }
    referencedFields[key] = value
  }

  private static func isOrdered(
    _ lhs: (GraphQLType, deprecationReason: String?),
    before rhs: (GraphQLType, deprecationReason: String?)
  ) -> Bool {
    let lhsTypeReference = lhs.0.typeReference.utf8
    let rhsTypeReference = rhs.0.typeReference.utf8
    guard lhsTypeReference.elementsEqual(rhsTypeReference) else {
      // Ranking `!` after every other character keeps the variant that is nullable at the
      // innermost wrapper where two otherwise identical types differ.
      return lhsTypeReference.lexicographicallyPrecedes(rhsTypeReference) {
        nullableFirstRank($0) < nullableFirstRank($1)
      }
    }

    switch (lhs.deprecationReason, rhs.deprecationReason) {
    case let (lhsReason?, rhsReason?):
      return lhsReason.utf8.lexicographicallyPrecedes(rhsReason.utf8)

    case (nil, .some):
      return true

    default:
      return false
    }
  }

  private static func nullableFirstRank(_ byte: UInt8) -> UInt16 {
    byte == UInt8(ascii: "!") ? 0x100 : UInt16(byte)
  }

  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [(String, GraphQLType, deprecationReason: String?)] {
    var fields = collectedFields[type] ?? [:]

    for interface in type.interfaces {
      if let interfaceFields = collectedFields[interface] {
        fields.merge(interfaceFields) { field, interfaceField in
          Self.isOrdered(interfaceField, before: field) ? interfaceField : field
        }
      }
    }

    return fields.sorted { $0.0 < $1.0 }.map { ($0.key, $0.value.0, $0.value.deprecationReason )}
  }
}
