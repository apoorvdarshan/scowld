import SwiftUI

// MARK: - Memory View

/// Browse and manage memory slots — each slot is a saved conversation context.
struct MemoryView: View {
    var memoryStore: MemoryStore
    @State private var showNewSlotAlert = false
    @State private var newSlotName = ""
    @State private var renameSlotId: UUID?
    @State private var renameText = ""

    var body: some View {
        List {
            // MARK: - Memory Slots
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
                Label("Save Slots", systemImage: "tray.2")
            } footer: {
                Text("Select a memory to continue that conversation. The character remembers everything in the active slot.")
            }

            // MARK: - Actions
            Section {
                Button {
                    newSlotName = "Memory \(memoryStore.slots.count + 1)"
                    showNewSlotAlert = true
                } label: {
                    Label("New Memory", systemImage: "plus.circle")
                        .foregroundStyle(.amicaBlue)
                }
            }
        }
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Memory", isPresented: $showNewSlotAlert) {
            TextField("Name", text: $newSlotName)
            Button("Create") {
                let slot = memoryStore.createSlot(name: newSlotName)
                memoryStore.setActiveSlot(id: slot.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a new conversation memory.")
        }
        .alert("Rename", isPresented: Binding(
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

        Button {
            memoryStore.setActiveSlot(id: slot.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? .amicaBlue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text("\(slot.messageCount) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(slot.lastUsedDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
    }
}
