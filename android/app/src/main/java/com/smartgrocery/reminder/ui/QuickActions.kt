package com.smartgrocery.reminder.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Requests from outside the list screen, such as the launcher's "Add item" shortcut. */
object QuickActions {
    const val ACTION_ADD_ITEM = "com.smartgrocery.reminder.ADD_ITEM"

    private val _addItemRequested = MutableStateFlow(false)
    val addItemRequested: StateFlow<Boolean> = _addItemRequested.asStateFlow()

    fun requestAddItem() {
        _addItemRequested.value = true
    }

    fun consumeAddItem() {
        _addItemRequested.value = false
    }
}
