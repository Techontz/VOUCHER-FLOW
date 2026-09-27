<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompanyResource;
use App\Http\Resources\UserResource;
use App\Models\Company;
use App\Models\OtpCode;
use App\Models\Plan;
use App\Models\User;
use App\Notifications\OneTimeCodeNotification;
use App\Services\AuditLogger;
use App\Services\CompanyProvisioner;
use App\Services\TwoFactorLogin;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(
        private readonly CompanyProvisioner $provisioner,
        private readonly TenantContext $tenant,
        private readonly AuditLogger $audit,
        private readonly TwoFactorLogin $twoFactor,
    ) {}

    /** Registers a company together with its first administrator. */
    public function register(Request $request)
    {
        $data = $request->validate([
            'company_name' => ['required', 'string', 'max:180'],
            'business_email' => ['required', 'email', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'website' => ['nullable', 'string', 'max:180'],
            'country' => ['nullable', 'string', 'size:2'],
            'currency' => ['nullable', 'string', 'size:3'],
            'locale' => ['nullable', Rule::in(config('vouchflow.locales'))],

            'name' => ['required', 'string', 'max:180'],
            'email' => ['required', 'email', 'max:180'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'plan_code' => ['nullable', 'string', 'exists:plans,code'],
        ]);

        $plan = $data['plan_code'] ?? null
            ? Plan::where('code', $data['plan_code'])->first()
            : Plan::where('is_active', true)->where('is_public', true)->orderBy('sort_order')->first();

        ['company' => $company, 'admin' => $admin] = $this->provisioner->provision(
            [
                'name' => $data['company_name'],
                'email' => $data['business_email'],
                'phone' => $data['phone'] ?? null,
                'address' => $data['address'] ?? null,
                'website' => $data['website'] ?? null,
                'country' => $data['country'] ?? 'TZ',
                'currency' => $data['currency'] ?? 'TZS',
                'locale' => $data['locale'] ?? 'en',
            ],
            [
                'name' => $data['name'],
                'email' => $data['email'],
                'password' => $data['password'],
                'phone' => $data['phone'] ?? null,
            ],
            $plan,
        );

        $challenge = $this->issueOtp($admin, $admin->email, 'registration');

        return response()->json([
            'token' => $admin->createToken('web')->plainTextToken,
            'user' => new UserResource($admin->load('company')),
            'company' => new CompanyResource($company->load('plan')),
            'requires_verification' => true,
            'otp' => $challenge,
        ], 201);
    }

    /**
     * Checks the password. With two-step sign-in on (the default) this opens a
     * verification challenge and returns no token; the token comes from
     * `verifyLogin` once the one-time code is accepted.
     */
    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'string', 'max:180'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:80'],
        ]);

        $key = 'login:'.mb_strtolower($data['email']).'|'.$request->ip();

        if (RateLimiter::tooManyAttempts($key, 6)) {
            throw ValidationException::withMessages([
                'email' => ['Too many attempts. Try again in '.RateLimiter::availableIn($key).' seconds.'],
            ]);
        }

        // Email or phone, matching the design's "Email or phone" field. The same
        // address may belong to people in two companies, so the account is the
        // one whose password matches, never simply the first row found.
        $user = User::with('company')
            ->where(fn ($q) => $q->where('email', $data['email'])->orWhere('phone', $data['email']))
            ->orderBy('id')
            ->get()
            ->first(fn (User $candidate) => Hash::check($data['password'], $candidate->password));

        if (! $user) {
            RateLimiter::hit($key, 300);

            throw ValidationException::withMessages(['email' => ['These credentials do not match our records.']]);
        }

        if ($blocked = $this->signInBlockedReason($user)) {
            throw ValidationException::withMessages(['email' => [$blocked]]);
        }

        RateLimiter::clear($key);

        if (! $this->twoFactor->enabled()) {
            return $this->completeSignIn($request, $user, $data['device_name'] ?? null);
        }

        return response()->json($this->twoFactor->start($user, $request->ip()));
    }

    /** Sends (or re-sends) the sign-in code on the channel the person chose. */
    public function sendLoginCode(Request $request)
    {
        $data = $request->validate([
            'challenge' => ['required', 'string', 'max:128'],
            'channel' => ['required', Rule::in(['email', 'sms'])],
        ]);

        $challenge = $this->twoFactor->open($data['challenge']);

        return response()->json($this->twoFactor->send($challenge, $data['channel']));
    }

    /** Exchanges a correct sign-in code for a token. */
    public function verifyLogin(Request $request)
    {
        $data = $request->validate([
            'challenge' => ['required', 'string', 'max:128'],
            'code' => ['required', 'string', 'max:10'],
            'device_name' => ['nullable', 'string', 'max:80'],
        ]);

        $challenge = $this->twoFactor->open($data['challenge']);
        $user = $this->twoFactor->verify($challenge, trim($data['code']));

        // The account may have been suspended while the code was in transit.
        if ($blocked = $this->signInBlockedReason($user)) {
            $this->twoFactor->fail(422, 'account_unavailable', $blocked, 'code');
        }

        return $this->completeSignIn($request, $user, $data['device_name'] ?? null);
    }

    /** Why this account may not sign in right now, if anything. */
    private function signInBlockedReason(User $user): ?string
    {
        if ($user->status === 'suspended') {
            return 'This account has been suspended.';
        }

        if ($user->company && ! $user->isSuperAdmin() && in_array($user->company->status, ['suspended', 'cancelled'], true)) {
            return 'This company account is not active. Contact your administrator.';
        }

        return null;
    }

    /** Records the sign-in and issues the token the clients store. */
    private function completeSignIn(Request $request, User $user, ?string $deviceName)
    {
        $user->forceFill([
            'last_login_at' => now(),
            'last_login_ip' => $request->ip(),
            'status' => $user->status === 'invited' ? 'active' : $user->status,
        ])->save();

        if ($user->company) {
            $this->tenant->set($user->company);
        }

        $this->audit->log('auth.login', "{$user->name} signed in", $user, null, null, $user->company_id, $user);

        return response()->json([
            'token' => $user->createToken($deviceName ?? 'web')->plainTextToken,
            'user' => new UserResource($user->load(['company.plan', 'department'])),
            'company' => $user->company ? new CompanyResource($user->company->load('plan')) : null,
        ]);
    }

    public function me(Request $request)
    {
        $user = $request->user()->load(['company.plan', 'department']);

        return response()->json([
            'user' => new UserResource($user),
            'company' => $user->company ? new CompanyResource($user->company->load('plan')) : null,
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json(['message' => 'Signed out.']);
    }

    public function logoutAll(Request $request)
    {
        $request->user()->tokens()->delete();

        return response()->json(['message' => 'Signed out of every device.']);
    }

    /** Active sessions, as listed on the profile & security screen. */
    public function sessions(Request $request)
    {
        $current = $request->user()->currentAccessToken();

        return response()->json([
            'data' => $request->user()->tokens()
                ->orderByDesc('last_used_at')
                ->get()
                ->map(fn ($token) => [
                    'id' => $token->id,
                    'device' => $token->name,
                    'last_used_at' => $token->last_used_at?->toIso8601String(),
                    'created_at' => $token->created_at?->toIso8601String(),
                    'is_current' => $current && $token->id === $current->id,
                ]),
        ]);
    }

    public function revokeSession(Request $request, int $id)
    {
        $request->user()->tokens()->whereKey($id)->delete();

        return response()->json(['message' => 'Session revoked.']);
    }

    /* ------------------------------------------------------------------- OTP */

    /**
     * (Re)sends a registration or password-reset code. Sign-in codes have their
     * own challenge flow and are not issued here. The answer is the same whether
     * or not the identifier matches an account.
     */
    public function sendOtp(Request $request)
    {
        $data = $request->validate([
            'identifier' => ['required', 'string', 'max:180'],
            'purpose' => ['nullable', Rule::in(['registration', 'password_reset'])],
        ]);

        $purpose = $data['purpose'] ?? 'registration';

        $user = User::where(fn ($q) => $q->where('email', $data['identifier'])->orWhere('phone', $data['identifier']))
            ->when($purpose === 'registration', fn ($q) => $q->whereNull('email_verified_at')->latest('id'))
            ->first();

        return response()->json([
            'otp' => $user
                ? $this->issueOtp($user, $data['identifier'], $purpose)
                : ['identifier' => $data['identifier'], 'purpose' => $purpose, 'expires_in' => 600],
        ]);
    }

    /** Confirms a new account's address. Never signs anyone in. */
    public function verifyOtp(Request $request)
    {
        $data = $request->validate([
            'identifier' => ['required', 'string', 'max:180'],
            'code' => ['required', 'string', 'max:10'],
            'purpose' => ['nullable', Rule::in(['registration'])],
        ]);

        $otp = OtpCode::where('identifier', $data['identifier'])
            ->where('purpose', 'registration')
            ->whereNull('consumed_at')
            ->latest('id')
            ->first();

        if (! $otp || ! $otp->isUsable() || ! $otp->user) {
            throw ValidationException::withMessages(['code' => ['That code has expired. Request a new one.']]);
        }

        $otp->increment('attempts');

        if (! Hash::check($data['code'], $otp->code_hash)) {
            throw ValidationException::withMessages(['code' => ['That code is not correct.']]);
        }

        $otp->forceFill(['consumed_at' => now()])->save();

        $user = $otp->user;

        if (! $user->email_verified_at) {
            $user->forceFill(['email_verified_at' => now()])->save();
        }

        return response()->json([
            'verified' => true,
            'user' => new UserResource($user->load('company')),
        ]);
    }

    /* -------------------------------------------------------------- passwords */

    public function forgotPassword(Request $request)
    {
        $data = $request->validate(['email' => ['required', 'email']]);

        $user = User::where('email', $data['email'])->first();

        // Always answers the same way, so the endpoint cannot enumerate accounts.
        $challenge = $user
            ? $this->issueOtp($user, $user->email, 'password_reset')
            : ['identifier' => $data['email'], 'purpose' => 'password_reset', 'expires_in' => 600];

        return response()->json([
            'message' => 'If that address matches an account, a reset code is on its way.',
            'otp' => $challenge,
        ]);
    }

    public function resetPassword(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'code' => ['required', 'string', 'max:10'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $otp = OtpCode::where('identifier', $data['email'])
            ->where('purpose', 'password_reset')
            ->whereNull('consumed_at')
            ->latest('id')
            ->first();

        if (! $otp || ! $otp->isUsable() || ! $otp->user) {
            throw ValidationException::withMessages(['code' => ['That reset code is not valid.']]);
        }

        $otp->increment('attempts');

        if (! Hash::check($data['code'], $otp->code_hash)) {
            throw ValidationException::withMessages(['code' => ['That reset code is not valid.']]);
        }

        // The code was issued to one account; an address shared by two
        // companies must not reset the other one.
        $user = $otp->user;
        $user->forceFill(['password' => $data['password']])->save();
        $user->tokens()->delete();

        $otp->forceFill(['consumed_at' => now()])->save();

        $this->audit->log('auth.password_reset', "{$user->name} reset their password", $user, null, null, $user->company_id, $user);

        return response()->json(['message' => 'Password updated. Sign in with your new password.']);
    }

    public function changePassword(Request $request)
    {
        $data = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = $request->user();

        if (! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages(['current_password' => ['That is not your current password.']]);
        }

        $user->forceFill(['password' => $data['password']])->save();
        $this->audit->log('auth.password_changed', "{$user->name} changed their password", $user);

        return response()->json(['message' => 'Password updated.']);
    }

    /**
     * Issues a one-time code and delivers it by e-mail, or by SMS when the
     * identifier is the account's phone number. Earlier unused codes for the
     * same account and purpose stop working. The code itself never appears in
     * a response or in the application log.
     *
     * @return array{identifier: string, purpose: string, expires_in: int}
     */
    private function issueOtp(User $user, string $identifier, string $purpose): array
    {
        $code = (string) random_int(100000, 999999);
        $channel = filter_var($identifier, FILTER_VALIDATE_EMAIL) ? 'email' : 'sms';

        OtpCode::where('user_id', $user->id)
            ->where('purpose', $purpose)
            ->whereNull('consumed_at')
            ->update(['consumed_at' => now()]);

        OtpCode::create([
            'user_id' => $user->id,
            'identifier' => $identifier,
            'channel' => $channel,
            'purpose' => $purpose,
            'code_hash' => Hash::make($code),
            'expires_at' => now()->addMinutes(10),
        ]);

        try {
            $user->notify(new OneTimeCodeNotification($code, $purpose, $channel, 10));
        } catch (\Throwable $e) {
            // The account exists either way; the person can ask for a new code.
            report($e);
        }

        return [
            'identifier' => $identifier,
            'purpose' => $purpose,
            'expires_in' => 600,
        ];
    }
}
