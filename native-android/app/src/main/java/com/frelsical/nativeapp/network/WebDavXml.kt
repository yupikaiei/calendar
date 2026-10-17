package com.frelsical.nativeapp.network

import org.w3c.dom.Element
import org.xml.sax.InputSource
import java.io.StringReader
import javax.xml.parsers.DocumentBuilderFactory

data class DavResponse(
    var href: String? = null,
    var displayName: String? = null,
    var color: String? = null,
    var cTag: String? = null,
    var calendarData: String? = null,
)

/**
 * Namespace-agnostic parser for WebDAV multistatus responses. Only the handful
 * of properties the app needs are extracted.
 */
object WebDavXml {

    fun parse(xml: String): List<DavResponse> {
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            isExpandEntityReferences = false
        }
        runCatching {
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        runCatching {
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
        }
        runCatching {
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        }

        val document = factory.newDocumentBuilder()
            .parse(InputSource(StringReader(xml)))
        val responses = document.getElementsByTagNameNS("*", "response")

        return buildList {
            for (index in 0 until responses.length) {
                val element = responses.item(index) as? Element ?: continue
                add(
                    DavResponse(
                        href = element.firstText("href"),
                        displayName = element.firstText("displayname"),
                        color = element.firstText("calendar-color"),
                        cTag = element.firstText("getctag"),
                        calendarData = element.firstText("calendar-data", trim = false),
                    ),
                )
            }
        }
    }

    private fun Element.firstText(localName: String, trim: Boolean = true): String? {
        val nodes = getElementsByTagNameNS("*", localName)
        if (nodes.length == 0) return null
        val value = nodes.item(0)?.textContent ?: return null
        return if (trim) value.trim().takeIf { it.isNotEmpty() } else value.takeIf { it.isNotBlank() }
    }
}
