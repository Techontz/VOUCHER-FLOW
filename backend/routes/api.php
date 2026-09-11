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
    Route::post('otp/send', [AuthController::class, 'sendOtp'])->middleware('throttle:10,1');
    Route::post('otp/verify', [AuthController::class, 'verifyOtp'])->middleware('throttle:20,1');
    Route::post('forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:6,1');
    Route::post('reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:6,1');
});

// The pricing table on the marketing pages.
Route::get('plans', [BillingController::class, 'plans']);

/*
|--------------------------------------------------------------------------
| Authenticated — every route below resolves a tenant first
|--------------------------------------------------------------------------
*/

// Bindings run last so models resolve inside the caller's tenant scope.
Route::middleware(['auth:sanctum', 'tenant', SubstituteBindings::class])->group(function () {

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
        Route::get('{voucher}/pdf', [VoucherDocumentController::class, 'stream'])->name('pdf');
        Route::get('{voucher}/pdf/download', [VoucherDocumentController::class, 'download'])->name('pdf.download');

        Route::post('{voucher}/attachments', [VoucherAttachmentController::class, 'store'])->middleware('subscription');
        Route::get('{voucher}/attachments/{attachment}', [VoucherAttachmentController::class, 'show'])->name('attachments.show');
        Route::delete('{voucher}/attachments/{attachment}', [VoucherAttachmentController::class, 'destroy']);

        Route::post('{voucher}/comments', [VoucherCommentController::class, 'store']);
        Route::delete('{voucher}/comments/{comment}', [VoucherCommentController::class, 'destroy']);
    });

    /* ------------------------------------------------------ company & people */
    Route::get('company', [CompanyController::class, 'show']);
    Route::put('company', [CompanyController::class, 'update']);
    Route::post('company/branding', [CompanyController::class, 'updateBranding']);
    Route::get('company/usage', [CompanyController::class, 'usage']);

    Route::get('directory', [EmployeeController::class, 'directory']);
    Route::apiResource('employees', EmployeeController::class);
    Route::post('employees/{user}/resend-invitation', [EmployeeController::class, 'resendInvitation']);

    Route::apiResource('departments', DepartmentController::class);
    Route::apiResource('voucher-types', VoucherTypeController::class)->parameters(['voucher-types' => 'voucherType']);

    /* ------------------------------------------------------------ workflows */
    Route::get('workflows/presets', [WorkflowController::class, 'presets']);
    Route::post('workflows/apply-preset', [WorkflowController::class, 'applyPreset']);
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
        Route::post('companies/{company}/change-plan', [Platform\CompanyController::class, 'changePlan']);

        Route::apiResource('plans', Platform\PlanController::class)->except(['show']);

        Route::get('payments', [Platform\PaymentController::class, 'index']);
        Route::get('subscriptions', [Platform\PaymentController::class, 'subscriptions']);
        Route::post('payments/{invoice}/refund', [Platform\PaymentController::class, 'refund']);
        Route::post('payments/{invoice}/mark-paid', [Platform\PaymentController::class, 'markPaid']);

        Route::get('users', [Platform\UserController::class, 'index']);
        Route::put('users/{user}', [Platform\UserController::class, 'update']);
    });
});
