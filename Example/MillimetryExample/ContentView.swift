import Millimetry
import SwiftUI

struct ContentView: View {
    @State private var analyticsEnabled = true
    @State private var price = 4.99
    @State private var isSending = false
    @State private var lastSent: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section("Screens") {
                    ForEach(DemoScreen.allCases) { screen in
                        Button("View \(screen.title)") {
                            Millimetry.track("screen_view", ["screen": .string(screen.rawValue)])
                        }
                    }
                }

                Section("Purchase") {
                    Stepper(value: $price, in: 0.99...99.99, step: 1) {
                        LabeledContent("Price", value: price, format: .currency(code: "USD"))
                    }
                    Button("Buy Pro") {
                        Millimetry.track("purchase", ["price": .double(price), "plan": "pro", "trial": false])
                    }
                }

                Section {
                    Toggle("Share Analytics", isOn: $analyticsEnabled)
                        .onChange(of: analyticsEnabled) {
                            Millimetry.setEnabled(analyticsEnabled)
                        }
                } footer: {
                    Text("Turning this off deletes the events waiting to be sent. Millimetry stores no identifiers on this device either way.")
                }

                Section {
                    Button("Send Now", action: sendNow)
                        .disabled(isSending)
                    if let lastSent {
                        LabeledContent("Last Sent", value: lastSent, format: .dateTime.hour().minute().second())
                    }
                } footer: {
                    Text("Events are also sent every few seconds, after 50 events, and when the app goes to the background.")
                }
            }
            .navigationTitle("Millimetry")
        }
    }

    private func sendNow() {
        isSending = true
        Task {
            await Millimetry.flush()
            lastSent = .now
            isSending = false
        }
    }
}

#Preview {
    ContentView()
}
