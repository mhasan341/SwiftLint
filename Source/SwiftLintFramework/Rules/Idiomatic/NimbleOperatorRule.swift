import SwiftSyntax

public struct NimbleOperatorRule: ConfigurationProviderRule, SwiftSyntaxCorrectableRule, OptInRule {
    public var configuration = SeverityConfiguration(.warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "nimble_operator",
        name: "Nimble Operator",
        description: "Prefer Nimble operator overloads over free matcher functions.",
        kind: .idiomatic,
        nonTriggeringExamples: [
            Example("expect(seagull.squawk) != \"Hi!\"\n"),
            Example("expect(\"Hi!\") == \"Hi!\"\n"),
            Example("expect(10) > 2\n"),
            Example("expect(10) >= 10\n"),
            Example("expect(10) < 11\n"),
            Example("expect(10) <= 10\n"),
            Example("expect(x) === x"),
            Example("expect(10) == 10"),
            Example("expect(success) == true"),
            Example("expect(value) == nil"),
            Example("expect(value) != nil"),
            Example("expect(object.asyncFunction()).toEventually(equal(1))\n"),
            Example("expect(actual).to(haveCount(expected))\n"),
            Example("""
            foo.method {
                expect(value).to(equal(expectedValue), description: "Failed")
                return Bar(value: ())
            }
            """)
        ],
        triggeringExamples: [
            Example("↓expect(seagull.squawk).toNot(equal(\"Hi\"))\n"),
            Example("↓expect(12).toNot(equal(10))\n"),
            Example("↓expect(10).to(equal(10))\n"),
            Example("↓expect(10, line: 1).to(equal(10))\n"),
            Example("↓expect(10).to(beGreaterThan(8))\n"),
            Example("↓expect(10).to(beGreaterThanOrEqualTo(10))\n"),
            Example("↓expect(10).to(beLessThan(11))\n"),
            Example("↓expect(10).to(beLessThanOrEqualTo(10))\n"),
            Example("↓expect(x).to(beIdenticalTo(x))\n"),
            Example("↓expect(success).to(beTrue())\n"),
            Example("↓expect(success).to(beFalse())\n"),
            Example("↓expect(value).to(beNil())\n"),
            Example("↓expect(value).toNot(beNil())\n"),
            Example("expect(10) > 2\n ↓expect(10).to(beGreaterThan(2))\n")
        ],
        corrections: [
            Example("↓expect(seagull.squawk).toNot(equal(\"Hi\"))\n"): Example("expect(seagull.squawk) != \"Hi\"\n"),
            Example("↓expect(\"Hi!\").to(equal(\"Hi!\"))\n"): Example("expect(\"Hi!\") == \"Hi!\"\n"),
            Example("↓expect(12).toNot(equal(10))\n"): Example("expect(12) != 10\n"),
            Example("↓expect(value1).to(equal(value2))\n"): Example("expect(value1) == value2\n"),
            Example("↓expect(   value1  ).to(equal(  value2.foo))\n"): Example("expect(   value1  ) == value2.foo\n"),
            Example("↓expect(value1).to(equal(10))\n"): Example("expect(value1) == 10\n"),
            Example("↓expect(10).to(beGreaterThan(8))\n"): Example("expect(10) > 8\n"),
            Example("↓expect(10).to(beGreaterThanOrEqualTo(10))\n"): Example("expect(10) >= 10\n"),
            Example("↓expect(10).to(beLessThan(11))\n"): Example("expect(10) < 11\n"),
            Example("↓expect(10).to(beLessThanOrEqualTo(10))\n"): Example("expect(10) <= 10\n"),
            Example("↓expect(x).to(beIdenticalTo(x))\n"): Example("expect(x) === x\n"),
            Example("↓expect(success).to(beTrue())\n"): Example("expect(success) == true\n"),
            Example("↓expect(success).to(beFalse())\n"): Example("expect(success) == false\n"),
            Example("↓expect(success).toNot(beFalse())\n"): Example("expect(success) != false\n"),
            Example("↓expect(success).toNot(beTrue())\n"): Example("expect(success) != true\n"),
            Example("↓expect(value).to(beNil())\n"): Example("expect(value) == nil\n"),
            Example("↓expect(value).toNot(beNil())\n"): Example("expect(value) != nil\n"),
            Example("expect(10) > 2\n ↓expect(10).to(beGreaterThan(2))\n"): Example("expect(10) > 2\n expect(10) > 2\n")
        ]
    )

    public func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor {
        Visitor(viewMode: .sourceAccurate)
    }

