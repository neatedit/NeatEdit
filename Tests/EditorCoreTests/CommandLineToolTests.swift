import Testing
@testable import EditorCore

struct CommandLineToolTests {
    @Test func linksTheBundledScriptIntoUsrLocalBin() {
        let command = CommandLineTool.installCommand(script: "/Applications/NeatEdit.app/Contents/Resources/neatedit")
        #expect(command == "sudo mkdir -p /usr/local/bin && sudo ln -sf '/Applications/NeatEdit.app/Contents/Resources/neatedit' /usr/local/bin/neatedit")
    }

    @Test func quotesPathsWithSpacesAndApostrophes() {
        let command = CommandLineTool.installCommand(script: "/Users/me/My Apps/Bob's/NeatEdit.app/Contents/Resources/neatedit")
        #expect(command.contains("ln -sf '/Users/me/My Apps/Bob'\\''s/NeatEdit.app/Contents/Resources/neatedit' "))
    }
}
