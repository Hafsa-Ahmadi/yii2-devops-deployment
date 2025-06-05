<?php

// comment out the following two lines when deployed to production
defined('YII_DEBUG') or define('YII_DEBUG', getenv('YII_DEBUG') ? (bool)getenv('YII_DEBUG') : true);
defined('YII_ENV') or define('YII_ENV', getenv('YII_ENV') ?: 'dev');

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../vendor/yiisoft/yii2/Yii.php';

$config = require __DIR__ . '/../config/web.php';

try {
    $application = new yii\web\Application($config);
    $application->run();
} catch (Exception $e) {
    echo "Application Error: " . $e->getMessage();
    exit(1);
}