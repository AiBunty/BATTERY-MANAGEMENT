<?php

declare(strict_types=1);

namespace App\Modules\Tracking\Controllers;

use App\Modules\Tracking\Services\TrackingService;
use App\Shared\Http\Request;
use App\Shared\Http\Response;

final class TrackingController
{
    private TrackingService $service;

    public function __construct()
    {
        $this->service = new TrackingService();
    }

    public function show(Request $request): Response
    {
        $token = (string) $request->param('token', '');
        $result = $this->service->resolve($token);

        if ($result === null) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'INVALID_OR_EXPIRED_LINK', 'message' => 'Invalid or expired link'],
            ], 404);
        }

        if (($result['expired'] ?? false) === true) {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'TRACKING_EXPIRED', 'message' => 'Tracking link has expired'],
            ], 410);
        }

        return Response::json(['success' => true, 'data' => $result]);
    }

    public function lookup(Request $request): Response
    {
        $tenantSlug = (string) $request->input('tenant_slug', 'default');
        $ticket = (string) $request->input('ticket_number', '');

        if ($ticket === '') {
            return Response::json([
                'success' => false,
                'error' => ['code' => 'VALIDATION_ERROR', 'message' => 'ticket_number is required'],
            ], 422);
        }

        $result = $this->service->lookupByTicket($tenantSlug, strtoupper($ticket), $request->ip);
        if (!$result['ok']) {
            return Response::json([
                'success' => false,
                'error' => ['code' => $result['code'], 'message' => $result['message']],
            ], $result['status']);
        }

        return Response::json([
            'success' => true,
            'data' => [
                'token' => $result['token'],
                'tracking_url' => $result['tracking_url'],
            ],
        ], 200);
    }
}
