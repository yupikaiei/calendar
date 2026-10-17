package com.frelsical.nativeapp.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class WebDavXmlTest {

    @Test
    fun parsesMultistatusProperties() {
        val xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <d:multistatus xmlns:d="DAV:"
                           xmlns:cs="http://calendarserver.org/ns/"
                           xmlns:ical="http://apple.com/ns/ical/"
                           xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:response>
                <d:href>/user/work/</d:href>
                <d:propstat>
                  <d:prop>
                    <d:displayname>Work</d:displayname>
                    <ical:calendar-color>#FF5500FF</ical:calendar-color>
                    <cs:getctag>"ctag-1"</cs:getctag>
                  </d:prop>
                </d:propstat>
              </d:response>
              <d:response>
                <d:href>/user/work/event.ics</d:href>
                <d:propstat>
                  <d:prop>
                    <c:calendar-data><![CDATA[BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:x
            END:VEVENT
            END:VCALENDAR]]></c:calendar-data>
                  </d:prop>
                </d:propstat>
              </d:response>
            </d:multistatus>
        """.trimIndent()

        val responses = WebDavXml.parse(xml)

        assertEquals(2, responses.size)
        assertEquals("/user/work/", responses[0].href)
        assertEquals("Work", responses[0].displayName)
        assertEquals("#FF5500FF", responses[0].color)
        assertEquals("\"ctag-1\"", responses[0].cTag)
        assertNull(responses[0].calendarData)

        assertEquals("/user/work/event.ics", responses[1].href)
        assertNotNull(responses[1].calendarData)
        assertEquals(true, responses[1].calendarData!!.contains("BEGIN:VEVENT"))
    }
}
