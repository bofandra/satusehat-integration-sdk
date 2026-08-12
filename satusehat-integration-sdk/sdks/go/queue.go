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

const ddl = `CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT);CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);`

type sqliteQueue struct{ db *sql.DB }

func newQueue(path string) (*sqliteQueue, error) {
	db, err := sql.Open("sqlite3", path+"?_journal_mode=WAL&_busy_timeout=30000")
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec(ddl); err != nil {
		db.Close()
		return nil, err
	}
	return &sqliteQueue{db: db}, nil
}
func uuidLike() string              { b := make([]byte, 16); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func nowISO() string                { return time.Now().UTC().Format(time.RFC3339Nano) }
func (q *sqliteQueue) close() error { return q.db.Close() }
func (q *sqliteQueue) enqueue(org, op, rt, id string, payload []byte) (string, error) {
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
	eid := uuidLike()
	now := nowISO()
	_, err := q.db.Exec(`INSERT INTO integration_events(event_id,organization_id,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES(?,?,?,?,?,?,?,0,?,?)`, eid, org, op, rt, nullStr(id), nullBytes(payload), string(Queued), now, now)
	return eid, err
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
	rows, err := q.db.Query(`SELECT event_id,organization_id,operation,resource_type,COALESCE(resource_id,''),COALESCE(payload_json,''),status,attempt,COALESCE(error_category,''),COALESCE(error_message,''),created_at,updated_at,COALESCE(next_retry_at,'') FROM integration_events WHERE status IN('QUEUED','RETRYING','RATE_LIMITED') AND (next_retry_at IS NULL OR next_retry_at<=?) ORDER BY created_at LIMIT ?`, nowISO(), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.EventID, &e.OrganizationID, &e.Operation, &e.ResourceType, &e.ResourceID, &e.PayloadJSON, &e.Status, &e.Attempt, &e.ErrorCategory, &e.ErrorMessage, &e.CreatedAt, &e.UpdatedAt, &e.NextRetryAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
func (q *sqliteQueue) markProcessing(id string) (int, error) {
	if _, err := q.db.Exec(`UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=? WHERE event_id=?`, nowISO(), id); err != nil {
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
