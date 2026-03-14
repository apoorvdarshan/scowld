import SwiftUI

// MARK: - Memory View

/// Browse, search, and manage persistent memories.
/// Users can see everything Scowld remembers about them.
struct MemoryView: View {
    var memoryStore: MemoryStore
    @State private var selectedCategory: MemoryCategory? = nil
    @State private var searchText = ""

    private var filteredMemories: [MemoryItem] {
        var items = memoryStore.memories

        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "All", category: nil)
                    ForEach(MemoryCategory.allCases, id: \.self) { category in
                        categoryChip(title: category.displayName, category: category)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Memory list
            if filteredMemories.isEmpty {
                ContentUnavailableView(
                    "No Memories",
                    systemImage: "brain",
                    description: Text("Scowld will remember things about you as you chat.")
                )
            } else {
                List {
                    ForEach(filteredMemories) { memory in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: memory.category.icon)
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(memory.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Text(memory.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(memory.content)
                                .font(.body)

                            HStack {
                                Text("Confidence: \(Int(memory.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let memory = filteredMemories[index]
                            memoryStore.deleteMemory(memory)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search memories")
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func categoryChip(title: String, category: MemoryCategory?) -> some View {
        let isSelected = selectedCategory == category

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.orange : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}
