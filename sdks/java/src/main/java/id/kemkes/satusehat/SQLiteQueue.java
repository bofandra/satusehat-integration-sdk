package id.kemkes.satusehat;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.Types;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

final class SQLiteQueue implements AutoCloseable {
    record Event(String eventId, String idempotencyKey, String operation, String resourceType, String resourceId, String payloadJson, int attempt) {}

    private final Connection db;
    private final int processingTimeoutSeconds;

    SQLiteQueue(String path, int processingTimeoutSeconds) throws Exception {
        Class.forName("org.sqlite.JDBC");
        this.processingTimeoutSeconds = processingTimeoutSeconds;
        db = DriverManager.getConnection("jdbc:sqlite:" + path);
        try (var s = db.createStatement()) {
            s.execute("PRAGMA journal_mode=WAL");
            s.execute("CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,idempotency_key TEXT,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT)");
            s.execute("CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at)");
        }
        migrate();
    }

    private void migrate() throws Exception {
        boolean hasIdempotencyKey = false;
        try (var r = db.createStatement().executeQuery("PRAGMA table_info(integration_events)")) {
            while (r.next()) {
                if ("idempotency_key".equals(r.getString("name"))) {
                    hasIdempotencyKey = true;
                }
            }
        }
        try (var s = db.createStatement()) {
            if (!hasIdempotencyKey) {
                s.execute("ALTER TABLE integration_events ADD COLUMN idempotency_key TEXT");
            }
            s.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL");
        }
    }

    String enqueue(String org, String op, String rt, String id, String payload, String idempotencyKey) throws Exception {
        op = op.toUpperCase();
        if (!Set.of("GET", "POST", "PUT", "PATCH").contains(op)) {
            throw new IllegalArgumentException("unsupported operation");
        }
        if (Set.of("PUT", "PATCH").contains(op) && (id == null || id.isBlank())) {
            throw new IllegalArgumentException("resourceId required for PUT/PATCH");
        }
        idempotencyKey = (idempotencyKey == null || idempotencyKey.isBlank()) ? null : idempotencyKey.trim();
        if (idempotencyKey != null) {
            String existing = findByIdempotencyKey(org, idempotencyKey);
            if (existing != null) {
                return existing;
            }
        }

        String eid = UUID.randomUUID().toString();
        String n = now();
        try (PreparedStatement p = db.prepareStatement("INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES(?,?,?,?,?,?,?,?,0,?,?)")) {
            p.setString(1, eid);
            p.setString(2, org);
            p.setString(3, idempotencyKey);
            p.setString(4, op);
            p.setString(5, rt);
            p.setString(6, id);
            p.setString(7, payload);
            p.setString(8, EventStatus.QUEUED.name());
            p.setString(9, n);
            p.setString(10, n);
            p.executeUpdate();
        } catch (java.sql.SQLException ex) {
            if (idempotencyKey != null) {
                String existing = findByIdempotencyKey(org, idempotencyKey);
                if (existing != null) {
                    return existing;
                }
            }
            throw ex;
        }
        return eid;
    }

    private String findByIdempotencyKey(String org, String idempotencyKey) throws Exception {
        try (PreparedStatement p = db.prepareStatement("SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?")) {
            p.setString(1, org);
            p.setString(2, idempotencyKey);
            try (var r = p.executeQuery()) {
                return r.next() ? r.getString(1) : null;
            }
        }
    }

    List<Event> ready(int limit) throws Exception {
        var out = new ArrayList<Event>();
        String n = now();
        try (PreparedStatement p = db.prepareStatement("SELECT event_id,idempotency_key,operation,resource_type,resource_id,payload_json,attempt FROM integration_events WHERE (status IN ('QUEUED','RETRYING','RATE_LIMITED') AND (next_retry_at IS NULL OR next_retry_at<=?)) OR (status='PROCESSING' AND next_retry_at IS NOT NULL AND next_retry_at<=?) ORDER BY created_at LIMIT ?")) {
            p.setString(1, n);
            p.setString(2, n);
            p.setInt(3, limit);
            try (var r = p.executeQuery()) {
                while (r.next()) {
                    out.add(new Event(r.getString(1), r.getString(2), r.getString(3), r.getString(4), r.getString(5), r.getString(6), r.getInt(7)));
                }
            }
        }
        return out;
    }

