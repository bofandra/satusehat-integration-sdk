<?php
require __DIR__.'/../vendor/autoload.php';
use Satusehat\IntegrationSdk\Config;use Satusehat\IntegrationSdk\SatusehatSdk;use Satusehat\IntegrationSdk\ErrorClassifier;
[$c,$r]=ErrorClassifier::classify(429);if($c!=='rate_limited'||!$r)exit(1);$p=sys_get_temp_dir().'/ss-sdk-'.bin2hex(random_bytes(4)).'.db';$cfg=new Config('x','y','1','sandbox',$p,1,100000,5,1,10);$sdk=new SatusehatSdk($cfg);$id=$sdk->enqueue('POST','Encounter',null,'{"resourceType":"Encounter"}');if(!$id)exit(2);@unlink($p);echo "OK\n";
