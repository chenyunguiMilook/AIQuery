import Testing
@testable import AIQCore

@Test
func kindClassifierType() {
    let r = AIQKind.classify(kindIdentifier: "swift.struct")
    #expect(r.kind == "type")
    #expect(r.typeKind == "struct")
}

@Test
func kindClassifierMethod() {
    let r = AIQKind.classify(kindIdentifier: "swift.method")
    #expect(r.kind == "method")
    #expect(r.typeKind == "func")
}

@Test
func relativize() {
    let base = "/tmp/MyPkg"
    let file = "/tmp/MyPkg/Sources/Foo/Bar.swift"
    #expect(AIQPaths.relativize(path: file, to: base) == "Sources/Foo/Bar.swift")
}
