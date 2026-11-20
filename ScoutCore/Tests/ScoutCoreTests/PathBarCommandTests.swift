import Testing
@testable import ScoutCore

@Suite struct PathBarCommandTests {
    let known: Set<String> = ["code", "cursor", "terminal"]

    @Test func commandsAndPaths() {
        #expect(PathBarCommand.parse("code .", known: known) == PathBarCommand(name: "code", argument: "."))
        #expect(PathBarCommand.parse("  Cursor  ", known: known) == PathBarCommand(name: "cursor"))
        #expect(PathBarCommand.parse("terminal ~/Sites/app", known: known) == PathBarCommand(name: "terminal", argument: "~/Sites/app"))
        #expect(PathBarCommand.parse("~/code", known: known) == nil)
        #expect(PathBarCommand.parse("/usr/local", known: known) == nil)
        #expect(PathBarCommand.parse("vim .", known: known) == nil)
        #expect(PathBarCommand.parse("", known: known) == nil)
    }

    @Test func targets() {
        let cur = "/Users/j/Sites"
        #expect(PathBarCommand(name: "code", argument: ".").target(current: cur, home: "/Users/j") == cur)
        #expect(PathBarCommand(name: "code").target(current: cur, home: "/Users/j") == cur)
        #expect(PathBarCommand(name: "code", argument: "app").target(current: cur, home: "/Users/j") == "/Users/j/Sites/app")
        #expect(PathBarCommand(name: "code", argument: "..").target(current: cur, home: "/Users/j") == "/Users/j")
        #expect(PathBarCommand(name: "code", argument: "~/x").target(current: cur, home: "/Users/j") == "/Users/j/x")
    }
}
