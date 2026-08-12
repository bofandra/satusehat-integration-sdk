# Java SDK

Java 21+ reference implementation using `java.net.http.HttpClient` and SQLite JDBC.

```bash
mvn test
```

```java
SatusehatConfig cfg = SatusehatConfig.fromEnv();
try (SatusehatSdk sdk = new SatusehatSdk(cfg)) {
    String id = sdk.enqueue("POST", "Encounter", null, payloadJson);
    sdk.processOnce(20);
}
```
