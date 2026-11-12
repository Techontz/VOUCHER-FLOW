<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\JournalLine;
use App\Services\AuditLogger;
use App\Services\Erp\ChartOfAccounts;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AccountController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(ChartOfAccounts $chart): JsonResponse
    {
        $balances = collect($chart->trialBalance()['rows'])->keyBy('account_id');

        return response()->json(['data' => Account::query()->orderBy('code')->get()
            ->each(fn (Account $a) => $a->setAttribute('balance', $balances[$a->id]['balance'] ?? 0))]);
    }

    public function store(Request $request): JsonResponse
    {
        $account = Account::create($this->rules($request));
        $this->audit->log('account.created', "Added account {$account->code} {$account->name}", $account);

        return response()->json(['data' => $account], 201);
    }

    public function update(Request $request, Account $account): JsonResponse
    {
        $data = $this->rules($request, $account);

        // An account with postings keeps its type, or every report built on
        // those postings would change meaning retroactively.
        if (isset($data['type']) && $data['type'] !== $account->type && JournalLine::where('account_id', $account->id)->exists()) {
            abort(422, "{$account->code} has postings; its type cannot change.");
        }

        abort_if(isset($data['is_active']) && ! $data['is_active'] && $account->system_key, 422, 'The posting rules use this account; it cannot be deactivated.');

        $account->update($data);
        $this->audit->log('account.updated', "Updated account {$account->code}", $account);

        return response()->json(['data' => $account]);
    }

    public function destroy(Account $account): JsonResponse
    {
        abort_if($account->system_key !== null, 422, 'The posting rules use this account; it cannot be deleted.');
        abort_if(JournalLine::where('account_id', $account->id)->exists(), 422, "{$account->code} has postings. Deactivate it instead.");

        $account->delete();
        $this->audit->log('account.deleted', "Deleted account {$account->code}", $account);

        return response()->json(['message' => "{$account->code} deleted."]);
    }

    private function rules(Request $request, ?Account $account = null): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'code' => [$account ? 'sometimes' : 'required', 'string', 'max:20', Rule::unique('accounts')->where('company_id', $company)->ignore($account?->id)],
            'name' => [$account ? 'sometimes' : 'required', 'string', 'max:160'],
            'type' => [$account ? 'sometimes' : 'required', Rule::in(Account::TYPES)],
            'parent_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}
