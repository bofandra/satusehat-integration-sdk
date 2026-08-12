using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Satusehat.IntegrationSdk;

internal sealed class SQLiteQueue : IAsyncDisposable
{
    private readonly SqliteConnection db;
    private readonly int processingTimeoutSeconds;

    public SQLiteQueue(string path, int processingTimeoutSeconds = 300)
    {
        this.processingTimeoutSeconds = processingTimeoutSeconds;
        db = new SqliteConnection($"Data Source={path}");
        db.Open();

        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS integration_events(
                event_id TEXT PRIMARY KEY,
                organization_id TEXT NOT NULL,
                idempotency_key TEXT,
                operation TEXT NOT NULL,
                resource_type TEXT NOT NULL,
                resource_id TEXT,
                payload_json TEXT,
                status TEXT NOT NULL,
                attempt INTEGER NOT NULL DEFAULT 0,
                http_status INTEGER,
                error_category TEXT,
                error_message TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                next_retry_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_integration_events_ready
            ON integration_events(status,next_retry_at,created_at);
            """;
        cmd.ExecuteNonQuery();
        Migrate();
    }

    private void Migrate()
    {
        var columns = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var c = db.CreateCommand())
        {
            c.CommandText = "PRAGMA table_info(integration_events)";
            using var r = c.ExecuteReader();
            while (r.Read())
            {
                columns.Add(r.GetString(1));
            }
        }
        if (!columns.Contains("idempotency_key"))
        {
            using var alter = db.CreateCommand();
            alter.CommandText = "ALTER TABLE integration_events ADD COLUMN idempotency_key TEXT";
            alter.ExecuteNonQuery();
        }
        using var index = db.CreateCommand();
        index.CommandText = "CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL";
        index.ExecuteNonQuery();
    }

    public string Enqueue(string org, string op, string rt, string? id, string? payload, string? idempotencyKey = null)
    {
        op = op.ToUpperInvariant();
        if (op != "GET" && op != "POST" && op != "PUT" && op != "PATCH")
        {
            throw new ArgumentException("unsupported operation");
        }
        if ((op == "PUT" || op == "PATCH") && string.IsNullOrWhiteSpace(id))
        {
            throw new ArgumentException("resourceId required for PUT/PATCH");
        }
        if (payload is not null)
        {
            JsonDocument.Parse(payload).Dispose();
        }

        idempotencyKey = string.IsNullOrWhiteSpace(idempotencyKey) ? null : idempotencyKey.Trim();
        if (idempotencyKey is not null)
        {
            var existing = FindByIdempotencyKey(org, idempotencyKey);
            if (existing is not null)
            {
                return existing;
            }
        }

        var eid = Guid.NewGuid().ToString();
        var n = Now();
        try
        {
            using var c = db.CreateCommand();
            c.CommandText = "INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES($e,$o,$k,$op,$rt,$id,$p,'QUEUED',0,$n,$n)";
            c.Parameters.AddWithValue("$e", eid);
            c.Parameters.AddWithValue("$o", org);
            c.Parameters.AddWithValue("$k", (object?)idempotencyKey ?? DBNull.Value);
            c.Parameters.AddWithValue("$op", op);
            c.Parameters.AddWithValue("$rt", rt);
            c.Parameters.AddWithValue("$id", (object?)id ?? DBNull.Value);
            c.Parameters.AddWithValue("$p", (object?)payload ?? DBNull.Value);
            c.Parameters.AddWithValue("$n", n);
            c.ExecuteNonQuery();
        }
        catch (SqliteException)
        {
            if (idempotencyKey is not null)
            {
                var existing = FindByIdempotencyKey(org, idempotencyKey);
                if (existing is not null)
                {
                    return existing;
                }
            }
            throw;
        }
        return eid;
    }

    private string? FindByIdempotencyKey(string org, string idempotencyKey)
    {
        using var c = db.CreateCommand();
        c.CommandText = "SELECT event_id FROM integration_events WHERE organization_id=$o AND idempotency_key=$k";
        c.Parameters.AddWithValue("$o", org);
        c.Parameters.AddWithValue("$k", idempotencyKey);
        return c.ExecuteScalar() as string;
    }

    public List<QueueEvent> Ready(int limit)
    {
        var outp = new List<QueueEvent>();
        var n = Now();
        using var c = db.CreateCommand();
        c.CommandText = """
            SELECT event_id,operation,resource_type,resource_id,payload_json,attempt
            FROM integration_events
            WHERE (
                status IN ('QUEUED','RETRYING','RATE_LIMITED')
                AND (next_retry_at IS NULL OR next_retry_at <= $n)
            ) OR (
                status = 'PROCESSING'
                AND next_retry_at IS NOT NULL
                AND next_retry_at <= $n
            )
            ORDER BY created_at
            LIMIT $l
            """;
        c.Parameters.AddWithValue("$n", n);
        c.Parameters.AddWithValue("$l", limit);
        using var r = c.ExecuteReader();
        while (r.Read())
        {
            outp.Add(new QueueEvent(
                r.GetString(0),
                r.GetString(1),
                r.GetString(2),
                r.IsDBNull(3) ? null : r.GetString(3),
                r.IsDBNull(4) ? null : r.GetString(4),
                r.GetInt32(5)));
        }
        return outp;
    }

    public int MarkProcessing(string id)
    {
        using (var c = db.CreateCommand())
        {
            c.CommandText = "UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=$n,next_retry_at=$r WHERE event_id=$e";
            c.Parameters.AddWithValue("$n", Now());
            c.Parameters.AddWithValue("$r", Format(DateTimeOffset.UtcNow.AddSeconds(processingTimeoutSeconds)));
            c.Parameters.AddWithValue("$e", id);
            c.ExecuteNonQuery();
        }

        using var q = db.CreateCommand();
        q.CommandText = "SELECT attempt FROM integration_events WHERE event_id=$e";
        q.Parameters.AddWithValue("$e", id);
        return Convert.ToInt32(q.ExecuteScalar());
    }

    public void Complete(string id, EventStatus status, int? http = null, string? cat = null, string? msg = null, string? next = null)
    {
        using var c = db.CreateCommand();
        c.CommandText = "UPDATE integration_events SET status=$s,http_status=$h,error_category=$c,error_message=$m,updated_at=$n,next_retry_at=$r WHERE event_id=$e";
        c.Parameters.AddWithValue("$s", status.ToString());
        c.Parameters.AddWithValue("$h", (object?)http ?? DBNull.Value);
        c.Parameters.AddWithValue("$c", (object?)cat ?? DBNull.Value);
        c.Parameters.AddWithValue("$m", (object?)(msg is null ? null : msg[..Math.Min(2000, msg.Length)]) ?? DBNull.Value);
        c.Parameters.AddWithValue("$n", Now());
        c.Parameters.AddWithValue("$r", (object?)next ?? DBNull.Value);
        c.Parameters.AddWithValue("$e", id);
        c.ExecuteNonQuery();
    }

    public IReadOnlyDictionary<EventStatus, int> Stats()
    {
        var outp = Enum.GetValues<EventStatus>().ToDictionary(status => status, _ => 0);
        using var c = db.CreateCommand();
        c.CommandText = "SELECT status,COUNT(*) FROM integration_events GROUP BY status";
        using var r = c.ExecuteReader();
        while (r.Read())
        {
            outp[Enum.Parse<EventStatus>(r.GetString(0))] = r.GetInt32(1);
        }
        return outp;
    }

    public List<QueueRecord> DeadLetters(int limit)
    {
        var outp = new List<QueueRecord>();
        using var c = db.CreateCommand();
        c.CommandText = "SELECT event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,http_status,error_category,error_message,created_at,updated_at,next_retry_at FROM integration_events WHERE status=$s ORDER BY updated_at DESC LIMIT $l";
        c.Parameters.AddWithValue("$s", EventStatus.DEAD_LETTER.ToString());
        c.Parameters.AddWithValue("$l", limit);
        using var r = c.ExecuteReader();
        while (r.Read())
        {
            outp.Add(new QueueRecord(
                r.GetString(0),
                r.GetString(1),
                r.IsDBNull(2) ? null : r.GetString(2),
                r.GetString(3),
                r.GetString(4),
                r.IsDBNull(5) ? null : r.GetString(5),
                r.IsDBNull(6) ? null : r.GetString(6),
                Enum.Parse<EventStatus>(r.GetString(7)),
                r.GetInt32(8),
                r.IsDBNull(9) ? null : r.GetInt32(9),
                r.IsDBNull(10) ? null : r.GetString(10),
                r.IsDBNull(11) ? null : r.GetString(11),
                r.GetString(12),
                r.GetString(13),
                r.IsDBNull(14) ? null : r.GetString(14)));
        }
        return outp;
    }

    public bool Requeue(string id)
    {
        using var c = db.CreateCommand();
        c.CommandText = "UPDATE integration_events SET status='QUEUED',attempt=0,http_status=NULL,error_category=NULL,error_message=NULL,updated_at=$n,next_retry_at=NULL WHERE event_id=$e AND status IN ('DEAD_LETTER','WAITING_FOR_CORRECTION','CANCELLED')";
        c.Parameters.AddWithValue("$n", Now());
        c.Parameters.AddWithValue("$e", id);
        return c.ExecuteNonQuery() > 0;
    }

    public async ValueTask DisposeAsync() => await db.DisposeAsync();

    private static string Now() => Format(DateTimeOffset.UtcNow);

    private static string Format(DateTimeOffset value) =>
        value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", CultureInfo.InvariantCulture);
}
