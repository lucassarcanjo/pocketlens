import SwiftUI
import Domain
import Persistence
import Importing
import Categorization
import LLM

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("PocketLens")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Local-first personal finance")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Scaffold check — package wiring")
                    .font(.headline)
                    .padding(.top, 8)
                Text(Domain.placeholder)
                    .font(.system(.body, design: .monospaced))
                Text(Persistence.placeholder)
                    .font(.system(.body, design: .monospaced))
                Text(Importing.placeholder)
                    .font(.system(.body, design: .monospaced))
                Text(Categorization.placeholder)
                    .font(.system(.body, design: .monospaced))
                Text(LLM.placeholder)
                    .font(.system(.body, design: .monospaced))
            }
            .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    ContentView()
}
