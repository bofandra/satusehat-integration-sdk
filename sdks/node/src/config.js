export const SANDBOX_OAUTH='https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1';
export const SANDBOX_FHIR='https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1';
export const PRODUCTION_OAUTH='https://api-satusehat.kemkes.go.id/oauth2/v1';
export const PRODUCTION_FHIR='https://api-satusehat.kemkes.go.id/fhir-r4/v1';

export class SatusehatConfig {
  constructor(o={}) {
    this.clientId=o.clientId; this.clientSecret=o.clientSecret; this.organizationId=o.organizationId;
    this.environment=(o.environment ?? 'sandbox').toLowerCase(); this.queuePath=o.queuePath ?? './satusehat-sdk.db';
    this.timeoutSeconds=Number(o.timeoutSeconds ?? 30); this.rateLimitRpm=Number(o.rateLimitRpm ?? 300);
    this.maxRetries=Number(o.maxRetries ?? 5); this.processingTimeoutSeconds=Number(o.processingTimeoutSeconds ?? 300);
    this.initialBackoffMs=Number(o.initialBackoffMs ?? 1000); this.maxBackoffMs=Number(o.maxBackoffMs ?? 60000);
    this.oauthBaseUrlOverride=o.oauthBaseUrlOverride; this.fhirBaseUrlOverride=o.fhirBaseUrlOverride;
    if(!['sandbox','production'].includes(this.environment)) throw new Error('environment must be sandbox or production');
    if(!this.clientId||!this.clientSecret||!this.organizationId) throw new Error('clientId, clientSecret, organizationId are required');
    if(this.rateLimitRpm<=0||this.maxRetries<=0||this.processingTimeoutSeconds<=0) throw new Error('rateLimitRpm, maxRetries, and processingTimeoutSeconds must be > 0');
  }
  get oauthBaseUrl(){return (this.oauthBaseUrlOverride ?? (this.environment==='production'?PRODUCTION_OAUTH:SANDBOX_OAUTH)).replace(/\/$/,'')}
  get fhirBaseUrl(){return (this.fhirBaseUrlOverride ?? (this.environment==='production'?PRODUCTION_FHIR:SANDBOX_FHIR)).replace(/\/$/,'')}
  static fromEnv(){return new SatusehatConfig({clientId:process.env.SATUSEHAT_CLIENT_ID,clientSecret:process.env.SATUSEHAT_CLIENT_SECRET,organizationId:process.env.SATUSEHAT_ORGANIZATION_ID,environment:process.env.SATUSEHAT_ENV,queuePath:process.env.SATUSEHAT_QUEUE_PATH,timeoutSeconds:process.env.SATUSEHAT_TIMEOUT_SECONDS,rateLimitRpm:process.env.SATUSEHAT_RATE_LIMIT_RPM,maxRetries:process.env.SATUSEHAT_MAX_RETRIES,processingTimeoutSeconds:process.env.SATUSEHAT_PROCESSING_TIMEOUT_SECONDS,initialBackoffMs:process.env.SATUSEHAT_INITIAL_BACKOFF_MS,maxBackoffMs:process.env.SATUSEHAT_MAX_BACKOFF_MS,oauthBaseUrlOverride:process.env.SATUSEHAT_OAUTH_BASE_URL,fhirBaseUrlOverride:process.env.SATUSEHAT_FHIR_BASE_URL})}
}
