import SwiftUI

// MARK: - Past Chats View

private enum ChatSortOption: String, CaseIterable, Identifiable {
    case createdDescending
    case createdAscending
    case nameAscending
    case nameDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createdDescending: "Created: Newest"
        case .createdAscending: "Created: Oldest"
        case .nameAscending: "Name: A to Z"
        case .nameDescending: "Name: Z to A"
        }
    }

    var localizedTitle: String {
        NSLocalizedString(title, comment: "Chat sort option")
    }

    var systemImage: String {
        switch self {
        case .createdDescending: "arrow.down"
        case .createdAscending: "arrow.up"
        case .nameAscending: "arrow.up"
        case .nameDescending: "arrow.down"
        }
    }
}

/// Browse saved chat threads and switch which one is used as context.
struct MemoryView: View {
    var memoryStore: MemoryStore
    @AppStorage("chatSortOption") private var chatSortOptionRaw = ChatSortOption.createdDescending.rawValue
    @State private var renameSlotId: UUID?
    @State private var renameText = ""

    private var chatSortOption: ChatSortOption {
        ChatSortOption(rawValue: chatSortOptionRaw) ?? .createdDescending
    }

    private var sortedSlots: [MemorySlot] {
        memoryStore.slots.sorted { lhs, rhs in
            switch chatSortOption {
            case .createdDescending:
                if lhs.createdDate != rhs.createdDate {
                    return lhs.createdDate > rhs.createdDate
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .createdAscending:
                if lhs.createdDate != rhs.createdDate {
                    return lhs.createdDate < rhs.createdDate
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameAscending:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.createdDate > rhs.createdDate
            case .nameDescending:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedDescending
                }
                return lhs.createdDate > rhs.createdDate
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedSlots) { slot in
                    slotRow(slot)
                }
                .onDelete { indexSet in
                    let slotsToDelete = indexSet.compactMap { index in
                        sortedSlots.indices.contains(index) ? sortedSlots[index] : nil
                    }
                    for slot in slotsToDelete {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort Chats", selection: $chatSortOptionRaw) {
                        ForEach(ChatSortOption.allCases) { option in
                            Label(option.localizedTitle, systemImage: option.systemImage)
                                .tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort chats")
            }
        }
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
    }

    // MARK: - Slot Row

    @ViewBuilder
    private func slotRow(_ slot: MemorySlot) -> some View {
        let isActive = memoryStore.activeSlotId == slot.id
        let messages = memoryStore.fetchMessages(slotId: slot.id)
        let lastMessage = messages.last

        HStack(spacing: 12) {
            Button {
                if !isActive {
                    memoryStore.setActiveSlot(id: slot.id)
                }
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? .amicaBlue : .secondary)
                    .font(.title3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? activeChatLabel : useChatAccessibilityLabel(for: slot.name))

            NavigationLink {
                PastChatDetailView(memoryStore: memoryStore, slot: slot)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(slot.name)
                            .font(.body)
                            .fontWeight(isActive ? .semibold : .regular)
                            .foregroundStyle(.primary)

                        Text(messageCountLabel(slot.messageCount))
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
                }
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

    private var activeChatLabel: String {
        NSLocalizedString("Active chat", comment: "Accessibility label for selected chat")
    }

    private func useChatAccessibilityLabel(for name: String) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("Use %@", comment: "Accessibility label for selecting a chat"),
            name
        )
    }

    private func messageCountLabel(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%d messages", comment: "Saved chat message count"),
            count
        )
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
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(messages) { message in
                                PastChatMessageRow(message: message)
                                    .id(message.id)
                            }
                        } footer: {
                            Text("Saved chats are read-only. Switch to this chat to use it as context for future replies.")
                        }
                    }
                    .onAppear {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: messages.count) {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
        .navigationTitle(slot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let latestMessageID = messages.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(latestMessageID, anchor: .bottom)
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
        case .user: NSLocalizedString("You", comment: "User message role")
        case .assistant: CharacterPack.resolveCharacterName()
        case .system: NSLocalizedString("System", comment: "System message role")
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
