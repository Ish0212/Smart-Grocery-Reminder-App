package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.data.ItemDraft
import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.ui.AppViewModel
import com.smartgrocery.reminder.ui.QuickActions

@Composable
fun ShoppingListScreen(viewModel: AppViewModel) {
    val snapshot by viewModel.list.collectAsState()
    val listError by viewModel.listError.collectAsState()
    var adding by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<GroceryItem?>(null) }
    val addRequested by QuickActions.addItemRequested.collectAsState()
    LaunchedEffect(addRequested) {
        if (addRequested) {
            adding = true
            QuickActions.consumeAddItem()
        }
    }

    val toBuy = snapshot.items.filterNot { it.isCompleted }
    val done = snapshot.items.filter { it.isCompleted }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Text("Grocery List", style = MaterialTheme.typography.headlineMedium)
            }
            item {
                ReceiptScanControls(viewModel)
            }
            if (snapshot.savedOnDevice) {
                item {
                    Text(
                        "Saved on this device. It will sync when you're back online.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            listError?.let { message ->
                item {
                    Text(message, color = MaterialTheme.colorScheme.error)
                }
            }
            item {
                SectionHeader("To buy (${toBuy.size})")
            }
            items(toBuy, key = { it.id }) { item ->
                GroceryRow(item, onToggle = { viewModel.toggle(item) }, onEdit = { editing = item })
            }
            if (done.isNotEmpty()) {
                item {
                    SectionHeader("Completed")
                }
                items(done, key = { it.id }) { item ->
                    GroceryRow(item, onToggle = { viewModel.toggle(item) }, onEdit = { editing = item })
                }
            }
        }

        FloatingActionButton(
            onClick = { adding = true },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = "Add grocery item")
        }
    }

    if (adding) {
        ItemEditorDialog(
            item = null,
            onSave = { draft ->
                viewModel.addItem(draft)
                adding = false
            },
            onDelete = null,
            onDismiss = { adding = false },
        )
    }
    editing?.let { item ->
        ItemEditorDialog(
            item = item,
            onSave = { draft ->
                viewModel.saveEdit(item.id, draft)
                editing = null
            },
            onDelete = {
                viewModel.delete(item.id)
                editing = null
            },
            onDismiss = { editing = null },
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun GroceryRow(item: GroceryItem, onToggle: () -> Unit, onEdit: () -> Unit) {
    val details = listOf(item.aisle, item.notes).filter { it.isNotEmpty() }.joinToString(" · ")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onToggle)
            .padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked = item.isCompleted, onCheckedChange = null)
        Column(Modifier.padding(start = 8.dp).weight(1f)) {
            Text(
                item.title,
                style = MaterialTheme.typography.bodyLarge,
                textDecoration = if (item.isCompleted) TextDecoration.LineThrough else TextDecoration.None,
            )
            if (details.isNotEmpty()) {
                Text(
                    details,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        IconButton(onClick = onEdit) {
            Icon(Icons.Filled.Edit, contentDescription = "Edit ${item.title}")
        }
    }
}

@Composable
private fun ItemEditorDialog(
    item: GroceryItem?,
    onSave: (ItemDraft) -> Unit,
    onDelete: (() -> Unit)?,
    onDismiss: () -> Unit,
) {
    var title by rememberSaveable { mutableStateOf(item?.title.orEmpty()) }
    var aisle by rememberSaveable { mutableStateOf(item?.aisle.orEmpty()) }
    var notes by rememberSaveable { mutableStateOf(item?.notes.orEmpty()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (item == null) "New Item" else "Edit Item") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Item name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = aisle,
                    onValueChange = { aisle = it },
                    label = { Text("Aisle (optional)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(ItemDraft(title.trim(), aisle.trim(), notes.trim())) },
                enabled = title.isNotBlank(),
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            if (onDelete != null) {
                TextButton(
                    onClick = onDelete,
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("Delete")
                }
            } else {
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
            }
        },
    )
}
