import SwiftSyntax

public struct RedundantVoidReturnRule: ConfigurationProviderRule, SwiftSyntaxCorrectableRule {
    public var configuration = SeverityConfiguration(.warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "redundant_void_return",
        name: "Redundant Void Return",
        description: "Returning Void in a function declaration is redundant.",
        kind: .idiomatic,
        nonTriggeringExamples: [
            Example("func foo() {}\n"),
            Example("func foo() -> Int {}\n"),
            Example("func foo() -> Int -> Void {}\n"),
            Example("func foo() -> VoidResponse\n"),
            Example("let foo: (Int) -> Void\n"),
            Example("func foo() -> Int -> () {}\n"),
            Example("let foo: (Int) -> ()\n"),
            Example("func foo() -> ()?\n"),
            Example("func foo() -> ()!\n"),
            Example("func foo() -> Void?\n"),
            Example("func foo() -> Void!\n"),
            Example("""
            struct A {
                subscript(key: String) {
                    print(key)
                }
            }
            """)
        ],
        triggeringExamples: [
            Example("func foo() ↓-> Void {}\n"),
            Example("""
            protocol Foo {
              func foo() ↓-> Void
            }
            """),
            Example("func foo() ↓-> () {}\n"),
            Example("func foo() ↓-> ( ) {}"),
            Example("""
            protocol Foo {
              func foo() ↓-> ()
            }
            """),
            Example("""
            doSomething { arg ↓-> () in
                print(arg)
            }
            """),
            Example("""
            doSomething { arg ↓-> Void in
                print(arg)
            }
            """)
        ],
        corrections: [
            Example("func foo() ↓-> Void {}\n"): Example("func foo() {}\n"),
            Example("protocol Foo {\n func foo() ↓-> Void\n}\n"): Example("protocol Foo {\n func foo()\n}\n"),
            Example("func foo() ↓-> () {}\n"): Example("func foo() {}\n"),
            Example("protocol Foo {\n func foo() ↓-> ()\n}\n"): Example("protocol Foo {\n func foo()\n}\n"),
            Example("protocol Foo {\n    #if true\n    func foo() ↓-> Void\n    #endif\n}\n"):
                Example("protocol Foo {\n    #if true\n    func foo()\n    #endif\n}\n")
        ]
    )

    public func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor? {
        Visitor()
    }

    public func makeRewriter(file: SwiftLintFile) -> ViolationsSyntaxRewriter? {
        file.locationConverter.map { locationConverter in
            Rewriter(
                locationConverter: locationConverter,
                disabledRegions: disabledRegions(file: file)
            )
        }
    }

}

private extension RedundantVoidReturnRule {
    final class Visitor: SyntaxVisitor, ViolationsSyntaxVisitor {
        private(set) var violationPositions: [AbsolutePosition] = []

        override func visitPost(_ node: ReturnClauseSyntax) {
            if node.containsRedundantVoidViolation {
                violationPositions.append(node.arrow.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    final class Rewriter: SyntaxRewriter, ViolationsSyntaxRewriter {
        private(set) var correctionPositions: [AbsolutePosition] = []
        let locationConverter: SourceLocationConverter
        let disabledRegions: [SourceRange]

        init(locationConverter: SourceLocationConverter, disabledRegions: [SourceRange]) {
            self.locationConverter = locationConverter
            self.disabledRegions = disabledRegions
        }

        override func visit(_ node: FunctionSignatureSyntax) -> Syntax {
            guard let output = node.output,
                  output.containsRedundantVoidViolation else {
                return super.visit(node)
            }

            let isInDisabledRegion = disabledRegions.contains { region in
                region.contains(node.positionAfterSkippingLeadingTrivia, locationConverter: locationConverter)
            }

            guard !isInDisabledRegion else {
                return super.visit(node)
            }

            correctionPositions.append(output.arrow.positionAfterSkippingLeadingTrivia)
            return super.visit(node.withOutput(nil))
        }
    }
}

private extension ReturnClauseSyntax {
    var containsRedundantVoidViolation: Bool {
        if let simpleReturnType = returnType.as(SimpleTypeIdentifierSyntax.self) {
           return simpleReturnType.typeName == "Void"
        }

        if let tupleReturnType = returnType.as(TupleTypeSyntax.self) {
            return tupleReturnType.elements.isEmpty
        }

        return false
    }
}
