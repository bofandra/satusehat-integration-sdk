#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/satusehat-lab-matrix.XXXXXX")"
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
  printf 'sandbox_lab_matrix must run with SATUSEHAT_ENV=sandbox\n' >&2
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
  PYTHONPATH="$ROOT/sdks/python/src" python3 - <<'PY'
import json
import os
import sys
import time
from datetime import datetime, timezone
from satusehat_sdk import SatusehatConfig, SatusehatSdk

cfg = SatusehatConfig.from_env()
sdk = SatusehatSdk(cfg)
unique = f"SDKLAB-PY-{int(time.time())}"
patient_id = os.environ["SATUSEHAT_SANDBOX_PATIENT_ID"]
patient_name = os.environ["SATUSEHAT_SANDBOX_PATIENT_NAME"]
practitioner_id = os.environ["SATUSEHAT_SANDBOX_PRACTITIONER_ID"]
practitioner_name = os.environ["SATUSEHAT_SANDBOX_PRACTITIONER_NAME"]
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
created = {}

panel_code = {"system": "http://loinc.org", "code": "24326-1", "display": "Electrolytes 1998 panel - Serum or Plasma"}
lab_category = {"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory", "display": "Laboratory"}

def post(resource_type, payload, created_key=None):
    response = sdk.request("POST", resource_type, payload=payload)
    body = json.loads(response.body) if response.body else {}
    result = {"resource": resource_type, "http_status": response.status_code, "resourceType": body.get("resourceType"), "id": body.get("id")}
    if response.status_code < 200 or response.status_code > 299:
        result["issues"] = body.get("issue", [])[:4]
    print(json.dumps(result, indent=2))
    if response.status_code < 200 or response.status_code > 299:
        raise SystemExit(1)
    created[created_key or resource_type] = body["id"]
    return body["id"]

