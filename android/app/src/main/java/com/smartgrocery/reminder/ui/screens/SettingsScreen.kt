package com.smartgrocery.reminder.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.ui.AppViewModel

@Composable
fun SettingsScreen(viewModel: AppViewModel) {
    val user by viewModel.user.collectAsState()
    val error by viewModel.authError.collectAsState()
    var showingDiagnostics by rememberSaveable { mutableStateOf(false) }
    var confirmingDelete by rememberSaveable { mutableStateOf(false) }

    if (showingDiagnostics) {
        BackHandler { showingDiagnostics = false }
        DiagnosticsScreen(viewModel.reminders, onBack = { showingDiagnostics = false })
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Signed in as ${user?.email.orEmpty()}",
            style = MaterialTheme.typography.bodyMedium,
        )

        OutlinedButton(onClick = { showingDiagnostics = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Diagnostics")
        }
        Button(onClick = viewModel::signOut, modifier = Modifier.fillMaxWidth()) {
            Text("Sign out")
        }
        OutlinedButton(
            onClick = { confirmingDelete = true },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
        ) {
            Text("Delete account")
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }

    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text("Delete your account?") },
            text = {
                Text("Your list is deleted for good. Places and the reminder log are removed from this phone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmingDelete = false
                        viewModel.deleteAccount()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) { Text("Cancel") }
            },
        )
    }
}
