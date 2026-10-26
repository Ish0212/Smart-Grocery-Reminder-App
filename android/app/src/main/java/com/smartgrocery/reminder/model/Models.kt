package com.smartgrocery.reminder.model

data class GroceryItem(
    val id: String,
    val title: String,
    val aisle: String = "",
    val notes: String = "",
    val isCompleted: Boolean = false,
)

/** The demo account's starting list, matching the iOS app's SampleData. */
object SampleData {
    val groceryItems = listOf(
        GroceryItem(id = "milk", title = "Milk", aisle = "Dairy", notes = "2% gallon"),
        GroceryItem(id = "bread", title = "Sourdough bread", aisle = "Bakery"),
        GroceryItem(id = "bananas", title = "Bananas", aisle = "Produce"),
        GroceryItem(id = "coffee", title = "Coffee beans", aisle = "Beverages"),
        GroceryItem(id = "eggs", title = "Eggs", aisle = "Dairy", notes = "Cage-free dozen", isCompleted = true),
    )
}
