<?php

namespace Database\Seeders\Erp;

use App\Models\User;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;

/**
 * The money Watercom started with: share capital paid into the bank, cash on
 * hand and a petty cash float, dated before any other demo activity.
 *
 * Runs before every other module's demo data, so the salaries, fuel and
 * supplier payments they record are paid out of real balances rather than
 * driving the cash accounts below zero. Keyed to the company with its own
 * purpose, so a second run finds the entry and posts nothing.
 */
class Step10OpeningBalancesSeeder extends Seeder
{
    public const BANK = 650_000_000;

    public const CASH = 35_000_000;

    public const PETTY_CASH = 2_000_000;

    public function __construct(private readonly JournalPoster $journal) {}

    public function run(): void
    {
        $company = app(TenantContext::class)->company();

        if (! $company || ! BusinessConfig::of($company)->postsToLedger()
            || $this->journal->existing($company, 'opening_capital')) {
            return;
        }

        $admin = User::query()->where('email', 'admin@watercom.test')->first();
        $total = self::BANK + self::CASH + self::PETTY_CASH;

        $this->journal->post([
            ['account' => 'bank', 'debit' => self::BANK, 'description' => 'Share capital paid in'],
            ['account' => 'cash', 'debit' => self::CASH, 'description' => 'Cash on hand'],
            ['account' => 'petty_cash', 'debit' => self::PETTY_CASH, 'description' => 'Petty cash float'],
            ['account' => 'share_capital', 'credit' => $total, 'description' => 'Paid-up share capital'],
        ], 'Opening capital and cash balances', now()->subMonths(8)->startOfMonth()->toDateString(), $company, 'opening_capital', $admin);
    }
}
