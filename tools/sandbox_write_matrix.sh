#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}/satusehat-live-write-matrix.$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

missing=()
for name in SATUSEHAT_CLIENT_ID SATUSEHAT_CLIENT_SECRET SATUSEHAT_ORGANIZATION_ID; do
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
  printf 'sandbox_write_matrix must run with SATUSEHAT_ENV=sandbox\n' >&2
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
import sys
import time
from satusehat_sdk import SatusehatConfig, SatusehatSdk

cfg = SatusehatConfig.from_env()
sdk = SatusehatSdk(cfg)
unique = f"SDKTEST-PY-{int(time.time())}"
payload = {
    "resourceType": "Organization",
    "active": True,
    "identifier": [{"use": "official", "system": f"http://sys-ids.kemkes.go.id/organization/{cfg.organization_id}", "value": unique}],
    "type": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/organization-type", "code": "dept", "display": "Hospital Department"}]}],
    "name": f"SDK Sandbox Test Python {unique}",
    "partOf": {"reference": f"Organization/{cfg.organization_id}"},
}
try:
    response = sdk.request("POST", "Organization", payload=payload)
    body = json.loads(response.body) if response.body else {}
    result = {"platform": "python", "http_status": response.status_code, "resourceType": body.get("resourceType"), "id": body.get("id"), "identifier": unique}
    if response.status_code < 200 or response.status_code > 299:
        result["issues"] = body.get("issue", [])[:4]
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if 200 <= response.status_code <= 299 else 1)
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
const unique = `SDKTEST-NODE-${Math.floor(Date.now() / 1000)}`;
const payload = {
  resourceType: 'Organization',
  active: true,
  identifier: [{ use: 'official', system: `http://sys-ids.kemkes.go.id/organization/${cfg.organizationId}`, value: unique }],
  type: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/organization-type', code: 'dept', display: 'Hospital Department' }] }],
  name: `SDK Sandbox Test Node ${unique}`,
  partOf: { reference: `Organization/${cfg.organizationId}` },
};
try {
  const response = await sdk.request('POST', 'Organization', undefined, payload);
  const body = response.body ? JSON.parse(response.body) : {};
  const result = { platform: 'node', http_status: response.statusCode, resourceType: body.resourceType, id: body.id, identifier: unique };
  if (response.statusCode < 200 || response.statusCode > 299) result.issues = (body.issue ?? []).slice(0, 4);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = response.statusCode >= 200 && response.statusCode <= 299 ? 0 : 1;
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
module satusehat-live-write

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

	unique := fmt.Sprintf("SDKTEST-GO-%d", time.Now().Unix())
	payload := map[string]any{
		"resourceType": "Organization",
		"active":       true,
		"identifier": []map[string]string{{
			"use":    "official",
			"system": "http://sys-ids.kemkes.go.id/organization/" + cfg.OrganizationID,
			"value":  unique,
		}},
		"type": []map[string]any{{
			"coding": []map[string]string{{
				"system":  "http://terminology.hl7.org/CodeSystem/organization-type",
				"code":    "dept",
				"display": "Hospital Department",
			}},
		}},
		"name":   "SDK Sandbox Test Go " + unique,
		"partOf": map[string]string{"reference": "Organization/" + cfg.OrganizationID},
	}
	raw, _ := json.Marshal(payload)
	response, err := sdk.Request(context.Background(), "POST", "Organization", "", raw)
	if err != nil {
		panic(err)
	}
	var body map[string]any
	_ = json.Unmarshal(response.Body, &body)
	result := map[string]any{"platform": "go", "http_status": response.StatusCode, "resourceType": body["resourceType"], "id": body["id"], "identifier": unique}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		result["issues"] = body["issue"]
	}
	out, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(out))
	if response.StatusCode < 200 || response.StatusCode > 299 {
		os.Exit(1)
	}
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
  cat > "$java_dir/LiveWrite.java" <<'JAVA'
import id.kemkes.satusehat.*;
import java.util.regex.*;

