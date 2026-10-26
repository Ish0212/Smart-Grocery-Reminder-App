package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import com.smartgrocery.reminder.ui.AppViewModel

/** Invite someone to your list, join someone else's, or leave it. */
@Composable
fun SharedListSection(viewModel: AppViewModel) {
    val user by viewModel.user.collectAsState()
    val activeListId by viewModel.activeListId.collectAsState()
    val inviteCode by viewModel.inviteCode.collectAsState()
    val status by viewModel.shareStatus.collectAsState()
    var joinCode by rememberSaveable { mutableStateOf("") }

    val onOwnList = activeListId == null || activeListId == user?.uid

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Shared list", style = MaterialTheme.typography.titleMedium)
        if (onOwnList) {
            Text(
                "Invite someone to your list with a code. They see the same items. Reminders stay on each phone.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = viewModel::createInvite, modifier = Modifier.fillMaxWidth()) {
                Text("Create an invite code")
            }
            inviteCode?.let { code ->
                Text(
                    "Code: $code. Valid for 7 days.",
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
            OutlinedTextField(
                value = joinCode,
                onValueChange = { joinCode = it.uppercase() },
                label = { Text("Invite code") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedButton(
                onClick = { viewModel.joinList(joinCode) },
                enabled = joinCode.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Join a list with a code")
            }
        } else {
            Text("You're on a shared list.", style = MaterialTheme.typography.bodyMedium)
            OutlinedButton(onClick = viewModel::leaveList, modifier = Modifier.fillMaxWidth()) {
                Text("Leave shared list")
            }
        }
        status?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
    }
}
