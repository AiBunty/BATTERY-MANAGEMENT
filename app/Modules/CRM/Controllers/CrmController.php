<?php

declare(strict_types=1);

namespace App\Modules\CRM\Controllers;

use App\Modules\CRM\Services\CrmService;
use App\Shared\Http\Request;
use App\Shared\Http\Response;
use InvalidArgumentException;
use JsonException;

final class CrmController
{
    public function __construct(private readonly CrmService $crmService)
    {
    }

    public function upsertCustomer(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->upsertCustomer($this->body($request)), 201);
    }

    public function createLead(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->createLead($this->body($request)), 201);
    }

    public function transitionLead(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->transitionLead($this->body($request)), 200);
    }

    public function createSegment(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->createSegment($this->body($request)), 201);
    }

    public function resolveSegment(Request $request): Response
    {
        return $this->wrap(function () use ($request): array {
            $payload = $this->body($request);
            $segmentId = (int) ($payload['segment_id'] ?? 0);
            $tenantId = (int) ($payload['tenant_id'] ?? 0);
            if ($segmentId <= 0 || $tenantId <= 0) {
                throw new InvalidArgumentException('segment_id and tenant_id are required.');
            }

            return [
                'segment_id' => $segmentId,
                'customers' => $this->crmService->resolveSegment($segmentId, $tenantId),
            ];
        }, 200);
    }

    public function createCampaign(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->createCampaign($this->body($request)), 201);
    }

    public function dispatchCampaign(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->dispatchCampaign($this->body($request)), 200);
    }

    public function optOut(Request $request): Response
    {
        return $this->wrap(fn () => $this->crmService->optOut($this->body($request)), 200);
    }

    public function dashboardStats(Request $request): Response
    {
        return $this->wrap(function () use ($request): array {
            $body = $this->body($request);
            $body['tenant_id'] = $this->resolveTenantId((string) ($body['tenant_slug'] ?? 'default'));
            return $this->crmService->dashboardStats($body);
        }, 200);
    }

    public function listCustomers(Request $request): Response
    {
        return $this->wrap(function () use ($request): array {
            $body = $this->body($request);
            $body['tenant_id'] = $this->resolveTenantId((string) ($body['tenant_slug'] ?? 'default'));
            return $this->crmService->listCustomers($body);
        }, 200);
    }

    private function resolveTenantId(string $slug): int
    {
        $pdo = \App\Shared\Database\Connection::get();
        $stmt = $pdo->prepare('SELECT id FROM tenants WHERE slug = :slug AND is_active = 1 LIMIT 1');
        $stmt->execute(['slug' => $slug]);
        $row = $stmt->fetch();
        if (!$row) {
            throw new \InvalidArgumentException('Tenant not found: ' . $slug);
        }
        return (int) $row['id'];
    }

    /** @return array<string,mixed> */
    private function body(Request $request): array
    {
        return $request->body;
    }

    private function wrap(callable $handler, int $successStatus): Response
    {
        try {
            /** @var array<string,mixed> $data */
            $data = $handler();
            return Response::json([
                'success' => true,
                'ok' => true,
                'data' => $data,
                'error' => null,
            ], $successStatus);
        } catch (InvalidArgumentException $exception) {
            return Response::json([
                'success' => false,
                'ok' => false,
                'data' => null,
                'error' => [
                    'code' => 'VALIDATION_ERROR',
                    'message' => $exception->getMessage(),
                ],
            ], 422);
        } catch (JsonException $exception) {
            return Response::json([
                'success' => false,
                'ok' => false,
                'data' => null,
                'error' => [
                    'code' => 'INVALID_JSON',
                    'message' => 'Invalid JSON payload.',
                ],
            ], 400);
        } catch (\Throwable $exception) {
            return Response::json([
                'success' => false,
                'ok' => false,
                'data' => null,
                'error' => [
                    'code' => 'INTERNAL_ERROR',
                    'message' => 'Internal server error.',
                ],
            ], 500);
        }
    }
}
