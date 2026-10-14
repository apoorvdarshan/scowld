import XCTest
@testable import Scowld

/// Saved chats (Core Data, in memory) and the context built from them.
@MainActor
final class MemoryStoreTests: XCTestCase {
    private func makeStore() -> MemoryStore {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }
        return MemoryStore(inMemory: true)
    }

    func testFreshStoreStartsWithOneActiveChat() throws {
        let store = makeStore()
        XCTAssertEqual(store.slots.map(\.name), ["Chat 1"])
        let active = try XCTUnwrap(store.activeSlotId)
        XCTAssertEqual(store.slots.first?.id, active)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "activeMemorySlotId"), active.uuidString)
        XCTAssertTrue(store.fetchMessages().isEmpty)
    }

    func testNewChatsAreNumberedAfterTheHighestDefaultName() {
        let store = makeStore()
        XCTAssertEqual(store.nextDefaultSlotName(), "Chat 2")
        store.createSlot(name: store.nextDefaultSlotName())
        store.createSlot(name: "Chat later")
        store.createSlot(name: "Ideas")
        XCTAssertEqual(store.nextDefaultSlotName(), "Chat 3")

        store.renameSlot(id: store.slots.first { $0.name == "Chat 1" }!.id, name: "Chat 9")
        XCTAssertEqual(store.nextDefaultSlotName(), "Chat 10")
    }

    func testSaveMessageTrimsTextIgnoresBlankMessagesAndUpdatesCounts() throws {
        let store = makeStore()
        store.saveMessage(role: .user, content: "  Hello there \n", emotion: .happy)
        store.saveMessage(role: .user, content: "   \n ")

        let messages = store.fetchMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.content, "Hello there")
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.emotion, .happy)
        XCTAssertEqual(try XCTUnwrap(store.slots.first).messageCount, 1)
    }

    func testSaveExchangeKeepsOrderAndSkipsAnExactRepeat() {
        let store = makeStore()
        store.saveExchange(userMessage: "What's the weather?", assistantResponse: "[happy] Sunny all day!")
        store.saveExchange(userMessage: "What's the weather?", assistantResponse: "[happy] Sunny all day!")

        var messages = store.fetchMessages()
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.content), ["What's the weather?", "[happy] Sunny all day!"])

        store.saveExchange(userMessage: "", assistantResponse: "Anything else?")
        messages = store.fetchMessages()
        XCTAssertEqual(messages.map(\.content).last, "Anything else?")
        XCTAssertEqual(messages.count, 3)

        store.saveExchange(userMessage: "  ", assistantResponse: "\n")
        XCTAssertEqual(store.fetchMessages().count, 3, "Blank exchanges are not saved")
    }

    func testMessagesStayInTheirOwnChat() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.activeSlotId)
        store.saveExchange(userMessage: "First chat", assistantResponse: "Reply one")

        let second = store.createSlot(name: store.nextDefaultSlotName())
        store.setActiveSlot(id: second.id)
        store.saveExchange(userMessage: "Second chat", assistantResponse: "Reply two")

        XCTAssertEqual(store.fetchMessages(slotId: first).map(\.content), ["First chat", "Reply one"])
        XCTAssertEqual(store.fetchMessages().map(\.content), ["Second chat", "Reply two"])
        XCTAssertEqual(store.slots.first { $0.id == first }?.messageCount, 2)
    }

    func testSwitchingChatsPersistsTheSelectionAndIgnoresUnknownIDs() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.activeSlotId)
        let second = store.createSlot(name: "Trip")

        store.setActiveSlot(id: second.id)
        XCTAssertEqual(store.activeSlotId, second.id)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "activeMemorySlotId"), second.id.uuidString)

        store.setActiveSlot(id: UUID())
        XCTAssertEqual(store.activeSlotId, second.id, "An unknown chat must not change the selection")

        store.setActiveSlot(id: first)
        XCTAssertEqual(store.activeSlotId, first)
    }

    func testRenameChat() {
        let store = makeStore()
        let slot = store.createSlot(name: "Untitled")
        store.renameSlot(id: slot.id, name: "Recipes")
        XCTAssertEqual(store.slots.first { $0.id == slot.id }?.name, "Recipes")
    }

    func testDeletingTheActiveChatSelectsAnotherAndRemovesItsMessages() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.activeSlotId)
        let second = store.createSlot(name: "Temporary")
        store.setActiveSlot(id: second.id)
        store.saveExchange(userMessage: "Delete me", assistantResponse: "Okay")

        store.deleteSlot(id: second.id)
        XCTAssertEqual(store.slots.map(\.id), [first])
        XCTAssertEqual(store.activeSlotId, first)
        XCTAssertTrue(store.fetchMessages(slotId: second.id).isEmpty)
    }

    func testDeletingTheLastChatCreatesAFreshOne() throws {
        let store = makeStore()
        let only = try XCTUnwrap(store.activeSlotId)
        store.deleteSlot(id: only)

        XCTAssertEqual(store.slots.count, 1)
        let replacement = try XCTUnwrap(store.activeSlotId)
        XCTAssertNotEqual(replacement, only)
        XCTAssertEqual(store.slots.first?.name, "Chat 1")
    }

    func testClearAllMemoriesLeavesOneEmptyChat() {
        let store = makeStore()
        store.saveExchange(userMessage: "One", assistantResponse: "Two")
        let other = store.createSlot(name: "Other")
        store.setActiveSlot(id: other.id)
        store.saveExchange(userMessage: "Three", assistantResponse: "Four")

        store.clearAllMemories()
        XCTAssertEqual(store.slots.map(\.name), ["Chat 1"])
        XCTAssertEqual(store.activeSlotId, store.slots.first?.id)
        XCTAssertTrue(store.fetchMessages().isEmpty)
    }

    func testMemoryLogBelongsToOneChat() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.activeSlotId)
        store.updateMemoryLog("Likes jasmine tea")
        let second = store.createSlot(name: "Work")

        XCTAssertEqual(store.getActiveMemoryLog(), "Likes jasmine tea")
        XCTAssertEqual(store.getMemoryLog(slotId: first), "Likes jasmine tea")
        XCTAssertEqual(store.getMemoryLog(slotId: second.id), "")

        store.updateMemoryLog("Prefers mornings", slotId: second.id)
        XCTAssertEqual(store.getMemoryLog(slotId: second.id), "Prefers mornings")
        XCTAssertEqual(store.slots.first { $0.id == second.id }?.memoryLog, "Prefers mornings")
    }

    func testContextUsesTheMostRecentMessagesWithSpeakerLabels() {
        let store = makeStore()
        UserDefaults.standard.set("Nova", forKey: "character_name")
        for turn in 1...3 {
            store.saveMessage(role: .user, content: "Question \(turn)")
            store.saveMessage(role: .assistant, content: "Answer \(turn)")
        }

        XCTAssertEqual(store.buildContextFromActiveSlot(limit: 3), [
            "Nova: Answer 2",
            "User: Question 3",
            "Nova: Answer 3",
        ])
        XCTAssertEqual(store.buildContextFromActiveSlot().count, 6)
    }
}