public class LiveWrite {
  static String value(String body, String key) {
    var m = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"").matcher(body);
    return m.find() ? m.group(1) : null;
  }

  public static void main(String[] args) throws Exception {
    var cfg = SatusehatConfig.fromEnv();
    var unique = "SDKTEST-JAVA-" + (System.currentTimeMillis() / 1000);
    var payload = """
      {
        "resourceType": "Organization",
        "active": true,
        "identifier": [{"use": "official", "system": "http://sys-ids.kemkes.go.id/organization/%s", "value": "%s"}],
        "type": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/organization-type", "code": "dept", "display": "Hospital Department"}]}],
        "name": "SDK Sandbox Test Java %s",
        "partOf": {"reference": "Organization/%s"}
      }
      """.formatted(cfg.organizationId(), unique, unique, cfg.organizationId());
    try (var sdk = new SatusehatSdk(cfg)) {
      var response = sdk.request("POST", "Organization", null, payload);
      var json = "{\"platform\":\"java\",\"http_status\":" + response.statusCode() + ",\"resourceType\":\"" + value(response.body(), "resourceType") + "\",\"id\":\"" + value(response.body(), "id") + "\",\"identifier\":\"" + unique + "\"}";
      System.out.println(json);
      if (response.statusCode() < 200 || response.statusCode() > 299) {
        System.err.println(response.body());
        System.exit(1);
      }
    }
  }
}
JAVA
  cp_value="$java_dir:$ROOT/sdks/java/target/classes:$sqlite_jdbc"
  if [ -n "$slf4j_api" ] && [ -f "$slf4j_api" ]; then
    cp_value="$cp_value:$slf4j_api"
  fi
  "$javac_bin" -cp "$cp_value" "$java_dir/LiveWrite.java" &&
    "$java_bin" -cp "$cp_value" LiveWrite
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
$unique = 'SDKTEST-PHP-' . time();
$payload = [
  'resourceType' => 'Organization',
  'active' => true,
  'identifier' => [[
    'use' => 'official',
    'system' => 'http://sys-ids.kemkes.go.id/organization/' . $cfg->organizationId,
    'value' => $unique,
  ]],
  'type' => [[
    'coding' => [[
      'system' => 'http://terminology.hl7.org/CodeSystem/organization-type',
      'code' => 'dept',
      'display' => 'Hospital Department',
    ]],
  ]],
  'name' => 'SDK Sandbox Test PHP ' . $unique,
  'partOf' => ['reference' => 'Organization/' . $cfg->organizationId],
];
$response = $sdk->request('POST', 'Organization', null, json_encode($payload, JSON_UNESCAPED_SLASHES));
$body = json_decode($response['body'] ?? '{}', true) ?: [];
$result = [
  'platform' => 'php',
  'http_status' => $response['statusCode'],
  'resourceType' => $body['resourceType'] ?? null,
  'id' => $body['id'] ?? null,
  'identifier' => $unique,
];
if ($response['statusCode'] < 200 || $response['statusCode'] > 299) {
  $result['issues'] = array_slice($body['issue'] ?? [], 0, 4);
}
echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit($response['statusCode'] >= 200 && $response['statusCode'] <= 299 ? 0 : 1);
PHP
}

run_dotnet() {
  export SATUSEHAT_QUEUE_PATH="$TMP_ROOT/dotnet.db"
  dotnet_dir="$TMP_ROOT/dotnet-live"
  mkdir -p "$dotnet_dir"
  cat > "$dotnet_dir/LiveWrite.csproj" <<EOF
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
var unique = $"SDKTEST-DOTNET-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
var payload = new
{
    resourceType = "Organization",
    active = true,
    identifier = new[] { new { use = "official", system = $"http://sys-ids.kemkes.go.id/organization/{cfg.OrganizationId}", value = unique } },
    type = new[] { new { coding = new[] { new { system = "http://terminology.hl7.org/CodeSystem/organization-type", code = "dept", display = "Hospital Department" } } } },
    name = $"SDK Sandbox Test .NET {unique}",
    partOf = new { reference = $"Organization/{cfg.OrganizationId}" }
};
var response = await sdk.RequestAsync("POST", "Organization", payload: JsonSerializer.Serialize(payload));
using var doc = JsonDocument.Parse(response.Body);
var root = doc.RootElement;
string? prop(string name) => root.TryGetProperty(name, out var value) ? value.GetString() : null;
var result = new Dictionary<string, object?>
{
    ["platform"] = "dotnet",
    ["http_status"] = response.StatusCode,
    ["resourceType"] = prop("resourceType"),
    ["id"] = prop("id"),
    ["identifier"] = unique,
};
Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
return response.StatusCode is >= 200 and <= 299 ? 0 : 1;
CS
  DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-Major}" "$dotnet_bin" run --project "$dotnet_dir/LiveWrite.csproj" --no-launch-profile
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
  printf '\n%s platform(s) failed live SATUSEHAT write validation.\n' "$failures" >&2
  exit 1
fi

printf '\nAll live SATUSEHAT sandbox write validations passed.\n'
