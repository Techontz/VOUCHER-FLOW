<?php

use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BillingController;
use App\Http\Controllers\Api\CompanyController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\DepartmentController;
use App\Http\Controllers\Api\EmployeeController;
use App\Http\Controllers\Api\Erp;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\Platform;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\VoucherAttachmentController;
use App\Http\Controllers\Api\VoucherCommentController;
use App\Http\Controllers\Api\VoucherController;
use App\Http\Controllers\Api\VoucherDocumentController;
use App\Http\Controllers\Api\VoucherPaymentController;
use App\Http\Controllers\Api\VoucherTemplateController;
use App\Http\Controllers\Api\VoucherTypeController;
use App\Http\Controllers\Api\WorkflowController;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public
|--------------------------------------------------------------------------
*/

Route::prefix('auth')->group(function () {
    Route::post('register', [AuthController::class, 'register'])->middleware('throttle:10,1');
    Route::post('login', [AuthController::class, 'login'])->middleware('throttle:20,1');
    Route::post('login/send-code', [AuthController::class, 'sendLoginCode'])->middleware('throttle:10,1');
    Route::post('login/verify', [AuthController::class, 'verifyLogin'])->middleware('throttle:20,1');
    Route::post('otp/send', [AuthController::class, 'sendOtp'])->middleware('throttle:10,1');
    Route::post('otp/verify', [AuthController::class, 'verifyOtp'])->middleware('throttle:20,1');
    Route::post('forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:6,1');
    Route::post('reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:6,1');
    Route::get('invitation/{token}', [AuthController::class, 'invitation'])->middleware('throttle:30,1');
    Route::post('invitation/accept', [AuthController::class, 'acceptInvitation'])->middleware('throttle:10,1');
});

// The pricing table on the marketing pages.
Route::get('plans', [BillingController::class, 'plans']);

// Voucher designs, shown while a company is still registering.
Route::get('voucher-templates', [VoucherTemplateController::class, 'index']);
Route::post('voucher-templates/preview', [VoucherTemplateController::class, 'preview'])->middleware('throttle:60,1');

/*
|--------------------------------------------------------------------------
| Authenticated, every route below resolves a tenant first
|--------------------------------------------------------------------------
*/

