import SwiftUI
import LocalAuthentication

/// Face ID / passcode gate shown when the lock setting is on.
/// The sky stays veiled until the owner looks at it.
struct LockView: View {
    let onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.01, blue: 0.05).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "moon.stars.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.3))
                Text("Your sky is yours alone.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                if failed {
                    Button("Try again", action: authenticate)
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.4))
                }
            }
        }
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        failed = false
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Device has no passcode at all — don't lock the user out of their own data.
            onUnlock()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock your sky") { success, _ in
            DispatchQueue.main.async {
                if success { onUnlock() } else { failed = true }
            }
        }
    }
}
