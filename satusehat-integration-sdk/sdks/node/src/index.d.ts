export type Environment='sandbox'|'production';
export interface ConfigOptions{clientId:string;clientSecret:string;organizationId:string;environment?:Environment;queuePath?:string;timeoutSeconds?:number;rateLimitRpm?:number;maxRetries?:number;initialBackoffMs?:number;maxBackoffMs?:number;oauthBaseUrlOverride?:string;fhirBaseUrlOverride?:string}
export class SatusehatConfig{constructor(o:ConfigOptions);static fromEnv():SatusehatConfig;clientId:string;clientSecret:string;organizationId:string;environment:Environment;queuePath:string;timeoutSeconds:number;rateLimitRpm:number;maxRetries:number;initialBackoffMs:number;maxBackoffMs:number;readonly oauthBaseUrl:string;readonly fhirBaseUrl:string}
export interface FhirResponse{statusCode:number;body:string;headers:Record<string,string>}
export class SatusehatSdk{constructor(config:SatusehatConfig);enqueue(operation:string,resourceType:string,resourceId?:string,payload?:unknown):string;processOnce(limit?:number):Promise<number>;request(operation:string,resourceType:string,resourceId?:string,payload?:unknown):Promise<FhirResponse>;close():void}
export const EventStatus:Readonly<Record<'QUEUED'|'PROCESSING'|'SUCCESS'|'WAITING_FOR_CORRECTION'|'RATE_LIMITED'|'RETRYING'|'DEAD_LETTER'|'CANCELLED',string>>;
export function classifyHttp(status:number):[string,boolean];
