import SwiftUI

struct ReviewRevealButton<Label: View>: View {
    let milliseconds: Int
    let enabled: Bool
    let cardKey: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @GestureState private var touching = false
    @State private var size = CGSize.zero
    @State private var began = false
    @State private var pending: Task<Void, Never>?
    private var hold: Int { max(0, min(2000, milliseconds)) }

    var body: some View {
        Button { if hold == 0 { action() } } label: { label() }
            .disabled(!enabled)
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { size = geometry.size }.onChange(of: geometry.size) { _, next in size = next }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    guard hold > 0, enabled else { return }
                    guard CGRect(origin: .zero, size: size).contains(value.location) else { pending?.cancel(); return }
                    guard !began else { return }
                    began = true
                    let delay = hold
                    pending = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                        catch { return }
                        guard touching, enabled, !Task.isCancelled else { return }
                        action()
                    }
                }
                .onEnded { _ in cancel() }, including: hold > 0 ? .all : .none)
            .onChange(of: touching) { _, next in if !next { cancel() } }
            .onChange(of: enabled) { _, next in if !next { cancel() } }
            .onChange(of: cardKey) { _, _ in cancel() }
            .onDisappear { cancel() }
            .accessibilityAction { if enabled { action() } }
    }
    private func cancel() { pending?.cancel(); pending = nil; began = false }
}
