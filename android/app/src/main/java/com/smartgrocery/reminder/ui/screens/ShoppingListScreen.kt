package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.ui.GroceryViewModel

@Composable
fun ShoppingListScreen(viewModel: GroceryViewModel) {
    val groceries by viewModel.items.collectAsState()
    val toBuy = groceries.filterNot { it.isCompleted }
    val done = groceries.filter { it.isCompleted }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Text("Grocery List", style = MaterialTheme.typography.headlineMedium)
        }
        item {
            SectionHeader("To buy (${toBuy.size})")
        }
        items(toBuy, key = { it.id }) { item ->
            GroceryRow(item) { viewModel.toggle(item.id) }
        }
        if (done.isNotEmpty()) {
            item {
                SectionHeader("Completed")
            }
            items(done, key = { it.id }) { item ->
                GroceryRow(item) { viewModel.toggle(item.id) }
            }
        }
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
private fun GroceryRow(item: GroceryItem, onToggle: () -> Unit) {
    val details = listOf(item.aisle, item.notes).filter { it.isNotEmpty() }.joinToString(" · ")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onToggle)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked = item.isCompleted, onCheckedChange = null)
        Column(Modifier.padding(start = 12.dp)) {
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
    }
}
