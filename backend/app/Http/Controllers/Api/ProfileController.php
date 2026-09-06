<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

/** The signed-in user's own profile, signature and preferences. */
class ProfileController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function update(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'job_title' => ['nullable', 'string', 'max:120'],
            'locale' => ['nullable', Rule::in(config('vouchflow.locales'))],
            'theme' => ['nullable', Rule::in(['light', 'dark'])],
            'two_factor_enabled' => ['nullable', 'boolean'],
            'avatar' => ['nullable', 'image', 'max:2048'],
        ]);

        if ($request->hasFile('avatar')) {
            if ($user->avatar_path) {
                Storage::disk('public')->delete($user->avatar_path);
            }

            $user->avatar_path = $request->file('avatar')->store("companies/{$user->company_id}/avatars", 'public');
        }

        $user->fill(collect($data)->except('avatar')->filter(fn ($v) => $v !== null)->all())->save();

        return new UserResource($user->fresh()->load('department'));
    }

    /** Saves the reusable signature offered in the sign dialog. */
    public function storeSignature(Request $request)
    {
        $data = $request->validate([
            'signature' => ['required', 'string', 'max:1500000', 'regex:/^data:image\/(png|jpeg|webp);base64,/'],
        ], [
            'signature.regex' => 'The signature must be a PNG, JPEG or WebP image.',
        ]);

        $user = $request->user();

        $user->forceFill([
            'signature_data' => $data['signature'],
            'signature_updated_at' => now(),
        ])->save();

        $this->audit->log('user.signature_updated', "{$user->name} updated their saved signature", $user);

        return response()->json(['message' => 'Signature saved.', 'updated_at' => $user->signature_updated_at?->toIso8601String()]);
    }

    public function showSignature(Request $request)
    {
        return response()->json(['signature' => $request->user()->signature_data]);
    }

    public function destroySignature(Request $request)
    {
        $request->user()->forceFill(['signature_data' => null, 'signature_updated_at' => null])->save();

        return response()->json(['message' => 'Signature removed.']);
    }
}
