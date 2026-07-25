<?php

/**
 * FrankenPHP worker entry point for Winter CMS under Laravel Octane.
 *
 * Octane ships a stub that resolves the application relative to its own location, assuming it sits
 * in a `public/` directory one level below the project root. Winter's public directory is produced
 * by `winter:mirror` and its Application::publicPath() returns the project root, so that relative
 * resolution does not hold here. The paths are therefore taken from the environment the image
 * already defines, with the project root as the fallback.
 */

$basePath = getenv('APP_BASE_PATH') ?: '/winter';
$publicPath = getenv('SERVER_ROOT') ?: $basePath . '/public';

$_SERVER['APP_BASE_PATH'] = $_ENV['APP_BASE_PATH'] = $basePath;
$_SERVER['APP_PUBLIC_PATH'] = $_ENV['APP_PUBLIC_PATH'] = $publicPath;

$worker = $basePath . '/vendor/laravel/octane/bin/frankenphp-worker.php';

if (!is_file($worker)) {
    fwrite(STDERR, sprintf("Octane's FrankenPHP worker was not found at %s.\n", $worker));

    exit(1);
}

require $worker;
