<?php

use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BillingController;
use App\Http\Controllers\Api\CompanyController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\DepartmentController;
use App\Http\Controllers\Api\EmployeeController;
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
});

// The pricing table on the marketing pages.
Route::get('plans', [BillingController::class, 'plans']);

// Voucher designs, shown while a company is still registering.
Route::get('voucher-templates', [VoucherTemplateController::class, 'index']);
Route::post('voucher-templates/preview', [VoucherTemplateController::class, 'preview'])->middleware('throttle:60,1');

/*
|--------------------------------------------------------------------------
| Authenticated — every route below resolves a tenant first
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

        // The printed document — available at every stage, per step permissions.
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

    /* ------------------------------------------------------------ audit log */
    Route::get('audit-logs', [AuditLogController::class, 'index']);
    Route::get('audit-logs/actions', [AuditLogController::class, 'actions']);

    /*
    |----------------------------------------------------------------------
    | Platform administration — super admin only
    |----------------------------------------------------------------------
    */
    Route::prefix('platform')->middleware('super_admin')->group(function () {
        Route::apiResource('companies', Platform\CompanyController::class);
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

        Route::apiResource('plans', Platform\PlanController::class)->except(['show']);

        Route::get('payments', [Platform\PaymentController::class, 'index']);
        Route::get('subscriptions', [Platform\PaymentController::class, 'subscriptions']);
        Route::post('payments/{invoice}/refund', [Platform\PaymentController::class, 'refund']);
        Route::post('payments/{invoice}/mark-paid', [Platform\PaymentController::class, 'markPaid']);

        Route::get('users', [Platform\UserController::class, 'index']);
        Route::put('users/{user}', [Platform\UserController::class, 'update']);
    });
});
