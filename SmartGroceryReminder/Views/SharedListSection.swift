import SwiftUI

/// Settings → Shared list: invite family into your list, join theirs, or leave.
struct SharedListSection: View {
    @EnvironmentObject private var appState: AppState

    @State private var inviteCode: String?
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            LabeledContent("List", value: status)

            if isOnOwnList {
                if let inviteCode {
                    LabeledContent("Invite code") {
                        Text(inviteCode)
                            .font(.body.monospaced().bold())
                            .textSelection(.enabled)
                    }
                    ShareLink(item: "Join my Smart Grocery list with code \(inviteCode)") {
                        Label("Send code", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        run { inviteCode = try await appState.createInvite() }
                    } label: {
                        Label("Invite someone", systemImage: "person.badge.plus")
                    }
                }

                if isJoining {
                    TextField("Code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("Join list") {
                        run {
                            try await appState.joinList(code: joinCode)
                            joinCode = ""
                            isJoining = false
                        }
                    }
                    .disabled(InviteCode.normalize(joinCode).count != InviteCode.length)
                } else {
                    Button {
                        isJoining = true
                    } label: {
                        Label("Join a list with a code", systemImage: "person.2")
                    }
                }
            } else {
                Button("Leave shared list", role: .destructive) {
                    run { try await appState.leaveSharedList() }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Shared list")
        } footer: {
            Text("Everyone on a list sees and edits the same items. Reminders stay on each person's own phone. Invite codes expire after 7 days.")
        }
        .disabled(isWorking)
        .task(id: appState.activeListId) { await appState.refreshSharedList() }
    }

    private var isOnOwnList: Bool {
        guard let userId = appState.currentUser?.id else { return true }
        return (appState.activeListId ?? userId) == userId
    }

    private var status: String {
        guard isOnOwnList else {
            let others = (appState.sharedList?.memberIds.count ?? 2) - 1
            return "Joined, with \(others) other\(others == 1 ? "" : "s")"
        }
        guard let list = appState.sharedList, list.isShared else { return "Just you" }
        let others = list.memberIds.count - 1
        return "Shared with \(others) other\(others == 1 ? "" : "s")"
    }

    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
