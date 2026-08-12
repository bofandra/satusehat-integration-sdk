package id.kemkes.satusehat;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.Files;
import org.junit.jupiter.api.Test;

class ErrorClassifierTest {
    @Test void classifiesSuccess() {
        var result = ErrorClassifier.classify(201);
        assertEquals("success", result.category());
        assertFalse(result.retryable());
    }

    @Test void classifiesRateLimitAsRetryable() {
        var result = ErrorClassifier.classify(429);
        assertEquals("rate_limited", result.category());
        assertTrue(result.retryable());
    }

    @Test void classifiesValidationAsNonRetryable() {
        var result = ErrorClassifier.classify(422);
        assertEquals("validation_error", result.category());
        assertFalse(result.retryable());
    }

    @Test void recoversStaleProcessingEvents() throws Exception {
        var db = Files.createTempFile("ss-sdk-", ".db");
        try (var q = new SQLiteQueue(db.toString(), 300)) {
            var id = q.enqueue("1", "POST", "Encounter", null, "{\"resourceType\":\"Encounter\"}", null);
            q.markProcessing(id);
            assertEquals(0, q.ready(10).size());
        }
        try (var conn = java.sql.DriverManager.getConnection("jdbc:sqlite:" + db)) {
            try (var p = conn.prepareStatement("UPDATE integration_events SET next_retry_at=? WHERE event_id IS NOT NULL")) {
                p.setString(1, "2000-01-01T00:00:00Z");
                p.executeUpdate();
            }
        }
        try (var q = new SQLiteQueue(db.toString(), 300)) {
            assertEquals(1, q.ready(10).size());
        }
    }

    @Test void idempotentEnqueueReturnsExistingEvent() throws Exception {
        var db = Files.createTempFile("ss-sdk-", ".db");
        try (var q = new SQLiteQueue(db.toString(), 300)) {
            var first = q.enqueue("1", "POST", "Encounter", null, "{\"resourceType\":\"Encounter\"}", "visit-1:create");
            var second = q.enqueue("1", "POST", "Encounter", null, "{\"resourceType\":\"Encounter\"}", "visit-1:create");
            assertEquals(first, second);
            assertEquals(1, q.stats().get(EventStatus.QUEUED));
        }
    }

    @Test void deadLetterAdminRequeue() throws Exception {
        var db = Files.createTempFile("ss-sdk-", ".db");
        try (var q = new SQLiteQueue(db.toString(), 300)) {
            var id = q.enqueue("1", "POST", "Encounter", null, "{\"resourceType\":\"Encounter\"}", null);
            q.complete(id, EventStatus.DEAD_LETTER, 503, "server_error", "failed", null);
            assertEquals(id, q.deadLetters(10).get(0).eventId());
            assertTrue(q.requeue(id));
            assertEquals(1, q.stats().get(EventStatus.QUEUED));
            assertEquals(0, q.stats().get(EventStatus.DEAD_LETTER));
        }
    }
}
