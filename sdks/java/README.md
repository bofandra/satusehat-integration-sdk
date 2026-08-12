# Java SDK

Java 21+ reference implementation using `java.net.http.HttpClient` and SQLite JDBC.

```bash
mvn test
```

```java
SatusehatConfig cfg = SatusehatConfig.fromEnv();
try (SatusehatSdk sdk = new SatusehatSdk(cfg)) {
    String id = sdk.enqueueIdempotent("POST", "Encounter", null, payloadJson, "encounter:local-visit-123:create");
    sdk.processOnce(20);
    var stats = sdk.queueStats();
}
```