def observation_payload(key, code, display, value, low, high, service_request_id, specimen_id, encounter_id):
    return {
        "resourceType": "Observation",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/observation/{cfg.organization_id}", "value": f"{unique}-{key}"}],
        "basedOn": [{"reference": f"ServiceRequest/{service_request_id}"}],
        "status": "final",
        "category": [{"coding": [lab_category]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": code, "display": display}]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "encounter": {"reference": f"Encounter/{encounter_id}"},
        "effectiveDateTime": now,
        "issued": now,
        "performer": [
            {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name},
            {"reference": f"Organization/{cfg.organization_id}"},
        ],
        "specimen": {"reference": f"Specimen/{specimen_id}"},
        "valueQuantity": {"value": value, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"},
        "interpretation": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation", "code": "N", "display": "Normal"}]}],
        "referenceRange": [{"low": {"value": low, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"}, "high": {"value": high, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"}}],
    }

try:
    location_id = post("Location", {
        "resourceType": "Location",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/location/{cfg.organization_id}", "value": f"{unique}-LOC"}],
        "status": "active",
        "name": f"SDK Sandbox Lab Room {unique}",
        "description": "Non-PHI SDK sandbox lab test location",
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
        "location": [{"location": {"reference": f"Location/{location_id}", "display": f"SDK Sandbox Lab Room {unique}"}}],
        "statusHistory": [{"status": "arrived", "period": {"start": now}}],
        "serviceProvider": {"reference": f"Organization/{cfg.organization_id}"},
    })
    service_request_id = post("ServiceRequest", {
        "resourceType": "ServiceRequest",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/servicerequest/{cfg.organization_id}", "value": f"{unique}-SR"}],
        "status": "active",
        "intent": "original-order",
        "category": [{"coding": [{"system": "http://snomed.info/sct", "code": "108252007", "display": "Laboratory procedure"}]}],
        "code": {"coding": [panel_code]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "encounter": {"reference": f"Encounter/{encounter_id}"},
        "occurrenceDateTime": now,
        "authoredOn": now,
        "requester": {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name},
        "performer": [{"reference": f"Organization/{cfg.organization_id}"}],
        "locationReference": [{"reference": f"Location/{location_id}", "display": f"SDK Sandbox Lab Room {unique}"}],
        "reasonCode": [{"coding": [{"system": "http://hl7.org/fhir/sid/icd-10", "code": "Z00.0", "display": "General medical examination"}]}],
    })
    specimen_id = post("Specimen", {
        "resourceType": "Specimen",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/specimen/{cfg.organization_id}", "value": f"{unique}-SPC"}],
        "status": "available",
        "type": {"coding": [{"system": "http://snomed.info/sct", "code": "119364003", "display": "Serum specimen"}]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "receivedTime": now,
        "request": [{"reference": f"ServiceRequest/{service_request_id}"}],
        "collection": {"collector": {"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name}, "collectedDateTime": now},
    })
    observations = [
        post("Observation", observation_payload("NA", "2951-2", "Sodium [Moles/volume] in Serum or Plasma", 140, 136, 145, service_request_id, specimen_id, encounter_id), "ObservationSodium"),
        post("Observation", observation_payload("K", "2823-3", "Potassium [Moles/volume] in Serum or Plasma", 4.2, 3.5, 5.1, service_request_id, specimen_id, encounter_id), "ObservationPotassium"),
        post("Observation", observation_payload("CL", "2075-0", "Chloride [Moles/volume] in Serum or Plasma", 103, 98, 107, service_request_id, specimen_id, encounter_id), "ObservationChloride"),
    ]
    post("DiagnosticReport", {
        "resourceType": "DiagnosticReport",
        "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/diagnostic/{cfg.organization_id}/lab", "value": f"{unique}-DR"}],
        "basedOn": [{"reference": f"ServiceRequest/{service_request_id}"}],
        "status": "final",
        "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v2-0074", "code": "LAB", "display": "Laboratory"}]}],
        "code": {"coding": [panel_code]},
        "subject": {"reference": f"Patient/{patient_id}", "display": patient_name},
        "encounter": {"reference": f"Encounter/{encounter_id}"},
        "effectiveDateTime": now,
        "issued": now,
        "performer": [{"reference": f"Organization/{cfg.organization_id}"}],
        "resultsInterpreter": [{"reference": f"Practitioner/{practitioner_id}", "display": practitioner_name}],
        "specimen": [{"reference": f"Specimen/{specimen_id}"}],
        "result": [{"reference": f"Observation/{observation_id}"} for observation_id in observations],
        "conclusion": "Electrolyte panel within reference range.",
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
const unique = `SDKLAB-NODE-${Math.floor(Date.now() / 1000)}`;
const patientId = process.env.SATUSEHAT_SANDBOX_PATIENT_ID;
const patientName = process.env.SATUSEHAT_SANDBOX_PATIENT_NAME;
const practitionerId = process.env.SATUSEHAT_SANDBOX_PRACTITIONER_ID;
const practitionerName = process.env.SATUSEHAT_SANDBOX_PRACTITIONER_NAME;
const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const created = {};

const panelCode = { system: 'http://loinc.org', code: '24326-1', display: 'Electrolytes 1998 panel - Serum or Plasma' };
const labCategory = { system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: 'laboratory', display: 'Laboratory' };

async function post(resourceType, payload, createdKey = resourceType) {
  const response = await sdk.request('POST', resourceType, undefined, payload);
  const body = response.body ? JSON.parse(response.body) : {};
  const result = { resource: resourceType, http_status: response.statusCode, resourceType: body.resourceType, id: body.id };
  if (response.statusCode < 200 || response.statusCode > 299) result.issues = (body.issue ?? []).slice(0, 4);
  console.log(JSON.stringify(result, null, 2));
  if (response.statusCode < 200 || response.statusCode > 299) process.exit(1);
  created[createdKey] = body.id;
  return body.id;
}

function observationPayload(key, code, display, value, low, high, serviceRequestId, specimenId, encounterId) {
  return {
    resourceType: 'Observation',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/observation/${cfg.organizationId}`, value: `${unique}-${key}` }],
    basedOn: [{ reference: `ServiceRequest/${serviceRequestId}` }],
    status: 'final',
    category: [{ coding: [labCategory] }],
    code: { coding: [{ system: 'http://loinc.org', code, display }] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    encounter: { reference: `Encounter/${encounterId}` },
    effectiveDateTime: now,
    issued: now,
    performer: [
      { reference: `Practitioner/${practitionerId}`, display: practitionerName },
      { reference: `Organization/${cfg.organizationId}` },
    ],
    specimen: { reference: `Specimen/${specimenId}` },
    valueQuantity: { value, unit: 'mmol/L', system: 'http://unitsofmeasure.org', code: 'mmol/L' },
    interpretation: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation', code: 'N', display: 'Normal' }] }],
    referenceRange: [{ low: { value: low, unit: 'mmol/L', system: 'http://unitsofmeasure.org', code: 'mmol/L' }, high: { value: high, unit: 'mmol/L', system: 'http://unitsofmeasure.org', code: 'mmol/L' } }],
  };
}

try {
  const locationId = await post('Location', {
    resourceType: 'Location',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/location/${cfg.organizationId}`, value: `${unique}-LOC` }],
    status: 'active',
    name: `SDK Sandbox Lab Room ${unique}`,
    description: 'Non-PHI SDK sandbox lab test location',
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
    location: [{ location: { reference: `Location/${locationId}`, display: `SDK Sandbox Lab Room ${unique}` } }],
    statusHistory: [{ status: 'arrived', period: { start: now } }],
    serviceProvider: { reference: `Organization/${cfg.organizationId}` },
  });
  const serviceRequestId = await post('ServiceRequest', {
    resourceType: 'ServiceRequest',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/servicerequest/${cfg.organizationId}`, value: `${unique}-SR` }],
    status: 'active',
    intent: 'original-order',
    category: [{ coding: [{ system: 'http://snomed.info/sct', code: '108252007', display: 'Laboratory procedure' }] }],
    code: { coding: [panelCode] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    encounter: { reference: `Encounter/${encounterId}` },
    occurrenceDateTime: now,
    authoredOn: now,
    requester: { reference: `Practitioner/${practitionerId}`, display: practitionerName },
    performer: [{ reference: `Organization/${cfg.organizationId}` }],
    locationReference: [{ reference: `Location/${locationId}`, display: `SDK Sandbox Lab Room ${unique}` }],
    reasonCode: [{ coding: [{ system: 'http://hl7.org/fhir/sid/icd-10', code: 'Z00.0', display: 'General medical examination' }] }],
  });
  const specimenId = await post('Specimen', {
    resourceType: 'Specimen',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/specimen/${cfg.organizationId}`, value: `${unique}-SPC` }],
    status: 'available',
    type: { coding: [{ system: 'http://snomed.info/sct', code: '119364003', display: 'Serum specimen' }] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    receivedTime: now,
    request: [{ reference: `ServiceRequest/${serviceRequestId}` }],
    collection: { collector: { reference: `Practitioner/${practitionerId}`, display: practitionerName }, collectedDateTime: now },
  });
  const observations = [
    await post('Observation', observationPayload('NA', '2951-2', 'Sodium [Moles/volume] in Serum or Plasma', 140, 136, 145, serviceRequestId, specimenId, encounterId), 'ObservationSodium'),
    await post('Observation', observationPayload('K', '2823-3', 'Potassium [Moles/volume] in Serum or Plasma', 4.2, 3.5, 5.1, serviceRequestId, specimenId, encounterId), 'ObservationPotassium'),
    await post('Observation', observationPayload('CL', '2075-0', 'Chloride [Moles/volume] in Serum or Plasma', 103, 98, 107, serviceRequestId, specimenId, encounterId), 'ObservationChloride'),
  ];
  await post('DiagnosticReport', {
    resourceType: 'DiagnosticReport',
    identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/diagnostic/${cfg.organizationId}/lab`, value: `${unique}-DR` }],
    basedOn: [{ reference: `ServiceRequest/${serviceRequestId}` }],
    status: 'final',
    category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/v2-0074', code: 'LAB', display: 'Laboratory' }] }],
    code: { coding: [panelCode] },
    subject: { reference: `Patient/${patientId}`, display: patientName },
    encounter: { reference: `Encounter/${encounterId}` },
    effectiveDateTime: now,
    issued: now,
    performer: [{ reference: `Organization/${cfg.organizationId}` }],
    resultsInterpreter: [{ reference: `Practitioner/${practitionerId}`, display: practitionerName }],
    specimen: [{ reference: `Specimen/${specimenId}` }],
    result: observations.map((observationId) => ({ reference: `Observation/${observationId}` })),
    conclusion: 'Electrolyte panel within reference range.',
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
module satusehat-lab-live

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

func firstIssues(body map[string]any) any {
	issues, ok := body["issue"].([]any)
	if !ok || len(issues) <= 4 {
		return body["issue"]
	}
	return issues[:4]
}

func post(ctx context.Context, sdk *satusehat.SDK, created map[string]string, resourceType string, payload map[string]any, createdKey string) (string, error) {
	raw, _ := json.Marshal(payload)
	response, err := sdk.Request(ctx, "POST", resourceType, "", raw)
	if err != nil {
		return "", err
	}
	var body map[string]any
	_ = json.Unmarshal(response.Body, &body)
	result := map[string]any{"resource": resourceType, "http_status": response.StatusCode, "resourceType": body["resourceType"], "id": body["id"]}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		result["issues"] = firstIssues(body)
	}
	out, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(out))
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return "", fmt.Errorf("%s HTTP %d", resourceType, response.StatusCode)
	}
	id, _ := body["id"].(string)
	created[createdKey] = id
	return id, nil
}

func observationPayload(unique string, cfg satusehat.Config, patientID string, patientName string, practitionerID string, practitionerName string, now string, key string, code string, display string, value float64, low float64, high float64, serviceRequestID string, specimenID string, encounterID string) map[string]any {
	return map[string]any{
		"resourceType": "Observation",
		"identifier":   []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/observation/" + cfg.OrganizationID, "value": unique + "-" + key}},
		"basedOn":      []map[string]string{{"reference": "ServiceRequest/" + serviceRequestID}},
		"status":       "final",
		"category":     []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory", "display": "Laboratory"}}}},
		"code":         map[string]any{"coding": []map[string]string{{"system": "http://loinc.org", "code": code, "display": display}}},
		"subject":      map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"encounter":    map[string]string{"reference": "Encounter/" + encounterID},
		"effectiveDateTime": now,
		"issued":            now,
		"performer":         []map[string]string{{"reference": "Practitioner/" + practitionerID, "display": practitionerName}, {"reference": "Organization/" + cfg.OrganizationID}},
		"specimen":          map[string]string{"reference": "Specimen/" + specimenID},
		"valueQuantity":     map[string]any{"value": value, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"},
		"interpretation":    []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation", "code": "N", "display": "Normal"}}}},
		"referenceRange":    []map[string]any{{"low": map[string]any{"value": low, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"}, "high": map[string]any{"value": high, "unit": "mmol/L", "system": "http://unitsofmeasure.org", "code": "mmol/L"}}},
	}
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
	unique := fmt.Sprintf("SDKLAB-GO-%d", time.Now().Unix())
	patientID := os.Getenv("SATUSEHAT_SANDBOX_PATIENT_ID")
	patientName := os.Getenv("SATUSEHAT_SANDBOX_PATIENT_NAME")
	practitionerID := os.Getenv("SATUSEHAT_SANDBOX_PRACTITIONER_ID")
	practitionerName := os.Getenv("SATUSEHAT_SANDBOX_PRACTITIONER_NAME")
	now := time.Now().UTC().Truncate(time.Second).Format(time.RFC3339)
	created := map[string]string{}

	panelCode := map[string]string{"system": "http://loinc.org", "code": "24326-1", "display": "Electrolytes 1998 panel - Serum or Plasma"}

	locationID, err := post(ctx, sdk, created, "Location", map[string]any{
		"resourceType": "Location",
		"identifier":   []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/location/" + cfg.OrganizationID, "value": unique + "-LOC"}},
		"status":       "active",
		"name":         "SDK Sandbox Lab Room " + unique,
		"description":  "Non-PHI SDK sandbox lab test location",
		"mode":         "instance",
		"physicalType": map[string]any{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/location-physical-type", "code": "ro", "display": "Room"}}},
		"managingOrganization": map[string]string{"reference": "Organization/" + cfg.OrganizationID},
	}, "Location")
	if err != nil {
		panic(err)
	}
	encounterID, err := post(ctx, sdk, created, "Encounter", map[string]any{
		"resourceType":  "Encounter",
		"identifier":    []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/encounter/" + cfg.OrganizationID, "value": unique + "-ENC"}},
		"status":        "arrived",
		"class":         map[string]string{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "AMB", "display": "ambulatory"},
		"subject":       map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"participant":   []map[string]any{{"type": []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/v3-ParticipationType", "code": "ATND", "display": "attender"}}}}, "individual": map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName}}},
		"period":        map[string]string{"start": now},
		"location":      []map[string]any{{"location": map[string]string{"reference": "Location/" + locationID, "display": "SDK Sandbox Lab Room " + unique}}},
		"statusHistory": []map[string]any{{"status": "arrived", "period": map[string]string{"start": now}}},
		"serviceProvider": map[string]string{"reference": "Organization/" + cfg.OrganizationID},
	}, "Encounter")
	if err != nil {
		panic(err)
	}
	serviceRequestID, err := post(ctx, sdk, created, "ServiceRequest", map[string]any{
		"resourceType":        "ServiceRequest",
		"identifier":          []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/servicerequest/" + cfg.OrganizationID, "value": unique + "-SR"}},
		"status":              "active",
		"intent":              "original-order",
		"category":            []map[string]any{{"coding": []map[string]string{{"system": "http://snomed.info/sct", "code": "108252007", "display": "Laboratory procedure"}}}},
		"code":                map[string]any{"coding": []map[string]string{panelCode}},
		"subject":             map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"encounter":           map[string]string{"reference": "Encounter/" + encounterID},
		"occurrenceDateTime":  now,
		"authoredOn":          now,
		"requester":           map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName},
		"performer":           []map[string]string{{"reference": "Organization/" + cfg.OrganizationID}},
		"locationReference":   []map[string]string{{"reference": "Location/" + locationID, "display": "SDK Sandbox Lab Room " + unique}},
		"reasonCode":          []map[string]any{{"coding": []map[string]string{{"system": "http://hl7.org/fhir/sid/icd-10", "code": "Z00.0", "display": "General medical examination"}}}},
	}, "ServiceRequest")
	if err != nil {
		panic(err)
	}
	specimenID, err := post(ctx, sdk, created, "Specimen", map[string]any{
		"resourceType": "Specimen",
		"identifier":   []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/specimen/" + cfg.OrganizationID, "value": unique + "-SPC"}},
		"status":       "available",
		"type":         map[string]any{"coding": []map[string]string{{"system": "http://snomed.info/sct", "code": "119364003", "display": "Serum specimen"}}},
		"subject":      map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"receivedTime": now,
		"request":      []map[string]string{{"reference": "ServiceRequest/" + serviceRequestID}},
		"collection":   map[string]any{"collector": map[string]string{"reference": "Practitioner/" + practitionerID, "display": practitionerName}, "collectedDateTime": now},
	}, "Specimen")
	if err != nil {
		panic(err)
	}
	observationIDs := []string{}
	observationDefinitions := []struct {
		key     string
		code    string
		display string
		value   float64
		low     float64
		high    float64
		mapKey  string
	}{
		{"NA", "2951-2", "Sodium [Moles/volume] in Serum or Plasma", 140, 136, 145, "ObservationSodium"},
		{"K", "2823-3", "Potassium [Moles/volume] in Serum or Plasma", 4.2, 3.5, 5.1, "ObservationPotassium"},
		{"CL", "2075-0", "Chloride [Moles/volume] in Serum or Plasma", 103, 98, 107, "ObservationChloride"},
	}
	for _, definition := range observationDefinitions {
		observationID, err := post(ctx, sdk, created, "Observation", observationPayload(unique, cfg, patientID, patientName, practitionerID, practitionerName, now, definition.key, definition.code, definition.display, definition.value, definition.low, definition.high, serviceRequestID, specimenID, encounterID), definition.mapKey)
		if err != nil {
			panic(err)
		}
		observationIDs = append(observationIDs, observationID)
	}
	results := []map[string]string{}
	for _, observationID := range observationIDs {
		results = append(results, map[string]string{"reference": "Observation/" + observationID})
	}
	if _, err := post(ctx, sdk, created, "DiagnosticReport", map[string]any{
		"resourceType":        "DiagnosticReport",
		"identifier":          []map[string]string{{"use": "official", "system": "http://sys-ids.kemkes.go.id/diagnostic/" + cfg.OrganizationID + "/lab", "value": unique + "-DR"}},
		"basedOn":             []map[string]string{{"reference": "ServiceRequest/" + serviceRequestID}},
		"status":              "final",
		"category":            []map[string]any{{"coding": []map[string]string{{"system": "http://terminology.hl7.org/CodeSystem/v2-0074", "code": "LAB", "display": "Laboratory"}}}},
		"code":                map[string]any{"coding": []map[string]string{panelCode}},
		"subject":             map[string]string{"reference": "Patient/" + patientID, "display": patientName},
		"encounter":           map[string]string{"reference": "Encounter/" + encounterID},
		"effectiveDateTime":   now,
		"issued":              now,
		"performer":           []map[string]string{{"reference": "Organization/" + cfg.OrganizationID}},
		"resultsInterpreter":  []map[string]string{{"reference": "Practitioner/" + practitionerID, "display": practitionerName}},
		"specimen":            []map[string]string{{"reference": "Specimen/" + specimenID}},
		"result":              results,
		"conclusion":          "Electrolyte panel within reference range.",
	}, "DiagnosticReport"); err != nil {
		panic(err)
	}
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
  cat > "$java_dir/LiveLab.java" <<'JAVA'
import id.kemkes.satusehat.*;
import java.time.*;
import java.util.*;
import java.util.regex.*;

public class LiveLab {
  static String value(String body, String key) {
    var m = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"").matcher(body);
    return m.find() ? m.group(1) : null;
  }

  static String esc(String value) {
    return value.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  static String issueSummary(String body) {
    var items = new ArrayList<String>();
    var matcher = Pattern.compile("\\\"(?:diagnostics|text)\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"").matcher(body);
    while (matcher.find() && items.size() < 4) {
      items.add("\"" + esc(matcher.group(1)) + "\"");
    }
    return "[" + String.join(",", items) + "]";
  }

  static String post(SatusehatSdk sdk, Map<String, String> created, String resourceType, String payload, String createdKey) throws Exception {
    var response = sdk.request("POST", resourceType, null, payload);
    var id = value(response.body(), "id");
    var result = "{\"resource\":\"" + resourceType + "\",\"http_status\":" + response.statusCode() + ",\"resourceType\":\"" + value(response.body(), "resourceType") + "\",\"id\":\"" + id + "\"";
    if (response.statusCode() < 200 || response.statusCode() > 299) {
      result += ",\"issues\":" + issueSummary(response.body());
    }
    System.out.println(result + "}");
    if (response.statusCode() < 200 || response.statusCode() > 299) {
      System.exit(1);
    }
    created.put(createdKey, id);
    return id;
  }

  static String createdJson(Map<String, String> created) {
    var items = new ArrayList<String>();
    for (var entry : created.entrySet()) {
      items.add("\"" + esc(entry.getKey()) + "\":\"" + esc(entry.getValue()) + "\"");
    }
    return "{" + String.join(",", items) + "}";
  }

  static String observationPayload(SatusehatConfig cfg, String unique, String patientId, String patientName, String practitionerId, String practitionerName, String now, String key, String code, String display, String value, String low, String high, String serviceRequestId, String specimenId, String encounterId) {
    return """
      {"resourceType":"Observation","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/observation/%s","value":"%s-%s"}],"basedOn":[{"reference":"ServiceRequest/%s"}],"status":"final","category":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/observation-category","code":"laboratory","display":"Laboratory"}]}],"code":{"coding":[{"system":"http://loinc.org","code":"%s","display":"%s"}]},"subject":{"reference":"Patient/%s","display":"%s"},"encounter":{"reference":"Encounter/%s"},"effectiveDateTime":"%s","issued":"%s","performer":[{"reference":"Practitioner/%s","display":"%s"},{"reference":"Organization/%s"}],"specimen":{"reference":"Specimen/%s"},"valueQuantity":{"value":%s,"unit":"mmol/L","system":"http://unitsofmeasure.org","code":"mmol/L"},"interpretation":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation","code":"N","display":"Normal"}]}],"referenceRange":[{"low":{"value":%s,"unit":"mmol/L","system":"http://unitsofmeasure.org","code":"mmol/L"},"high":{"value":%s,"unit":"mmol/L","system":"http://unitsofmeasure.org","code":"mmol/L"}}]}
      """.formatted(cfg.organizationId(), unique, key, serviceRequestId, code, display, patientId, patientName, encounterId, now, now, practitionerId, practitionerName, cfg.organizationId(), specimenId, value, low, high);
  }

  public static void main(String[] args) throws Exception {
    var cfg = SatusehatConfig.fromEnv();
    var patientId = System.getenv("SATUSEHAT_SANDBOX_PATIENT_ID");
    var patientName = esc(System.getenv("SATUSEHAT_SANDBOX_PATIENT_NAME"));
    var practitionerId = System.getenv("SATUSEHAT_SANDBOX_PRACTITIONER_ID");
    var practitionerName = esc(System.getenv("SATUSEHAT_SANDBOX_PRACTITIONER_NAME"));
    var unique = "SDKLAB-JAVA-" + (System.currentTimeMillis() / 1000);
    var now = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString();
    var created = new LinkedHashMap<String, String>();
    try (var sdk = new SatusehatSdk(cfg)) {
      var locationId = post(sdk, created, "Location", """
        {"resourceType":"Location","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/location/%s","value":"%s-LOC"}],"status":"active","name":"SDK Sandbox Lab Room %s","description":"Non-PHI SDK sandbox lab test location","mode":"instance","physicalType":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/location-physical-type","code":"ro","display":"Room"}]},"managingOrganization":{"reference":"Organization/%s"}}
        """.formatted(cfg.organizationId(), unique, unique, cfg.organizationId()), "Location");
      var encounterId = post(sdk, created, "Encounter", """
        {"resourceType":"Encounter","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/encounter/%s","value":"%s-ENC"}],"status":"arrived","class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"AMB","display":"ambulatory"},"subject":{"reference":"Patient/%s","display":"%s"},"participant":[{"type":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ParticipationType","code":"ATND","display":"attender"}]}],"individual":{"reference":"Practitioner/%s","display":"%s"}}],"period":{"start":"%s"},"location":[{"location":{"reference":"Location/%s","display":"SDK Sandbox Lab Room %s"}}],"statusHistory":[{"status":"arrived","period":{"start":"%s"}}],"serviceProvider":{"reference":"Organization/%s"}}
        """.formatted(cfg.organizationId(), unique, patientId, patientName, practitionerId, practitionerName, now, locationId, unique, now, cfg.organizationId()), "Encounter");
      var serviceRequestId = post(sdk, created, "ServiceRequest", """
        {"resourceType":"ServiceRequest","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/servicerequest/%s","value":"%s-SR"}],"status":"active","intent":"original-order","category":[{"coding":[{"system":"http://snomed.info/sct","code":"108252007","display":"Laboratory procedure"}]}],"code":{"coding":[{"system":"http://loinc.org","code":"24326-1","display":"Electrolytes 1998 panel - Serum or Plasma"}]},"subject":{"reference":"Patient/%s","display":"%s"},"encounter":{"reference":"Encounter/%s"},"occurrenceDateTime":"%s","authoredOn":"%s","requester":{"reference":"Practitioner/%s","display":"%s"},"performer":[{"reference":"Organization/%s"}],"locationReference":[{"reference":"Location/%s","display":"SDK Sandbox Lab Room %s"}],"reasonCode":[{"coding":[{"system":"http://hl7.org/fhir/sid/icd-10","code":"Z00.0","display":"General medical examination"}]}]}
        """.formatted(cfg.organizationId(), unique, patientId, patientName, encounterId, now, now, practitionerId, practitionerName, cfg.organizationId(), locationId, unique), "ServiceRequest");
      var specimenId = post(sdk, created, "Specimen", """
        {"resourceType":"Specimen","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/specimen/%s","value":"%s-SPC"}],"status":"available","type":{"coding":[{"system":"http://snomed.info/sct","code":"119364003","display":"Serum specimen"}]},"subject":{"reference":"Patient/%s","display":"%s"},"receivedTime":"%s","request":[{"reference":"ServiceRequest/%s"}],"collection":{"collector":{"reference":"Practitioner/%s","display":"%s"},"collectedDateTime":"%s"}}
        """.formatted(cfg.organizationId(), unique, patientId, patientName, now, serviceRequestId, practitionerId, practitionerName, now), "Specimen");
      var sodiumId = post(sdk, created, "Observation", observationPayload(cfg, unique, patientId, patientName, practitionerId, practitionerName, now, "NA", "2951-2", "Sodium [Moles/volume] in Serum or Plasma", "140", "136", "145", serviceRequestId, specimenId, encounterId), "ObservationSodium");
      var potassiumId = post(sdk, created, "Observation", observationPayload(cfg, unique, patientId, patientName, practitionerId, practitionerName, now, "K", "2823-3", "Potassium [Moles/volume] in Serum or Plasma", "4.2", "3.5", "5.1", serviceRequestId, specimenId, encounterId), "ObservationPotassium");
      var chlorideId = post(sdk, created, "Observation", observationPayload(cfg, unique, patientId, patientName, practitionerId, practitionerName, now, "CL", "2075-0", "Chloride [Moles/volume] in Serum or Plasma", "103", "98", "107", serviceRequestId, specimenId, encounterId), "ObservationChloride");
      post(sdk, created, "DiagnosticReport", """
        {"resourceType":"DiagnosticReport","identifier":[{"use":"official","system":"http://sys-ids.kemkes.go.id/diagnostic/%s/lab","value":"%s-DR"}],"basedOn":[{"reference":"ServiceRequest/%s"}],"status":"final","category":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v2-0074","code":"LAB","display":"Laboratory"}]}],"code":{"coding":[{"system":"http://loinc.org","code":"24326-1","display":"Electrolytes 1998 panel - Serum or Plasma"}]},"subject":{"reference":"Patient/%s","display":"%s"},"encounter":{"reference":"Encounter/%s"},"effectiveDateTime":"%s","issued":"%s","performer":[{"reference":"Organization/%s"}],"resultsInterpreter":[{"reference":"Practitioner/%s","display":"%s"}],"specimen":[{"reference":"Specimen/%s"}],"result":[{"reference":"Observation/%s"},{"reference":"Observation/%s"},{"reference":"Observation/%s"}],"conclusion":"Electrolyte panel within reference range."}
        """.formatted(cfg.organizationId(), unique, serviceRequestId, patientId, patientName, encounterId, now, now, cfg.organizationId(), practitionerId, practitionerName, specimenId, sodiumId, potassiumId, chlorideId), "DiagnosticReport");
      System.out.println("{\"platform\":\"java\",\"created\":" + createdJson(created) + "}");
    }
  }
}
JAVA
  cp_value="$java_dir:$ROOT/sdks/java/target/classes:$sqlite_jdbc"
  if [ -n "$slf4j_api" ] && [ -f "$slf4j_api" ]; then
    cp_value="$cp_value:$slf4j_api"
  fi
  "$javac_bin" -cp "$cp_value" "$java_dir/LiveLab.java" &&
    "$java_bin" -cp "$cp_value" LiveLab
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
$unique = 'SDKLAB-PHP-' . time();
$patientId = getenv('SATUSEHAT_SANDBOX_PATIENT_ID');
$patientName = getenv('SATUSEHAT_SANDBOX_PATIENT_NAME');
$practitionerId = getenv('SATUSEHAT_SANDBOX_PRACTITIONER_ID');
$practitionerName = getenv('SATUSEHAT_SANDBOX_PRACTITIONER_NAME');
$now = gmdate('Y-m-d\TH:i:s\Z');
$created = [];
$panelCode = ['system' => 'http://loinc.org', 'code' => '24326-1', 'display' => 'Electrolytes 1998 panel - Serum or Plasma'];

function postResource(SatusehatSdk $sdk, array &$created, string $resourceType, array $payload, ?string $createdKey = null): string {
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
    $created[$createdKey ?? $resourceType] = $body['id'];
    return $body['id'];
}

function observationPayload(Config $cfg, string $unique, string $patientId, string $patientName, string $practitionerId, string $practitionerName, string $now, string $key, string $code, string $display, float $value, float $low, float $high, string $serviceRequestId, string $specimenId, string $encounterId): array {
    return [
        'resourceType' => 'Observation',
        'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/observation/' . $cfg->organizationId, 'value' => $unique . '-' . $key]],
        'basedOn' => [['reference' => 'ServiceRequest/' . $serviceRequestId]],
        'status' => 'final',
        'category' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/observation-category', 'code' => 'laboratory', 'display' => 'Laboratory']]]],
        'code' => ['coding' => [['system' => 'http://loinc.org', 'code' => $code, 'display' => $display]]],
        'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
        'encounter' => ['reference' => 'Encounter/' . $encounterId],
        'effectiveDateTime' => $now,
        'issued' => $now,
        'performer' => [['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName], ['reference' => 'Organization/' . $cfg->organizationId]],
        'specimen' => ['reference' => 'Specimen/' . $specimenId],
        'valueQuantity' => ['value' => $value, 'unit' => 'mmol/L', 'system' => 'http://unitsofmeasure.org', 'code' => 'mmol/L'],
        'interpretation' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation', 'code' => 'N', 'display' => 'Normal']]]],
        'referenceRange' => [['low' => ['value' => $low, 'unit' => 'mmol/L', 'system' => 'http://unitsofmeasure.org', 'code' => 'mmol/L'], 'high' => ['value' => $high, 'unit' => 'mmol/L', 'system' => 'http://unitsofmeasure.org', 'code' => 'mmol/L']]],
    ];
}

$locationId = postResource($sdk, $created, 'Location', [
  'resourceType' => 'Location',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/location/' . $cfg->organizationId, 'value' => $unique . '-LOC']],
  'status' => 'active',
  'name' => 'SDK Sandbox Lab Room ' . $unique,
  'description' => 'Non-PHI SDK sandbox lab test location',
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
  'location' => [['location' => ['reference' => 'Location/' . $locationId, 'display' => 'SDK Sandbox Lab Room ' . $unique]]],
  'statusHistory' => [['status' => 'arrived', 'period' => ['start' => $now]]],
  'serviceProvider' => ['reference' => 'Organization/' . $cfg->organizationId],
]);
$serviceRequestId = postResource($sdk, $created, 'ServiceRequest', [
  'resourceType' => 'ServiceRequest',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/servicerequest/' . $cfg->organizationId, 'value' => $unique . '-SR']],
  'status' => 'active',
  'intent' => 'original-order',
  'category' => [['coding' => [['system' => 'http://snomed.info/sct', 'code' => '108252007', 'display' => 'Laboratory procedure']]]],
  'code' => ['coding' => [$panelCode]],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'encounter' => ['reference' => 'Encounter/' . $encounterId],
  'occurrenceDateTime' => $now,
  'authoredOn' => $now,
  'requester' => ['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName],
  'performer' => [['reference' => 'Organization/' . $cfg->organizationId]],
  'locationReference' => [['reference' => 'Location/' . $locationId, 'display' => 'SDK Sandbox Lab Room ' . $unique]],
  'reasonCode' => [['coding' => [['system' => 'http://hl7.org/fhir/sid/icd-10', 'code' => 'Z00.0', 'display' => 'General medical examination']]]],
]);
$specimenId = postResource($sdk, $created, 'Specimen', [
  'resourceType' => 'Specimen',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/specimen/' . $cfg->organizationId, 'value' => $unique . '-SPC']],
  'status' => 'available',
  'type' => ['coding' => [['system' => 'http://snomed.info/sct', 'code' => '119364003', 'display' => 'Serum specimen']]],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'receivedTime' => $now,
  'request' => [['reference' => 'ServiceRequest/' . $serviceRequestId]],
  'collection' => ['collector' => ['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName], 'collectedDateTime' => $now],
]);
$observations = [
  postResource($sdk, $created, 'Observation', observationPayload($cfg, $unique, $patientId, $patientName, $practitionerId, $practitionerName, $now, 'NA', '2951-2', 'Sodium [Moles/volume] in Serum or Plasma', 140, 136, 145, $serviceRequestId, $specimenId, $encounterId), 'ObservationSodium'),
  postResource($sdk, $created, 'Observation', observationPayload($cfg, $unique, $patientId, $patientName, $practitionerId, $practitionerName, $now, 'K', '2823-3', 'Potassium [Moles/volume] in Serum or Plasma', 4.2, 3.5, 5.1, $serviceRequestId, $specimenId, $encounterId), 'ObservationPotassium'),
  postResource($sdk, $created, 'Observation', observationPayload($cfg, $unique, $patientId, $patientName, $practitionerId, $practitionerName, $now, 'CL', '2075-0', 'Chloride [Moles/volume] in Serum or Plasma', 103, 98, 107, $serviceRequestId, $specimenId, $encounterId), 'ObservationChloride'),
];
postResource($sdk, $created, 'DiagnosticReport', [
  'resourceType' => 'DiagnosticReport',
  'identifier' => [['use' => 'official', 'system' => 'http://sys-ids.kemkes.go.id/diagnostic/' . $cfg->organizationId . '/lab', 'value' => $unique . '-DR']],
  'basedOn' => [['reference' => 'ServiceRequest/' . $serviceRequestId]],
  'status' => 'final',
  'category' => [['coding' => [['system' => 'http://terminology.hl7.org/CodeSystem/v2-0074', 'code' => 'LAB', 'display' => 'Laboratory']]],
  ],
  'code' => ['coding' => [$panelCode]],
  'subject' => ['reference' => 'Patient/' . $patientId, 'display' => $patientName],
  'encounter' => ['reference' => 'Encounter/' . $encounterId],
  'effectiveDateTime' => $now,
  'issued' => $now,
  'performer' => [['reference' => 'Organization/' . $cfg->organizationId]],
  'resultsInterpreter' => [['reference' => 'Practitioner/' . $practitionerId, 'display' => $practitionerName]],
  'specimen' => [['reference' => 'Specimen/' . $specimenId]],
  'result' => array_map(fn($observationId) => ['reference' => 'Observation/' . $observationId], $observations),
  'conclusion' => 'Electrolyte panel within reference range.',
]);
echo json_encode(['platform' => 'php', 'created' => $created], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
PHP
}

run_dotnet() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/dotnet.db"
  dotnet_dir="$TMP_ROOT/dotnet-live"
  mkdir -p "$dotnet_dir"
  cat > "$dotnet_dir/LiveLab.csproj" <<EOF
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
var unique = $"SDKLAB-DOTNET-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
var patientId = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PATIENT_ID")!;
var patientName = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PATIENT_NAME")!;
var practitionerId = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PRACTITIONER_ID")!;
var practitionerName = Environment.GetEnvironmentVariable("SATUSEHAT_SANDBOX_PRACTITIONER_NAME")!;
var now = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", System.Globalization.CultureInfo.InvariantCulture);
var created = new Dictionary<string, string>();
var panelCode = new { system = "http://loinc.org", code = "24326-1", display = "Electrolytes 1998 panel - Serum or Plasma" };

async Task<string> Post(string resourceType, object payload, string? createdKey = null)
{
    var response = await sdk.RequestAsync("POST", resourceType, payload: JsonSerializer.Serialize(payload));
    using var doc = JsonDocument.Parse(response.Body);
    var root = doc.RootElement;
    string? prop(string name) => root.TryGetProperty(name, out var value) ? value.GetString() : null;
    var result = new Dictionary<string, object?> { ["resource"] = resourceType, ["http_status"] = response.StatusCode, ["resourceType"] = prop("resourceType"), ["id"] = prop("id") };
    if (response.StatusCode is < 200 or > 299 && root.TryGetProperty("issue", out var issues))
    {
        var firstIssues = new List<JsonElement>();
        foreach (var issue in issues.EnumerateArray())
        {
            if (firstIssues.Count == 4) break;
            firstIssues.Add(issue.Clone());
        }
        result["issues"] = firstIssues;
    }
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    if (response.StatusCode is < 200 or > 299) Environment.Exit(1);
    var id = prop("id")!;
    created[createdKey ?? resourceType] = id;
    return id;
}

object ObservationPayload(string key, string code, string display, double value, double low, double high, string serviceRequestId, string specimenId, string encounterId) => new
{
    resourceType = "Observation",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/observation/{cfg.OrganizationId}", value = $"{unique}-{key}" } },
    basedOn = new[] { new { reference = $"ServiceRequest/{serviceRequestId}" } },
    status = "final",
    category = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/observation-category", code = "laboratory", display = "Laboratory" } } } },
    code = new { coding = new[] { new { system = "http://loinc.org", code, display } } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    encounter = new { reference = $"Encounter/{encounterId}" },
    effectiveDateTime = now,
    issued = now,
    performer = new[] { new { reference = $"Practitioner/{practitionerId}", display = practitionerName } },
    specimen = new { reference = $"Specimen/{specimenId}" },
    valueQuantity = new { value, unit = "mmol/L", system = "http://unitsofmeasure.org", code = "mmol/L" },
    interpretation = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation", code = "N", display = "Normal" } } } },
    referenceRange = new[] { new { low = new { value = low, unit = "mmol/L", system = "http://unitsofmeasure.org", code = "mmol/L" }, high = new { value = high, unit = "mmol/L", system = "http://unitsofmeasure.org", code = "mmol/L" } } }
};

var locationId = await Post("Location", new
{
    resourceType = "Location",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/location/{cfg.OrganizationId}", value = $"{unique}-LOC" } },
    status = "active",
    name = $"SDK Sandbox Lab Room {unique}",
    description = "Non-PHI SDK sandbox lab test location",
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
    location = new[] { new { location = new { reference = $"Location/{locationId}", display = $"SDK Sandbox Lab Room {unique}" } } },
    statusHistory = new[] { new { status = "arrived", period = new { start = now } } },
    serviceProvider = new { reference = $"Organization/{cfg.OrganizationId}" }
});
var serviceRequestId = await Post("ServiceRequest", new
{
    resourceType = "ServiceRequest",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/servicerequest/{cfg.OrganizationId}", value = $"{unique}-SR" } },
    status = "active",
    intent = "original-order",
    category = new[] { new { coding = new[] { new { system = "http://snomed.info/sct", code = "108252007", display = "Laboratory procedure" } } } },
    code = new { coding = new[] { panelCode } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    encounter = new { reference = $"Encounter/{encounterId}" },
    occurrenceDateTime = now,
    authoredOn = now,
    requester = new { reference = $"Practitioner/{practitionerId}", display = practitionerName },
    performer = new[] { new { reference = $"Organization/{cfg.OrganizationId}" } },
    locationReference = new[] { new { reference = $"Location/{locationId}", display = $"SDK Sandbox Lab Room {unique}" } },
    reasonCode = new[] { new { coding = new[] { new { system = "http://hl7.org/fhir/sid/icd-10", code = "Z00.0", display = "General medical examination" } } } }
});
var specimenId = await Post("Specimen", new
{
    resourceType = "Specimen",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/specimen/{cfg.OrganizationId}", value = $"{unique}-SPC" } },
    status = "available",
    type = new { coding = new[] { new { system = "http://snomed.info/sct", code = "119364003", display = "Serum specimen" } } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    receivedTime = now,
    request = new[] { new { reference = $"ServiceRequest/{serviceRequestId}" } },
    collection = new { collector = new { reference = $"Practitioner/{practitionerId}", display = practitionerName }, collectedDateTime = now }
});
var observations = new[]
{
    await Post("Observation", ObservationPayload("NA", "2951-2", "Sodium [Moles/volume] in Serum or Plasma", 140, 136, 145, serviceRequestId, specimenId, encounterId), "ObservationSodium"),
    await Post("Observation", ObservationPayload("K", "2823-3", "Potassium [Moles/volume] in Serum or Plasma", 4.2, 3.5, 5.1, serviceRequestId, specimenId, encounterId), "ObservationPotassium"),
    await Post("Observation", ObservationPayload("CL", "2075-0", "Chloride [Moles/volume] in Serum or Plasma", 103, 98, 107, serviceRequestId, specimenId, encounterId), "ObservationChloride")
};
await Post("DiagnosticReport", new
{
    resourceType = "DiagnosticReport",
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/diagnostic/{cfg.OrganizationId}/lab", value = $"{unique}-DR" } },
    basedOn = new[] { new { reference = $"ServiceRequest/{serviceRequestId}" } },
    status = "final",
    category = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/v2-0074", code = "LAB", display = "Laboratory" } } } },
    code = new { coding = new[] { panelCode } },
    subject = new { reference = $"Patient/{patientId}", display = patientName },
    encounter = new { reference = $"Encounter/{encounterId}" },
    effectiveDateTime = now,
    issued = now,
    performer = new[] { new { reference = $"Organization/{cfg.OrganizationId}" } },
    resultsInterpreter = new[] { new { reference = $"Practitioner/{practitionerId}", display = practitionerName } },
    specimen = new[] { new { reference = $"Specimen/{specimenId}" } },
    result = observations.Select(observationId => new { reference = $"Observation/{observationId}" }).ToArray(),
    conclusion = "Electrolyte panel within reference range."
});
Console.WriteLine(JsonSerializer.Serialize(new Dictionary<string, object?> { ["platform"] = "dotnet", ["created"] = created }, new JsonSerializerOptions { WriteIndented = true }));
CS
  DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-Major}" "$dotnet_bin" run --project "$dotnet_dir/LiveLab.csproj" --no-launch-profile
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
  printf '\n%s platform(s) failed live SATUSEHAT lab validation.\n' "$failures" >&2
  exit 1
fi

printf '\nAll live SATUSEHAT sandbox lab validations passed.\n'
