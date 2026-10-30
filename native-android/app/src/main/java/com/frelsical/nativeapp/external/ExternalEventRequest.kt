package com.frelsical.nativeapp.external

import android.net.Uri
import com.frelsical.nativeapp.data.EventDraft

/** Work requested by another app through an Android intent. */
sealed interface ExternalEventRequest {
    /** A new event requested with `ACTION_INSERT`; shown in the editor first. */
    data class NewEvent(val draft: EventDraft) : ExternalEventRequest

    /** A calendar file opened or shared with the app. */
    data class ImportIcs(val uri: Uri) : ExternalEventRequest

    /** Calendar contents shared as text rather than as a file. */
    data class ImportIcsText(val contents: String) : ExternalEventRequest
}