    int markProcessing(String id) throws Exception {
        String n = now();
        String leaseUntil = Instant.now().plus(processingTimeoutSeconds, ChronoUnit.SECONDS).toString();
        try (PreparedStatement p = db.prepareStatement("UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=?,next_retry_at=? WHERE event_id=?")) {
            p.setString(1, n);
            p.setString(2, leaseUntil);
            p.setString(3, id);
            p.executeUpdate();
        }
        try (PreparedStatement p = db.prepareStatement("SELECT attempt FROM integration_events WHERE event_id=?")) {
            p.setString(1, id);
            try (var r = p.executeQuery()) {
                r.next();
                return r.getInt(1);
            }
        }
    }

    void complete(String id, EventStatus status, Integer http, String cat, String msg, String next) throws Exception {
        if (msg != null && msg.length() > 2000) {
            msg = msg.substring(0, 2000);
        }
        try (PreparedStatement p = db.prepareStatement("UPDATE integration_events SET status=?,http_status=?,error_category=?,error_message=?,updated_at=?,next_retry_at=? WHERE event_id=?")) {
            p.setString(1, status.name());
            if (http == null) {
                p.setNull(2, Types.INTEGER);
            } else {
                p.setInt(2, http);
            }
            p.setString(3, cat);
            p.setString(4, msg);
            p.setString(5, now());
            p.setString(6, next);
            p.setString(7, id);
            p.executeUpdate();
        }
    }

    Map<EventStatus, Integer> stats() throws Exception {
        var out = new EnumMap<EventStatus, Integer>(EventStatus.class);
        for (EventStatus status : EventStatus.values()) {
            out.put(status, 0);
        }
        try (var r = db.createStatement().executeQuery("SELECT status,COUNT(*) FROM integration_events GROUP BY status")) {
            while (r.next()) {
                out.put(EventStatus.valueOf(r.getString(1)), r.getInt(2));
            }
        }
        return out;
    }

    List<QueueRecord> deadLetters(int limit) throws Exception {
        var out = new ArrayList<QueueRecord>();
        try (PreparedStatement p = db.prepareStatement("SELECT event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,http_status,error_category,error_message,created_at,updated_at,next_retry_at FROM integration_events WHERE status=? ORDER BY updated_at DESC LIMIT ?")) {
            p.setString(1, EventStatus.DEAD_LETTER.name());
            p.setInt(2, limit);
            try (var r = p.executeQuery()) {
                while (r.next()) {
                    Integer httpStatus = r.getObject(10) == null ? null : r.getInt(10);
                    out.add(new QueueRecord(
                        r.getString(1), r.getString(2), r.getString(3), r.getString(4),
                        r.getString(5), r.getString(6), r.getString(7), EventStatus.valueOf(r.getString(8)),
                        r.getInt(9), httpStatus, r.getString(11), r.getString(12),
                        r.getString(13), r.getString(14), r.getString(15)
                    ));
                }
            }
        }
        return out;
    }

    boolean requeue(String id) throws Exception {
        try (PreparedStatement p = db.prepareStatement("UPDATE integration_events SET status=?,attempt=0,http_status=NULL,error_category=NULL,error_message=NULL,updated_at=?,next_retry_at=NULL WHERE event_id=? AND status IN (?,?,?)")) {
            p.setString(1, EventStatus.QUEUED.name());
            p.setString(2, now());
            p.setString(3, id);
            p.setString(4, EventStatus.DEAD_LETTER.name());
            p.setString(5, EventStatus.WAITING_FOR_CORRECTION.name());
            p.setString(6, EventStatus.CANCELLED.name());
            return p.executeUpdate() > 0;
        }
    }

    @Override
    public void close() throws Exception {
        db.close();
    }

    private static String now() {
        return Instant.now().toString();
    }
}
