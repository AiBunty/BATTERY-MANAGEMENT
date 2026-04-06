<?php

declare(strict_types=1);

namespace App\Shared\Http;

final class Response
{
    public function __construct(
        private readonly int $status,
        private readonly array $payload,
    ) {
    }

    public static function json(array $payload, int $status = 200): self
    {
        return new self($status, $payload);
    }

    public function send(): void
    {
        http_response_code($this->status);
        header('Content-Type: application/json');
        echo json_encode($this->payload, JSON_UNESCAPED_SLASHES);
    }
}
