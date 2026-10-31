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

    // MARK: Punctuation and lowercase

    func testPunctuationOffKeepsJustTheWords() {
        let options = TextProcessor.Options(punctuation: false)
        XCTAssertEqual(TextProcessor.clean("Hey, are you free? I'm out... Back at 5!", options: options),
                       "Hey are you free I'm out Back at 5")
    }

    func testPunctuationOffKeepsMarksInsideNumbersAndAddresses() {
        let options = TextProcessor.Options(punctuation: false)
        XCTAssertEqual(TextProcessor.clean("It's 3.5 miles, $1,000, at 10:30 on gold.com.", options: options),
                       "It's 3.5 miles $1,000 at 10:30 on gold.com")
    }

    func testPunctuationOffStillRemovesFillers() {
        let options = TextProcessor.Options(punctuation: false)
        XCTAssertEqual(TextProcessor.clean("I was, um, thinking. Uh, yes.", options: options), "I was thinking Yes")
    }

    func testPunctuationOffKeepsDictionaryMarks() {
        let options = TextProcessor.Options(punctuation: false, replacements: [Replacement(spoken: "c plus plus", written: "C++.")])
        XCTAssertEqual(TextProcessor.clean("I write c plus plus.", options: options), "I write C++.")
    }

    func testPunctuationOffDropsFullWidthMarks() {
        let options = TextProcessor.Options(punctuation: false)
        XCTAssertEqual(TextProcessor.clean("¿Qué tal? Bien.", options: options), "Qué tal Bien")
        XCTAssertEqual(TextProcessor.clean("你好。今天好吗？", options: options), "你好 今天好吗")
    }

    func testLowercaseKeepsPunctuation() {
        let options = TextProcessor.Options(lowercase: true)
        XCTAssertEqual(TextProcessor.clean("I think NASA called. Then Justin left.", options: options),
                       "i think nasa called. then justin left.")
    }

    func testRawLowercase() {
        let options = TextProcessor.Options(punctuation: false, lowercase: true,
                                            replacements: [Replacement(spoken: "gold penguin", written: "Gold Penguin")])
        XCTAssertEqual(TextProcessor.clean("Hey, I saw Gold Penguin today. It's great!", options: options),
                       "hey i saw Gold Penguin today it's great")
    }

    func testStyleSample() {
        XCTAssertEqual(TextProcessor.styleSample(punctuation: true, lowercase: false), "Hey, are you free Friday? I'll bring the snacks.")
        XCTAssertEqual(TextProcessor.styleSample(punctuation: false, lowercase: true), "hey are you free friday i'll bring the snacks")
    }

    func testFitWithoutAutocapitalizeKeepsLowercaseStart() {
        XCTAssertEqual(TextProcessor.fit("hey there", before: "", autocapitalize: false), "hey there")
        XCTAssertEqual(TextProcessor.fit("then we left", before: "it rained ", autocapitalize: false), "then we left")
    }

    // MARK: Spoken punctuation

    func testSaidMarksAreTyped() {
        XCTAssertEqual(TextProcessor.clean("Hello comma how are you question mark"), "Hello, how are you?")
        XCTAssertEqual(TextProcessor.clean("wow exclamation point"), "wow!")
        XCTAssertEqual(TextProcessor.clean("I'm home period see you soon"), "I'm home. See you soon")
    }

    func testSaidMarksSurvivePunctuationOff() {
        let options = TextProcessor.Options(punctuation: false)
        XCTAssertEqual(TextProcessor.clean("Hello, comma, how are you? Question mark. I'm fine period", options: options),
                       "Hello, how are you? I'm fine.")
        XCTAssertEqual(TextProcessor.clean("Check gold dot com dot", options: options), "Check gold.com.")
    }

    func testSaidMarksInLowercaseDontCapitalize() {
        let options = TextProcessor.Options(punctuation: false, lowercase: true)
        XCTAssertEqual(TextProcessor.clean("Okay period see you then", options: options), "okay. see you then")
    }

    func testSaidNewLine() {
        XCTAssertEqual(TextProcessor.clean("Dear Sam comma new line thanks for coming"), "Dear Sam,\nThanks for coming")
    }

    func testTheWordStaysWhenItMeansTheThing() {
        XCTAssertEqual(TextProcessor.clean("It took a period of time and the Oxford comma matters."),
                       "It took a period of time and the Oxford comma matters.")
        XCTAssertEqual(TextProcessor.clean("Comma"), "Comma")
    }

    func testSpokenPunctuationOff() {
        let options = TextProcessor.Options(spokenPunctuation: false)
        XCTAssertEqual(TextProcessor.clean("Hello comma world", options: options), "Hello comma world")
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
