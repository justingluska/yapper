import XCTest

final class TextProcessorTests: XCTestCase {
    // MARK: Fillers

    func testLeadingFillerIsRemovedAndSentenceRecapitalized() {
        XCTAssertEqual(TextProcessor.clean("Um, so I think we should go."), "So I think we should go.")
    }

    func testFillerBetweenCommasCollapsesTheClause() {
        XCTAssertEqual(TextProcessor.clean("I was, um, thinking about it."), "I was thinking about it.")
    }

    func testFillerBeforeFinalPeriodKeepsThePeriod() {
        XCTAssertEqual(TextProcessor.clean("That is what I said um."), "That is what I said.")
    }

    func testFillerAfterSentenceEndRecapitalizesNextSentence() {
        XCTAssertEqual(TextProcessor.clean("It works. Uh, the next one is broken."), "It works. The next one is broken.")
    }

    func testWordsContainingFillersAreKept() {
        XCTAssertEqual(TextProcessor.clean("Bring an umbrella for the ermine."), "Bring an umbrella for the ermine.")
    }

    func testFillerRemovalCanBeTurnedOff() {
        let options = TextProcessor.Options(removeFillers: false, removeRepeats: true, replacements: [])
        XCTAssertEqual(TextProcessor.clean("Um, hello.", options: options), "Um, hello.")
    }

    // MARK: Repeats

    func testImmediateRepeatsAreRemoved() {
        XCTAssertEqual(TextProcessor.clean("I I think the the plan works."), "I think the plan works.")
    }

    func testNumbersAreNotTreatedAsStutters() {
        XCTAssertEqual(TextProcessor.clean("Call 555 555 1234."), "Call 555 555 1234.")
    }

    // MARK: Dictionary

    func testReplacementIsCaseInsensitiveAndWholeWord() {
        let options = TextProcessor.Options(replacements: [Replacement(spoken: "open ai", written: "OpenAI")])
        XCTAssertEqual(TextProcessor.clean("I use Open AI daily, not open aid.", options: options),
                       "I use OpenAI daily, not open aid.")
    }

    func testLongerReplacementWins() {
        let options = TextProcessor.Options(replacements: [
            Replacement(spoken: "gold", written: "Gold"),
            Replacement(spoken: "gold penguin", written: "Gold Penguin"),
        ])
        XCTAssertEqual(TextProcessor.clean("check gold penguin today", options: options), "check Gold Penguin today")
    }

    func testReplacementWithRegexCharactersIsLiteral() {
        let options = TextProcessor.Options(replacements: [Replacement(spoken: "c plus plus", written: "C++ $1")])
        XCTAssertEqual(TextProcessor.clean("I write c plus plus", options: options), "I write C++ $1")
    }

    // MARK: Spacing

    func testSpacesBeforePunctuationAreRemoved() {
        XCTAssertEqual(TextProcessor.tidySpacing("Hello ,  world !"), "Hello, world!")
    }

    func testEmptyInput() {
        XCTAssertEqual(TextProcessor.clean("   "), "")
    }

    // MARK: Fitting into the text field

    func testFitAtStartOfFieldCapitalizes() {
        XCTAssertEqual(TextProcessor.fit("hello there.", before: ""), "Hello there.")
    }

    func testFitAfterWordAddsSpaceAndLowercasesCommonWord() {
        XCTAssertEqual(TextProcessor.fit("The plan is good.", before: "I think"), " the plan is good.")
    }

    func testFitKeepsProperNounsAndI() {
        XCTAssertEqual(TextProcessor.fit("Justin said hi.", before: "and"), " Justin said hi.")
        XCTAssertEqual(TextProcessor.fit("I agree.", before: "and"), " I agree.")
        XCTAssertEqual(TextProcessor.fit("NASA called.", before: "and"), " NASA called.")
    }

    func testFitAfterSentenceCapitalizesWithoutDoubleSpace() {
        XCTAssertEqual(TextProcessor.fit("then we left.", before: "It rained. "), "Then we left.")
    }

    func testFitMidSentenceDropsTrailingPeriodAndSpacesBeforeFollowingWord() {
        XCTAssertEqual(TextProcessor.fit("Very big.", before: "hello ", after: "world"), "very big ")
    }

    func testFitWithoutAutocapitalizeLeavesCase() {
        XCTAssertEqual(TextProcessor.fit("The plan.", before: "", autocapitalize: false), "The plan.")
    }

    func testFitAfterOpeningBracketAddsNoSpace() {
        XCTAssertEqual(TextProcessor.fit("see above", before: "note ("), "see above")
    }
}
