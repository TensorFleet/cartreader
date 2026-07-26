import XCTest
@testable import OSCRCompanion

final class MenuParserTests: XCTestCase {
    func testBuildsMenuAndPagingActionsAcrossChunks() {
        var parser = MenuParser()

        parser.consume("0)Game Boy\r\n1)NES/Fami")
        parser.consume("com\r\n")

        XCTAssertEqual(
            parser.actions,
            [
                QuickAction(id: "menu-0", title: "0  Game Boy", value: "0", kind: .menu),
                QuickAction(id: "menu-1", title: "1  NES/Famicom", value: "1", kind: .menu),
                QuickAction(id: "page-up", title: "▲ page (u)", value: "u", kind: .page),
                QuickAction(id: "page-down", title: "▼ page (d)", value: "d", kind: .page)
            ]
        )
    }

    func testOptionZeroStartsANewMenu() {
        var parser = MenuParser()
        parser.consume("0)Old\n1)Old two\n0)New\n")

        XCTAssertEqual(parser.actions.first?.title, "0  New")
        XCTAssertFalse(parser.actions.contains { $0.title.contains("Old two") })
    }

    func testLetterPromptBuildsAlphabetActions() {
        var parser = MenuParser()
        parser.consume("Enter first letter: \r\n")

        XCTAssertEqual(parser.actions.count, 27)
        XCTAssertEqual(parser.actions.first?.value, "#")
        XCTAssertEqual(parser.actions.last?.value, "Z")
    }
}
