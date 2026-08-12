<?php
namespace Satusehat\IntegrationSdk;

final class SQLiteQueue {
    private \PDO $db;

    public function __construct(string $path, private int $processingTimeoutSeconds = 300) {
        $this->db = new \PDO('sqlite:'.$path, null, null, [\PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION]);
        $this->db->exec("PRAGMA journal_mode=WAL;CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,idempotency_key TEXT,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT);CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);");
        $this->migrate();
    }

    private function migrate(): void {
        $columns = array_map(fn($row) => $row['name'], $this->db->query('PRAGMA table_info(integration_events)')->fetchAll(\PDO::FETCH_ASSOC));
        if (!in_array('idempotency_key', $columns, true)) {
            $this->db->exec('ALTER TABLE integration_events ADD COLUMN idempotency_key TEXT');
        }
        $this->db->exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL');
    }

    private function now(): string {
        return gmdate('Y-m-d\TH:i:s\Z');
    }

    public function enqueue(string $org, string $op, string $rt, ?string $id, ?string $payload, ?string $idempotencyKey = null): string {
        $op = strtoupper($op);
        if (!in_array($op, ['GET', 'POST', 'PUT', 'PATCH'], true)) {
            throw new \InvalidArgumentException('unsupported operation');
        }
        if (in_array($op, ['PUT', 'PATCH'], true) && !$id) {
            throw new \InvalidArgumentException('resourceId required for PUT/PATCH');
        }
        if ($payload !== null) {
            json_decode($payload, true, 512, JSON_THROW_ON_ERROR);
        }
        $idempotencyKey = $idempotencyKey !== null && trim($idempotencyKey) !== '' ? trim($idempotencyKey) : null;
        if ($idempotencyKey !== null) {
            $existing = $this->findByIdempotencyKey($org, $idempotencyKey);
            if ($existing !== null) {
                return $existing;
            }
        }

        $eid = $this->uuid();
        $n = $this->now();
        try {
            $p = $this->db->prepare('INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES(?,?,?,?,?,?,?,?,0,?,?)');
            $p->execute([$eid, $org, $idempotencyKey, $op, $rt, $id, $payload, EventStatus::QUEUED->value, $n, $n]);
        } catch (\PDOException $e) {
            if ($idempotencyKey !== null) {
                $existing = $this->findByIdempotencyKey($org, $idempotencyKey);
                if ($existing !== null) {
                    return $existing;
                }
            }
            throw $e;
        }
        return $eid;
    }

    private function findByIdempotencyKey(string $org, string $key): ?string {
        $p = $this->db->prepare('SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?');
        $p->execute([$org, $key]);
        $value = $p->fetchColumn();
        return $value === false ? null : (string)$value;
    }

    public function ready(int $limit): array {
        $n = $this->now();
        $p = $this->db->prepare("SELECT * FROM integration_events WHERE (status IN ('QUEUED','RETRYING','RATE_LIMITED') AND (next_retry_at IS NULL OR next_retry_at<=?)) OR (status='PROCESSING' AND next_retry_at IS NOT NULL AND next_retry_at<=?) ORDER BY created_at LIMIT ?");
        $p->bindValue(1, $n);
        $p->bindValue(2, $n);
        $p->bindValue(3, $limit, \PDO::PARAM_INT);
        $p->execute();
        return $p->fetchAll(\PDO::FETCH_ASSOC);
    }

    public function markProcessing(string $id): int {
        $this->db->prepare("UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=?,next_retry_at=? WHERE event_id=?")->execute([$this->now(), gmdate('Y-m-d\TH:i:s\Z', time() + $this->processingTimeoutSeconds), $id]);
        $p = $this->db->prepare('SELECT attempt FROM integration_events WHERE event_id=?');
        $p->execute([$id]);
        return (int)$p->fetchColumn();
    }

    public function complete(string $id, EventStatus $status, ?int $http = null, ?string $cat = null, ?string $msg = null, ?string $next = null): void {
        $this->db->prepare('UPDATE integration_events SET status=?,http_status=?,error_category=?,error_message=?,updated_at=?,next_retry_at=? WHERE event_id=?')->execute([$status->value, $http, $cat, $msg ? substr($msg, 0, 2000) : null, $this->now(), $next, $id]);
    }

    public function get(string $id): array|false {
        $p = $this->db->prepare('SELECT * FROM integration_events WHERE event_id=?');
        $p->execute([$id]);
        return $p->fetch(\PDO::FETCH_ASSOC);
    }

    public function stats(): array {
        $out = [];
        foreach (EventStatus::cases() as $status) {
            $out[$status->value] = 0;
        }
        foreach ($this->db->query('SELECT status,COUNT(*) AS n FROM integration_events GROUP BY status') as $row) {
            $out[(string)$row['status']] = (int)$row['n'];
        }
        return $out;
    }

    public function deadLetters(int $limit = 50): array {
        $p = $this->db->prepare('SELECT * FROM integration_events WHERE status=? ORDER BY updated_at DESC LIMIT ?');
        $p->bindValue(1, EventStatus::DEAD_LETTER->value);
        $p->bindValue(2, $limit, \PDO::PARAM_INT);
        $p->execute();
        return $p->fetchAll(\PDO::FETCH_ASSOC);
    }

    public function requeue(string $id): bool {
        $p = $this->db->prepare('UPDATE integration_events SET status=?,attempt=0,http_status=NULL,error_category=NULL,error_message=NULL,updated_at=?,next_retry_at=NULL WHERE event_id=? AND status IN (?,?,?)');
        $p->execute([EventStatus::QUEUED->value, $this->now(), $id, EventStatus::DEAD_LETTER->value, EventStatus::WAITING_FOR_CORRECTION->value, EventStatus::CANCELLED->value]);
        return $p->rowCount() > 0;
    }

    private function uuid(): string {
        $d = random_bytes(16);
        $d[6] = chr((ord($d[6]) & 0x0f) | 0x40);
        $d[8] = chr((ord($d[8]) & 0x3f) | 0x80);
        $h = bin2hex($d);
        return substr($h, 0, 8).'-'.substr($h, 8, 4).'-'.substr($h, 12, 4).'-'.substr($h, 16, 4).'-'.substr($h, 20);
    }
}