// Bindings run last so models resolve inside the caller's tenant scope.
// 'approved' holds a self-registered company that the platform has not yet
// approved to its account, profile, notifications and billing.
Route::middleware(['auth:sanctum', 'tenant', 'approved', SubstituteBindings::class])->group(function () {

    /* -------------------------------------------------------------- account */
    Route::prefix('auth')->group(function () {
        Route::get('me', [AuthController::class, 'me']);
        Route::post('logout', [AuthController::class, 'logout']);
        Route::post('logout-all', [AuthController::class, 'logoutAll']);
        Route::post('change-password', [AuthController::class, 'changePassword']);
        Route::get('sessions', [AuthController::class, 'sessions']);
        Route::delete('sessions/{id}', [AuthController::class, 'revokeSession']);
    });

    Route::prefix('profile')->group(function () {
        Route::match(['put', 'post'], '/', [ProfileController::class, 'update']);
        Route::get('signature', [ProfileController::class, 'showSignature']);
        Route::post('signature', [ProfileController::class, 'storeSignature']);
        Route::delete('signature', [ProfileController::class, 'destroySignature']);
    });

    Route::get('dashboard', [DashboardController::class, 'index']);

    /* ------------------------------------------------------------- vouchers */
    Route::prefix('vouchers')->name('api.vouchers.')->group(function () {
        Route::get('/', [VoucherController::class, 'index']);
        Route::get('pending', [VoucherController::class, 'pending']);
        Route::get('awaiting-payment', [VoucherController::class, 'awaitingPayment']);
        Route::post('document-preview', [VoucherDocumentController::class, 'draftPreview'])->middleware('throttle:120,1');
        Route::post('bulk-approve', [VoucherController::class, 'bulkApprove'])->middleware(['subscription', 'throttle:30,1']);
        Route::post('/', [VoucherController::class, 'store'])->middleware('subscription');
        Route::get('{voucher}', [VoucherController::class, 'show']);
        Route::put('{voucher}', [VoucherController::class, 'update'])->middleware('subscription');
        Route::delete('{voucher}', [VoucherController::class, 'destroy']);

        // Workflow transitions.
        Route::middleware('subscription')->group(function () {
            Route::post('{voucher}/submit', [VoucherController::class, 'submit']);
            Route::post('{voucher}/sign', [VoucherController::class, 'sign']);
            Route::post('{voucher}/submit-signed', [VoucherController::class, 'submitSigned']);
            Route::post('{voucher}/approve', [VoucherController::class, 'approve']);
            Route::post('{voucher}/reject', [VoucherController::class, 'reject']);
            Route::post('{voucher}/request-changes', [VoucherController::class, 'requestChanges']);
            Route::post('{voucher}/cancel', [VoucherController::class, 'cancel']);
            Route::post('{voucher}/pay', [VoucherController::class, 'pay']);
        });

        // The printed document, available at every stage, per step permissions.
        Route::get('{voucher}/document', [VoucherDocumentController::class, 'html'])->name('document');
        Route::get('{voucher}/pdf', [VoucherDocumentController::class, 'stream'])->name('pdf');
        Route::get('{voucher}/pdf/download', [VoucherDocumentController::class, 'download'])->name('pdf.download');

        Route::post('{voucher}/attachments', [VoucherAttachmentController::class, 'store'])->middleware('subscription');

        Route::get('{voucher}/payments/{payment}/acknowledgement', [VoucherPaymentController::class, 'acknowledgement'])->name('payments.acknowledgement');
        Route::post('{voucher}/payments/{payment}/acknowledgement', [VoucherPaymentController::class, 'storeAcknowledgement'])->middleware('subscription');
        Route::get('{voucher}/attachments/{attachment}', [VoucherAttachmentController::class, 'show'])->name('attachments.show');
        Route::delete('{voucher}/attachments/{attachment}', [VoucherAttachmentController::class, 'destroy']);

        Route::post('{voucher}/comments', [VoucherCommentController::class, 'store']);
        Route::delete('{voucher}/comments/{comment}', [VoucherCommentController::class, 'destroy']);
    });

    /* ------------------------------------------------------ company & people */
    // The caller's own company. Which company that is comes from the
    // authenticated user, never from the request.
    Route::get('company', [CompanyController::class, 'show']);
    Route::match(['put', 'patch'], 'company', [CompanyController::class, 'update']);
    Route::post('company/branding', [CompanyController::class, 'updateBranding']);
    Route::post('company/logo', [CompanyController::class, 'storeLogo']);
    Route::delete('company/logo', [CompanyController::class, 'destroyLogo']);
    Route::get('company/usage', [CompanyController::class, 'usage']);
    Route::get('company/voucher-template', [VoucherTemplateController::class, 'show']);
    Route::post('company/voucher-template/preview', [VoucherTemplateController::class, 'companyPreview'])->middleware('throttle:60,1');
    Route::put('company/voucher-template', [VoucherTemplateController::class, 'update'])->middleware('throttle:10,1');
    Route::post('company/voucher-template/request', [VoucherTemplateController::class, 'requestChange'])->middleware('throttle:5,10');

    Route::get('directory', [EmployeeController::class, 'directory']);
    // The controller binds `User $user`; without this the route would name the
    // parameter {employee}, no model would be bound, and every show, update
    // and delete would 404.
    Route::apiResource('employees', EmployeeController::class)->parameters(['employees' => 'user']);
    Route::post('employees/{user}/resend-invitation', [EmployeeController::class, 'resendInvitation']);

    Route::apiResource('departments', DepartmentController::class);
    Route::apiResource('voucher-types', VoucherTypeController::class)->parameters(['voucher-types' => 'voucherType']);

    /* ------------------------------------------------------------ workflows */
    Route::get('workflows/presets', [WorkflowController::class, 'presets']);
    Route::post('workflows/apply-preset', [WorkflowController::class, 'applyPreset']);
    Route::get('workflows/{workflow}/routing', [WorkflowController::class, 'routing']);
    Route::post('workflows/{workflow}/make-default', [WorkflowController::class, 'makeDefault']);
    Route::apiResource('workflows', WorkflowController::class);

    /* -------------------------------------------------------- notifications */
    Route::prefix('notifications')->group(function () {
        Route::get('/', [NotificationController::class, 'index']);
        Route::get('unread-count', [NotificationController::class, 'unreadCount']);
        Route::post('read-all', [NotificationController::class, 'markAllRead']);
        Route::post('{notification}/read', [NotificationController::class, 'markRead']);
        Route::delete('{notification}', [NotificationController::class, 'destroy']);
    });

    /* -------------------------------------------------------------- reports */
    Route::get('reports', [ReportController::class, 'kinds']);
    Route::get('reports/{kind}', [ReportController::class, 'show']);
    Route::get('reports/{kind}/export', [ReportController::class, 'export']);

    /* -------------------------------------------------------------- billing */
    Route::prefix('billing')->group(function () {
        Route::get('subscription', [BillingController::class, 'subscription']);
        Route::get('invoices', [BillingController::class, 'invoices']);
        Route::post('subscribe', [BillingController::class, 'subscribe']);
        Route::post('invoices/{invoice}/pay', [BillingController::class, 'pay']);
        Route::post('auto-renew', [BillingController::class, 'setAutoRenew']);
    });

    /*
    |----------------------------------------------------------------------
    | ERP: Phase 1 core. Every route names its module and its permission;
    | the tenant scope underneath keeps each company to its own rows.
    |----------------------------------------------------------------------
    */
    Route::prefix('erp')->middleware('subscription')->group(function () {
        Route::get('templates', [Erp\SetupController::class, 'templates']);
        Route::get('config', [Erp\SetupController::class, 'show']);
        Route::get('overview', [Erp\SetupController::class, 'overview']);
        Route::post('setup', [Erp\SetupController::class, 'apply'])->middleware('permission:erp.configure');
        Route::put('config', [Erp\SetupController::class, 'update'])->middleware('permission:erp.configure');

        Route::middleware('permission:roles.manage')->group(function () {
            Route::get('roles', [Erp\RoleController::class, 'index']);
            Route::post('roles', [Erp\RoleController::class, 'store']);
            Route::put('roles/{key}', [Erp\RoleController::class, 'update']);
            Route::delete('roles/{key}', [Erp\RoleController::class, 'destroy']);
        });

        Route::middleware('module:inventory')->group(function () {
            Route::middleware('permission:inventory.view')->group(function () {
                Route::get('units', [Erp\UnitController::class, 'index']);
                Route::get('categories', [Erp\CategoryController::class, 'index']);
                Route::get('warehouses', [Erp\WarehouseController::class, 'index']);
                Route::get('warehouses/{warehouse}', [Erp\WarehouseController::class, 'show']);
                Route::get('products', [Erp\ProductController::class, 'index']);
                Route::get('products/{product}', [Erp\ProductController::class, 'show']);
                Route::get('stock/balances', [Erp\StockController::class, 'balances']);
                Route::get('stock/movements', [Erp\StockController::class, 'movements']);
                Route::get('stock/alerts', [Erp\StockController::class, 'alerts']);
                Route::get('stock/valuation', [Erp\StockController::class, 'valuation']);
                Route::get('stock-documents', [Erp\StockDocumentController::class, 'index']);
                Route::get('stock-documents/{stockDocument}', [Erp\StockDocumentController::class, 'show']);
            });

            Route::middleware('permission:inventory.manage')->group(function () {
                Route::apiResource('units', Erp\UnitController::class)->only(['store', 'update', 'destroy']);
                Route::apiResource('categories', Erp\CategoryController::class)->only(['store', 'update', 'destroy'])
                    ->parameters(['categories' => 'category']);
                Route::apiResource('warehouses', Erp\WarehouseController::class)->only(['store', 'update', 'destroy']);
                Route::apiResource('products', Erp\ProductController::class)->only(['store', 'update', 'destroy']);
            });

            // Which kind of document may be prepared is checked per type in the controller.
            Route::post('stock-documents', [Erp\StockDocumentController::class, 'store']);
            Route::put('stock-documents/{stockDocument}', [Erp\StockDocumentController::class, 'update']);
            Route::post('stock-documents/{stockDocument}/cancel', [Erp\StockDocumentController::class, 'cancel']);
            Route::post('stock-documents/{stockDocument}/post', [Erp\StockDocumentController::class, 'post'])->middleware('permission:inventory.post');
            Route::post('stock-documents/{stockDocument}/reverse', [Erp\StockDocumentController::class, 'reverse'])->middleware('permission:inventory.reverse');
        });

        Route::middleware('module:sales')->group(function () {
            Route::apiResource('customers', Erp\CustomerController::class)->only(['index', 'show'])->middleware('permission:customers.view');
            Route::apiResource('customers', Erp\CustomerController::class)->only(['store', 'update', 'destroy'])->middleware('permission:customers.manage');
        });

        Route::middleware('module:procurement')->group(function () {
            Route::apiResource('suppliers', Erp\SupplierController::class)->only(['index', 'show'])->middleware('permission:suppliers.view');
            Route::apiResource('suppliers', Erp\SupplierController::class)->only(['store', 'update', 'destroy'])->middleware('permission:suppliers.manage');
        });

        Route::middleware('module:accounting')->group(function () {
            Route::get('accounts', [Erp\AccountController::class, 'index'])->middleware('permission:accounting.view');
            Route::apiResource('accounts', Erp\AccountController::class)->only(['store', 'update', 'destroy'])->middleware('permission:accounting.manage');
            Route::get('journals', [Erp\JournalController::class, 'index'])->middleware('permission:accounting.view');
            Route::get('journals/{journalEntry}', [Erp\JournalController::class, 'show'])->middleware('permission:accounting.view');
            Route::post('journals', [Erp\JournalController::class, 'store'])->middleware('permission:accounting.post');
            Route::post('journals/{journalEntry}/reverse', [Erp\JournalController::class, 'reverse'])->middleware('permission:accounting.reverse');
            Route::get('trial-balance', [Erp\JournalController::class, 'trialBalance'])->middleware('permission:accounting.view');
        });

        // Every later module brings its own routes file (routes/erp/*.php),
        // inside this group: authenticated, tenant-scoped, subscription-checked.
        foreach (glob(__DIR__.'/erp/*.php') ?: [] as $moduleRoutes) {
            require $moduleRoutes;
        }
    });

    /* ------------------------------------------------------------ audit log */
    Route::get('audit-logs', [AuditLogController::class, 'index']);
    Route::get('audit-logs/actions', [AuditLogController::class, 'actions']);

    /*
    |----------------------------------------------------------------------
    | Platform administration, super admin only
    |----------------------------------------------------------------------
    */
    Route::prefix('platform')->middleware('super_admin')->group(function () {
        Route::get('analytics', Platform\AnalyticsController::class);
        Route::get('settings', [Platform\SettingsController::class, 'show']);
        Route::put('settings', [Platform\SettingsController::class, 'update']);

        Route::apiResource('companies', Platform\CompanyController::class);
        Route::put('companies/{company}/modules', [Platform\CompanyController::class, 'modules']);
        Route::post('companies/{company}/extend', [Platform\CompanyController::class, 'extend']);
        Route::post('companies/{company}/suspend', [Platform\CompanyController::class, 'suspend']);
        Route::post('companies/{company}/activate', [Platform\CompanyController::class, 'activate']);
        Route::post('companies/{company}/approve', [Platform\CompanyController::class, 'approve']);
        Route::post('companies/{company}/change-plan', [Platform\CompanyController::class, 'changePlan']);
        Route::post('companies/{company}/branding', [Platform\CompanyController::class, 'updateBranding']);
        Route::post('companies/{company}/logo', [Platform\CompanyController::class, 'storeLogo']);
        Route::delete('companies/{company}/logo', [Platform\CompanyController::class, 'destroyLogo']);
        Route::get('companies/{company}/voucher-template', [VoucherTemplateController::class, 'platformShow']);
        Route::post('companies/{company}/voucher-template/preview', [VoucherTemplateController::class, 'platformPreview']);
        Route::put('companies/{company}/voucher-template', [VoucherTemplateController::class, 'platformUpdate']);

        // Read-only views into one tenant, each run inside that tenant's scope.
        Route::get('companies/{company}/overview', [Platform\CompanyInsightController::class, 'overview']);
        Route::get('companies/{company}/users', [Platform\CompanyInsightController::class, 'users']);
        Route::get('companies/{company}/departments', [Platform\CompanyInsightController::class, 'departments']);
        Route::get('companies/{company}/workflows', [Platform\CompanyInsightController::class, 'workflows']);
        Route::get('companies/{company}/vouchers', [Platform\CompanyInsightController::class, 'vouchers']);

        Route::post('plans/reorder', [Platform\PlanController::class, 'reorder']);
        Route::apiResource('plans', Platform\PlanController::class)->except(['show']);

        Route::get('payments', [Platform\PaymentController::class, 'index']);
        Route::get('subscriptions', [Platform\SubscriptionController::class, 'index']);
        Route::post('subscriptions/{subscription}/extend', [Platform\SubscriptionController::class, 'extend']);
        Route::post('subscriptions/{subscription}/cancel', [Platform\SubscriptionController::class, 'cancel']);
        Route::post('subscriptions/{subscription}/reactivate', [Platform\SubscriptionController::class, 'reactivate']);
        Route::post('subscriptions/{subscription}/invoice', [Platform\SubscriptionController::class, 'invoice']);
        Route::post('payments/{invoice}/refund', [Platform\PaymentController::class, 'refund']);
        Route::post('payments/{invoice}/mark-paid', [Platform\PaymentController::class, 'markPaid']);

        Route::get('users', [Platform\UserController::class, 'index']);
        Route::get('users/roles', [Platform\UserController::class, 'roles']);
        Route::post('users/bulk-delete', [Platform\UserController::class, 'bulkDestroy']);
        Route::post('users/bulk-status', [Platform\UserController::class, 'bulkStatus']);
        Route::post('users/{user}/invite', [Platform\UserController::class, 'invite']);
        Route::put('users/{user}', [Platform\UserController::class, 'update']);
        Route::delete('users/{user}', [Platform\UserController::class, 'destroy']);
    });
});
