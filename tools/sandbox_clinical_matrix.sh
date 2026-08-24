#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/satusehat-clinical-matrix.$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

missing=()
for name in \
  SATUSEHAT_CLIENT_ID \
  SATUSEHAT_CLIENT_SECRET \
  SATUSEHAT_ORGANIZATION_ID \
  SATUSEHAT_SANDBOX_PATIENT_ID \
  SATUSEHAT_SANDBOX_PATIENT_NAME \
  SATUSEHAT_SANDBOX_PRACTITIONER_ID \
  SATUSEHAT_SANDBOX_PRACTITIONER_NAME; do
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'missing required environment variables: %s\n' "${missing[*]}" >&2
  exit 1
fi

export SATUSEHAT_ENV="${SATUSEHAT_ENV:-sandbox}"
export SDK_ROOT="$ROOT"

if [ "$SATUSEHAT_ENV" != "sandbox" ]; then
  printf 'sandbox_clinical_matrix must run with SATUSEHAT_ENV=sandbox\n' >&2
  exit 1
fi

node_bin="${NODE_BIN:-node}"
go_bin="${GO_BIN:-go}"
php_bin="${PHP_BIN:-php}"
java_bin="${JAVA_BIN:-java}"
javac_bin="${JAVAC_BIN:-javac}"
dotnet_bin="${DOTNET_BIN:-dotnet}"

sqlite_jdbc="${JAVA_SQLITE_JDBC_JAR:-}"
if [ -z "$sqlite_jdbc" ]; then
  sqlite_jdbc="$(find /private/tmp/satusehat-m2 "$HOME/.m2/repository" -name 'sqlite-jdbc-*.jar' 2>/dev/null | sort | tail -n 1 || true)"
fi
slf4j_api="${JAVA_SLF4J_API_JAR:-}"
if [ -z "$slf4j_api" ]; then
  slf4j_api="$(find /private/tmp/satusehat-m2 "$HOME/.m2/repository" -name 'slf4j-api-*.jar' 2>/dev/null | sort | tail -n 1 || true)"
fi

failures=0

run_step() {
  platform="$1"
  shift
  printf '\n== %s ==\n' "$platform"
  if "$@"; then
    printf 'PASS %s\n' "$platform"
  else
    status=$?
    printf 'FAIL %s exit=%s\n' "$platform" "$status" >&2
    failures=$((failures + 1))
  fi
}

run_python() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/python.db"
  PYTHONPATH="$ROOT/sdks/python/src" python - <<'PY'
import json
import os
import sys
import time
from datetime import datetime, timezone
from satusehat_sdk import SatusehatConfig, SatusehatSdk

cfg = SatusehatConfig.from_env()
sdk = SatusehatSdk(cfg)
unique = f"SDKCLIN-PY-{int(time.time())}"
patient_id = os.environ["SATUSEHAT_SANDBOX_PATIENT_ID"]
patient_name = os.environ["SATUSEHAT_SANDBOX_PATIENT_NAME"]
practitioner_id = os.environ["SATUSEHAT_SANDBOX_PRACTITIONER_ID"]
practitioner_name = os.environ["SATUSEHAT_SANDBOX_PRACTITIONER_NAME"]
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
created = {}

def post(resource_type, payload):
    response = sdk.request("POST", resource_type, payload=payload)
    body = json.loads(response.body) if response.body else {}
    result = {"resource": resource_type, "http_status": response.status_code, "resourceType": body.get("resourceType"), "id": body.get("id")}
    if response.status_code < 200 or response.status_code > 299:
        result["issues"] = body.get("issue", [])[:4]
    print(json.dumps(result, indent=2))
    if response.status_code < 200 or response.status_code > 299:
        raise SystemExit(1)
    created[resource_type] = body["id"]
    return body["id"]

