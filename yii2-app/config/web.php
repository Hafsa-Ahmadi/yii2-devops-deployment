<?php

$params = [];

$config = [
    'id' => 'yii2-devops',
    'name' => 'Yii2 DevOps Application',
    'basePath' => dirname(__DIR__),
    'bootstrap' => ['log'],
    'aliases' => [
        '@bower' => '@vendor/bower-asset',
        '@npm'   => '@vendor/npm-asset',
    ],
    'components' => [
        'request' => [
            'cookieValidationKey' => getenv('COOKIE_VALIDATION_KEY') ?: 'test-key-for-devops-assessment',
            'enableCsrfValidation' => false, // Disable for API endpoints
        ],
        'cache' => [
            'class' => 'yii\caching\FileCache',
        ],
        'user' => [
            'identityClass' => 'app\models\User',
            'enableAutoLogin' => true,
        ],
        'errorHandler' => [
            'errorAction' => 'site/error',
        ],
        'mailer' => [
            'class' => 'yii\swiftmailer\Mailer',
            'useFileTransport' => true,
        ],
        'log' => [
            'traceLevel' => YII_DEBUG ? 3 : 0,
            'targets' => [
                [
                    'class' => 'yii\log\FileTarget',
                    'levels' => ['error', 'warning'],
                    'logFile' => '@runtime/logs/app.log',
                ],
            ],
        ],
        'db' => [
            'class' => 'yii\db\Connection',
            'dsn' => 'sqlite:' . __DIR__ . '/../runtime/db.sqlite',
            'charset' => 'utf8',
        ],
        'urlManager' => [
            'enablePrettyUrl' => true,
            'showScriptName' => false,
            'rules' => [
                '' => 'site/index',
                'health' => 'site/health',
                'info' => 'site/info',
                '<action:\w+>' => 'site/<action>',
            ],
        ],
        'response' => [
            'format' => yii\web\Response::FORMAT_JSON,
            'charset' => 'UTF-8',
        ],
    ],
    'controllerMap' => [
        'site' => [
            'class' => 'yii\web\Controller',
            'actions' => [
                'index' => function() {
                    \Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;
                    return [
                        'status' => 'success',
                        'message' => 'Yii2 DevOps Application is running!',
                        'timestamp' => date('c'),
                        'hostname' => gethostname(),
                        'environment' => YII_ENV,
                        'debug' => YII_DEBUG,
                        'version' => '1.0.0',
                    ];
                },
                'health' => function() {
                    \Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;
                    
                    $status = 'healthy';
                    $checks = [
                        'app' => 'ok',
                        'database' => 'ok',
                        'cache' => 'ok',
                    ];
                    
                    // Check database
                    try {
                        \Yii::$app->db->open();
                        $checks['database'] = 'ok';
                    } catch (Exception $e) {
                        $checks['database'] = 'error';
                        $status = 'unhealthy';
                    }
                    
                    // Check cache
                    try {
                        \Yii::$app->cache->set('health_check', time(), 10);
                        $checks['cache'] = 'ok';
                    } catch (Exception $e) {
                        $checks['cache'] = 'error';
                        $status = 'unhealthy';
                    }
                    
                    if ($status === 'unhealthy') {
                        \Yii::$app->response->statusCode = 503;
                    }
                    
                    return [
                        'status' => $status,
                        'timestamp' => date('c'),
                        'checks' => $checks,
                        'uptime' => sys_getloadavg()[0],
                    ];
                },
                'info' => function() {
                    \Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;
                    return [
                        'php_version' => PHP_VERSION,
                        'yii_version' => \Yii::getVersion(),
                        'server_time' => date('c'),
                        'timezone' => date_default_timezone_get(),
                        'memory_usage' => memory_get_usage(true),
                        'memory_peak' => memory_get_peak_usage(true),
                    ];
                }
            ]
        ]
    ],
    'params' => $params,
];

if (YII_ENV_DEV) {
    // configuration adjustments for 'dev' environment
    $config['bootstrap'][] = 'debug';
    $config['modules']['debug'] = [
        'class' => 'yii\debug\Module',
    ];

    $config['bootstrap'][] = 'gii';
    $config['modules']['gii'] = [
        'class' => 'yii\gii\Module',
    ];
}

return $config;