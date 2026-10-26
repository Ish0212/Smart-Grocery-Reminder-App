package com.smartgrocery.reminder.receipt

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.tasks.await
import java.io.File

/** Reads a receipt photo on the device with ML Kit. The photo never leaves the phone. */
object ReceiptScanner {
    suspend fun recognize(context: Context, photo: Uri): List<String> {
        val image = InputImage.fromFilePath(context, photo)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val text = recognizer.process(image).await()
        val fragments = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            TextFragment(line.text, box.top.toFloat(), box.bottom.toFloat(), box.left.toFloat())
        }
        return ReceiptText.lines(fragments)
    }

    /** A cache file the camera writes the photo into, and the content URI that grants it access. */
    fun newPhotoUri(context: Context): Uri {
        val folder = File(context.cacheDir, "receipts").apply { mkdirs() }
        val file = File(folder, "receipt-${System.currentTimeMillis()}.jpg")
        return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }
}