try:
    location_id = post("Location", {
        "resourceType": "Location",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/location/{cfg.organization_id}", "value": f"{unique}-LOC"}],
        "status": "active",
        "name": f"SDK Sandbox Test Room {unique}",
        "description": "Non-PHI SDK sandbox test location",
        "mode": "instance",
        "physicalType": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/location-physical-type", "code": "ro", "display": "Room"}]},
        "managingOrganization": {"reference": f"Organization/{cfg.organization_id}"},
    })
    encounter_id = post("Encounter", {
        "resourceType": "Encounter",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/encounter/{cfg.organization_id}", "value": f"{unique}-ENC"}],
        "status": "arrived",
        "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "AMB", "display": "ambulatory"},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "participant": [{"type": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ParticipationType", "code": "ATND", "display": "attender"}]}], "individual": {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name}}],
        "period": {"start": now},
        "location": [{"location": {"reference": f"Location/{location_id}", "display": f"SDK Sandbox Test Room {unique}"}}],
        "statusHistory": [{"status": "arrived", "period": {"start": now}}],
        "serviceProvider": {"reference": f"Organization/{cfg.organization_id}"},
    })
    post("Condition", {
        "resourceType": "Condition",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/condition/{cfg.organization_id}", "value": f"{unique}-COND"}],
        "clinicalStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-clinical", "code": "active", "display": "Active"}]},
        "verificationStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed", "display": "Confirmed"}]},
        "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-category", "code": "encounter-diagnosis", "display": "Encounter Diagnosis"}]}],
        "code": {"coding": [{"system": "http://hl7.org/fhir/sid/icd-10", "code": "Z00.0", "display": "General medical examination"}]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "encounter": {"reference": f"Encounter/{encounter_id}"},
        "onsetDateTime": now,
        "recordedDate": now,
        "recorder": {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name},
        "asserter": {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name},
    })
    post("Observation", {
        "resourceType": "Observation",
        "status": "final",
        "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "vital-signs", "display": "Vital Signs"}]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"}]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "encounter": {"reference": f"Encounter/{encounter_id}"},
        "effectiveDateTime": now,
        "issued": now,
        "performer": [{"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name}],
        "valueQuantity": {"value": 80, "unit": "{beats}/min", "system": "http://unitsofmeasure.org", "code": "{beats}/min"},
    })
    print(json.dumps({"platform": "python", "created": created}, indent=2))
finally:
    sdk.close()
PY
}

run_node() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/node.db"
  "$node_bin" --input-type=module - <<'JS'
import { pathToFileURL } from 'node:url';

const { SatusehatConfig, SatusehatSdk } = await import(pathToFileURL(`${process.env.SDK_ROOT}/sdks/node/src/index.js`).href);
const cfg = SatusehatConfig.fromEnv();
const sdk = new SatusehatSdk(cfg);
const unique = `SDKCLIN-NODE-${Math.floor(Date.now() / 1000)}`;
const patientId = process.env.SATUSEHAT_SANDBOX_PATIENT_ID;
const patientName = process.env.SATUSEHAT_SANDBOX_PATIENT_NAME;
const practitionerId = process.env.SATUSEHAT_SANDBOX_PRACTITIONER_ID;
const practitionerName = process.env.SATUSEHAT_SANDBOX_PRACTITIONER_NAME;
const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const created = {};

async function post(resourceType, payload) {
  const response = await sdk.request('POST', resourceType, undefined, payload);
  const body = response.body ? JSON.parse(response.body) : {};
  const result = { resource: resourceType, http_status: response.statusCode, resourceType: body.resourceType, id: body.id };
  if (response.statusCode < 200 || response.statusCode > 299) result.issues = (body.issue ?? []).slice(0, 4);
  console.log(JSON.stringify(result, null, 2));
  if (response.statusCode < 200 || response.statusCode > 299) process.exit(1);
  created[resourceType] = body.id;
  return body.id;
}

