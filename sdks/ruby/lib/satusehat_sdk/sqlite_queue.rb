require "fileutils"
require "json"
require "securerandom"
require "sqlite3"
require "time"

module Satusehat
    module IntegrationSdk
        class SQLiteQueue
            DDL = <<~SQL
                PRAGMA journal_mode=WAL;
                PRAGMA foreign_keys=ON;
                CREATE TABLE IF NOT EXISTS integration_events(
                    event_id TEXT PRIMARY KEY,
                    organization_id TEXT NOT NULL,
                    idempotency_key TEXT,
                    operation TEXT NOT NULL CHECK(operation IN ('GET','POST','PUT','PATCH')),
                    resource_type TEXT NOT NULL,
                    resource_id TEXT,
                    payload_json TEXT,
                    status TEXT NOT NULL CHECK(status IN ('QUEUED','PROCESSING','SUCCESS','WAITING_FOR_CORRECTION','RATE_LIMITED','RETRYING','DEAD_LETTER','CANCELLED')),
                    attempt INTEGER NOT NULL DEFAULT 0,
                    http_status INTEGER,
                    error_category TEXT,
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    next_retry_at TEXT,
                    correlation_id TEXT,
                    parent_event_id TEXT,
                    revision INTEGER NOT NULL DEFAULT 1,
                    source_system TEXT,
                    source_record_id TEXT,
                    disposition TEXT,
                    error_details_json TEXT,
                    completed_at TEXT,
                    superseded_by_event_id TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);
                CREATE INDEX IF NOT EXISTS idx_integration_events_resource ON integration_events(resource_type,resource_id);
                CREATE INDEX IF NOT EXISTS idx_integration_events_correlation ON integration_events(correlation_id,revision);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency
                    ON integration_events(organization_id,idempotency_key)
                    WHERE idempotency_key IS NOT NULL;
                CREATE TABLE IF NOT EXISTS integration_event_history(
                    history_id TEXT PRIMARY KEY,
                    event_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    attempt INTEGER NOT NULL DEFAULT 0,
                    http_status INTEGER,
                    error_category TEXT,
                    error_message TEXT,
                    observed_updated_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE(event_id,status,attempt,observed_updated_at)
                );
                CREATE INDEX IF NOT EXISTS idx_event_history_event ON integration_event_history(event_id,created_at);
                CREATE TABLE IF NOT EXISTS integration_notifications(
                    notification_id TEXT PRIMARY KEY,
                    event_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    destination TEXT,
                    payload_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    attempt INTEGER NOT NULL DEFAULT 0,
                    http_status INTEGER,
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    next_retry_at TEXT,
                    delivered_at TEXT,
                    UNIQUE(event_id,event_type)
                );
                CREATE INDEX IF NOT EXISTS idx_notifications_ready ON integration_notifications(status,next_retry_at,created_at);
            SQL

            MIGRATION_COLUMNS = {
                "idempotency_key" => "TEXT",
                "correlation_id" => "TEXT",
                "parent_event_id" => "TEXT",
                "revision" => "INTEGER NOT NULL DEFAULT 1",
                "source_system" => "TEXT",
                "source_record_id" => "TEXT",
                "disposition" => "TEXT",
                "error_details_json" => "TEXT",
                "completed_at" => "TEXT",
                "superseded_by_event_id" => "TEXT"
            }.freeze

            attr_reader :db

            def initialize(path, processing_timeout_seconds = 300)
                FileUtils.mkdir_p(File.dirname(path)) unless path == ":memory:"
                @processing_timeout_seconds = processing_timeout_seconds
                @db = SQLite3::Database.new(path)
                @db.results_as_hash = true
                @db.busy_timeout = 30_000
                @db.execute_batch(DDL)
                migrate
            end

            def close
                @db.close
            end

            def enqueue(organization_id, operation, resource_type, resource_id, payload, idempotency_key = nil)
                operation = operation.to_s.upcase
                validate_operation!(operation, resource_id)
                idempotency_key = normalize_idempotency_key(idempotency_key)

                existing = find_by_idempotency_key(organization_id, idempotency_key) if idempotency_key
                return existing if existing

                event_id = SecureRandom.uuid
                now = self.class.utcnow
                payload_json = serialize_payload(payload)

                begin
                    @db.execute(
                        <<~SQL,
                            INSERT INTO integration_events(
                                event_id,organization_id,idempotency_key,operation,resource_type,resource_id,
                                payload_json,status,attempt,created_at,updated_at,correlation_id,revision
                            ) VALUES(?,?,?,?,?,?,?,?,0,?,?,?,1)
                        SQL
                        [event_id, organization_id, idempotency_key, operation, resource_type, resource_id, payload_json, EventStatus::QUEUED, now, now, event_id]
                    )
                rescue SQLite3::ConstraintException
                    existing = find_by_idempotency_key(organization_id, idempotency_key) if idempotency_key
                    return existing if existing

                    raise
                end

                event_id
            end

            def ready(limit)
                now = self.class.utcnow
                @db.execute(
                    <<~SQL,
                        SELECT * FROM integration_events
                        WHERE (
                            status IN ('QUEUED','RETRYING','RATE_LIMITED')
                            AND (next_retry_at IS NULL OR next_retry_at <= ?)
                        ) OR (
                            status = 'PROCESSING'
                            AND next_retry_at IS NOT NULL
                            AND next_retry_at <= ?
                        )
                        ORDER BY created_at LIMIT ?
                    SQL
                    [now, now, limit]
                )
            end

            def mark_processing(event_id)
                now = self.class.utcnow
                lease_until = (Time.now.utc + @processing_timeout_seconds).iso8601(6)
                @db.execute(
                    "UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=?,next_retry_at=? WHERE event_id=?",
                    [now, lease_until, event_id]
                )
                row = get(event_id)
                row["attempt"].to_i
            end

            def complete(event_id, status, http_status = nil, category = nil, message = nil, next_retry_at = nil)
                updated_at = self.class.utcnow
                completed_at = EventStatus::TERMINAL.include?(status) ? updated_at : nil
                @db.execute(
                    <<~SQL,
                        UPDATE integration_events
                        SET status=?, http_status=?, error_category=?, error_message=?,
                            updated_at=?, next_retry_at=?, completed_at=?
                        WHERE event_id=?
                    SQL
                    [status, http_status, category, truncate(message), updated_at, next_retry_at, completed_at, event_id]
                )
            end

            def get(event_id)
                @db.get_first_row("SELECT * FROM integration_events WHERE event_id=?", [event_id])
            end

            def stats
                out = {}
                EventStatus::ALL.each { |status| out[status] = 0 }
                @db.execute("SELECT status, COUNT(*) AS n FROM integration_events GROUP BY status").each do |row|
                    out[row["status"]] = row["n"].to_i
                end
                out
            end

            def dead_letters(limit = 50)
                @db.execute(
                    "SELECT * FROM integration_events WHERE status=? ORDER BY updated_at DESC LIMIT ?",
                    [EventStatus::DEAD_LETTER, limit]
                )
            end

            def requeue(event_id)
                @db.execute(
                    <<~SQL,
                        UPDATE integration_events
                        SET status=?, attempt=0, http_status=NULL, error_category=NULL, error_message=NULL,
                            error_details_json=NULL, updated_at=?, next_retry_at=NULL, completed_at=NULL, disposition=NULL
                        WHERE event_id=? AND status IN (?,?,?) AND superseded_by_event_id IS NULL
                    SQL
                    [
                        EventStatus::QUEUED,
                        self.class.utcnow,
                        event_id,
                        EventStatus::DEAD_LETTER,
                        EventStatus::WAITING_FOR_CORRECTION,
                        EventStatus::CANCELLED
                    ]
                )
                @db.changes.positive?
            end

            def self.utcnow
                Time.now.utc.iso8601(6)
            end

            private

            def migrate
                columns = @db.execute("PRAGMA table_info(integration_events)").map { |row| row["name"] }
                MIGRATION_COLUMNS.each do |name, type|
                    @db.execute("ALTER TABLE integration_events ADD COLUMN #{name} #{type}") unless columns.include?(name)
                end
                @db.execute_batch(DDL)
                @db.execute("UPDATE integration_events SET correlation_id=event_id WHERE correlation_id IS NULL OR correlation_id=''")
                @db.execute("UPDATE integration_events SET revision=1 WHERE revision IS NULL OR revision<1")
            end

            def validate_operation!(operation, resource_id)
                raise ArgumentError, "unsupported operation" unless %w[GET POST PUT PATCH].include?(operation)

                if %w[PUT PATCH].include?(operation) && (resource_id.nil? || resource_id.to_s.empty?)
                    raise ArgumentError, "resource_id is required for PUT/PATCH"
                end
            end

            def normalize_idempotency_key(key)
                return nil if key.nil?

                key = key.to_s.strip
                key.empty? ? nil : key
            end

            def serialize_payload(payload)
                return nil if payload.nil?

                if payload.is_a?(String)
                    JSON.parse(payload)
                    payload
                else
                    JSON.generate(payload)
                end
            end

            def find_by_idempotency_key(organization_id, idempotency_key)
                row = @db.get_first_row(
                    "SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?",
                    [organization_id, idempotency_key]
                )
                row && row["event_id"]
            end

            def truncate(value)
                return nil if value.nil?

                value.to_s[0, 2000]
            end
        end
    end
end
