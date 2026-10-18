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
import okhttp3.Response
import org.xml.sax.SAXException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class RemoteCalendar(
    val urlPath: String,
    val displayName: String,
    val color: String?,
)

data class ConnectionTestResult(val success: Boolean, val message: String)

class CalDavException(
    message: String,
    val statusCode: Int? = null,
    cause: Throwable? = null,
) : Exception(message, cause)

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
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    init {
        val parsed = serverUrl.trim().toHttpUrlOrNull()
            ?: throw IllegalArgumentException(
                "Invalid server URL. Include http:// or https://, for example http://192.168.1.10:5232",
            )
        origin = parsed.newBuilder().encodedPath("/").build()
        basePath = normalizeBasePath(parsed.encodedPath.ifBlank { "/" }, username)
    }

    fun close() {
        client.dispatcher.cancelAll()
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }

    /**
     * Lightweight connectivity/auth check for the settings screen.
     */
    suspend fun testConnection(userPath: String): ConnectionTestResult = withContext(Dispatchers.IO) {
        try {
            val calendars = getCalendars(userPath)
            ConnectionTestResult(
                success = true,
                message = "Connected. Found ${calendars.size} calendar(s).",
            )
        } catch (exception: CalDavException) {
            ConnectionTestResult(false, exception.message ?: "Connection failed.")
        } catch (exception: Exception) {
            ConnectionTestResult(false, networkMessage(exception))
        }
    }

    suspend fun getCTag(calendarPath: String): String? = withContext(Dispatchers.IO) {
        val body = """
            <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
              <d:prop><cs:getctag /></d:prop>
            </d:propfind>
        """.trimIndent()

        execute("Reading the calendar sync tag", {
            request(storedUrl(calendarPath), "PROPFIND", body) { header("Depth", "0") }
        }) { response ->
            if (response.code !in 200..299) {
                throw httpError(response.code, "reading the calendar sync tag")
            }
            val text = response.body?.string().orEmpty()
            WebDavXml.parse(text).firstOrNull()?.cTag?.trim()?.takeIf { it.isNotEmpty() }
        }
    }

    suspend fun getCalendars(userPath: String): List<RemoteCalendar> = withContext(Dispatchers.IO) {
        val body = """
            <d:propfind xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
              <d:prop><d:displayname /><ical:calendar-color /></d:prop>
            </d:propfind>
        """.trimIndent()

        execute("Listing calendars", {
            request(userUrl(userPath), "PROPFIND", body) { header("Depth", "1") }
        }) { response ->
            if (response.code !in 200..299) {
                throw httpError(response.code, "listing calendars")
            }
            val requestedPath = joinPath(basePath, userPath)
            val text = response.body?.string().orEmpty()
            WebDavXml.parse(text).mapNotNull { dav ->
                val href = dav.href?.trim() ?: return@mapNotNull null
                val rawPath = normalizeHrefPath(href) ?: return@mapNotNull null
                val path = effectiveStoredPath(rawPath)
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

        execute("Downloading events", {
            request(storedUrl(calendarPath), "REPORT", body) { header("Depth", "1") }
        }) { response ->
            if (response.code !in 200..299) {
                throw httpError(response.code, "downloading events")
            }
            val text = response.body?.string().orEmpty()
            WebDavXml.parse(text).mapNotNull { it.calendarData?.takeIf(String::isNotBlank) }
        }
    }

    suspend fun putEvent(calendarPath: String, filename: String, icsData: String): Boolean =
        withContext(Dispatchers.IO) {
            execute("Uploading $filename", {
                request(storedUrl(calendarPath, filename), "PUT", icsData, ICS_MEDIA_TYPE)
            }) { response ->
                if (response.code !in setOf(200, 201, 204)) {
                    throw httpError(response.code, "uploading $filename")
                }
                true
            }
        }

    suspend fun deleteEvent(calendarPath: String, filename: String): Boolean =
        withContext(Dispatchers.IO) {
            execute("Deleting $filename", {
                request(storedUrl(calendarPath, filename), "DELETE")
            }) { response ->
                if (response.code !in setOf(200, 204, 404)) {
                    throw httpError(response.code, "deleting $filename")
                }
                true
            }
        }

    suspend fun createCalendar(calendarPath: String, displayName: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:set><d:prop><d:displayname>${escapeXml(displayName)}</d:displayname></d:prop></d:set>
                </c:mkcalendar>
            """.trimIndent()

            execute("Creating a calendar", {
                request(userUrl(calendarPath), "MKCALENDAR", body)
            }) { response ->
                if (response.code != 201) {
                    throw httpError(response.code, "creating a calendar")
                }
                true
            }
        }

    suspend fun updateCalendarColor(calendarPath: String, color: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <d:propertyupdate xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
                  <d:set><d:prop><ical:calendar-color>${escapeXml(color)}</ical:calendar-color></d:prop></d:set>
                </d:propertyupdate>
            """.trimIndent()

            execute("Updating the calendar color", {
                request(storedUrl(calendarPath), "PROPPATCH", body)
            }) { response ->
                if (response.code !in setOf(200, 207)) {
                    throw httpError(response.code, "updating the calendar color")
                }
                true
            }
        }

    suspend fun updateCalendarName(calendarPath: String, displayName: String): Boolean =
        withContext(Dispatchers.IO) {
            val body = """
                <d:propertyupdate xmlns:d="DAV:">
                  <d:set><d:prop><d:displayname>${escapeXml(displayName)}</d:displayname></d:prop></d:set>
                </d:propertyupdate>
            """.trimIndent()

            execute("Renaming the calendar", {
                request(storedUrl(calendarPath), "PROPPATCH", body)
            }) { response ->
                if (response.code !in setOf(200, 207)) {
                    throw httpError(response.code, "renaming the calendar")
                }
                true
            }
        }

    suspend fun deleteCalendar(calendarPath: String): Boolean = withContext(Dispatchers.IO) {
        execute("Deleting the calendar", {
            request(storedUrl(calendarPath), "DELETE")
        }) { response ->
            if (response.code !in setOf(200, 204, 404)) {
                throw httpError(response.code, "deleting the calendar")
            }
            true
        }
    }

    private suspend fun <T> execute(
        operation: String,
        requestBuilder: () -> Request,
        block: (Response) -> T,
    ): T {
        val request = try {
            requestBuilder()
        } catch (exception: Exception) {
            throw wrap(operation, exception)
        }
        Log.d(TAG, "$operation: ${request.method} ${request.url}")

        val call = client.newCall(request)
        val response = try {
            suspendCancellableCoroutine<Response> { continuation ->
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(
                    object : Callback {
                        override fun onFailure(call: Call, exception: IOException) {
                            if (continuation.isActive) {
                                continuation.resumeWithException(wrap(operation, exception))
                            }
                        }

                        override fun onResponse(call: Call, response: Response) {
                            if (continuation.isActive) {
                                continuation.resume(response)
                            } else {
                                response.close()
                            }
                        }
                    },
                )
            }
        } catch (exception: CancellationException) {
            throw exception
        } catch (exception: CalDavException) {
            throw exception
        } catch (exception: Exception) {
            throw wrap(operation, exception)
        }

        return response.use {
            Log.d(TAG, "$operation: HTTP ${it.code}")
            try {
                block(it)
            } catch (exception: CalDavException) {
                throw exception
            } catch (exception: Exception) {
                throw wrap(operation, exception)
            }
        }
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
        val effective = effectiveStoredPath(path)
        val builder = origin.newBuilder().encodedPath(effective)
        if (!effective.endsWith("/")) builder.addPathSegment("")
        if (extraSegment != null) builder.addPathSegment(extraSegment)
        return builder.build()
    }

    /**
     * Makes paths returned by a reverse proxy usable even when the proxy strips
     * the configured base path (for example /radicale) from server hrefs.
     */
    private fun effectiveStoredPath(path: String): String {
        val normalized = if (path.startsWith("/")) path else "/$path"
        if (basePath == "/") return normalized
        val normalizedBase = if (basePath.endsWith("/")) basePath else "$basePath/"
        return if (normalized.startsWith(normalizedBase)) {
            normalized
        } else {
            joinPath(normalizedBase, normalized)
        }
    }

    override fun toString(): String = "CalDavClient(user=$username)"

    /**
     * Accepts a base URL that accidentally includes the principal or calendar
     * path (for example /radicale/test/ or /test/work/) and trims back to the
     * server root so requests do not end up as /radicale/test/test/.
     */
    private fun normalizeBasePath(path: String, userName: String): String {
        val userSegment = userName.trim().trim('/')
        val segments = path.split('/').filter { it.isNotEmpty() }
        if (userSegment.isNotEmpty()) {
            val userIndex = segments.indexOfFirst { it == userSegment }
            if (userIndex >= 0) {
                return if (userIndex == 0) "/" else "/${segments.take(userIndex).joinToString("/")}/"
            }
        }
        return if (path.endsWith("/")) path else "$path/"
    }

    private fun normalizeHrefPath(href: String): String? {
        val path = if (href.startsWith("http://") || href.startsWith("https://")) {
            runCatching { URI(href).rawPath }.getOrNull()
        } else {
            href.substringBefore('?').substringBefore('#')
        } ?: return null
        if (path.isBlank()) return null
        val normalized = if (path.startsWith("/")) path else "/$path"
        return if (normalized.endsWith("/")) normalized else "$normalized/"
    }

    private fun wrap(operation: String, exception: Exception): CalDavException {
        Log.w(TAG, "$operation failed", exception)
        if (exception is SAXException) {
            return CalDavException(
                "$operation failed: the server did not return valid WebDAV XML. " +
                    "Check that the URL points to the CalDAV server, not a login page.",
                cause = exception,
            )
        }
        return CalDavException("$operation failed: ${networkMessage(exception)}", cause = exception)
    }

    private fun httpError(code: Int, operation: String): CalDavException {
        val message = when (code) {
            401 -> "Authentication failed (401). Check the username and password."
            403 -> "Access denied (403). Check Radicale's permissions for this user."
            404 -> "Not found (404) while $operation. Use the Radicale base URL, for example " +
                "http://192.168.1.10:5232, not the calendar or web UI path."
            405, 501 -> "The server rejected the request (HTTP $code) while $operation. " +
                "Check that the URL points to a CalDAV server."
            in 500..599 -> "Server error (HTTP $code) while $operation."
            else -> "Unexpected server response (HTTP $code) while $operation."
        }
        Log.w(TAG, "HTTP $code while $operation")
        return CalDavException(message, code)
    }

    private fun networkMessage(error: Throwable): String {
        val chain = generateSequence(error) { it.cause }.toList()
        return when {
            chain.any { it is SSLException } ->
                "TLS certificate error. The phone does not trust the server certificate. " +
                    "Install the server's CA certificate or use a certificate the phone trusts."
            chain.any { it is UnknownHostException } ->
                "Server host not found. Check the URL and your network connection."
            chain.any { it is ConnectException } ->
                "Cannot connect to the server. Check the host/port and make sure Radicale " +
                    "listens on 0.0.0.0 (not just localhost)."
            chain.any { it is SocketTimeoutException } ->
                "The connection timed out. Check your network and the server."
            chain.any { it.message?.contains("CLEARTEXT", ignoreCase = true) == true } ->
                "HTTP connections are blocked on this device. Use HTTPS or allow cleartext traffic."
            else -> chain.lastOrNull()?.message ?: error.javaClass.simpleName
        }
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
