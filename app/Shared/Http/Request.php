<?php

declare(strict_types=1);

namespace App\Shared\Http;

final class Request
{
    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $headers,
        public readonly array $body,
        public readonly string $ip,
        public readonly array $params = [],
    ) {
    }

    public static function capture(): self
    {
        $uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $raw = file_get_contents('php://input') ?: '';
        $decoded = json_decode($raw, true);

        $headers = function_exists('getallheaders') ? getallheaders() : [];

        return new self(
            method: $method,
            path: $uri,
            headers: $headers,
            body: is_array($decoded) ? $decoded : [],
            ip: $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0',
            params: [],
        );
    }

    public function input(string $key, mixed $default = null): mixed
    {
        return $this->body[$key] ?? $default;
    }

    public function param(string $key, mixed $default = null): mixed
    {
        return $this->params[$key] ?? $default;
    }

    public function header(string $name, mixed $default = null): mixed
    {
        foreach ($this->headers as $key => $value) {
            if (strcasecmp((string) $key, $name) === 0) {
                return $value;
            }
        }

        return $default;
    }

    public function withParams(array $params): self
    {
        return new self(
            method: $this->method,
            path: $this->path,
            headers: $this->headers,
            body: $this->body,
            ip: $this->ip,
            params: $params,
        );
    }
}
