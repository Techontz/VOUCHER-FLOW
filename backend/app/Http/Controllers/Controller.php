<?php

namespace App\Http\Controllers;

use Illuminate\Foundation\Auth\Access\AuthorizesRequests;

/**
 * Laravel 11 dropped AuthorizesRequests from the generated base controller.
 * It is back because authorisation belongs in policies, and `$this->authorize()`
 * is how a controller asks one — without it every controller reinvents the
 * question as a private helper, which is exactly the drift the policies were
 * introduced to stop.
 */
abstract class Controller
{
    use AuthorizesRequests;
}
