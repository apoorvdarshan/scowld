import SwiftUI

// MARK: - Past Chats View

/// Browse saved chat threads and switch which one is used as context.
struct MemoryView: View {
    var memoryStore: MemoryStore
    @State private var renameSlotId: UUID?
    @State private var renameText = ""
    @State private var viewingSlot: MemorySlot?

    var body: some View {
        List {
            Section {
                ForEach(memoryStore.slots) { slot in
                    slotRow(slot)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let slot = memoryStore.slots[index]
                        if memoryStore.slots.count > 1 {
                            memoryStore.deleteSlot(id: slot.id)
                        }
                    }
                }
            } header: {
                Label("Past Chats", systemImage: "text.bubble")
            } footer: {
                Text("Tap a chat to read it. The active chat is used as reference for future replies.")
            }

            Section {
                Button {
                    let slot = memoryStore.createSlot(name: memoryStore.nextDefaultSlotName())
                    memoryStore.setActiveSlot(id: slot.id)
                } label: {
                    Label("New Chat", systemImage: "plus.circle")
                        .foregroundStyle(.amicaBlue)
                }
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Chat", isPresented: Binding(
            get: { renameSlotId != nil },
            set: { if !$0 { renameSlotId = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renameSlotId {
                    memoryStore.renameSlot(id: id, name: renameText)
                }
                renameSlotId = nil
            }
            Button("Cancel", role: .cancel) { renameSlotId = nil }
        }
        .sheet(item: $viewingSlot) { slot in
            NavigationStack {
                PastChatDetailView(memoryStore: memoryStore, slot: slot)
            }
        }
    }

    // MARK: - Slot Row

    @ViewBuilder
    private func slotRow(_ slot: MemorySlot) -> some View {
        let isActive = memoryStore.activeSlotId == slot.id
        let messages = memoryStore.fetchMessages(slotId: slot.id)
        let lastMessage = messages.last

        Button {
            viewingSlot = slot
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? .amicaBlue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(.primary)

                    Text("\(slot.messageCount) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastMessage {
                        Text(lastMessage.content)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.amicaBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.amicaBlue.opacity(0.15), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .swipeActions(edge: .trailing) {
            if memoryStore.slots.count > 1 {
                Button(role: .destructive) {
                    memoryStore.deleteSlot(id: slot.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                renameText = slot.name
                renameSlotId = slot.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.amicaBlue)
        }
        .swipeActions(edge: .leading) {
            if !isActive {
                Button {
                    memoryStore.setActiveSlot(id: slot.id)
                } label: {
                    Label("Use Chat", systemImage: "checkmark.circle")
                }
                .tint(.amicaBlue)
            }
        }
    }
}

// MARK: - Past Chat Detail

struct PastChatDetailView: View {
    var memoryStore: MemoryStore
    let slot: MemorySlot
    @Environment(\.dismiss) private var dismiss

    private var messages: [ChatMessage] {
        memoryStore.fetchMessages(slotId: slot.id)
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                ContentUnavailableView(
                    "No Messages Yet",
                    systemImage: "text.bubble",
                    description: Text("Start chatting and this conversation will appear here as a read-only transcript.")
                )
            } else {
                List {
                    Section {
                        ForEach(messages) { message in
                            PastChatMessageRow(message: message)
                        }
                    } footer: {
                        Text("Saved chats are read-only. Switch to this chat to use it as context for future replies.")
                    }
                }
            }
        }
        .navigationTitle(slot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            if memoryStore.activeSlotId != slot.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        memoryStore.setActiveSlot(id: slot.id)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.amicaBlue)
                }
            }
        }
    }
}

private struct PastChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(roleTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var roleTitle: String {
        switch message.role {
        case .user: "You"
        case .assistant: CharacterPack.resolveCharacterName()
        case .system: "System"
        }
    }

    private var iconName: String {
        switch message.role {
        case .user: "person.crop.circle.fill"
        case .assistant: "sparkles"
        case .system: "gearshape.fill"
        }
    }

    private var iconColor: Color {
        switch message.role {
        case .user: .secondary
        case .assistant: .amicaBlue
        case .system: .secondary
        }
    }
}
