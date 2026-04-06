<?php

declare(strict_types=1);

namespace App\Modules\CRM\Services;

use App\Shared\Database\Connection;
use InvalidArgumentException;
use PDO;

final class CrmService
{
    private const ALLOWED_LIFECYCLE_STAGES = ['LEAD', 'PROSPECT', 'ACTIVE', 'REPEAT', 'CHURNED'];
    private const ALLOWED_CUSTOMER_SOURCES = ['HANDSHAKE', 'MANUAL', 'IMPORT', 'API'];
    private const ALLOWED_LEAD_STAGES = ['NEW', 'CONTACTED', 'QUALIFIED', 'PROPOSAL', 'WON', 'LOST'];
    private const LEAD_STAGE_TRANSITIONS = [
        'NEW' => ['CONTACTED', 'LOST'],
        'CONTACTED' => ['QUALIFIED', 'LOST'],
        'QUALIFIED' => ['PROPOSAL', 'LOST'],
        'PROPOSAL' => ['WON', 'LOST'],
        'WON' => [],
        'LOST' => [],
    ];
    private const ALLOWED_CAMPAIGN_CHANNELS = ['EMAIL', 'WHATSAPP', 'BOTH'];
    private const ALLOWED_OPT_OUT_CHANNELS = ['EMAIL', 'WHATSAPP', 'ALL'];

    public function __construct(private readonly Connection $connection)
    {
    }

    public function upsertCustomer(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $dealerId = (int) ($input['dealer_id'] ?? 0);
        $name = trim((string) ($input['name'] ?? ''));

        if ($tenantId <= 0 || $dealerId <= 0 || $name === '') {
            throw new InvalidArgumentException('tenant_id, dealer_id and name are required.');
        }

        $email = $this->nullableString($input['email'] ?? null);
        $phone = $this->nullableString($input['phone'] ?? null);
        $city = $this->nullableString($input['city'] ?? null);
        $source = strtoupper((string) ($input['source'] ?? 'MANUAL'));
        $lifecycle = strtoupper((string) ($input['lifecycle_stage'] ?? 'LEAD'));
        $totalBought = max(0, (int) ($input['total_batteries_bought'] ?? 0));

        $this->assertTenantUser($tenantId, $dealerId, 'dealer_id');
        $this->assertEnum($source, self::ALLOWED_CUSTOMER_SOURCES, 'source');
        $this->assertEnum($lifecycle, self::ALLOWED_LIFECYCLE_STAGES, 'lifecycle_stage');
        if ($email !== null && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException('email format is invalid.');
        }
        if ($phone !== null && !preg_match('/^[0-9+][0-9]{7,19}$/', $phone)) {
            throw new InvalidArgumentException('phone format is invalid.');
        }

        $pdo = Connection::get();

        if ($email !== null) {
            $lookup = $pdo->prepare(
                'SELECT id FROM crm_customers WHERE tenant_id = :tenant_id AND email = :email LIMIT 1'
            );
            $lookup->execute([
                'tenant_id' => $tenantId,
                'email' => $email,
            ]);

            $existingId = (int) ($lookup->fetchColumn() ?: 0);
            if ($existingId > 0) {
                $update = $pdo->prepare(
                    'UPDATE crm_customers
                     SET dealer_id = :dealer_id,
                         name = :name,
                         phone = :phone,
                         city = :city,
                         lifecycle_stage = :lifecycle_stage,
                         source = :source,
                         total_batteries_bought = :total_batteries_bought
                     WHERE id = :id'
                );
                $update->execute([
                    'dealer_id' => $dealerId,
                    'name' => $name,
                    'phone' => $phone,
                    'city' => $city,
                    'lifecycle_stage' => $lifecycle,
                    'source' => $source,
                    'total_batteries_bought' => $totalBought,
                    'id' => $existingId,
                ]);

                return $this->getCustomerById($existingId);
            }
        }

        $insert = $pdo->prepare(
            'INSERT INTO crm_customers (
                tenant_id,
                dealer_id,
                name,
                email,
                phone,
                city,
                lifecycle_stage,
                source,
                total_batteries_bought
            ) VALUES (
                :tenant_id,
                :dealer_id,
                :name,
                :email,
                :phone,
                :city,
                :lifecycle_stage,
                :source,
                :total_batteries_bought
            )'
        );

