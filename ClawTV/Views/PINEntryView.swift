import SwiftUI

struct PINEntryView: View {
    enum Mode {
        case verify(prompt: String)
        case set(prompt: String)
    }

    let mode: Mode
    let onResult: (Result) -> Void

    enum Result {
        case success(String)
        case cancelled
    }

    @EnvironmentObject var parental: ParentalControls
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var stage: Stage = .first
    @State private var error: String?
    @FocusState private var firstFocused: Bool
    @FocusState private var secondFocused: Bool

    private enum Stage { case first, confirm }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(prompt)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if case .set = mode, stage == .confirm {
                    Text("Re-enter to confirm")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if stage == .first {
                    SecureField("4-digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .frame(width: 320)
                        .focused($firstFocused)
                        .onSubmit(advance)
                } else {
                    SecureField("Confirm 4-digit PIN", text: $confirmPin)
                        .keyboardType(.numberPad)
                        .frame(width: 320)
                        .focused($secondFocused)
                        .onSubmit(advance)
                }
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 16) {
                    Button("Cancel") {
                        onResult(.cancelled)
                        dismiss()
                    }
                    Button {
                        advance()
                    } label: {
                        Label(buttonLabel, systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(submitDisabled)
                }
            }
            .padding(48)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
            .shadow(radius: 30)
        }
        .onAppear { firstFocused = true }
    }

    private var prompt: String {
        switch mode {
        case .verify(let p), .set(let p): return p
        }
    }

    private var buttonLabel: String {
        switch (mode, stage) {
        case (.set, .first): return "Next"
        case (.set, .confirm): return "Set PIN"
        case (.verify, _): return "Unlock"
        }
    }

    private var submitDisabled: Bool {
        switch stage {
        case .first: return pin.count < 4
        case .confirm: return confirmPin.count < 4
        }
    }

    private func advance() {
        error = nil
        switch (mode, stage) {
        case (.verify, _):
            if parental.verify(pin) {
                onResult(.success(pin))
                dismiss()
            } else {
                error = "Incorrect PIN. Please try again."
                pin = ""
                firstFocused = true
            }
        case (.set, .first):
            guard pin.count >= 4, pin.allSatisfy(\.isNumber) else {
                error = "PIN must be 4 digits."
                return
            }
            stage = .confirm
            secondFocused = true
        case (.set, .confirm):
            if pin == confirmPin {
                onResult(.success(pin))
                dismiss()
            } else {
                error = "PINs don't match. Please try again."
                confirmPin = ""
                secondFocused = true
            }
        }
    }
}
