import Testing
@testable import EditorCore

/// macOS names an unsaved draft from its text, but its own draft file is
/// called "Unsaved <App> Document", so the app's name leaks into the result.
@Suite struct DraftNameTests {
    @Test func dropsTheAppNameInFront() {
        #expect(DraftName.removing(app: "NeatEdit", from: "NeatEdit Roadmap Update") == "Roadmap Update")
    }

    @Test func dropsTheAppNameAnywhere() {
        #expect(DraftName.removing(app: "NeatEdit", from: "Roadmap NeatEdit Update") == "Roadmap Update")
        #expect(DraftName.removing(app: "NeatEdit", from: "Roadmap Update NeatEdit") == "Roadmap Update")
    }

    @Test func dropsTheSeparatorLeftBehind() {
        #expect(DraftName.removing(app: "NeatEdit", from: "NeatEdit - Build Test") == "Build Test")
        #expect(DraftName.removing(app: "NeatEdit", from: "NeatEdit: Build Test") == "Build Test")
        #expect(DraftName.removing(app: "NeatEdit", from: "Build Test – NeatEdit") == "Build Test")
        #expect(DraftName.removing(app: "NeatEdit", from: "Build - NeatEdit - Test") == "Build - Test")
    }

    @Test func ignoresCase() {
        #expect(DraftName.removing(app: "NeatEdit", from: "Neatedit Auto-Save") == "Auto-Save")
    }

    @Test func leavesOtherNamesAlone() {
        #expect(DraftName.removing(app: "NeatEdit", from: "Google Ads Campaign") == "Google Ads Campaign")
        #expect(DraftName.removing(app: "NeatEdit", from: "Auto-Save Notes") == "Auto-Save Notes")
    }

    @Test func onlyWholeWords() {
        #expect(DraftName.removing(app: "Edit", from: "NeatEdit Editing Notes") == "NeatEdit Editing Notes")
    }

    @Test func nothingLeftIsNoName() {
        #expect(DraftName.removing(app: "NeatEdit", from: "NeatEdit") == nil)
        #expect(DraftName.removing(app: "NeatEdit", from: " NeatEdit - ") == nil)
    }

    @Test func anEmptyAppNameChangesNothing() {
        #expect(DraftName.removing(app: "", from: "Roadmap Update") == "Roadmap Update")
    }
}
