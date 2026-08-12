export function classifyHttp(status){
 if(status>=200&&status<=299)return ['success',false];
 if(status===401)return ['unauthorized',true]; if(status===403)return ['forbidden',false]; if(status===404)return ['not_found',false]; if(status===409)return ['conflict',false]; if(status===422)return ['validation_error',false]; if(status===429)return ['rate_limited',true]; if(status>=500&&status<=599)return ['server_error',true]; if(status>=400&&status<=499)return ['invalid_request',false]; return ['unexpected_http_status',false];
}
export const EventStatus=Object.freeze({QUEUED:'QUEUED',PROCESSING:'PROCESSING',SUCCESS:'SUCCESS',WAITING_FOR_CORRECTION:'WAITING_FOR_CORRECTION',RATE_LIMITED:'RATE_LIMITED',RETRYING:'RETRYING',DEAD_LETTER:'DEAD_LETTER',CANCELLED:'CANCELLED'});
