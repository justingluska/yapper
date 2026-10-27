import XCTest

final class BilingualTests: XCTestCase {
    private typealias Word = Bilingual.Word

    /// Words a tenth of a second apart, each `length` long, starting at `start`.
    private func words(_ texts: [String], start: Double = 0, length: Double = 0.3, confidence: Double = 0.9) -> [Word] {
        texts.enumerated().map { index, text in
            let begin = start + Double(index) * (length + 0.1)
            return Word(text: text, start: begin, end: begin + length, confidence: confidence)
        }
    }

    func testStrategyFollowsScripts() {
        XCTAssertEqual(Bilingual.strategy("en", "es"), .windows)
        XCTAssertEqual(Bilingual.strategy("fr", "de"), .windows)
        XCTAssertEqual(Bilingual.strategy("en", "zh"), .script(base: 1))
        XCTAssertEqual(Bilingual.strategy("yue", "en"), .script(base: 0))
        XCTAssertEqual(Bilingual.strategy("ja", "ko"), .windows)
    }

    func testWindowCutsSitInGapsAndLeaveNoSliverAtTheEnd() {
        let heard = words(["I", " need", " to", " go", " al", " supermercado", " before", " it", " closes", " tonight."])
        let duration = 4.0
        let cuts = Bilingual.windowCuts([heard], duration: duration)
        XCTAssertFalse(cuts.isEmpty)
        for cut in cuts {
            // In a gap, never inside a word.
            XCTAssertFalse(heard.contains { $0.start < cut && cut < $0.end }, "\(cut)")
        }
        for (a, b) in zip([0] + cuts, cuts + [duration]) {
            XCTAssertGreaterThanOrEqual(b - a, Bilingual.windowLength * 0.6)
        }
    }

    func testShortDictationIsOneWindow() {
        XCTAssertEqual(Bilingual.windowCuts([words(["Hola", " amigo"])], duration: 0.8), [])
    }

    func testWindowLanguageIsTheSurerModel() {
        let english = words(["the", " link"], confidence: 0.4)
        let spanish = words(["el", " link"], confidence: 0.8)
        XCTAssertEqual(Bilingual.language(of: [english, spanish], previous: nil), 1)
        // A model that heard nothing loses.
        XCTAssertEqual(Bilingual.language(of: [[], spanish], previous: 0), 1)
    }

    func testWindowLanguageLeansToTheWindowBefore() {
        let a = words(["x"], confidence: 0.70)
        let b = words(["y"], confidence: 0.72)
        XCTAssertEqual(Bilingual.language(of: [a, b], previous: nil), 1)
        XCTAssertEqual(Bilingual.language(of: [a, b], previous: 0), 0)
    }

    func testRegionsJoinNeighboursInTheSameLanguage() {
        let regions = Bilingual.regions(cuts: [1, 2, 3], languages: [0, 1, 1, 0], duration: 4)
        XCTAssertEqual(regions, [
            Bilingual.Region(start: 0, end: 1, language: 0),
            Bilingual.Region(start: 1, end: 3, language: 1),
            Bilingual.Region(start: 3, end: 4, language: 0),
        ])
    }

    func testPaddingStaysInsideTheDictation() {
        let edge = Bilingual.padded(start: 0.1, end: 2, by: 0.4, duration: 2.2)
        XCTAssertEqual(edge.lowerBound, 0)
        XCTAssertEqual(edge.upperBound, 2.2)
        let middle = Bilingual.padded(start: 1, end: 2, by: 0.4, duration: 5)
        XCTAssertEqual(middle.lowerBound, 0.6, accuracy: 1e-9)
        XCTAssertEqual(middle.upperBound, 2.4, accuracy: 1e-9)
    }

    func testInsideKeepsWordsWhoseMiddleIsInThePiece() {
        // Padded audio began at 0.6 s; the piece is 1...2 s.
        let heard = [
            Word(text: "before", start: 0.0, end: 0.3, confidence: 1),  // 0.75 s: padding
            Word(text: " al", start: 0.4, end: 0.6, confidence: 1),     // 1.1 s
            Word(text: " super", start: 0.8, end: 1.3, confidence: 1),  // 1.65 s
            Word(text: " after", start: 1.5, end: 1.7, confidence: 1),  // 2.2 s: padding
        ]
        let kept = Bilingual.inside(heard, offset: 0.6, start: 1, end: 2, isFirst: false, isLast: false)
        XCTAssertEqual(kept.map(\.text), [" al", " super"])
        let first = Bilingual.inside(heard, offset: 0.6, start: 1, end: 2, isFirst: true, isLast: false)
        XCTAssertEqual(first.map(\.text), ["before", " al", " super"])
    }

    func testLatinSpansGroupEnglishInChinese() {
        let heard = [
            Word(text: "他们", start: 0, end: 0.4, confidence: 1),
            Word(text: " take", start: 0.4, end: 0.6, confidence: 0.99),
            Word(text: " the", start: 0.6, end: 0.7, confidence: 0.5),
            Word(text: " risponsbility", start: 0.7, end: 1.2, confidence: 0.8),
            Word(text: "，", start: 1.2, end: 1.25, confidence: 0.9),
            Word(text: " risk", start: 1.3, end: 1.6, confidence: 0.7),
            Word(text: "然后", start: 1.6, end: 2.0, confidence: 1),
            Word(text: " report", start: 3.0, end: 3.4, confidence: 0.8),
        ]
        // Punctuation between close stretches joins them; a far one stands alone.
        XCTAssertEqual(Bilingual.latinSpans(heard), [1...5, 7...7])
    }

    func testSpliceOnlyWhenTheRedoIsSureEnough() {
        let own = words(["risponsbility"], confidence: 0.6)
        XCTAssertTrue(Bilingual.shouldSplice(own: own, redo: words(["responsibility"], confidence: 0.9)))
        XCTAssertTrue(Bilingual.shouldSplice(own: own, redo: words(["responsibility"], confidence: 0.58)))
        XCTAssertFalse(Bilingual.shouldSplice(own: own, redo: words(["response"], confidence: 0.5)))
        XCTAssertFalse(Bilingual.shouldSplice(own: own, redo: words(["x"], confidence: 0.3)))
        XCTAssertFalse(Bilingual.shouldSplice(own: own, redo: []))
    }

    func testJoinSpacesLatinWordsButNotChinese() {
        XCTAssertEqual(Bilingual.join(["我", "明天", " finish the report ", "然后", "去"]), "我明天 finish the report 然后去")
        XCTAssertEqual(Bilingual.join(["I need to go", "al supermercado"]), "I need to go al supermercado")
        XCTAssertEqual(Bilingual.join([" Hola,", " ", "  amigo. "]), "Hola, amigo.")
        // A piece that starts a new language never runs into the full stop before it.
        XCTAssertEqual(Bilingual.join(["se llama neutral.", "Que son como los colors"]), "se llama neutral. Que son como los colors")
        // A full-width stop carries its own space.
        XCTAssertEqual(Bilingual.join(["回到这里。", "Then"]), "回到这里。Then")
    }

    func testSplicedStretchLosesTheClipsFullStop() {
        XCTAssertEqual(Bilingual.join(["开始", Bilingual.spliced("talk about our research topics."), "。"]),
                       "开始 talk about our research topics 。")
        XCTAssertEqual(Bilingual.spliced(" Why did you come? "), " Why did you come ")
    }
}
