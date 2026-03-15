import SwiftUI

// MARK: - Memory View

/// Browse and manage memory slots — each slot is a saved conversation context.
struct MemoryView: View {
    var memoryStore: MemoryStore
    @State private var showNewSlotAlert = false
    @State private var newSlotName = ""
    @State private var renameSlotId: UUID?
    @State private var renameText = ""
    @State private var viewingSlot: MemorySlot?

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
                Text("Tap to activate. Tap the info button to view/edit what the character remembers.")
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
        .sheet(item: $viewingSlot) { slot in
            NavigationStack {
                MemoryLogView(memoryStore: memoryStore, slot: slot)
            }
        }
    }

    // MARK: - Slot Row

    @ViewBuilder
    private func slotRow(_ slot: MemorySlot) -> some View {
        let isActive = memoryStore.activeSlotId == slot.id

        Button {
            viewingSlot = slot
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
                        if !slot.memoryLog.isEmpty {
                            Image(systemName: "brain.fill")
                                .font(.caption2)
                                .foregroundStyle(.amicaBlue)
                        }

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
        .swipeActions(edge: .leading) {
            if !isActive {
                Button {
                    memoryStore.setActiveSlot(id: slot.id)
                } label: {
                    Label("Activate", systemImage: "checkmark.circle")
                }
                .tint(.amicaBlue)
            }
        }
    }
}

// MARK: - Memory Log View

/// View and edit what the character remembers in a specific slot.
struct MemoryLogView: View {
    var memoryStore: MemoryStore
    let slot: MemorySlot
    @State private var editedLog: String = ""
    @State private var hasChanges = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editedLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Memories Yet",
                    systemImage: "brain.head.profile.fill",
                    description: Text("Chat with the character and memories will be saved here automatically.")
                )
            } else {
                List {
                    Section {
                        TextEditor(text: $editedLog)
                            .frame(minHeight: 300)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .onChange(of: editedLog) { hasChanges = true }
                    } header: {
                        Label("What \(slot.name) remembers", systemImage: "brain.fill")
                    } footer: {
                        Text("This is what the AI knows about you from this conversation. Edit or remove anything you want.")
                    }

                    if memoryStore.activeSlotId != slot.id {
                        Section {
                            Button {
                                memoryStore.setActiveSlot(id: slot.id)
                                dismiss()
                            } label: {
                                Label("Use This Memory", systemImage: "checkmark.circle")
                                    .foregroundStyle(.amicaBlue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(slot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    memoryStore.updateMemoryLog(editedLog, slotId: slot.id)
                    hasChanges = false
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundStyle(hasChanges ? .amicaBlue : .secondary)
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            // Load fresh from CoreData
            editedLog = memoryStore.getMemoryLog(slotId: slot.id)
        }
    }
}
