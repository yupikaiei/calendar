package com.frelsical.nativeapp.network

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URI
import java.util.concurrent.TimeUnit

data class RemoteCalendar(
    val urlPath: String,
    val displayName: String,
    val color: String?,
)

/**
 * Minimal CalDAV client speaking to Radicale/Nextcloud-style servers.
 */
class CalDavClient(
    serverUrl: String,
    private val username: String,
    private val password: String,
) {
    private val origin: HttpUrl
    private val basePath: String
    private val authorization: String = Credentials.basic(username, password)

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    init {
        val parsed = serverUrl.trim().toHttpUrlOrNull()
            ?: throw IllegalArgumentException("Invalid CalDAV server URL")
        origin = parsed.newBuilder().encodedPath("/").build()
        basePath = parsed.encodedPath.ifBlank { "/" }
    }

    fun close() {
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }

    suspend fun getCTag(calendarPath: String): String? = withContext(Dispatchers.IO) {
        val body = """
            <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
              <d:prop><cs:getctag /></d:prop>
            </d:propfind>
        """.trimIndent()
        runCatching {
            client.newCall(
                request(storedUrl(calendarPath), "PROPFIND", body) { header("Depth", "0") },
            ).execute().use { response ->
                if (response.code !in setOf(200, 207)) {
                    Log.w(TAG, "PROPFIND ctag failed with ${response.code} for $calendarPath")
                    return@withContext null
                }
                val text = response.body?.string().orEmpty()
                WebDavXml.parse(text).firstOrNull()?.cTag?.trim()?.takeIf { it.isNotEmpty() }
            }
        }.onFailure { Log.w(TAG, "Unable to fetch ctag for $calendarPath", it) }.getOrNull()
    }

    suspend fun getCalendars(userPath: String): List<RemoteCalendar> = withContext(Dispatchers.IO) {
        val body = """
            <d:propfind xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
              <d:prop><d:displayname /><ical:calendar-color /></d:prop>
            </d:propfind>
        """.trimIndent()
        runCatching {
            val requestedPath = joinPath(basePath, userPath)
            client.newCall(
                request(userUrl(userPath), "PROPFIND", body) { header("Depth", "1") },
            ).execute().use { response ->
                if (response.code !in setOf(200, 207)) {
                    Log.w(TAG, "PROPFIND calendars failed with ${response.code}")
                    return@withContext emptyList()
                }
                val text = response.body?.string().orEmpty()
                WebDavXml.parse(text).mapNotNull { dav ->
                    val href = dav.href?.trim() ?: return@mapNotNull null
                    val path = normalizeHrefPath(href) ?: return@mapNotNull null
                    if (path.trimEnd('/') == requestedPath.trimEnd('/') || !path.endsWith("/")) {
                        return@mapNotNull null
                    }
                    RemoteCalendar(
                        urlPath = path,
                        displayName = dav.displayName?.trim()?.takeIf { it.isNotEmpty() } ?: "Calendar",
                        color = dav.color?.trim()?.takeIf { it.isNotEmpty() },
                    )
                }.distinctBy { it.urlPath }
            }
        }.onFailure { Log.w(TAG, "Unable to list calendars", it) }.getOrDefault(emptyList())
    }

    suspend fun getCalendarEvents(calendarPath: String): List<String> = withContext(Dispatchers.IO) {
        val body = """
            <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop><d:getetag /><c:calendar-data /></d:prop>
              <c:filter>
                <c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT" /></c:comp-filter>
              </c:filter>
            </c:calendar-query>
        """.trimIndent()
        runCatching {
            client.newCall(
                request(storedUrl(calendarPath), "REPORT", body) { header("Depth", "1") },
            ).execute().use { response ->
                if (response.code !in setOf(200, 207)) {
                    Log.w(TAG, "REPORT events failed with ${response.code} for $calendarPath")
                    return@withContext emptyList()
                }
                val text = response.body?.string().orEmpty()
                WebDavXml.parse(text).mapNotNull { it.calendarData?.takeIf(String::isNotBlank) }
            }
        }.onFailure { Log.w(TAG, "Unable to fetch events for $calendarPath", it) }
            .getOrDefault(emptyList())
    }

    suspend fun putEvent(calendarPath: String, filename: String, icsData: String): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                client.newCall(
                    request(storedUrl(calendarPath, filename), "PUT", icsData, ICS_MEDIA_TYPE),
                ).execute().use { it.code in setOf(200, 201, 204) }
            }.onFailure { Log.w(TAG, "Unable to upload $filename", it) }.getOrDefault(false)
        }

    suspend fun deleteEvent(calendarPath: String, filename: String): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                client.newCall(
                    request(storedUrl(calendarPath, filename), "DELETE"),
                ).execute().use { it.code in setOf(200, 204, 404) }
            }.onFailure { Log.w(TAG, "Unable to delete $filename", it) }.getOrDefault(false)
        }

    suspend fun createCalendar(calendarPath: String, displayName: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:set><d:prop><d:displayname>${escapeXml(displayName)}</d:displayname></d:prop></d:set>
                </c:mkcalendar>
            """.trimIndent()
            runCatching {
                client.newCall(
                    request(userUrl(calendarPath), "MKCALENDAR", body),
                ).execute().use { it.code == 201 }
            }.onFailure { Log.w(TAG, "Unable to create calendar $calendarPath", it) }.getOrDefault(false)
        }

    suspend fun updateCalendarColor(calendarPath: String, color: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <d:propertyupdate xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
                  <d:set><d:prop><ical:calendar-color>${escapeXml(color)}</ical:calendar-color></d:prop></d:set>
                </d:propertyupdate>
            """.trimIndent()
            runCatching {
                client.newCall(
                    request(storedUrl(calendarPath), "PROPPATCH", body),
                ).execute().use { it.code in setOf(200, 207) }
            }.onFailure { Log.w(TAG, "Unable to update calendar color", it) }.getOrDefault(false)
        }

    suspend fun updateCalendarName(calendarPath: String, displayName: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <d:propertyupdate xmlns:d="DAV:">
                  <d:set><d:prop><d:displayname>${escapeXml(displayName)}</d:displayname></d:prop></d:set>
                </d:propertyupdate>
            """.trimIndent()
            runCatching {
                client.newCall(
                    request(storedUrl(calendarPath), "PROPPATCH", body),
                ).execute().use { it.code in setOf(200, 207) }
            }.onFailure { Log.w(TAG, "Unable to rename calendar", it) }.getOrDefault(false)
        }

    suspend fun deleteCalendar(calendarPath: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            client.newCall(
                request(storedUrl(calendarPath), "DELETE"),
            ).execute().use { it.code in setOf(200, 204, 404) }
        }.onFailure { Log.w(TAG, "Unable to delete calendar $calendarPath", it) }.getOrDefault(false)
    }

    private fun request(
        url: HttpUrl,
        method: String,
        body: String? = null,
        mediaType: okhttp3.MediaType = XML_MEDIA_TYPE,
        configure: Request.Builder.() -> Unit = {},
    ): Request {
        val requestBody = body?.toRequestBody(mediaType)
        return Request.Builder()
            .url(url)
            .header("Authorization", authorization)
            .header("Accept", "*/*")
            .method(method, requestBody)
            .apply(configure)
            .build()
    }

    private fun userUrl(path: String): HttpUrl {
        return origin.newBuilder()
            .encodedPath(joinPath(basePath, path))
            .build()
    }

    private fun storedUrl(path: String, extraSegment: String? = null): HttpUrl {
        val builder = origin.newBuilder().encodedPath(path)
        if (!path.endsWith("/")) builder.addPathSegment("")
        if (extraSegment != null) builder.addPathSegment(extraSegment)
        return builder.build()
    }

    override fun toString(): String = "CalDavClient(user=$username)"

    private fun normalizeHrefPath(href: String): String? {
        val path = if (href.startsWith("http://") || href.startsWith("https://")) {
            runCatching { URI(href).rawPath }.getOrNull()
        } else {
            href.substringBefore('?').substringBefore('#')
        } ?: return null
        if (path.isBlank()) return null
        return if (path.endsWith("/")) path else "$path/"
    }

    private companion object {
        const val TAG = "CalDavClient"
        val XML_MEDIA_TYPE = "application/xml; charset=utf-8".toMediaType()
        val ICS_MEDIA_TYPE = "text/calendar; charset=utf-8".toMediaType()

        fun joinPath(base: String, path: String): String {
            return base.trimEnd('/') + "/" + path.trimStart('/')
        }

        fun escapeXml(value: String): String {
            return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&apos;")
        }
    }
}
