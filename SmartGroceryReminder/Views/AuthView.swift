import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode: Mode = .signIn
    @State private var email = "demo@grocery.app"
    @State private var password = "demo123"
    @State private var displayName = "Demo Shopper"
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum Mode {
        case signIn, signUp
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    formCard
                    demoHint
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "basket.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color("AccentGreen"))
                .accessibilityHidden(true)

            Text("Smart Grocery Reminder")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Lists that follow you home — and nudge you before groceries sit in the car.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                Text("Sign In").tag(Mode.signIn)
                Text("Create Account").tag(Mode.signUp)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Authentication mode")

            if mode == .signUp {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))

            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentGreen"))
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .accessibilityHint("Signs you into the grocery reminder app")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }

    private var demoHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prototype demo account")
                .font(.subheadline.weight(.semibold))
            Text("demo@grocery.app / demo123 — mock auth, no Firebase required.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("AccentGreen").opacity(0.12))
        )
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if mode == .signIn {
                try await appState.signIn(email: email, password: password)
            } else {
                try await appState.signUp(email: email, password: password, displayName: displayName)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
