<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** One platform-wide default, set by the operator. Not tenant data. */
class PlatformSetting extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['value' => 'json'];
    }
}
