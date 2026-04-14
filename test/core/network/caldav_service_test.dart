import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frelsi_cal/core/network/caldav_service.dart';

/// Helper to build a CalDavService with a MockClient.
CalDavService _buildService(MockClient client) {
  return CalDavService(
    serverUrl: 'https://dav.example.com',
    username: 'testuser',
    password: 'testpass',
    client: client,
  );
}

/// Helper to create a MockClient that returns a streamed response.
MockClient _mockClient(int statusCode, String body) {
  return MockClient.streaming((request, _) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
    );
  });
}

void main() {
  group('auth header', () {
    test('sends correct Basic auth header', () async {
      String? capturedAuth;
      final client = MockClient.streaming((request, _) async {
        capturedAuth = request.headers['authorization'];
        return http.StreamedResponse(
          Stream.value(utf8.encode('')),
          207,
        );
      });
      final svc = _buildService(client);
      await svc.getCTag('/cal/');
      final expected =
          'Basic ${base64Encode(utf8.encode('testuser:testpass'))}';
      expect(capturedAuth, expected);
    });
  });

  group('getCTag', () {
    test('returns CTag from valid 207 response', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:propstat>
      <d:prop>
        <cs:getctag>abc123</cs:getctag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';
      final svc = _buildService(_mockClient(207, xml));
      final result = await svc.getCTag('/user/cal/');
      expect(result, 'abc123');
    });

    test('returns null on non-207 status', () async {
      final svc = _buildService(_mockClient(401, 'Unauthorized'));
      expect(await svc.getCTag('/cal/'), isNull);
    });

    test('returns null on malformed XML', () async {
      final svc = _buildService(_mockClient(207, '<not-valid-xml'));
      expect(await svc.getCTag('/cal/'), isNull);
    });
  });

  group('getCalendars', () {
    test('parses calendars from 207 multistatus', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/">
  <d:response>
    <d:href>/user/</d:href>
    <d:propstat>
      <d:prop><d:displayname>User Root</d:displayname></d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/user/personal/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Personal</d:displayname>
        <ical:calendar-color>#FF0000</ical:calendar-color>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/user/work/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Work</d:displayname>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';
      final svc = _buildService(_mockClient(207, xml));
      final result = await svc.getCalendars('/user/');

      expect(result.length, 2);
      expect(result[0]['urlPath'], '/user/personal/');
      expect(result[0]['displayName'], 'Personal');
      expect(result[0]['color'], '#FF0000');
      expect(result[1]['urlPath'], '/user/work/');
      expect(result[1]['displayName'], 'Work');
      expect(result[1]['color'], '');
    });

    test('skips root user path href', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/user/</d:href>
    <d:propstat><d:prop><d:displayname>Root</d:displayname></d:prop></d:propstat>
  </d:response>
</d:multistatus>''';
      final svc = _buildService(_mockClient(207, xml));
      expect(await svc.getCalendars('/user/'), isEmpty);
    });

    test('returns empty list on error status', () async {
      final svc = _buildService(_mockClient(500, 'Error'));
      expect(await svc.getCalendars('/user/'), isEmpty);
    });
  });

  group('getCalendarEvents', () {
    test('extracts ICS strings from calendar-data nodes', () async {
      const ics1 = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Event1\nEND:VEVENT\nEND:VCALENDAR';
      const ics2 = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Event2\nEND:VEVENT\nEND:VCALENDAR';
      final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:propstat>
      <d:prop>
        <c:calendar-data>$ics1</c:calendar-data>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:propstat>
      <d:prop>
        <c:calendar-data>$ics2</c:calendar-data>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>''';
      final svc = _buildService(_mockClient(207, xml));
      final result = await svc.getCalendarEvents('/user/cal/');
      expect(result.length, 2);
      expect(result[0], contains('Event1'));
      expect(result[1], contains('Event2'));
    });

    test('returns empty list on error status', () async {
      final svc = _buildService(_mockClient(403, 'Forbidden'));
      expect(await svc.getCalendarEvents('/cal/'), isEmpty);
    });
  });

  group('putEvent', () {
    test('returns true on 201', () async {
      final svc = _buildService(_mockClient(201, ''));
      expect(await svc.putEvent('/cal/', 'ev.ics', 'data'), isTrue);
    });

    test('returns true on 204', () async {
      final svc = _buildService(_mockClient(204, ''));
      expect(await svc.putEvent('/cal/', 'ev.ics', 'data'), isTrue);
    });

    test('returns false on 400', () async {
      final svc = _buildService(_mockClient(400, 'Bad Request'));
      expect(await svc.putEvent('/cal/', 'ev.ics', 'data'), isFalse);
    });
  });

  group('createCalendar', () {
    test('returns true on 201', () async {
      final svc = _buildService(_mockClient(201, ''));
      expect(await svc.createCalendar('/user/new/', 'New Cal'), isTrue);
    });

    test('returns false on 409 conflict', () async {
      final svc = _buildService(_mockClient(409, 'Conflict'));
      expect(await svc.createCalendar('/user/new/', 'New Cal'), isFalse);
    });
  });

  group('updateCalendarColor', () {
    test('returns true on 207', () async {
      final svc = _buildService(_mockClient(207, ''));
      expect(await svc.updateCalendarColor('/cal/', '#00FF00'), isTrue);
    });

    test('returns false on 403', () async {
      final svc = _buildService(_mockClient(403, 'Forbidden'));
      expect(await svc.updateCalendarColor('/cal/', '#00FF00'), isFalse);
    });
  });

  group('updateCalendarName', () {
    test('returns true on 207', () async {
      final svc = _buildService(_mockClient(207, ''));
      expect(await svc.updateCalendarName('/cal/', 'Renamed'), isTrue);
    });

    test('returns false on 500', () async {
      final svc = _buildService(_mockClient(500, 'Error'));
      expect(await svc.updateCalendarName('/cal/', 'Renamed'), isFalse);
    });
  });

  group('deleteCalendar', () {
    test('returns true on 204', () async {
      final svc = _buildService(_mockClient(204, ''));
      expect(await svc.deleteCalendar('/cal/'), isTrue);
    });

    test('returns true on 404 (already gone)', () async {
      final svc = _buildService(_mockClient(404, ''));
      expect(await svc.deleteCalendar('/cal/'), isTrue);
    });

    test('returns false on 500', () async {
      final svc = _buildService(_mockClient(500, 'Error'));
      expect(await svc.deleteCalendar('/cal/'), isFalse);
    });
  });

  group('deleteEvent', () {
    test('returns true on 204', () async {
      final svc = _buildService(_mockClient(204, ''));
      expect(await svc.deleteEvent('/cal/', 'ev.ics'), isTrue);
    });

    test('returns true on 404 (already gone)', () async {
      final svc = _buildService(_mockClient(404, ''));
      expect(await svc.deleteEvent('/cal/', 'ev.ics'), isTrue);
    });

    test('returns false on 500', () async {
      final svc = _buildService(_mockClient(500, 'Error'));
      expect(await svc.deleteEvent('/cal/', 'ev.ics'), isFalse);
    });
  });

  group('close', () {
    test('closes the underlying client', () {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(Stream.value([]), 200);
      });
      final svc = CalDavService(
        serverUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
        client: client,
      );
      // MockClient doesn't track close, but calling it should not throw
      expect(() => svc.close(), returnsNormally);
    });
  });
}
