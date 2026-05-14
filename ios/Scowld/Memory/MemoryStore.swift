import CoreData

// MARK: - Memory Store

/// CoreData-backed storage for chat threads and messages.
/// Each slot is a saved conversation thread that can be resumed later.
@Observable
final class MemoryStore {
    let container: NSPersistentContainer
    var slots: [MemorySlot] = []
    var activeSlotId: UUID?
    var totalMemoryCount: Int { slots.count }
    private let defaultSlotPrefix = "Chat"

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Scowld")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                print("CoreData error: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        loadSlots()
        migrateLegacySlotNames()

        if let idStr = UserDefaults.standard.string(forKey: "activeMemorySlotId"),
           let id = UUID(uuidString: idStr),
           slots.contains(where: { $0.id == id }) {
            activeSlotId = id
        }

        ensureActiveSlot()
    }

    // MARK: - Slot CRUD

    @discardableResult
    func createSlot(name: String) -> MemorySlot {
        let context = container.viewContext
        let entity = MemorySlotEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.name = name
        entity.createdDate = Date()
        entity.lastUsedDate = Date()
        save(context)
        loadSlots()
        return MemorySlot(id: id, name: name, createdDate: Date(), lastUsedDate: Date(), messageCount: 0, memoryLog: "")
    }

    func renameSlot(id: UUID, name: String) {
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let results = try? context.fetch(request), let entity = results.first {
            entity.name = name
            save(context)
            loadSlots()
        }
    }

    func deleteSlot(id: UUID) {
        let context = container.viewContext

        // Delete all messages in this slot
        let msgRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        msgRequest.predicate = NSPredicate(format: "sessionId == %@", id as CVarArg)
        let msgDelete = NSBatchDeleteRequest(fetchRequest: msgRequest)
        _ = try? context.execute(msgDelete)

        // Delete the slot
        let slotRequest: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        slotRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let results = try? context.fetch(slotRequest), let entity = results.first {
            context.delete(entity)
        }

        save(context)
        loadSlots()

        if activeSlotId == id {
            activeSlotId = nil
        }
        ensureActiveSlot()
    }

    func setActiveSlot(id: UUID) {
        guard slots.contains(where: { $0.id == id }) else {
            ensureActiveSlot()
            return
        }

        activeSlotId = id
        saveActiveSlotId()

        // Update lastUsedDate
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let results = try? context.fetch(request), let entity = results.first {
            entity.lastUsedDate = Date()
            save(context)
            loadSlots()
        }
    }

    func clearAllMemories() {
        let context = container.viewContext

        // Delete all messages
        let msgFetch: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        if let messages = try? context.fetch(msgFetch) {
            for msg in messages { context.delete(msg) }
        }

        // Delete all slots
        let slotFetch: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        if let slots = try? context.fetch(slotFetch) {
            for slot in slots { context.delete(slot) }
        }

        // Delete all old memory entities
        let memFetch: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        if let mems = try? context.fetch(memFetch) {
            for mem in mems { context.delete(mem) }
        }

        save(context)
        loadSlots()

        // Create fresh default slot
        let slot = createSlot(name: nextDefaultSlotName())
        activeSlotId = slot.id
        saveActiveSlotId()
    }

    // MARK: - Messages

    func saveMessage(role: MessageRole, content: String, emotion: Emotion? = nil) {
        let slotId = ensureActiveSlot()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = container.viewContext
        let message = MessageEntity(context: context)
        message.id = UUID()
        message.role = role.rawValue
        message.content = trimmed
        message.emotion = emotion?.rawValue ?? ""
        message.timestamp = Date()
        message.sessionId = slotId
        touchSlot(id: slotId, context: context)
        save(context)
        loadSlots() // refresh message counts
    }

    func saveExchange(userMessage: String, assistantResponse: String) {
        let slotId = ensureActiveSlot()
        let userText = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty || !assistantText.isEmpty else { return }

        let existing = fetchMessages(slotId: slotId)
        if existing.suffix(2).map(\.content) == [userText, assistantText] {
            return
        }

        let context = container.viewContext
        let timestamp = Date()

        if !userText.isEmpty {
            let user = MessageEntity(context: context)
            user.id = UUID()
            user.role = MessageRole.user.rawValue
            user.content = userText
            user.emotion = ""
            user.timestamp = timestamp
            user.sessionId = slotId
        }

        if !assistantText.isEmpty {
            let assistant = MessageEntity(context: context)
            assistant.id = UUID()
            assistant.role = MessageRole.assistant.rawValue
            assistant.content = assistantText
            assistant.emotion = ""
            assistant.timestamp = timestamp.addingTimeInterval(0.001)
            assistant.sessionId = slotId
        }

        touchSlot(id: slotId, context: context)
        save(context)
        loadSlots()
    }

    func fetchMessages(slotId: UUID? = nil) -> [ChatMessage] {
        let id = slotId ?? ensureActiveSlot()
        let context = container.viewContext
        let request: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        guard let results = try? context.fetch(request) else { return [] }

        return results.compactMap { entity in
            guard let id = entity.id,
                  let roleStr = entity.role,
                  let role = MessageRole(rawValue: roleStr),
                  let content = entity.content
            else { return nil }
            let emotion = Emotion(rawValue: entity.emotion ?? "")
            return ChatMessage(id: id, role: role, content: content, emotion: emotion, timestamp: entity.timestamp ?? Date())
        }
    }

    /// Build context string from active slot's chat history for system prompt injection
    func buildContextFromActiveSlot(limit: Int = 30) -> [String] {
        let messages = fetchMessages()
        let recent = messages.suffix(limit)
        return recent.map { "\($0.role.promptLabel): \($0.content)" }
    }

    // MARK: - Memory Log

    /// Get the memory log for the active slot
    func getActiveMemoryLog() -> String {
        getMemoryLog(slotId: ensureActiveSlot())
    }

    /// Get the memory log for a specific slot
    func getMemoryLog(slotId: UUID) -> String {
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", slotId as CVarArg)
        guard let results = try? context.fetch(request), let entity = results.first else { return "" }
        return entity.memoryLog ?? ""
    }

    /// Update the memory log for the active slot
    func updateMemoryLog(_ log: String) {
        updateMemoryLog(log, slotId: ensureActiveSlot())
    }

    /// Update the memory log for a specific slot
    func updateMemoryLog(_ log: String, slotId: UUID) {
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", slotId as CVarArg)
        if let results = try? context.fetch(request), let entity = results.first {
            entity.memoryLog = log
            entity.lastUsedDate = Date()
            save(context)
            loadSlots()
        }
    }

    // MARK: - Legacy compatibility

    var memories: [MemoryItem] { [] }

    func deleteMemory(_ memory: MemoryItem) {}

    func fetchRelevantMemories(limit: Int = 5) -> [MemoryItem] { [] }

    func fetchMemories(category: MemoryCategory) -> [MemoryItem] { [] }

    // MARK: - Private

    private func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CoreData save error: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func ensureActiveSlot() -> UUID {
        if let activeSlotId, slots.contains(where: { $0.id == activeSlotId }) {
            return activeSlotId
        }

        if let firstSlot = slots.first {
            activeSlotId = firstSlot.id
            saveActiveSlotId()
            return firstSlot.id
        }

        let slot = createSlot(name: nextDefaultSlotName())
        activeSlotId = slot.id
        saveActiveSlotId()
        return slot.id
    }

    private func loadSlots() {
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "lastUsedDate", ascending: false)]

        guard let results = try? context.fetch(request) else { return }

        slots = results.compactMap { entity in
            guard let id = entity.id, let name = entity.name else { return nil }
            // Count messages for this slot
            let msgRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            msgRequest.predicate = NSPredicate(format: "sessionId == %@", id as CVarArg)
            let count = (try? context.count(for: msgRequest)) ?? 0

            return MemorySlot(
                id: id,
                name: name,
                createdDate: entity.createdDate ?? Date(),
                lastUsedDate: entity.lastUsedDate ?? Date(),
                messageCount: count,
                memoryLog: entity.memoryLog ?? ""
            )
        }
    }

    private func touchSlot(id: UUID, context: NSManagedObjectContext) {
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let results = try? context.fetch(request), let entity = results.first {
            entity.lastUsedDate = Date()
        }
    }

    private func migrateLegacySlotNames() {
        let context = container.viewContext
        let request: NSFetchRequest<MemorySlotEntity> = MemorySlotEntity.fetchRequest()
        guard let results = try? context.fetch(request) else { return }

        var changed = false
        for entity in results {
            guard let name = entity.name, name.hasPrefix("Memory ") else { continue }
            let suffix = name.dropFirst("Memory ".count)
            guard Int(suffix) != nil else { continue }
            entity.name = "\(defaultSlotPrefix) \(suffix)"
            changed = true
        }

        if changed {
            save(context)
            loadSlots()
        }
    }

    func nextDefaultSlotName() -> String {
        let numbers = slots.compactMap { slot -> Int? in
            guard slot.name.hasPrefix("\(defaultSlotPrefix) ") else { return nil }
            return Int(slot.name.dropFirst(defaultSlotPrefix.count + 1))
        }
        return "\(defaultSlotPrefix) \((numbers.max() ?? 0) + 1)"
    }

    private func saveActiveSlotId() {
        UserDefaults.standard.set(activeSlotId?.uuidString, forKey: "activeMemorySlotId")
    }
}

private extension MessageRole {
    var promptLabel: String {
        switch self {
        case .user: "User"
        case .assistant: CharacterPack.resolveCharacterName()
        case .system: "System"
        }
    }
}

// MARK: - Memory Slot (View Model)

struct MemorySlot: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdDate: Date
    let lastUsedDate: Date
    let messageCount: Int
    let memoryLog: String
}

// MARK: - Legacy MemoryItem (kept for compilation)

struct MemoryItem: Identifiable, Sendable {
    let id: UUID
    let content: String
    let category: MemoryCategory
    let confidence: Double
    let date: Date
    let lastAccessed: Date

    init?(entity: MemoryEntity) {
        guard let id = entity.id,
              let content = entity.content,
              let categoryStr = entity.category,
              let category = MemoryCategory(rawValue: categoryStr)
        else { return nil }

        self.id = id
        self.content = content
        self.category = category
        self.confidence = entity.confidence
        self.date = entity.date ?? Date()
        self.lastAccessed = entity.lastAccessed ?? Date()
    }
}
