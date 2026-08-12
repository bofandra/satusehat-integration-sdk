package satusehat

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	_ "github.com/mattn/go-sqlite3"
	"time"
)

const ddl = `CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,idempotency_key TEXT,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT);CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL;`

type sqliteQueue struct {
	db                   *sql.DB
	processingTimeoutSec int
}

func newQueue(path string, processingTimeoutSec int) (*sqliteQueue, error) {
	db, err := sql.Open("sqlite3", path+"?_journal_mode=WAL&_busy_timeout=30000")
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec(ddl); err != nil {
		db.Close()
		return nil, err
	}
	if err = migrateQueue(db); err != nil {
		db.Close()
		return nil, err
	}
	return &sqliteQueue{db: db, processingTimeoutSec: processingTimeoutSec}, nil
}
func uuidLike() string              { b := make([]byte, 16); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func nowISO() string                { return time.Now().UTC().Format("2006-01-02T15:04:05.000000000Z") }
func (q *sqliteQueue) close() error { return q.db.Close() }
func migrateQueue(db *sql.DB) error {
	rows, err := db.Query(`PRAGMA table_info(integration_events)`)
	if err != nil {
		return err
	}
	defer rows.Close()
	hasIdempotencyKey := false
	for rows.Next() {
		var cid int
		var name, typ string
		var notnull int
		var dflt interface{}
		var pk int
		if err := rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk); err != nil {
			return err
		}
		if name == "idempotency_key" {
			hasIdempotencyKey = true
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if !hasIdempotencyKey {
		if _, err := db.Exec(`ALTER TABLE integration_events ADD COLUMN idempotency_key TEXT`); err != nil {
			return err
		}
	}
	_, err = db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL`)
	return err
}
func (q *sqliteQueue) enqueue(org, op, rt, id string, payload []byte, idempotencyKey string) (string, error) {
	op = normalizeOp(op)
	if op == "" {
		return "", fmt.Errorf("unsupported operation")
	}
	if (op == "PUT" || op == "PATCH") && id == "" {
		return "", fmt.Errorf("resource_id required for PUT/PATCH")
	}
	if payload != nil && !json.Valid(payload) {
		return "", fmt.Errorf("payload must be valid json")
	}
	if idempotencyKey != "" {
		existing, err := q.findByIdempotencyKey(org, idempotencyKey)
		if err != nil {
			return "", err
		}
		if existing != "" {
			return existing, nil
		}
	}
	eid := uuidLike()
	now := nowISO()
	_, err := q.db.Exec(`INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES(?,?,?,?,?,?,?,?,0,?,?)`, eid, org, nullStr(idempotencyKey), op, rt, nullStr(id), nullBytes(payload), string(Queued), now, now)
	if err != nil && idempotencyKey != "" {
		existing, findErr := q.findByIdempotencyKey(org, idempotencyKey)
		if findErr != nil {
			return "", findErr
		}
		if existing != "" {
			return existing, nil
		}
	}
	return eid, err
}
func (q *sqliteQueue) findByIdempotencyKey(org, key string) (string, error) {
	var eventID string
	err := q.db.QueryRow(`SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?`, org, key).Scan(&eventID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return eventID, err
}
func normalizeOp(s string) string {
	switch s {
	case "GET", "get":
		return "GET"
	case "POST", "post":
		return "POST"
	case "PUT", "put":
		return "PUT"
	case "PATCH", "patch":
		return "PATCH"
	}
	return ""
}
func nullStr(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
func nullBytes(b []byte) interface{} {
	if b == nil {
		return nil
	}
	return string(b)
}
func (q *sqliteQueue) ready(limit int) ([]Event, error) {
	now := nowISO()
	rows, err := q.db.Query(`SELECT event_id,organization_id,COALESCE(idempotency_key,''),operation,resource_type,COALESCE(resource_id,''),COALESCE(payload_json,''),status,attempt,COALESCE(error_category,''),COALESCE(error_message,''),created_at,updated_at,COALESCE(next_retry_at,'') FROM integration_events WHERE (status IN('QUEUED','RETRYING','RATE_LIMITED') AND (next_retry_at IS NULL OR next_retry_at<=?)) OR (status='PROCESSING' AND next_retry_at IS NOT NULL AND next_retry_at<=?) ORDER BY created_at LIMIT ?`, now, now, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.EventID, &e.OrganizationID, &e.IdempotencyKey, &e.Operation, &e.ResourceType, &e.ResourceID, &e.PayloadJSON, &e.Status, &e.Attempt, &e.ErrorCategory, &e.ErrorMessage, &e.CreatedAt, &e.UpdatedAt, &e.NextRetryAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
func (q *sqliteQueue) stats() (map[EventStatus]int, error) {
	out := map[EventStatus]int{
		Queued: 0, Processing: 0, Success: 0, WaitingForCorrection: 0,
		RateLimited: 0, Retrying: 0, DeadLetter: 0, Cancelled: 0,
	}
	rows, err := q.db.Query(`SELECT status,COUNT(*) FROM integration_events GROUP BY status`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var status string
		var count int
		if err := rows.Scan(&status, &count); err != nil {
			return nil, err
		}
		out[EventStatus(status)] = count
	}
	return out, rows.Err()
}
func (q *sqliteQueue) deadLetters(limit int) ([]Event, error) {
	rows, err := q.db.Query(`SELECT event_id,organization_id,COALESCE(idempotency_key,''),operation,resource_type,COALESCE(resource_id,''),COALESCE(payload_json,''),status,attempt,http_status,COALESCE(error_category,''),COALESCE(error_message,''),created_at,updated_at,COALESCE(next_retry_at,'') FROM integration_events WHERE status=? ORDER BY updated_at DESC LIMIT ?`, string(DeadLetter), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.EventID, &e.OrganizationID, &e.IdempotencyKey, &e.Operation, &e.ResourceType, &e.ResourceID, &e.PayloadJSON, &e.Status, &e.Attempt, &e.HTTPStatus, &e.ErrorCategory, &e.ErrorMessage, &e.CreatedAt, &e.UpdatedAt, &e.NextRetryAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
func (q *sqliteQueue) requeue(id string) (bool, error) {
	r, err := q.db.Exec(`UPDATE integration_events SET status=?,attempt=0,http_status=NULL,error_category=NULL,error_message=NULL,updated_at=?,next_retry_at=NULL WHERE event_id=? AND status IN (?,?,?)`, string(Queued), nowISO(), id, string(DeadLetter), string(WaitingForCorrection), string(Cancelled))
	if err != nil {
		return false, err
	}
	n, err := r.RowsAffected()
	return n > 0, err
}
func (q *sqliteQueue) markProcessing(id string) (int, error) {
	now := nowISO()
	leaseUntil := time.Now().UTC().Add(time.Duration(q.processingTimeoutSec) * time.Second).Format("2006-01-02T15:04:05.000000000Z")
	if _, err := q.db.Exec(`UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=?,next_retry_at=? WHERE event_id=?`, now, leaseUntil, id); err != nil {
		return 0, err
	}
	var a int
	err := q.db.QueryRow(`SELECT attempt FROM integration_events WHERE event_id=?`, id).Scan(&a)
	return a, err
}
func (q *sqliteQueue) complete(id string, status EventStatus, httpStatus *int, cat, msg, next string) error {
	if len(msg) > 2000 {
		msg = msg[:2000]
	}
	_, err := q.db.Exec(`UPDATE integration_events SET status=?,http_status=?,error_category=?,error_message=?,updated_at=?,next_retry_at=? WHERE event_id=?`, string(status), httpStatus, nullStr(cat), nullStr(msg), nowISO(), nullStr(next), id)
	return err
}
