<?php

declare(strict_types=1);

namespace App\Modules\Identity\Services;

use App\Shared\Config\Env;

final class TokenService
{
    public function issueAccessToken(int $tenantId, int $userId, string $tenantSlug): string
    {
        $payload = [
            'iss' => Env::get('APP_URL', 'http://localhost:8000'),
            'aud' => 'battery-local',
            'tenant_id' => $tenantId,
            'tenant_slug' => $tenantSlug,
            'sub' => $userId,
            'iat' => time(),
            'exp' => time() + (int) Env::get('JWT_ACCESS_TTL', '900'),
        ];

        $payloadEncoded = $this->base64UrlEncode(json_encode($payload, JSON_UNESCAPED_SLASHES) ?: '{}');
        $signature = hash_hmac('sha256', $payloadEncoded, (string) Env::get('JWT_SECRET', 'local-secret'));

        return $payloadEncoded . '.' . $signature;
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