    public func makeRewriter(file: SwiftLintFile) -> ViolationsSyntaxRewriter? {
        Rewriter(
            locationConverter: file.locationConverter,
            disabledRegions: disabledRegions(file: file)
        )
    }
}

private extension NimbleOperatorRule {
    final class Visitor: ViolationsSyntaxVisitor {
        override func visitPost(_ node: FunctionCallExprSyntax) {
            guard predicateDescription(for: node) != nil else {
                return
            }

            violations.append(node.positionAfterSkippingLeadingTrivia)
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

        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            guard let expectation = node.expectation(),
                  let predicate = predicatesMapping[expectation.operatorExpr.identifier.text],
                  let operatorExpr = expectation.operatorExpr(for: predicate),
                  let expectedValueExpr = expectation.expectedValueExpr(for: predicate),
                  !node.isContainedIn(regions: disabledRegions, locationConverter: locationConverter) else {
                return super.visit(node)
            }

            correctionPositions.append(node.positionAfterSkippingLeadingTrivia)

            let elements = ExprListSyntax([
                expectation.baseExpr.withTrailingTrivia(.space),
                operatorExpr.withTrailingTrivia(.space),
                expectedValueExpr.withTrailingTrivia(node.trailingTrivia ?? .zero)
            ])
            return super.visit(SequenceExprSyntax(elements: elements))
        }
    }

    typealias MatcherFunction = String
    static let predicatesMapping: [MatcherFunction: PredicateDescription] = [
        "equal": (to: "==", toNot: "!=", .withArguments),
        "beIdenticalTo": (to: "===", toNot: "!==", .withArguments),
        "beGreaterThan": (to: ">", toNot: nil, .withArguments),
        "beGreaterThanOrEqualTo": (to: ">=", toNot: nil, .withArguments),
        "beLessThan": (to: "<", toNot: nil, .withArguments),
        "beLessThanOrEqualTo": (to: "<=", toNot: nil, .withArguments),
        "beTrue": (to: "==", toNot: "!=", .nullary(analogueValue: BooleanLiteralExprSyntax(booleanLiteral: true))),
        "beFalse": (to: "==", toNot: "!=", .nullary(analogueValue: BooleanLiteralExprSyntax(booleanLiteral: false))),
        "beNil": (to: "==", toNot: "!=", .nullary(analogueValue: NilLiteralExprSyntax(nilKeyword: .nilKeyword())))
    ]

    static func predicateDescription(for node: FunctionCallExprSyntax) -> PredicateDescription? {
        guard let expectation = node.expectation() else {
            return nil
        }

        return Self.predicatesMapping[expectation.operatorExpr.identifier.text]
    }
}

private extension FunctionCallExprSyntax {
    func expectation() -> Expectation? {
        guard trailingClosure == nil,
              argumentList.count == 1,
              let memberExpr = calledExpression.as(MemberAccessExprSyntax.self),
              let kind = Expectation.Kind(rawValue: memberExpr.name.text),
              let baseExpr = memberExpr.base?.as(FunctionCallExprSyntax.self),
              baseExpr.calledExpression.as(IdentifierExprSyntax.self)?.identifier.text == "expect",
              let predicateExpr = argumentList.first?.expression.as(FunctionCallExprSyntax.self),
              let operatorExpr = predicateExpr.calledExpression.as(IdentifierExprSyntax.self) else {
            return nil
        }

        let expected = predicateExpr.argumentList.first?.expression
        return Expectation(kind: kind, baseExpr: baseExpr, operatorExpr: operatorExpr, expected: expected)
    }
}

private typealias PredicateDescription = (to: String, toNot: String?, arity: Arity)

private enum Arity {
    case nullary(analogueValue: ExprSyntaxProtocol)
    case withArguments
}

private struct Expectation {
    let kind: Kind
    let baseExpr: FunctionCallExprSyntax
    let operatorExpr: IdentifierExprSyntax
    let expected: ExprSyntax?

    enum Kind {
        case positive
        case negative

        init?(rawValue: String) {
            switch rawValue {
            case "to":
                self = .positive
            case "toNot", "notTo":
                self = .negative
            default:
                return nil
            }
        }
    }

    func expectedValueExpr(for predicate: PredicateDescription) -> ExprSyntaxProtocol? {
        switch predicate.arity {
        case .withArguments:
            return expected
        case .nullary(let analogueValue):
            return analogueValue
        }
    }

    func operatorExpr(for predicate: PredicateDescription) -> BinaryOperatorExprSyntax? {
        let operatorStr: String? = {
            switch kind {
            case .negative:
                return predicate.toNot
            case .positive:
                return predicate.to
            }
        }()

        return operatorStr.map(BinaryOperatorExprSyntax.init(text:))
    }
}
