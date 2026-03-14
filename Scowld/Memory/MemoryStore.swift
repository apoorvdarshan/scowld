import CoreData

// MARK: - Memory Store

/// CoreData-backed persistent storage for memories, sessions, and messages.
/// All data is stored locally — NEVER synced to any cloud service.
@Observable
final class MemoryStore {
    let container: NSPersistentContainer
    var memories: [MemoryItem] = []
    var totalMemoryCount: Int = 0

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
        loadMemories()
    }

    // MARK: - Memory CRUD

    func saveMemory(content: String, category: MemoryCategory, confidence: Double = 0.8) {
        let context = container.viewContext
        let entity = MemoryEntity(context: context)
        entity.id = UUID()
        entity.content = content
        entity.category = category.rawValue
        entity.confidence = confidence
        entity.date = Date()
        entity.lastAccessed = Date()

        save(context)
        loadMemories()
    }

    func deleteMemory(_ memory: MemoryItem) {
        let context = container.viewContext
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", memory.id as CVarArg)

        if let results = try? context.fetch(request), let entity = results.first {
            context.delete(entity)
            save(context)
            loadMemories()
        }
    }

    func clearAllMemories() {
        let context = container.viewContext
        let request: NSFetchRequest<NSFetchRequestResult> = MemoryEntity.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)

        do {
            try context.execute(deleteRequest)
            save(context)
            loadMemories()
        } catch {
            print("Failed to clear memories: \(error)")
        }
    }

    /// Fetch the most relevant memories for context injection
    func fetchRelevantMemories(limit: Int = 5) -> [MemoryItem] {
        let context = container.viewContext
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastAccessed", ascending: false),
            NSSortDescriptor(key: "confidence", ascending: false),
        ]
        request.fetchLimit = limit

        guard let results = try? context.fetch(request) else { return [] }

        // Update lastAccessed for fetched memories
        for entity in results {
            entity.lastAccessed = Date()
        }
        save(context)

        return results.compactMap { MemoryItem(entity: $0) }
    }

    /// Fetch memories filtered by category
    func fetchMemories(category: MemoryCategory) -> [MemoryItem] {
        let context = container.viewContext
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "category == %@", category.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.compactMap { MemoryItem(entity: $0) }
    }

    // MARK: - Session Management

    func createSession() -> UUID {
        let context = container.viewContext
        let session = SessionEntity(context: context)
        let id = UUID()
        session.id = id
        session.date = Date()
        session.duration = 0
        session.summary = ""
        save(context)
        return id
    }

    func updateSession(id: UUID, summary: String, duration: Double) {
        let context = container.viewContext
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let results = try? context.fetch(request), let session = results.first {
            session.summary = summary
            session.duration = duration
            save(context)
        }
    }

    // MARK: - Message Storage

    func saveMessage(role: MessageRole, content: String, emotion: Emotion?, sessionId: UUID) {
        let context = container.viewContext
        let message = MessageEntity(context: context)
        message.id = UUID()
        message.role = role.rawValue
        message.content = content
        message.emotion = emotion?.rawValue ?? ""
        message.timestamp = Date()
        message.sessionId = sessionId
        save(context)
    }

    func fetchMessages(sessionId: UUID) -> [ChatMessage] {
        let context = container.viewContext
        let request: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
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

    // MARK: - Private

    private func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CoreData save error: \(error.localizedDescription)")
        }
    }

    private func loadMemories() {
        let context = container.viewContext
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        if let results = try? context.fetch(request) {
            memories = results.compactMap { MemoryItem(entity: $0) }
            totalMemoryCount = memories.count
        }
    }
}

// MARK: - Memory Item (View Model)

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
