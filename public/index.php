<?php

declare(strict_types=1);

$requestPath = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$requestMethod = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($requestMethod === 'GET') {
	if ($requestPath === '/') {
		header('Content-Type: text/html; charset=utf-8');
		readfile(__DIR__ . '/app-shell.html');
		exit;
	}

	if ($requestPath === '/dashboard') {
		header('Content-Type: text/html; charset=utf-8');
		readfile(__DIR__ . '/app-shell.html');
		exit;
	}
}

use App\Modules\Identity\Controllers\AuthController;
use App\Modules\Claims\Controllers\ClaimController;
use App\Modules\Drivers\Controllers\DriverController;
use App\Modules\CRM\Controllers\CrmController;
use App\Modules\Reports\Controllers\ReportController;
use App\Modules\ServiceCenter\Controllers\ServiceController;
use App\Modules\Tracking\Controllers\TrackingController;
use App\Modules\Tally\Controllers\TallyController;
use App\Shared\Http\Request;
use App\Shared\Http\Response;
use App\Shared\Http\Router;

require_once __DIR__ . '/../app/Shared/Config/Env.php';
require_once __DIR__ . '/../app/Shared/Database/Connection.php';
require_once __DIR__ . '/../app/Shared/Http/Request.php';
require_once __DIR__ . '/../app/Shared/Http/Response.php';
require_once __DIR__ . '/../app/Shared/Http/Router.php';
require_once __DIR__ . '/../app/Modules/Identity/Services/AuthService.php';
require_once __DIR__ . '/../app/Modules/Identity/Services/TokenService.php';
require_once __DIR__ . '/../app/Modules/Identity/Controllers/AuthController.php';
require_once __DIR__ . '/../app/Modules/Batteries/Services/BatteryService.php';
require_once __DIR__ . '/../app/Modules/Audit/Services/AuditService.php';
require_once __DIR__ . '/../app/Modules/Claims/Services/ClaimService.php';
require_once __DIR__ . '/../app/Modules/Claims/Controllers/ClaimController.php';
require_once __DIR__ . '/../app/Modules/Drivers/Services/DriverService.php';
require_once __DIR__ . '/../app/Modules/Finance/Services/IncentiveService.php';
require_once __DIR__ . '/../app/Modules/Drivers/Controllers/DriverController.php';
require_once __DIR__ . '/../app/Modules/CRM/Services/CrmService.php';
require_once __DIR__ . '/../app/Modules/CRM/Controllers/CrmController.php';
require_once __DIR__ . '/../app/Modules/Reports/Services/ReportService.php';
require_once __DIR__ . '/../app/Modules/Reports/Controllers/ReportController.php';
require_once __DIR__ . '/../app/Modules/ServiceCenter/Services/ServiceJobService.php';
require_once __DIR__ . '/../app/Modules/ServiceCenter/Controllers/ServiceController.php';
require_once __DIR__ . '/../app/Modules/Tracking/Services/TrackingService.php';
require_once __DIR__ . '/../app/Modules/Tracking/Controllers/TrackingController.php';
require_once __DIR__ . '/../app/Modules/Tally/Services/TallyService.php';
require_once __DIR__ . '/../app/Modules/Tally/Controllers/TallyController.php';

$router = new Router();
$authController = new AuthController();
$claimController = new ClaimController();
$crmController = new CrmController(new \App\Modules\CRM\Services\CrmService(new \App\Shared\Database\Connection()));
$driverController = new DriverController();
$reportController = new ReportController();
$serviceController = new ServiceController();
$trackingController = new TrackingController();
$tallyController = new TallyController();

$router->post('/api/v1/auth/send-otp', [$authController, 'sendOtp']);
$router->post('/api/v1/auth/verify-otp', [$authController, 'verifyOtp']);
$router->post('/api/v1/auth/refresh', [$authController, 'refresh']);
$router->post('/api/v1/auth/logout', [$authController, 'logout']);
$router->post('/api/v1/claims/check-serial', [$claimController, 'checkSerial']);
$router->post('/api/v1/claims/list', [$claimController, 'list']);
$router->post('/api/v1/claims', [$claimController, 'create']);
$router->post('/api/v1/crm/customers', [$crmController, 'upsertCustomer']);
$router->post('/api/v1/crm/customers/list', [$crmController, 'listCustomers']);
$router->post('/api/v1/crm/dashboard-stats', [$crmController, 'dashboardStats']);
$router->post('/api/v1/crm/leads', [$crmController, 'createLead']);
$router->post('/api/v1/crm/leads/transition', [$crmController, 'transitionLead']);
$router->post('/api/v1/crm/segments', [$crmController, 'createSegment']);
$router->post('/api/v1/crm/segments/resolve', [$crmController, 'resolveSegment']);
$router->post('/api/v1/crm/campaigns', [$crmController, 'createCampaign']);
$router->post('/api/v1/crm/campaigns/dispatch', [$crmController, 'dispatchCampaign']);
$router->post('/api/v1/crm/opt-out', [$crmController, 'optOut']);
$router->post('/api/v1/driver/routes', [$driverController, 'createRoute']);
$router->post('/api/v1/driver/routes/active', [$driverController, 'activeRoute']);
$router->post('/api/v1/driver/tasks', [$driverController, 'assignTask']);
$router->post('/api/v1/driver/tasks/complete', [$driverController, 'completeTask']);
$router->post('/api/v1/service/inward', [$serviceController, 'inward']);
$router->post('/api/v1/service/diagnose', [$serviceController, 'diagnose']);
$router->post('/api/v1/reports/lemon', [$reportController, 'lemon']);
$router->post('/api/v1/reports/finance', [$reportController, 'finance']);
$router->post('/api/v1/reports/audit-summary', [$reportController, 'auditSummary']);
$router->post('/api/v1/tally/import', [$tallyController, 'import']);
$router->post('/api/v1/tally/export', [$tallyController, 'export']);
$router->post('/api/v1/track/lookup', [$trackingController, 'lookup']);
$router->get('/api/v1/track/{token}', [$trackingController, 'show']);

$request = Request::capture();
$response = $router->dispatch($request);

$response->send();
