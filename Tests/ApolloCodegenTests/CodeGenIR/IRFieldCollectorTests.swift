import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
import IR
@testable import ApolloCodegenLib

class IRFieldCollectorTests: XCTestCase {

  typealias ReferencedFields = [(String, GraphQLType, deprecationReason: String?)]

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var subject: IR.FieldCollector!
  var compilationResult: CompilationResult!

  var schema: IR.Schema { ir.schema }

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    subject = nil
    compilationResult = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildIR(
    operationOrder operationNames: [String]? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    if compilationResult == nil {
      compilationResult = try await GraphQLJSFrontend().compile(schema: schemaSDL, document: document)
    }
    ir = .mock(compilationResult: compilationResult)

    let operations = try operationNames?.map { operationName in
      try compilationResult.operations
        .first { $0.name == operationName }
        .xctUnwrapped(file: file, line: line)
    } ?? compilationResult.operations

    for operation in operations {
      _ = await ir.build(operation: operation)
    }

    subject = ir.fieldCollector
  }

  // MARK: - Tests

  func test__collectedFields__givenObject_collectsReferencedFieldsOnly() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        a
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenInterface_collectsReferencedFieldsOnly() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    interface Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        a
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[interface: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsInNonAlphabeticalOrder_retrurnsReferencedFieldsSortedAlphabetically() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
    }
    """

    document = """
    query Test {
      dog {
        b
        a
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenObjectImplementingInterface_collectsFieldsReferencedOnInterface() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal{
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      animal {
        a
        ... on Dog {
          b
        }
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromFragment_collectsFieldsReferencedInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        ...FragmentB
        a
      }
    }

    fragment FragmentB on Dog {
      b
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromFragmentOnInterface_collectsFieldsReferencedInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      animal {
        a
        ... on Dog {
          ...FragmentB
        }
      }
    }

    fragment FragmentB on Dog {
      b
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromQueryOnImplementedInterface_collectsFieldsReferencedInQueryOnInterface() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
      dog: Dog!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test1 {
      animal {
        a
      }
    }

    query Test2 {
      dog {
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenAliasedField_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test1 {
      dog {
        aliasedA: a
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("aliasedA", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldWithArguments_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a(arg1: String): String
    }
    """

    document = """
    query Test1 {
      dog {
        a(arg1: "test")
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenAliasedFieldsWithArguments_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a(arg1: String): String
    }
    """

    document = """
    query Test1 {
      dog {
        field1: a(arg1: "one")
        field2: a(arg1: "two")
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog)

    let expected: ReferencedFields = [
      ("field1", .string(), nil),
      ("field2", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsOnNestedInlineFragmentWithRedundantType_referenceFieldOnNestedTypeNotMatchingTargetType_doesNotCollectsField() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    interface Pet {
      b: String
    }

    type PetRock implements Pet {
      b: String
    }

    type Dog implements Animal & Pet {
      a: String
      b: String
    }
    """

    document = """
    query Test1 {
      animal {
        ... on Pet {
          ... on Animal {
            a
          }
          b
        }
      }
    }
    """

    // when
    try await buildIR()

    let PetRock = try schema[object: "PetRock"].xctUnwrapped()
    let petRockActual = await subject.collectedFields(for: PetRock)

    let petRockExpected: ReferencedFields = [
      ("b", .string(), nil),
    ]

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let dogActual = await subject.collectedFields(for: Dog)

    let dogExpected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil),
    ]

    expect(petRockActual).to(equal(petRockExpected))
    expect(dogActual).to(equal(dogExpected))
  }

  func test__collectedFields__givenFieldsOnNestedNamedFragmentWithRedundantType_referenceFieldOnNestedTypeNotMatchingTargetType_doesNotCollectsField() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    interface Pet {
      b: String
    }

    type PetRock implements Pet {
      b: String
    }

    type Dog implements Animal & Pet {
      a: String
      b: String
    }
    """

    document = """
    query Test1 {
      animal {
        ... on Pet {
          ...FragA
          b
        }
      }
    }

    fragment FragA on Animal {
      a
    }
    """

    // when
    try await buildIR()

    let PetRock = try schema[object: "PetRock"].xctUnwrapped()
    let petRockActual = await subject.collectedFields(for: PetRock)

    let petRockExpected: ReferencedFields = [
      ("b", .string(), nil),
    ]

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let dogActual = await subject.collectedFields(for: Dog)

    let dogExpected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil),
    ]

    expect(petRockActual).to(equal(petRockExpected))
    expect(dogActual).to(equal(dogExpected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDifferentTypes_collectsSameTypeRegardlessOfBuildOrder() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String!
      subtitle: String
      cover: Image
      thumbnail: Thumbnail
      gallery: [Image]
      strictGallery: [Image!]!
    }

    type Image {
      url: String
    }

    type Thumbnail {
      url: String
    }
    """

    document = """
    query BookQuery {
      book {
        title
        cover {
          url
        }
        gallery {
          url
        }
      }
    }

    query AliasedBookQuery {
      book {
        title: subtitle
        cover: thumbnail {
          url
        }
        gallery: strictGallery {
          url
        }
      }
    }
    """

    // when
    try await buildIR(operationOrder: ["BookQuery", "AliasedBookQuery"])
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book)

    try await buildIR(operationOrder: ["AliasedBookQuery", "BookQuery"])
    let reverseOrderActual = await subject.collectedFields(for: Book)

    // then
    let Image = try schema[object: "Image"].xctUnwrapped()

    let expected: ReferencedFields = [
      ("cover", .entity(Image), nil),
      ("gallery", .list(.entity(Image)), nil),
      ("title", .string(), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDifferentDeprecationReasons_collectsSameDeprecationReasonRegardlessOfBuildOrder() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String @deprecated(reason: "Use name.")
      name: String
      label: String @deprecated(reason: "Use caption.")
      caption: String @deprecated(reason: "Use heading.")
      status: String @deprecated(reason: "Use state.")
      state: String!
    }
    """

    document = """
    query BookQuery {
      book {
        title
        label
        status
      }
    }

    query AliasedBookQuery {
      book {
        title: name
        label: caption
        status: state
      }
    }
    """

    // when
    try await buildIR(operationOrder: ["BookQuery", "AliasedBookQuery"])
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book)

    try await buildIR(operationOrder: ["AliasedBookQuery", "BookQuery"])
    let reverseOrderActual = await subject.collectedFields(for: Book)

    // then
    let expected: ReferencedFields = [
      ("label", .string(), "Use caption."),
      ("status", .string(), "Use state."),
      ("title", .string(), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithCanonicallyEquivalentDeprecationReasons_collectsSameReasonRegardlessOfBuildOrder() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String @deprecated(reason: "Caf\\u00E9")
      name: String @deprecated(reason: "Cafe\\u0301")
    }
    """

    document = """
    query BookQuery {
      book {
        title
      }
    }

    query AliasedBookQuery {
      book {
        title: name
      }
    }
    """

    // when
    try await buildIR(operationOrder: ["BookQuery", "AliasedBookQuery"])
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book)

    try await buildIR(operationOrder: ["AliasedBookQuery", "BookQuery"])
    let reverseOrderActual = await subject.collectedFields(for: Book)

    // then
    let expected = [Array("Cafe\u{301}".utf8)]

    expect(documentOrderActual.map { $0.deprecationReason.map { Array($0.utf8) } }).to(Nimble.equal(expected))
    expect(reverseOrderActual.map { $0.deprecationReason.map { Array($0.utf8) } }).to(Nimble.equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedOnObjectAndInterfacesWithDifferentTypes_collectsSameTypeRegardlessOfWhereSelected() async throws {
    // given
    schemaSDL = """
    type Query {
      magazine: Magazine!
      titled: Titled!
      named: Named!
    }

    interface Titled {
      title: String!
      shortTitle: String
    }

    interface Named {
      title: String!
      shortTitle: String
    }

    type Book implements Titled & Named {
      title: String!
      shortTitle: String
    }

    type Magazine implements Named & Titled {
      title: String!
      shortTitle: String
    }
    """

    document = """
    query MagazineQuery {
      magazine {
        title
      }
    }

    query TitledQuery {
      titled {
        title
      }
    }

    query NamedQuery {
      named {
        title: shortTitle
      }
    }
    """

    // when
    try await buildIR(operationOrder: ["MagazineQuery", "TitledQuery", "NamedQuery"])
    let Book = try schema[object: "Book"].xctUnwrapped()
    let Magazine = try schema[object: "Magazine"].xctUnwrapped()
    let documentOrderBookActual = await subject.collectedFields(for: Book)
    let documentOrderMagazineActual = await subject.collectedFields(for: Magazine)

    try await buildIR(operationOrder: ["NamedQuery", "TitledQuery", "MagazineQuery"])
    let reverseOrderBookActual = await subject.collectedFields(for: Book)
    let reverseOrderMagazineActual = await subject.collectedFields(for: Magazine)

    // then
    let expected: ReferencedFields = [
      ("title", .string(), nil)
    ]

    expect(documentOrderBookActual).to(equal(expected))
    expect(documentOrderMagazineActual).to(equal(expected))
    expect(reverseOrderBookActual).to(equal(expected))
    expect(reverseOrderMagazineActual).to(equal(expected))
  }

  /// MARK: - Custom Matchers
  func equal(
    _ expected: ReferencedFields
  ) -> Nimble.Matcher<ReferencedFields> {
    return Matcher.define { actual in
      let message: ExpectationMessage = .expectedActualValueTo("have fields equal to \(expected)")

      guard let actual = try actual.evaluate(),
            expected.count == actual.count else {
        return MatcherResult(status: .fail, message: message.appended(details: "Fields Did Not Match!"))
      }

      for (index, field) in zip(expected, actual).enumerated() {
        guard field.0.0 == field.1.0, field.0.1 == field.1.1, field.0.2 == field.1.2 else {
          return MatcherResult(
            status: .fail,
            message: message.appended(
              details: "Expected fields[\(index)] to equal \(field.0), got \(field.1)."
            )
          )
        }
      }

      return MatcherResult(status: .matches, message: message)
    }
  }
}

