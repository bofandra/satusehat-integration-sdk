package id.kemkes.satusehat;

public record SatusehatConfig(String clientId,String clientSecret,String organizationId,String environment,String queuePath,int timeoutSeconds,int rateLimitRpm,int maxRetries,int initialBackoffMs,int maxBackoffMs,String oauthBaseUrlOverride,String fhirBaseUrlOverride) {
 public static final String SANDBOX_OAUTH="https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1", SANDBOX_FHIR="https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1", PRODUCTION_OAUTH="https://api-satusehat.kemkes.go.id/oauth2/v1", PRODUCTION_FHIR="https://api-satusehat.kemkes.go.id/fhir-r4/v1";
 public SatusehatConfig { if(!"sandbox".equals(environment)&&!"production".equals(environment))throw new IllegalArgumentException("environment must be sandbox or production");if(blank(clientId)||blank(clientSecret)||blank(organizationId))throw new IllegalArgumentException("credentials and organizationId required"); }
 private static boolean blank(String s){return s==null||s.isBlank();}
 public String oauthBaseUrl(){return trim(oauthBaseUrlOverride!=null?oauthBaseUrlOverride:("production".equals(environment)?PRODUCTION_OAUTH:SANDBOX_OAUTH));}
 public String fhirBaseUrl(){return trim(fhirBaseUrlOverride!=null?fhirBaseUrlOverride:("production".equals(environment)?PRODUCTION_FHIR:SANDBOX_FHIR));}
 private static String trim(String s){return s.endsWith("/")?s.substring(0,s.length()-1):s;}
 private static int envInt(String k,int d){try{return Integer.parseInt(System.getenv().getOrDefault(k,Integer.toString(d)));}catch(Exception e){return d;}}
 public static SatusehatConfig fromEnv(){var e=System.getenv();return new SatusehatConfig(e.get("SATUSEHAT_CLIENT_ID"),e.get("SATUSEHAT_CLIENT_SECRET"),e.get("SATUSEHAT_ORGANIZATION_ID"),e.getOrDefault("SATUSEHAT_ENV","sandbox").toLowerCase(),e.getOrDefault("SATUSEHAT_QUEUE_PATH","./satusehat-sdk.db"),envInt("SATUSEHAT_TIMEOUT_SECONDS",30),envInt("SATUSEHAT_RATE_LIMIT_RPM",300),envInt("SATUSEHAT_MAX_RETRIES",5),envInt("SATUSEHAT_INITIAL_BACKOFF_MS",1000),envInt("SATUSEHAT_MAX_BACKOFF_MS",60000),e.get("SATUSEHAT_OAUTH_BASE_URL"),e.get("SATUSEHAT_FHIR_BASE_URL"));}
}
