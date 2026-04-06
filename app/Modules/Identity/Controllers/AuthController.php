<?php

declare(strict_types=1);

namespace App\Modules\Identity\Controllers;

use App\Modules\Identity\Services\AuthService;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class AuthController
{
    private AuthService $service;

    public function __construct()
    {
        $this->service = new AuthService();
    }

    public function sendOtp(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $email = (string) $request->input('email', '');

        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'Valid email is required'],
            ], 422);
        }

        $result = $this->service->sendOtp($tenantSlug, strtolower($email), $request->ip);

        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => [
                'message' => 'OTP sent',
                'debug_otp' => $result['debug_otp'],
            ],
        ], 200);
    }

    public function verifyOtp(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $email = (string) $request->input('email', '');
        $otp = (string) $request->input('otp', '');

        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($otp) !== 6) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'Valid email and 6-digit OTP are required'],
            ], 422);
        }

        $result = $this->service->verifyOtp($tenantSlug, strtolower($email), $otp, $request->ip);

        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => [
                'access_token' => $result['access_token'],
                'refresh_token' => $result['refresh_token'],
                'expires_in' => $result['expires_in'],
            ],
        ], 200);
    }

    public function refresh(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $refreshToken = (string) $request->input('refresh_token', '');

        if ($refreshToken === '') {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'refresh_token is required'],
            ], 422);
        }

        $result = $this->service->refresh($tenantSlug, $refreshToken, $request->ip);
        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => [
                'access_token' => $result['access_token'],
                'refresh_token' => $result['refresh_token'],
                'expires_in' => $result['expires_in'],
            ],
        ], 200);
    }

    public function logout(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $refreshToken = (string) $request->input('refresh_token', '');

        if ($refreshToken === '') {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'refresh_token is required'],
            ], 422);
        }

        $result = $this->service->logout($tenantSlug, $refreshToken);
        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => ['message' => 'Logged out'],
        ], 200);
    }
}