try {
  const locationId = await post('Location', {
    resourceType: 'Location',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/location/${cfg.organizationId}`, value: `${unique}-LOC` }],
    status: 'active',
    name: `SDK Sandbox Test Room ${unique}`,
    description: 'Non-PHI SDK sandbox test location',
    mode: 'instance',
    physicalType: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/location-physical-type', code: 'ro', display: 'Room' }] },
    managingOrganization: { reference: `Organization/${cfg.organizationId}` },
  });
  const encounterId = await post('Encounter', {
    resourceType: 'Encounter',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/encounter/${cfg.organizationId}`, value: `${unique}-ENC` }],
    status: 'arrived',
    class: { system: 'http://terminology.hl7.org/CodeSystem/v3-ActCode', code: 'AMB', display: 'ambulatory' },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    participant: [{ type: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/v3-ParticipationType', code: 'ATND', display: 'attender' }] }], individual: { reference: `Practitioner/${practitionerId}`, display: practitionerName } }],
    period: { start: now },
    location: [{ location: { reference: `Location/${locationId}`, display: `SDK Sandbox Test Room ${unique}` } }],
    statusHistory: [{ status: 'arrived', period: { start: now } }],
    serviceProvider: { reference: `Organization/${cfg.organizationId}` },
  });
  await post('Condition', {
    resourceType: 'Condition',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/condition/${cfg.organizationId}`, value: `${unique}-COND` }],
    clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-clinical', code: 'active', display: 'Active' }] },
    verificationStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-ver-status', code: 'confirmed', display: 'Confirmed' }] },
    category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-category', code: 'encounter-diagnosis', display: 'Encounter Diagnosis' }] }],
    code: { coding: [{ system: 'http://hl7.org/fhir/sid/icd-10', code: 'Z00.0', display: 'General medical examination' }] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    encounter: { reference: `Encounter/${encounterId}` },
    onsetDateTime: now,
    recordedDate: now,
    recorder: { reference: `Practitioner/${practitionerId}`, display: practitionerName },
    asserter: { reference: `Practitioner/${practitionerId}`, display: practitionerName },
  });
  await post('Observation', {
    resourceType: 'Observation',
    status: 'final',
    category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: 'vital-signs', display: 'Vital Signs' }] }],
    code: { coding: [{ system: 'http://loinc.org', code: '8867-4', display: 'Heart rate' }] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    encounter: { reference: `Encounter/${encounterId}` },
    effectiveDateTime: now,
    issued: now,
    performer: [{ reference: `Practitioner/${practitionerId}`, display: practitionerName }],
    valueQuantity: { value: 80, unit: '{beats}/min', system: 'http://unitsofmeasure.org', code: '{beats}/min' },
  });
  console.log(JSON.stringify({ platform: 'node', created }, null, 2));
} finally {
  sdk.close();
}
JS
}

run_go() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/go.db"
  go_dir="$TMP_ROOT/go-live"
  mkdir -p "$go_dir"
  cat > "$go_dir/go.mod" <<EOF
module satusehat-clinical-live

go 1.23

require github.com/bofandra/satusehat-integration-sdk/sdks/go v0.0.0

replace github.com/bofandra/satusehat-integration-sdk/sdks/go => $ROOT/sdks/go
EOF
  cat > "$go_dir/main.go" <<'GO'
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	satusehat "github.com/bofandra/satusehat-integration-sdk/sdks/go"
)

func post(ctx context.Context, sdk *satusehat.SDK, resourceType string, payload map[string]any) (string, error) {
	raw, _ := json.Marshal(payload)
	response, err := sdk.Request(ctx, "POST", resourceType, "", raw)
	if err != nil {
		return "", err
	}
	var body map[string]any
	_ = json.Unmarshal(response.Body, &body)
	result := map[string]any{"resource": resourceType, "http_status": response.StatusCode, "resourceType": body["resourceType"], "id": body["id"]}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		result["issues"] = body["issue"]
	}
	out, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(out))
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return "", fmt.Errorf("%s HTTP %d", resourceType, response.StatusCode)
	}
	id, _ := body["id"].(string)
	return id, nil
}

func main() {
	cfg, err := satusehat.ConfigFromEnv()
	if err != nil {
		panic(err)
	}
	sdk, err := satusehat.New(cfg)
	if err != nil {
		panic(err)
	}
	defer sdk.Close()
	ctx := context.Background()
	unique := fmt.Sprintf("SDKCLIN-GO-%d", time.Now().Unix())
	patientID := os.Getenv("SATUSEHAT_SANDBOX_PATIENT_ID")
	patientName := os.Getenv("SATUSEHAT_SANDBOX_PATIENT_NAME")
	practitionerID := os.Getenv("SATUSEHAT_SANDBOX_PRACTITIONER_ID")
	practitionerName := os.Getenv("SATUSEHAT_SANDBOX_PRACTITIONER_NAME")
	now := time.Now().UTC().Truncate(time.Second).Format(time.RFC3339)
	created := map[string]string{}

	locationID, err := post(ctx, sdk, "Location", map[string]any{
		"resourceType": "Location",
		"identifier":   []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/location/" + cfg.OrganizationID, "value": unique + "-LOC"}},
		"status":       "active",
		"name":         "SDK Sandbox Test Room " + unique,
		"description":  "Non-PHI SDK sandbox test location",
		"mode":         "instance",
		"physicalType": map[string]any{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/location-physical-type", "code": "ro", "display": "Room"}}},
		"managingOrganization": map[string]string{"reference": "Organization/" + cfg.OrganizationID},
	})
	if err != nil {
		panic(err)
	}
	created["Location"] = locationID
	encounterID, err := post(ctx, sdk, "Encounter", map[string]any{
		"resourceType":  "Encounter",
		"identifier":    []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/encounter/" + cfg.OrganizationID, "value": unique + "-ENC"}},
		"status":        "arrived",
		"class":         map[string]string{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "AMB", "display": "ambulatory"},
		"subject":       map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"participant":   []map[string]any{{"type": []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/v3-ParticipationType", "code": "ATND", "display": "attender"}}}}, "individual": map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName}}},
		"period":        map[string]string{"start": now},
		"location":      []map[string]any{{"location": map[string]string{"reference": "Location/" + locationID, "display": "SDK Sandbox Test Room " + unique}}},
		"statusHistory": []map[string]any{{"status": "arrived", "period": map[string]string{"start": now}}},
		"serviceProvider": map[string]string{"reference": "Organization/" + cfg.OrganizationID},
	})
	if err != nil {
		panic(err)
	}
	created["Encounter"] = encounterID
	conditionID, err := post(ctx, sdk, "Condition", map[string]any{
		"resourceType":        "Condition",
		"identifier":          []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/condition/" + cfg.OrganizationID, "value": unique + "-COND"}},
		"clinicalStatus":      map[string]any{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/condition-clinical", "code": "active", "display": "Active"}}},
		"verificationStatus":  map[string]any{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed", "display": "Confirmed"}}},
		"category":            []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/condition-category", "code": "encounter-diagnosis", "display": "Encounter Diagnosis"}}}},
		"code":                map[string]any{"coding": []map[string]string{{"system": "http://hl7.org/fhir/sid/icd-10", "code": "Z00.0", "display": "General medical examination"}}},
		"subject":             map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"encounter":           map[string]string{"reference": "Encounter/" + encounterID},
		"onsetDateTime":       now,
		"recordedDate":        now,
		"recorder":            map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName},
		"asserter":            map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName},
	})
	if err != nil {
		panic(err)
	}
	created["Condition"] = conditionID
	observationID, err := post(ctx, sdk, "Observation", map[string]any{
		"resourceType":       "Observation",
		"status":             "final",
		"category":           []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "vital-signs", "display": "Vital Signs"}}}},
		"code":               map[string]any{"coding": []map[string]string{{"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"}}},
		"subject":            map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"encounter":          map[string]string{"reference": "Encounter/" + encounterID},
		"effectiveDateTime":  now,
		"issued":             now,
		"performer":          []map[string]string{{"reference": "Practitioner/" + practitionerID, "display": practitionerName}},
		"valueQuantity":      map[string]any{"value": 80, "unit": "{beats}/min", "system": "http://unitsofmeasure.org", "code": "{beats}/min"},
	})
	if err != nil {
		panic(err)
	}
	created["Observation"] = observationID
	out, _ := json.MarshalIndent(map[string]any{"platform": "go", "created": created}, "", "  ")
	fmt.Println(string(out))
}
GO
  (cd "$go_dir" && GOTOOLCHAIN=local "$go_bin" mod tidy >/dev/null && GOTOOLCHAIN=local "$go_bin" run .)
}

run_java() {
  if [ -z "$sqlite_jdbc" ] || [ ! -f "$sqlite_jdbc" ]; then
    printf 'sqlite-jdbc jar not found; run Java tests once to populate Maven cache or set JAVA_SQLITE_JDBC_JAR\n' >&2
    return 1
  fi
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/java.db"
  java_dir="$TMP_ROOT/java-live"
  mkdir -p "$java_dir"
  cat > "$java_dir/LiveClinical.java" <<'JAVA'
import id.kemkes.satusehat.*;
import java.time.*;
import java.util.*;
import java.util.regex.*;

public class LiveClinical {
  static String value(String body, String key) {
    var m = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"").matcher(body);
    return m.find() ? m.group(1) : null;
  }

  static String esc(String value) {
    return value.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  static String post(SatusehatSdk sdk, String resourceType, String payload) throws Exception {
    var response = sdk.request("POST", resourceType, null, payload);
    var id = value(response.body(), "id");
    System.out.println("{\"resource\":\"" + resourceType + "\",\"http_status\":" + response.statusCode() + ",\"resourceType\":\"" + value(response.body(), "resourceType") + "\",\"id\":\"" + id + "\"}");
    if (response.statusCode() < 200 || response.statusCode() > 299) {
      System.err.println(response.body());
      System.exit(1);
    }
    return id;
  }

  public static void main(String[] args) throws Exception {
    var cfg = SatusehatConfig.fromEnv();
    var patientId = System.getenv("SATUSEHAT_SANDBOX_PATIENT_ID");
    var patientName = esc(System.getenv("SATUSEHAT_SANDBOX_PATIENT_NAME"));
    var practitionerId = System.getenv("SATUSEHAT_SANDBOX_PRACTITIONER_ID");
    var practitionerName = esc(System.getenv("SATUSEHAT_SANDBOX_PRACTITIONER_NAME"));
    var unique = "SDKCLIN-JAVA-" + (System.currentTimeMillis() / 1000);
    var now = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString();
    try (var sdk = new SatusehatSdk(cfg)) {
      var locationId = post(sdk, "Location", """
        {"resourceType":"Location","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/location/%s","value":"%s-LOC"}],"status":"active","name":"SDK Sandbox Test Room %s","description":"Non-PHI SDK sandbox test location","mode":"instance","physicalType":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/location-physical-type","code":"ro","display":"Room"}]},"managingOrganization":{"reference":"Organization/%s"}}
        """.formatted(cfg.organizationId(), unique, unique, cfg.organizationId()));
      var encounterId = post(sdk, "Encounter", """
        {"resourceType":"Encounter","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/encounter/%s","value":"%s-ENC"}],"status":"arrived","class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"AMB","display":"ambulatory"},"subject":{"reference":"Patient/%s","display":"%s"},"participant":[{"type":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ParticipationType","code":"ATND","display":"attender"}]}],"individual":{"reference":"Practitioner/%s","display":"%s"}}],"period":{"start":"%s"},"location":[{"location":{"reference":"Location/%s","display":"SDK Sandbox Test Room %s"}}],"statusHistory":[{"status":"arrived","period":{"start":"%s"}}],"serviceProvider":{"reference":"Organization/%s"}}
        """.formatted(cfg.organizationId(), unique, patientId, patientName, practitionerId, practitionerName, now, locationId, unique, now, cfg.organizationId()));
      var conditionId = post(sdk, "Condition", """
        {"resourceType":"Condition","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/condition/%s","value":"%s-COND"}],"clinicalStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/condition-clinical","code":"active","display":"Active"}]},"verificationStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/condition-ver-status","code":"confirmed","display":"Confirmed"}]},"category":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/condition-category","code":"encounter-diagnosis","display":"Encounter Diagnosis"}]}],"code":{"coding":[{"system":"http://hl7.org/fhir/sid/icd-10","code":"Z00.0","display":"General medical examination"}]},"subject":{"reference":"Patient/%s","display":"%s"},"encounter":{"reference":"Encounter/%s"},"onsetDateTime":"%s","recordedDate":"%s","recorder":{"reference":"Practitioner/%s","display":"%s"},"asserter":{"reference":"Practitioner/%s","display":"%s"}}
        """.formatted(cfg.organizationId(), unique, patientId, patientName, encounterId, now, now, practitionerId, practitionerName, practitionerId, practitionerName));
      var observationId = post(sdk, "Observation", """
        {"resourceType":"Observation","status":"final","category":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/observation-category","code":"vital-signs","display":"Vital Signs"}]}],"code":{"coding":[{"system":"http://loinc.org","code":"8867-4","display":"Heart rate"}]},"subject":{"reference":"Patient/%s","display":"%s"},"encounter":{"reference":"Encounter/%s"},"effectiveDateTime":"%s","issued":"%s","performer":[{"reference":"Practitioner/%s","display":"%s"}],"valueQuantity":{"value":80,"unit":"{beats}/min","system":"http://unitsofmeasure.org","code":"{beats}/min"}}
        """.formatted(patientId, patientName, encounterId, now, now, practitionerId, practitionerName));
      System.out.println("{\"platform\":\"java\",\"created\":{\"Location\":\"" + locationId + "\",\"Encounter\":\"" + encounterId + "\",\"Condition\":\"" + conditionId + "\",\"Observation\":\"" + observationId + "\"}}");
    }
  }
}
JAVA
  cp_value="$java_dir:$ROOT/sdks/java/target/classes:$sqlite_jdbc"
  if [ -n "$slf4j_api" ] && [ -f "$slf4j_api" ]; then
    cp_value="$cp_value:$slf4j_api"
  fi
  "$javac_bin" -cp "$cp_value" "$java_dir/LiveClinical.java" &&
    "$java_bin" -cp "$cp_value" LiveClinical
}

run_php() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/php.db"
  "$php_bin" <<'PHP'
<?php
$root = getenv('SDK_ROOT');
require $root . '/sdks/php/src/Config.php';
require $root . '/sdks/php/src/EventStatus.php';
require $root . '/sdks/php/src/ErrorClassifier.php';
require $root . '/sdks/php/src/SQLiteQueue.php';
require $root . '/sdks/php/src/TokenProvider.php';
require $root . '/sdks/php/src/FhirClient.php';
require $root . '/sdks/php/src/SatusehatSdk.php';

use Satusehat\IntegrationSdk\Config;
use Satusehat\IntegrationSdk\SatusehatSdk;

$cfg = Config::fromEnv();
$sdk = new SatusehatSdk($cfg);
$unique = 'SDKCLIN-PHP-' . time();
$patientId = getenv('SATUSEHAT_SANDBOX_PATIENT_ID');
$patientName = getenv('SATUSEHAT_SANDBOX_PATIENT_NAME');
$practitionerId = getenv('SATUSEHAT_SANDBOX_PRACTITIONER_ID');
$practitionerName = getenv('SATUSEHAT_SANDBOX_PRACTITIONER_NAME');
$now = gmdate('Y-m-d\TH:i:s\Z');
$created = [];

function postResource(SatusehatSdk $sdk, array &$created, string $resourceType, array $payload): string {
    $response = $sdk->request('POST', $resourceType, null, json_encode($payload, JSON_UNESCAPED_SLASHES));
    $body = json_decode($response['body'] ?? '{}', true) ?: [];
    $result = ['resource' => $resourceType, 'http_status' => $response['statusCode'], 'resourceType' => $body['resourceType'] ?? null, 'id' => $body['id'] ?? null];
    if ($response['statusCode'] < 200 || $response['statusCode'] > 299) {
        $result['issues'] = array_slice($body['issue'] ?? [], 0, 4);
    }
    echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    if ($response['statusCode'] < 200 || $response['statusCode'] > 299) {
        exit(1);
    }
    $created[$resourceType] = $body['id'];
    return $body['id'];
}

$locationId = postResource($sdk, $created, 'Location', [
  'resourceType' => 'Location',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/location/' . $cfg->organizationId, 'value' => $unique . '-LOC']],
  'status' => 'active',
  'name' => 'SDK Sandbox Test Room ' . $unique,
  'description' => 'Non-PHI SDK sandbox test location',
  'mode' => 'instance',
  'physicalType' => ['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/location-physical-type', 'code' => 'ro', 'display' => 'Room']]],
  'managingOrganization' => ['reference' => 'Organization/' . $cfg->organizationId],
]);
$encounterId = postResource($sdk, $created, 'Encounter', [
  'resourceType' => 'Encounter',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/encounter/' . $cfg->organizationId, 'value' => $unique . '-ENC']],
  'status' => 'arrived',
  'class' => ['system' => 'http://terminology.hl7.org/CodeSystem/v3-ActCode', 'code' => 'AMB', 'display' => 'ambulatory'],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'participant' => [['type' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/v3-ParticipationType', 'code' => 'ATND', 'display' => 'attender']]]], 'individual' => ['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName]]],
  'period' => ['start' => $now],
  'location' => [['location' => ['reference' => 'Location/' . $locationId, 'display' => 'SDK Sandbox Test Room ' . $unique]]],
  'statusHistory' => [['status' => 'arrived', 'period' => ['start' => $now]]],
  'serviceProvider' => ['reference' => 'Organization/' . $cfg->organizationId],
]);
postResource($sdk, $created, 'Condition', [
  'resourceType' => 'Condition',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/condition/' . $cfg->organizationId, 'value' => $unique . '-COND']],
  'clinicalStatus' => ['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/condition-clinical', 'code' => 'active', 'display' => 'Active']]],
  'verificationStatus' => ['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/condition-ver-status', 'code' => 'confirmed', 'display' => 'Confirmed']]],
  'category' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/condition-category', 'code' => 'encounter-diagnosis', 'display' => 'Encounter Diagnosis']]]],
  'code' => ['coding' => [['system' => 'http://hl7.org/fhir/sid/icd-10', 'code' => 'Z00.0', 'display' => 'General medical examination']]],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'encounter' => ['reference' => 'Encounter/' . $encounterId],
  'onsetDateTime' => $now,
  'recordedDate' => $now,
  'recorder' => ['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName],
  'asserter' => ['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName],
]);
postResource($sdk, $created, 'Observation', [
  'resourceType' => 'Observation',
  'status' => 'final',
  'category' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/observation-category', 'code' => 'vital-signs', 'display' => 'Vital Signs']]]],
  'code' => ['coding' => [['system' => 'http://loinc.org', 'code' => '8867-4', 'display' => 'Heart rate']]],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'encounter' => ['reference' => 'Encounter/' . $encounterId],
  'effectiveDateTime' => $now,
  'issued' => $now,
  'performer' => [['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName]],
  'valueQuantity' => ['value' => 80, 'unit' => '{beats}/min', 'system' => 'http://unitsofmeasure.org', 'code' => '{beats}/min'],
]);
echo json_encode(['platform' => 'php', 'created' => $created], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
PHP
}

run_dotnet() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/dotnet.db"
  dotnet_dir="$TMP_ROOT/dotnet-live"
  mkdir -p "$dotnet_dir"
  cat > "$dotnet_dir/LiveClinical.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$ROOT/sdks/dotnet/Satusehat.IntegrationSdk.csproj" />
  </ItemGroup>
</Project>
EOF
  cat > "$dotnet_dir/Program.cs" <<'CS'
using System.Text.Json;
using Satusehat.IntegrationSdk;

var cfg = SatusehatConfig.FromEnvironment();
await using var sdk = new SatusehatSdk(cfg);
var unique = $"SDKCLIN-DOTNET-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
var patientId = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PATIENT_ID")!;
var patientName = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PATIENT_NAME")!;
var practitionerId = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PRACTITIONER_ID")!;
var practitionerName = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PRACTITIONER_NAME")!;
var now = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", System.Globalization.CultureInfo.InvariantCulture);
var created = new Dictionary<string, string>();

async Task<string> Post(string resourceType, object payload)
{
    var response = await sdk.RequestAsync("POST", resourceType, payload: JsonSerializer.Serialize(payload));
    using var doc = JsonDocument.Parse(response.Body);
    var root = doc.RootElement;
    string? prop(string name) => root.TryGetProperty(name, out var value) ? value.GetString() : null;
    var result = new Dictionary<string, object?> { ["resource"] = resourceType, ["http_status"] = response.StatusCode, ["resourceType"] = prop("resourceType"), ["id"] = prop("id") };
    if (response.StatusCode is < 200 or > 299 && root.TryGetProperty("issue", out var issues))
    {
        result["issues"] = issues.Clone();
    }
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    if (response.StatusCode is < 200 or > 299) Environment.Exit(1);
    var id = prop("id")!;
    created[resourceType] = id;
    return id;
}

var locationId = await Post("Location", new
{
    resourceType = "Location",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/location/{cfg.OrganizationId}", value = $"{unique}-LOC" } },
    status = "active",
    name = $"SDK Sandbox Test Room {unique}",
    description = "Non-PHI SDK sandbox test location",
    mode = "instance",
    physicalType = new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/location-physical-type", code = "ro", display = "Room" } } },
    managingOrganization = new { reference = $"Organization/{cfg.OrganizationId}" }
});
var encounterId = await Post("Encounter", new
{
    resourceType = "Encounter",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/encounter/{cfg.OrganizationId}", value = $"{unique}-ENC" } },
    status = "arrived",
    @class = new { system = "http://terminology.hl7.org/CodeSystem/v3-ActCode", code = "AMB", display = "ambulatory" },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    participant = new[] { new { type = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/v3-ParticipationType", code = "ATND", display = "attender" } } } }, individual = new { reference = $"Practitioner/{practitionerId}", display = practitionerName } } },
    period = new { start = now },
    location = new[] { new { location = new { reference = $"Location/{locationId}", display = $"SDK Sandbox Test Room {unique}" } } },
    statusHistory = new[] { new { status = "arrived", period = new { start = now } } },
    serviceProvider = new { reference = $"Organization/{cfg.OrganizationId}" }
});
await Post("Condition", new
{
    resourceType = "Condition",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/condition/{cfg.OrganizationId}", value = $"{unique}-COND" } },
    clinicalStatus = new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/condition-clinical", code = "active", display = "Active" } } },
    verificationStatus = new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/condition-ver-status", code = "confirmed", display = "Confirmed" } } },
    category = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/condition-category", code = "encounter-diagnosis", display = "Encounter Diagnosis" } } } },
    code = new { coding = new[] { new { system = "http://hl7.org/fhir/sid/icd-10", code = "Z00.0", display = "General medical examination" } } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    encounter = new { reference = $"Encounter/{encounterId}" },
    onsetDateTime = now,
    recordedDate = now,
    recorder = new { reference = $"Practitioner/{practitionerId}", display = practitionerName },
    asserter = new { reference = $"Practitioner/{practitionerId}", display = practitionerName }
});
await Post("Observation", new
{
    resourceType = "Observation",
    status = "final",
    category = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/observation-category", code = "vital-signs", display = "Vital Signs" } } } },
    code = new { coding = new[] { new { system = "http://loinc.org", code = "8867-4", display = "Heart rate" } } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    encounter = new { reference = $"Encounter/{encounterId}" },
    effectiveDateTime = now,
    issued = now,
    performer = new[] { new { reference = $"Practitioner/{practitionerId}", display = practitionerName } },
    valueQuantity = new { value = 80, unit = "{beats}/min", system = "http://unitsofmeasure.org", code = "{beats}/min" }
});
Console.WriteLine(JsonSerializer.Serialize(new Dictionary<string, object?> { ["platform"] = "dotnet", ["created"] = created }, new JsonSerializerOptions { WriteIndented = true }));
CS
  DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-Major}" "$dotnet_bin" run --project "$dotnet_dir/LiveClinical.csproj" --no-launch-profile
}

if [ "$#" -gt 0 ]; then
  platforms=("$@")
else
  platforms=(python node go java php dotnet)
fi

for platform in "${platforms[@]}"; do
  case "$platform" in
    python) run_step python run_python ;;
    node) run_step node run_node ;;
    go) run_step go run_go ;;
    java) run_step java run_java ;;
    php) run_step php run_php ;;
    dotnet) run_step dotnet run_dotnet ;;
    *)
      printf 'unknown platform: %s\n' "$platform" >&2
      failures=$((failures + 1))
      ;;
  esac
done

if [ "$failures" -gt 0 ]; then
  printf '\n%s platform(s) failed live SATUSEHAT clinical validation.\n' "$failures" >&2
  exit 1
fi

printf '\nAll live SATUSEHAT sandbox clinical validations passed.\n'
