export class TokenProvider{
 constructor(config){this.config=config;this.token=null;this.expiresAt=0;this.pending=null}
 invalidate(){this.token=null;this.expiresAt=0}
 async getToken(){if(this.token&&Date.now()<this.expiresAt-60000)return this.token;if(this.pending)return this.pending;this.pending=this.#fetch();try{return await this.pending}finally{this.pending=null}}
 async #fetch(){const body=new URLSearchParams({client_id:this.config.clientId,client_secret:this.config.clientSecret});const ctl=new AbortController();const t=setTimeout(()=>ctl.abort(),this.config.timeoutSeconds*1000);try{const r=await fetch(`${this.config.oauthBaseUrl}/accesstoken?grant_type=client_credentials`,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded','accept':'application/json'},body,signal:ctl.signal});const text=await r.text();if(!r.ok)throw new Error(`OAuth HTTP ${r.status}: ${text.slice(0,1000)}`);const obj=JSON.parse(text);if(!obj.access_token)throw new Error('OAuth response missing access_token');this.token=obj.access_token;this.expiresAt=Date.now()+Number(obj.expires_in??300)*1000;return this.token}finally{clearTimeout(t)}}
}
