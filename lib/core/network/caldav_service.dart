import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:logging/logging.dart';

class CalDavService {
  final String serverUrl;
  final String username;
  final String password;
  final _logger = Logger('CalDavService');

  CalDavService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  Map<String, String> get _headers {
    final basicAuth = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $basicAuth',
      'Content-Type': 'application/xml; charset=utf-8',
    };
  }

  /// PROPFIND to get the CTag representing the sync state
  Future<String?> getCTag(String calendarPath) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final requestBody = '''
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:prop>
          <cs:getctag />
        </d:prop>
      </d:propfind>
    ''';

    final request = http.Request('PROPFIND', url);
    request.headers.addAll(_headers);
    request.headers['Depth'] = '0';
    request.body = requestBody;

    final response = await http.Client().send(request);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200 || response.statusCode == 207) {
      try {
        final document = XmlDocument.parse(responseBody);
        final ctagNodes = document.findAllElements(
          'getctag',
          namespace: 'http://calendarserver.org/ns/',
        );
        if (ctagNodes.isNotEmpty) {
          return ctagNodes.first.innerText;
        }
      } catch (e) {
        _logger.warning('Failed to parse xml for ctag: $e');
      }
    } else {
      _logger.warning(
        'Failed to get CTag, status code: ${response.statusCode}',
      );
    }
    return null;
  }

  /// PROPFIND to get all calendars under a user path
  Future<List<Map<String, String>>> getCalendars(String userPath) async {
    final url = Uri.parse('$serverUrl$userPath');
    final requestBody = '''
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:ical="http://apple.com/ns/ical/">
        <d:prop>
          <d:displayname />
          <ical:calendar-color />
        </d:prop>
      </d:propfind>
    ''';

    final request = http.Request('PROPFIND', url);
    request.headers.addAll(_headers);
    request.headers['Depth'] = '1';
    request.body = requestBody;

    final response = await http.Client().send(request);
    final responseBody = await response.stream.bytesToString();
    final calendars = <Map<String, String>>[];

    if (response.statusCode == 200 || response.statusCode == 207) {
      try {
        final document = XmlDocument.parse(responseBody);
        final responses = document.findAllElements(
          'response',
          namespace: 'DAV:',
        );

        for (var node in responses) {
          final href = node
              .findElements('href', namespace: 'DAV:')
              .firstOrNull
              ?.innerText;
          // Only sync actual calendar directories, skip the root user directory
          if (href != null && href != userPath && href.endsWith('/')) {
            final displayName =
                node
                    .findAllElements('displayname', namespace: 'DAV:')
                    .firstOrNull
                    ?.innerText ??
                'Calendar';
            final color = node
                .findAllElements(
                  'calendar-color',
                  namespace: 'http://apple.com/ns/ical/',
                )
                .firstOrNull
                ?.innerText;

            calendars.add({
              'urlPath': href,
              'displayName': displayName,
              'color': color ?? '',
            });
          }
        }
      } catch (e) {
        _logger.warning('Failed to parse xml for calendars: $e');
      }
    } else {
      _logger.warning(
        'Failed to get calendars, status: ${response.statusCode}',
      );
    }
    return calendars;
  }

  /// REPORT to get all calendar events
  Future<List<String>> getCalendarEvents(String calendarPath) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final requestBody = '''
      <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <d:getetag />
          <c:calendar-data />
        </d:prop>
        <c:filter>
          <c:comp-filter name="VCALENDAR">
            <c:comp-filter name="VEVENT" />
          </c:comp-filter>
        </c:filter>
      </c:calendar-query>
    ''';

    final request = http.Request('REPORT', url);
    request.headers.addAll(_headers);
    request.headers['Depth'] = '1';
    request.body = requestBody;

    final response = await http.Client().send(request);
    final responseBody = await response.stream.bytesToString();
    final events = <String>[];

    if (response.statusCode == 200 || response.statusCode == 207) {
      try {
        final document = XmlDocument.parse(responseBody);
        final dataNodes = document.findAllElements(
          'calendar-data',
          namespace: 'urn:ietf:params:xml:ns:caldav',
        );
        for (var node in dataNodes) {
          events.add(node.innerText);
        }
      } catch (e) {
        _logger.warning('Failed to parse xml for events: $e');
      }
    } else {
      _logger.warning('Failed to get events, status: ${response.statusCode}');
    }
    return events;
  }

  /// PUT to upload or modify an event
  Future<bool> putEvent(
    String calendarPath,
    String filename,
    String icsData,
  ) async {
    final url = Uri.parse('$serverUrl$calendarPath/$filename');
    final request = http.Request('PUT', url);
    request.headers.addAll(_headers);
    request.body = icsData;

    final response = await http.Client().send(request);
    if (response.statusCode == 201 || response.statusCode == 204) {
      return true;
    }
    _logger.warning('Failed to put event, status: ${response.statusCode}');
    return false;
  }

  /// MKCALENDAR to create a new calendar collection
  Future<bool> createCalendar(String calendarPath, String displayName) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final requestBody =
        '''
      <c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:set>
          <d:prop>
            <d:displayname>$displayName</d:displayname>
          </d:prop>
        </d:set>
      </c:mkcalendar>
    ''';

    final request = http.Request('MKCALENDAR', url);
    request.headers.addAll(_headers);
    request.body = requestBody;

    final response = await http.Client().send(request);
    if (response.statusCode == 201) {
      _logger.info('Calendar created successfully at $calendarPath');
      return true;
    }
    _logger.warning(
      'Failed to create calendar, status: ${response.statusCode}',
    );
    return false;
  }

  /// PROPPATCH to update a calendar color
  Future<bool> updateCalendarColor(String calendarPath, String hexColor) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final requestBody =
        '''
      <d:propertyupdate xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
        <d:set>
          <d:prop>
            <ical:calendar-color>$hexColor</ical:calendar-color>
          </d:prop>
        </d:set>
      </d:propertyupdate>
    ''';

    final request = http.Request('PROPPATCH', url);
    request.headers.addAll(_headers);
    request.body = requestBody;

    final response = await http.Client().send(request);
    if (response.statusCode == 200 || response.statusCode == 207) {
      _logger.info('Calendar color updated successfully at $calendarPath');
      return true;
    }
    _logger.warning(
      'Failed to update calendar color, status: ${response.statusCode}',
    );
    return false;
  }

  /// PROPPATCH to update a calendar display name
  Future<bool> updateCalendarName(String calendarPath, String newName) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final requestBody =
        '''
      <d:propertyupdate xmlns:d="DAV:">
        <d:set>
          <d:prop>
            <d:displayname>$newName</d:displayname>
          </d:prop>
        </d:set>
      </d:propertyupdate>
    ''';

    final request = http.Request('PROPPATCH', url);
    request.headers.addAll(_headers);
    request.body = requestBody;

    final response = await http.Client().send(request);
    if (response.statusCode == 200 || response.statusCode == 207) {
      _logger.info(
        'Calendar display name updated successfully at $calendarPath',
      );
      return true;
    }
    _logger.warning(
      'Failed to update calendar display name, status: ${response.statusCode}',
    );
    return false;
  }

  /// DELETE to remove a calendar collection
  Future<bool> deleteCalendar(String calendarPath) async {
    final url = Uri.parse('$serverUrl$calendarPath');
    final request = http.Request('DELETE', url);
    request.headers.addAll(_headers);

    final response = await http.Client().send(request);
    if (response.statusCode == 200 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      _logger.info('Successfully deleted calendar $calendarPath on Radicale');
      return true;
    }
    _logger.warning(
      'Failed to delete calendar, status: ${response.statusCode}',
    );
    return false;
  }

  /// DELETE to remove an event
  Future<bool> deleteEvent(String calendarPath, String filename) async {
    final url = Uri.parse('$serverUrl$calendarPath/$filename');
    final request = http.Request('DELETE', url);
    request.headers.addAll(_headers);

    final response = await http.Client().send(request);
    // 200/204 means successful deletion, 404 means it's already gone on server
    if (response.statusCode == 200 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      _logger.info(
        'Successfully deleted (or verified absence of) $filename on Radicale',
      );
      return true;
    }
    _logger.warning('Failed to delete event, status: ${response.statusCode}');
    return false;
  }
}
