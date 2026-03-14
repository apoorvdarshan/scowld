import SwiftUI

// MARK: - Memory View

/// Browse, search, and manage persistent memories with glass-styled cards.
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
            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    glassCategoryChip(title: "All", icon: "tray.full", category: nil)
                    ForEach(MemoryCategory.allCases, id: \.self) { category in
                        glassCategoryChip(title: category.displayName, icon: category.icon, category: category)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            // Memory list
            if filteredMemories.isEmpty {
                ContentUnavailableView(
                    "No Memories Yet",
                    systemImage: "brain.head.profile.fill",
                    description: Text("Scowld will remember things about you as you chat.")
                )
            } else {
                List {
                    ForEach(filteredMemories) { memory in
                        memoryCard(memory)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            memoryStore.deleteMemory(filteredMemories[index])
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $searchText, prompt: "Search memories...")
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Memory Card

    @ViewBuilder
    private func memoryCard(_ memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: memory.category.icon)
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(memory.category.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
                Text(memory.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(memory.content)
                .font(.body)

            HStack {
                // Confidence bar
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(memory.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Glass Category Chip

    @ViewBuilder
    private func glassCategoryChip(title: String, icon: String, category: MemoryCategory?) -> some View {
        let isSelected = selectedCategory == category

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.orange)
                    : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.08), lineWidth: 0.5)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}
