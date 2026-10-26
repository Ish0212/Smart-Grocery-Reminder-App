package com.smartgrocery.reminder.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.receipt.ReceiptItem
import com.smartgrocery.reminder.receipt.ReceiptParser
import com.smartgrocery.reminder.receipt.ReceiptScanner
import com.smartgrocery.reminder.ui.AppViewModel
import kotlinx.coroutines.launch

/** Take or choose a receipt photo, read it on the device, then review it before anything changes. */
@Composable
fun ReceiptScanControls(viewModel: AppViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var cameraPhoto by remember { mutableStateOf<Uri?>(null) }
    var scanning by remember { mutableStateOf(false) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var review by remember { mutableStateOf<List<ReceiptItem>?>(null) }

    fun scan(photo: Uri) {
        scope.launch {
            scanning = true
            scanError = null
            try {
                val purchases = ReceiptParser.parse(ReceiptScanner.recognize(context, photo))
                if (purchases.isEmpty()) {
                    scanError = "No items found on that receipt."
                } else {
                    review = purchases
                }
            } catch (error: Exception) {
                scanError = "Couldn't read that photo. Try a clearer one."
            } finally {
                scanning = false
            }
        }
    }

    val takePhoto = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val photo = cameraPhoto
        if (saved && photo != null) scan(photo)
    }
    val choosePhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scan(uri)
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                onClick = {
                    val photo = ReceiptScanner.newPhotoUri(context)
                    cameraPhoto = photo
                    takePhoto.launch(photo)
                },
                modifier = Modifier.weight(1f),
            ) {
                Text("Scan receipt")
            }
            OutlinedButton(
                onClick = {
                    choosePhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
                modifier = Modifier.weight(1f),
            ) {
                Text("Choose photo")
            }
        }
        if (scanning) {
            Text(
                "Reading the receipt on this phone...",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        scanError?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }

    review?.let { purchases ->
        ReceiptReviewDialog(
            purchases = purchases,
            onApply = { chosen ->
                viewModel.applyReceipt(chosen)
                review = null
            },
            onCancel = { review = null },
        )
    }
}

private data class ReviewRow(val original: ReceiptItem, val name: String, val included: Boolean)

@Composable
private fun ReceiptReviewDialog(
    purchases: List<ReceiptItem>,
    onApply: (List<ReceiptItem>) -> Unit,
    onCancel: () -> Unit,
) {
    val rows = remember(purchases) {
        purchases.map { ReviewRow(it, name = it.name, included = true) }.toMutableStateList()
    }

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Review receipt") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "Matching list items are checked off. The rest are added as bought. Fix any name, or untick what isn't yours.",
                    style = MaterialTheme.typography.bodySmall,
                )
                rows.forEachIndexed { index, row ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = row.included,
                            onCheckedChange = { rows[index] = row.copy(included = it) },
                        )
                        OutlinedTextField(
                            value = row.name,
                            onValueChange = { rows[index] = row.copy(name = it) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                        )
                        row.original.price?.let {
                            Text(
                                it.toPlainString(),
                                modifier = Modifier.width(56.dp).padding(start = 8.dp),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onApply(
                    rows.filter { it.included && it.name.isNotBlank() }.map {
                        ReceiptItem(name = it.name.trim(), price = it.original.price, quantity = it.original.quantity)
                    },
                )
            }) {
                Text("Apply")
            }
        },
        dismissButton = {
            TextButton(onClick = onCancel) { Text("Cancel") }
        },
    )
}
