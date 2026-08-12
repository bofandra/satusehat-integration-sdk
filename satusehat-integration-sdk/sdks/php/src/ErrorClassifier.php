<?php
namespace Satusehat\IntegrationSdk;
final class ErrorClassifier {public static function classify(int $s):array{if($s>=200&&$s<=299)return['success',false];return match($s){401=>['unauthorized',true],403=>['forbidden',false],404=>['not_found',false],409=>['conflict',false],422=>['validation_error',false],429=>['rate_limited',true],default=>$s>=500&&$s<=599?['server_error',true]:($s>=400&&$s<=499?['invalid_request',false]:['unexpected_http_status',false])};}}
