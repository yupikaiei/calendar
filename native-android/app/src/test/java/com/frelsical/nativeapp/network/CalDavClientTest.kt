package com.frelsical.nativeapp.network

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class CalDavClientTest {

    private lateinit var server: MockWebServer
    private var baseUrl: String = ""

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        baseUrl = server.url("/").toString().trimEnd('/')
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun reAppliesBasePathWhenServerStripsIt() = runBlocking {
        respondWith(207, multistatus("/test/", "/test/frelsi/", "/test/work/"))
        val client = CalDavClient("$baseUrl/radicale/", "test", "secret")

        try {
            val calendars = client.getCalendars("/test/")

            assertEquals(listOf("/radicale/test/frelsi/", "/radicale/test/work/"), calendars.map { it.urlPath })
        } finally {
            client.close()
        }
    }

    @Test
    fun keepsBasePathWhenServerAlreadyIncludesIt() = runBlocking {
        respondWith(207, multistatus("/radicale/test/", "/radicale/test/frelsi/"))
        val client = CalDavClient("$baseUrl/radicale/", "test", "secret")

        try {
            val calendars = client.getCalendars("/test/")

            assertEquals(listOf("/radicale/test/frelsi/"), calendars.map { it.urlPath })
        } finally {
            client.close()
        }
    }

    @Test
    fun trimsPrincipalPathFromServerUrl() = runBlocking {
        respondWith(207, multistatus("/test/", "/test/frelsi/"))
        val client = CalDavClient("$baseUrl/test/work/", "test", "secret")

        try {
            client.getCalendars("/test/")

            assertEquals("/test/", server.takeRequest().path)
        } finally {
            client.close()
        }
    }

    @Test
    fun trimsCalendarPathFromPrefixedServerUrl() = runBlocking {
        respondWith(207, multistatus("/test/", "/test/frelsi/"))
        val client = CalDavClient("$baseUrl/radicale/test/work/", "test", "secret")

        try {
            val calendars = client.getCalendars("/test/")

            assertEquals("/radicale/test/", server.takeRequest().path)
            assertEquals(listOf("/radicale/test/frelsi/"), calendars.map { it.urlPath })
        } finally {
            client.close()
        }
    }

    @Test
    fun reportsAuthenticationFailures() = runBlocking {
        respondWith(401, "")
        val client = CalDavClient(baseUrl, "test", "wrong")

        try {
            client.getCalendars("/test/")
            fail("Expected CalDavException")
        } catch (exception: CalDavException) {
            assertEquals(401, exception.statusCode)
            assertTrue(exception.message!!.contains("Authentication failed"))
        } finally {
            client.close()
        }
    }

    @Test
    fun testConnectionReportsCalendarCount() = runBlocking {
        respondWith(207, multistatus("/test/", "/test/frelsi/"))
        val client = CalDavClient(baseUrl, "test", "secret")

        try {
            val result = client.testConnection("/test/")

            assertTrue(result.success)
            assertTrue(result.message.contains("Found 1 calendar"))
        } finally {
            client.close()
        }
    }

    private fun respondWith(status: Int, body: String) {
        server.enqueue(
            MockResponse()
                .setResponseCode(status)
                .setHeader("Content-Type", "application/xml; charset=utf-8")
                .setBody(body),
        )
    }

    private fun multistatus(vararg hrefs: String): String {
        val responses = hrefs.joinToString("") { href ->
            """
                <d:response>
                  <d:href>$href</d:href>
                  <d:propstat>
                    <d:prop>
                      <d:displayname>${href.trimEnd('/').substringAfterLast('/')}</d:displayname>
                      <ical:calendar-color>#FF5500FF</ical:calendar-color>
                    </d:prop>
                  </d:propstat>
                </d:response>
            """.trimIndent()
        }
        return "<d:multistatus xmlns:d=\"DAV:\" xmlns:ical=\"http://apple.com/ns/ical/\">" +
            responses +
            "</d:multistatus>"
    }
}
