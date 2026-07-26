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

/*
 * Winter's own entry point, and it has to run before Octane's.
 *
 * bootstrap/autoload.php requires Storm's global helpers and only then Composer's autoloader,
 * deliberately: Storm redefines e(), trans(), collect() and get(), every one of which Laravel also
 * defines, and all of them are guarded by function_exists() so whichever file loads first wins.
 * Winter's index.php and artisan both go through this file, so Storm's versions win in every
 * supported entry point.
 *
 * Octane's worker requires vendor/autoload.php directly and never sees it, which silently hands all
 * four to Laravel. The symptom that exposed it was trans(null) returning the Translator rather than an
 * empty string, making e(trans($value)) a TypeError on any back-end page with a settings menu.
 * collect() returning Illuminate's Collection instead of Storm's is the same defect with a wider blast
 * radius and nothing to point at it.
 *
 * Requiring it here is idempotent: the helpers are function_exists() guarded, and Composer's
 * autoloader registration is guarded too, so Octane requiring vendor/autoload.php afterwards is a
 * no-op.
 */
require $basePath . '/bootstrap/autoload.php';

$worker = $basePath . '/vendor/laravel/octane/bin/frankenphp-worker.php';

if (!is_file($worker)) {
    fwrite(STDERR, sprintf("Octane's FrankenPHP worker was not found at %s.\n", $worker));

    exit(1);
}

require $worker;
