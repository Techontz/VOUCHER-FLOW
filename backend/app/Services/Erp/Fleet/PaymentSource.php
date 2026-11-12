<?php

namespace App\Services\Erp\Fleet;

use App\Models\Erp\Account;
use App\Models\Erp\Supplier;
use RuntimeException;

/**
 * Where the money for a fleet cost came from: a cash or bank account (an
 * asset account coded 1100 to 1299), or credit from a supplier, which is
 * owed on Accounts payable. Exactly one of the two.
 */
class PaymentSource
{
    /**
     * @param  array<string, mixed>  $data
     * @return array{account_id: ?int, supplier_id: ?int}
     */
    public static function resolve(array $data): array
    {
        $accountId = ! empty($data['account_id']) ? (int) $data['account_id'] : null;
        $supplierId = ! empty($data['supplier_id']) ? (int) $data['supplier_id'] : null;

        if (($accountId === null) === ($supplierId === null)) {
            throw new RuntimeException('Say how this was paid: from a cash or bank account, or on credit from a supplier, not both.');
        }

        if ($accountId !== null) {
            self::assertCashOrBank($accountId);
        }

        if ($supplierId !== null && ! Supplier::query()->whereKey($supplierId)->exists()) {
            throw new RuntimeException('That supplier is not one of this company\'s suppliers.');
        }

        return ['account_id' => $accountId, 'supplier_id' => $supplierId];
    }

    public static function assertCashOrBank(int $accountId): Account
    {
        $account = Account::query()->whereKey($accountId)->first();

        $code = (string) $account?->code;

        if (! $account || $account->type !== 'asset' || ! ctype_digit($code) || (int) $code < 1100 || (int) $code > 1299) {
            throw new RuntimeException('Payments come from a cash or bank account (codes 1100 to 1299).');
        }

        if (! $account->is_active) {
            throw new RuntimeException("{$account->name} is inactive.");
        }

        return $account;
    }
}
