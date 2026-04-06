<?php

declare(strict_types=1);

namespace App\Shared\Http;

final class Router
{
    private array $routes = [];

    public function get(string $path, callable $handler): void
    {
        $this->routes['GET'][$path] = $handler;
    }

    public function post(string $path, callable $handler): void
    {
        $this->routes['POST'][$path] = $handler;
    }

    public function dispatch(Request $request): Response
    {
        $methodRoutes = $this->routes[$request->method] ?? [];
        $handler = $methodRoutes[$request->path] ?? null;

        if ($handler !== null) {
            return $handler($request);
        }

        foreach ($methodRoutes as $pattern => $candidate) {
            if (!str_contains($pattern, '{')) {
                continue;
            }

            $regex = preg_replace('/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/', '(?P<$1>[^/]+)', $pattern);
            if ($regex === null) {
                continue;
            }

            $regex = '#^' . $regex . '$#';
            if (!preg_match($regex, $request->path, $matches)) {
                continue;
            }

            $params = [];
            foreach ($matches as $k => $v) {
                if (is_string($k)) {
                    $params[$k] = $v;
                }
            }

            return $candidate($request->withParams($params));
        }

        return Response::json([
            'success' => false,
            'error' => [
                'code' => 'NOT_FOUND',
                'message' => 'Route not found',
            ],
        ], 404);
    }
}
