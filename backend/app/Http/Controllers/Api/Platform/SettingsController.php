<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Services\AuditLogger;
use App\Support\PlatformSettings;
use Illuminate\Http\Request;

/** Platform-wide defaults: trial length, support address, default currency. */
class SettingsController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function show()
    {
        return response()->json(['data' => PlatformSettings::all()]);
    }

    public function update(Request $request)
    {
        $rules = [];
        foreach (PlatformSettings::definitions() as $key => $definition) {
            $rules[$key] = ['sometimes', ...$definition['rules']];
        }

        $data = $request->validate($rules);

        if (isset($data['default_currency'])) {
            $data['default_currency'] = strtoupper($data['default_currency']);
        }

        $before = array_intersect_key(PlatformSettings::all(), $data);
        PlatformSettings::put($data);

        $this->audit->log('platform.settings_updated', 'Updated the platform settings', null, $before, array_intersect_key(PlatformSettings::all(), $data));

        return response()->json(['data' => PlatformSettings::all(), 'message' => 'Platform settings saved.']);
    }
}