        $insert->execute([
            'tenant_id' => $tenantId,
            'dealer_id' => $dealerId,
            'name' => $name,
            'email' => $email,
            'phone' => $phone,
            'city' => $city,
            'lifecycle_stage' => $lifecycle,
            'source' => $source,
            'total_batteries_bought' => $totalBought,
        ]);

        return $this->getCustomerById((int) $pdo->lastInsertId());
    }

    public function createLead(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $customerId = (int) ($input['customer_id'] ?? 0);
        $title = trim((string) ($input['title'] ?? ''));

        if ($tenantId <= 0 || $customerId <= 0 || $title === '') {
            throw new InvalidArgumentException('tenant_id, customer_id and title are required.');
        }

        $assignedTo = isset($input['assigned_to']) ? (int) $input['assigned_to'] : null;
        $source = $this->nullableString($input['source'] ?? null);
        $expectedValue = isset($input['expected_value']) ? (float) $input['expected_value'] : null;
        $followUpAt = $this->nullableString($input['follow_up_at'] ?? null);

        if (mb_strlen($title) > 255) {
            throw new InvalidArgumentException('title is too long.');
        }
        if ($assignedTo !== null) {
            $this->assertTenantUser($tenantId, $assignedTo, 'assigned_to');
        }
        $this->assertCustomerBelongsToTenant($tenantId, $customerId);
        if ($source !== null && mb_strlen($source) > 100) {
            throw new InvalidArgumentException('source is too long.');
        }
        if ($expectedValue !== null && $expectedValue < 0) {
            throw new InvalidArgumentException('expected_value must be non-negative.');
        }
        if ($followUpAt !== null) {
            $this->assertDateTimeString($followUpAt, 'follow_up_at');
        }

        $pdo = Connection::get();

        $insert = $pdo->prepare(
            'INSERT INTO crm_leads (
                tenant_id,
                customer_id,
                assigned_to,
                title,
                source,
                expected_value,
                follow_up_at
            ) VALUES (
                :tenant_id,
                :customer_id,
                :assigned_to,
                :title,
                :source,
                :expected_value,
                :follow_up_at
            )'
        );

        $insert->execute([
            'tenant_id' => $tenantId,
            'customer_id' => $customerId,
            'assigned_to' => $assignedTo,
            'title' => $title,
            'source' => $source,
            'expected_value' => $expectedValue,
            'follow_up_at' => $followUpAt,
        ]);

        return $this->getLeadById((int) $pdo->lastInsertId());
    }

    public function transitionLead(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $leadId = (int) ($input['lead_id'] ?? 0);
        $newStage = strtoupper((string) ($input['new_stage'] ?? ''));
        $userId = (int) ($input['user_id'] ?? 0);

        if ($tenantId <= 0 || $leadId <= 0 || $newStage === '' || $userId <= 0) {
            throw new InvalidArgumentException('tenant_id, lead_id, new_stage and user_id are required.');
        }

        $pdo = Connection::get();

        $lead = $this->getLeadById($leadId);
        if ((int) $lead['tenant_id'] !== $tenantId) {
            throw new InvalidArgumentException('Lead does not belong to tenant.');
        }

        $this->assertTenantUser($tenantId, $userId, 'user_id');
        $this->assertEnum($newStage, self::ALLOWED_LEAD_STAGES, 'new_stage');

        $oldStage = (string) $lead['stage'];
        $allowed = self::LEAD_STAGE_TRANSITIONS[$oldStage] ?? [];
        if (!in_array($newStage, $allowed, true)) {
            throw new InvalidArgumentException(sprintf('Invalid lead transition from %s to %s.', $oldStage, $newStage));
        }
        $closedAt = in_array($newStage, ['WON', 'LOST'], true) ? (new \DateTimeImmutable())->format('Y-m-d H:i:s') : null;

        $update = $pdo->prepare(
            'UPDATE crm_leads SET stage = :stage, closed_at = :closed_at WHERE id = :id'
        );
        $update->execute([
            'stage' => $newStage,
            'closed_at' => $closedAt,
            'id' => $leadId,
        ]);

        $activity = $pdo->prepare(
            'INSERT INTO crm_lead_activities (
                tenant_id,
                lead_id,
                user_id,
                activity_type,
                body,
                old_stage,
                new_stage
            ) VALUES (
                :tenant_id,
                :lead_id,
                :user_id,
                :activity_type,
                :body,
                :old_stage,
                :new_stage
            )'
        );

        $activity->execute([
            'tenant_id' => $tenantId,
            'lead_id' => $leadId,
            'user_id' => $userId,
            'activity_type' => 'STAGE_CHANGE',
            'body' => $this->nullableString($input['note'] ?? null),
            'old_stage' => $oldStage,
            'new_stage' => $newStage,
        ]);

        return $this->getLeadById($leadId);
    }

    public function createSegment(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $name = trim((string) ($input['name'] ?? ''));
        $rules = $input['rules'] ?? null;

        if ($tenantId <= 0 || $name === '' || !is_array($rules)) {
            throw new InvalidArgumentException('tenant_id, name and rules are required.');
        }

        if (mb_strlen($name) > 255) {
            throw new InvalidArgumentException('name is too long.');
        }
        $this->validateSegmentRules($rules);

        $createdBy = isset($input['created_by']) ? (int) $input['created_by'] : null;
        if ($createdBy !== null) {
            $this->assertTenantUser($tenantId, $createdBy, 'created_by');
        }

        $pdo = Connection::get();

        $insert = $pdo->prepare(
            'INSERT INTO crm_segments (tenant_id, name, rules, created_by) VALUES (:tenant_id, :name, :rules, :created_by)'
        );

        $insert->execute([
            'tenant_id' => $tenantId,
            'name' => $name,
            'rules' => json_encode($rules, JSON_THROW_ON_ERROR),
            'created_by' => $createdBy,
        ]);

        return $this->getSegmentById((int) $pdo->lastInsertId());
    }

    public function resolveSegment(int $segmentId, int $tenantId): array
    {
        $segment = $this->getSegmentById($segmentId);
        if ((int) $segment['tenant_id'] !== $tenantId) {
            throw new InvalidArgumentException('Segment does not belong to tenant.');
        }

        $rules = json_decode((string) $segment['rules'], true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($rules)) {
            throw new InvalidArgumentException('Segment rules are invalid.');
        }
        $this->validateSegmentRules($rules);

        $sql = 'SELECT id, name, email, phone, lifecycle_stage, city, dealer_id FROM crm_customers WHERE tenant_id = :tenant_id';
        $params = ['tenant_id' => $tenantId];

        if (!empty($rules['lifecycle_stage'])) {
            $sql .= ' AND lifecycle_stage = :lifecycle_stage';
            $params['lifecycle_stage'] = (string) $rules['lifecycle_stage'];
        }

        if (!empty($rules['dealer_id'])) {
            $sql .= ' AND dealer_id = :dealer_id';
            $params['dealer_id'] = (int) $rules['dealer_id'];
        }

        if (!empty($rules['city'])) {
            $sql .= ' AND city = :city';
            $params['city'] = (string) $rules['city'];
        }

        $sql .= ' ORDER BY id ASC';

        $stmt = Connection::get()->prepare($sql);
        $stmt->execute($params);

        return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    }

    public function createCampaign(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $name = trim((string) ($input['name'] ?? ''));
        $channel = strtoupper((string) ($input['channel'] ?? 'EMAIL'));
        $segmentId = isset($input['segment_id']) ? (int) $input['segment_id'] : null;
        $createdBy = isset($input['created_by']) ? (int) $input['created_by'] : null;

        if ($tenantId <= 0 || $name === '' || $segmentId === null || $segmentId <= 0) {
            throw new InvalidArgumentException('tenant_id, name and segment_id are required.');
        }

        $this->assertEnum($channel, self::ALLOWED_CAMPAIGN_CHANNELS, 'channel');
        $this->assertSegmentBelongsToTenant($tenantId, $segmentId);
        if ($createdBy !== null) {
            $this->assertTenantUser($tenantId, $createdBy, 'created_by');
        }

        $pdo = Connection::get();

        $insert = $pdo->prepare(
            'INSERT INTO crm_campaigns (tenant_id, name, channel, segment_id, created_by) VALUES (:tenant_id, :name, :channel, :segment_id, :created_by)'
        );

        $insert->execute([
            'tenant_id' => $tenantId,
            'name' => $name,
            'channel' => $channel,
            'segment_id' => $segmentId,
            'created_by' => $createdBy,
        ]);

        return $this->getCampaignById((int) $pdo->lastInsertId());
    }

    public function dispatchCampaign(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $campaignId = (int) ($input['campaign_id'] ?? 0);

        if ($tenantId <= 0 || $campaignId <= 0) {
            throw new InvalidArgumentException('tenant_id and campaign_id are required.');
        }

        $campaign = $this->getCampaignById($campaignId);
        if ((int) $campaign['tenant_id'] !== $tenantId) {
            throw new InvalidArgumentException('Campaign does not belong to tenant.');
        }

        if (!in_array((string) $campaign['status'], ['DRAFT', 'SCHEDULED'], true)) {
            throw new InvalidArgumentException('Campaign can only be dispatched from DRAFT or SCHEDULED status.');
        }

        $segmentId = (int) ($campaign['segment_id'] ?? 0);
        if ($segmentId <= 0) {
            throw new InvalidArgumentException('Campaign segment is missing.');
        }

        $customers = $this->resolveSegment($segmentId, $tenantId);
        $pdo = Connection::get();

        $channels = $this->expandChannels((string) $campaign['channel']);
        $total = 0;
        $sent = 0;

        $updateDispatching = $pdo->prepare('UPDATE crm_campaigns SET status = :status WHERE id = :id');
        $updateDispatching->execute(['status' => 'DISPATCHING', 'id' => $campaignId]);

        foreach ($customers as $customer) {
            $customerId = (int) $customer['id'];
            foreach ($channels as $channel) {
                if ($this->isOptedOut($tenantId, $customerId, $channel)) {
                    continue;
                }

                $address = $channel === 'EMAIL'
                    ? $this->nullableString($customer['email'] ?? null)
                    : $this->nullableString($customer['phone'] ?? null);

                if ($address === null) {
                    continue;
                }

                $total++;
                $recipient = $pdo->prepare(
                    'INSERT INTO crm_campaign_recipients (
                        tenant_id,
                        campaign_id,
                        customer_id,
                        channel,
                        address,
                        status,
                        sent_at
                    ) VALUES (
                        :tenant_id,
                        :campaign_id,
                        :customer_id,
                        :channel,
                        :address,
                        :status,
                        :sent_at
                    )
                    ON DUPLICATE KEY UPDATE
                        address = VALUES(address),
                        status = VALUES(status),
                        sent_at = VALUES(sent_at)'
                );

                $recipient->execute([
                    'tenant_id' => $tenantId,
                    'campaign_id' => $campaignId,
                    'customer_id' => $customerId,
                    'channel' => $channel,
                    'address' => $address,
                    'status' => 'SENT',
                    'sent_at' => (new \DateTimeImmutable())->format('Y-m-d H:i:s'),
                ]);
                $sent++;
            }
        }

        $complete = $pdo->prepare(
            'UPDATE crm_campaigns
             SET status = :status,
                 total_recipients = :total_recipients,
                 sent_count = :sent_count,
                 failed_count = :failed_count
             WHERE id = :id'
        );
        $complete->execute([
            'status' => 'COMPLETED',
            'total_recipients' => $total,
            'sent_count' => $sent,
            'failed_count' => max(0, $total - $sent),
            'id' => $campaignId,
        ]);

        return $this->getCampaignById($campaignId);
    }

    public function optOut(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        $customerId = (int) ($input['customer_id'] ?? 0);
        $channel = (string) ($input['channel'] ?? 'ALL');

        if ($tenantId <= 0 || $customerId <= 0) {
            throw new InvalidArgumentException('tenant_id and customer_id are required.');
        }

        $channel = strtoupper($channel);
        $this->assertEnum($channel, self::ALLOWED_OPT_OUT_CHANNELS, 'channel');
        $this->assertCustomerBelongsToTenant($tenantId, $customerId);

        $stmt = Connection::get()->prepare(
            'INSERT INTO crm_opt_outs (tenant_id, customer_id, channel, reason)
             VALUES (:tenant_id, :customer_id, :channel, :reason)
             ON DUPLICATE KEY UPDATE reason = VALUES(reason), opted_out_at = CURRENT_TIMESTAMP'
        );

        $stmt->execute([
            'tenant_id' => $tenantId,
            'customer_id' => $customerId,
            'channel' => $channel,
            'reason' => $this->nullableString($input['reason'] ?? null),
        ]);

        return [
            'tenant_id' => $tenantId,
            'customer_id' => $customerId,
            'channel' => $channel,
            'status' => 'OPTED_OUT',
        ];
    }

    private function isOptedOut(int $tenantId, int $customerId, string $channel): bool
    {
        $stmt = Connection::get()->prepare(
            'SELECT 1
             FROM crm_opt_outs
             WHERE tenant_id = :tenant_id
               AND customer_id = :customer_id
               AND (channel = :channel OR channel = :all_channel)
             LIMIT 1'
        );
        $stmt->execute([
            'tenant_id' => $tenantId,
            'customer_id' => $customerId,
            'channel' => $channel,
            'all_channel' => 'ALL',
        ]);

        return (bool) $stmt->fetchColumn();
    }

    private function getCustomerById(int $id): array
    {
        $stmt = Connection::get()->prepare('SELECT * FROM crm_customers WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row === false) {
            throw new InvalidArgumentException('Customer not found.');
        }

        return $row;
    }

    private function getLeadById(int $id): array
    {
        $stmt = Connection::get()->prepare('SELECT * FROM crm_leads WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row === false) {
            throw new InvalidArgumentException('Lead not found.');
        }

        return $row;
    }

    private function getSegmentById(int $id): array
    {
        $stmt = Connection::get()->prepare('SELECT * FROM crm_segments WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row === false) {
            throw new InvalidArgumentException('Segment not found.');
        }

        return $row;
    }

    private function getCampaignById(int $id): array
    {
        $stmt = Connection::get()->prepare('SELECT * FROM crm_campaigns WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row === false) {
            throw new InvalidArgumentException('Campaign not found.');
        }

        return $row;
    }

    private function nullableString(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $string = trim((string) $value);
        return $string === '' ? null : $string;
    }

    private function assertEnum(string $value, array $allowed, string $field): void
    {
        if (!in_array($value, $allowed, true)) {
            throw new InvalidArgumentException(sprintf('%s is invalid.', $field));
        }
    }

    private function assertTenantUser(int $tenantId, int $userId, string $field): void
    {
        $stmt = Connection::get()->prepare('SELECT 1 FROM users WHERE tenant_id = :tenant_id AND id = :id LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'id' => $userId,
        ]);

        if (!$stmt->fetchColumn()) {
            throw new InvalidArgumentException(sprintf('%s is invalid for tenant.', $field));
        }
    }

    private function assertCustomerBelongsToTenant(int $tenantId, int $customerId): void
    {
        $stmt = Connection::get()->prepare('SELECT 1 FROM crm_customers WHERE tenant_id = :tenant_id AND id = :id LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'id' => $customerId,
        ]);

        if (!$stmt->fetchColumn()) {
            throw new InvalidArgumentException('Customer does not belong to tenant.');
        }
    }

    private function assertSegmentBelongsToTenant(int $tenantId, int $segmentId): void
    {
        $stmt = Connection::get()->prepare('SELECT 1 FROM crm_segments WHERE tenant_id = :tenant_id AND id = :id LIMIT 1');
        $stmt->execute([
            'tenant_id' => $tenantId,
            'id' => $segmentId,
        ]);

        if (!$stmt->fetchColumn()) {
            throw new InvalidArgumentException('Segment does not belong to tenant.');
        }
    }

    private function assertDateTimeString(string $value, string $field): void
    {
        $dateTime = \DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $value);
        if ($dateTime === false || $dateTime->format('Y-m-d H:i:s') !== $value) {
            throw new InvalidArgumentException(sprintf('%s must use Y-m-d H:i:s format.', $field));
        }
    }

    private function validateSegmentRules(array $rules): void
    {
        $allowed = ['lifecycle_stage', 'dealer_id', 'city'];
        foreach ($rules as $key => $value) {
            if (!in_array((string) $key, $allowed, true)) {
                throw new InvalidArgumentException('Segment rules contain unsupported fields.');
            }

            if ($key === 'lifecycle_stage') {
                $this->assertEnum(strtoupper((string) $value), self::ALLOWED_LIFECYCLE_STAGES, 'rules.lifecycle_stage');
            }

            if ($key === 'dealer_id' && (int) $value <= 0) {
                throw new InvalidArgumentException('rules.dealer_id must be greater than zero.');
            }

            if ($key === 'city' && trim((string) $value) === '') {
                throw new InvalidArgumentException('rules.city cannot be empty.');
            }
        }
    }

    /** @return list<string> */
    private function expandChannels(string $channel): array
    {
        return match ($channel) {
            'BOTH' => ['EMAIL', 'WHATSAPP'],
            'WHATSAPP' => ['WHATSAPP'],
            default => ['EMAIL'],
        };
    }

    public function dashboardStats(array $input): array
    {
        $tenantId = (int) ($input['tenant_id'] ?? 0);
        if ($tenantId <= 0) {
            throw new InvalidArgumentException('tenant_id is required.');
        }

        $pdo = Connection::get();

        $leadsStmt = $pdo->prepare(
            'SELECT stage, COUNT(*) AS cnt FROM crm_leads WHERE tenant_id = :tenant_id GROUP BY stage'
        );
        $leadsStmt->execute(['tenant_id' => $tenantId]);
        $byStage = [];
        foreach ($leadsStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $byStage[(string) $row['stage']] = (int) $row['cnt'];
        }

        $campStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM crm_campaigns
             WHERE tenant_id = :tenant_id AND status NOT IN ('COMPLETED','CANCELLED')"
        );
        $campStmt->execute(['tenant_id' => $tenantId]);

        $closed = ($byStage['WON'] ?? 0) + ($byStage['LOST'] ?? 0);

        return [
            'leads_by_stage'   => $byStage,
            'open_leads'       => max(0, array_sum($byStage) - $closed),
            'active_campaigns' => (int) $campStmt->fetchColumn(),
        ];
    }

    public function listCustomers(array $input): array
    {
        $tenantId  = (int) ($input['tenant_id'] ?? 0);
        $limit     = min((int) ($input['limit'] ?? 20), 100);
        $lifecycle = isset($input['lifecycle_stage']) ? strtoupper((string) $input['lifecycle_stage']) : null;

        if ($tenantId <= 0) {
            throw new InvalidArgumentException('tenant_id is required.');
        }

        if ($lifecycle !== null) {
            $this->assertEnum($lifecycle, self::ALLOWED_LIFECYCLE_STAGES, 'lifecycle_stage');
        }

        $pdo = Connection::get();
        $sql = 'SELECT id, name, email, phone, city, lifecycle_stage, total_batteries_bought, created_at
                FROM crm_customers
                WHERE tenant_id = :tenant_id';
        $params = ['tenant_id' => $tenantId];

        if ($lifecycle !== null) {
            $sql .= ' AND lifecycle_stage = :lifecycle_stage';
            $params['lifecycle_stage'] = $lifecycle;
        }

        $sql .= ' ORDER BY created_at DESC LIMIT ' . $limit;
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        return ['customers' => $stmt->fetchAll(PDO::FETCH_ASSOC) ?: []];
    }
}
