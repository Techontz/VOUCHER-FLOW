<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\Company;
use App\Models\User;
use App\Models\Voucher;
use App\Models\WorkflowStep;
use App\Notifications\VoucherReminderNotification;
use App\Support\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Reminds whoever is holding a voucher once it has waited 24 hours.
 *
 * "Holding" follows the real workflow: the signer or approver at the current
 * step, whoever pays an approved voucher, and the requester of a voucher sent
 * back for changes. Nobody is reminded about the same voucher more than once
 * in 24 hours, so a voucher that keeps waiting draws one reminder a day. A
 * step with nobody to act (no HOD set, say) falls to the company admins.
 */
class VoucherReminders
{
    public const TYPE = 'voucher.reminder';

    public const AFTER_HOURS = 24;

    public function __construct(
        private readonly WorkflowEngine $engine,
        private readonly Notifier $notifier,
        private readonly TenantContext $tenant,
    ) {}

    /** Sends every reminder that is due; returns how many were sent. */
    public function run(?Carbon $now = null): int
    {
        $now ??= now();
        $sent = 0;

        $companies = $this->tenant->withoutScope(
            fn () => Company::whereIn('status', ['active', 'trial'])->get(),
        );

        foreach ($companies as $company) {
            $sent += $this->tenant->forCompany($company, fn () => $this->forCompany($now));
        }

        return $sent;
    }

    private function forCompany(Carbon $now): int
    {
        $cutoff = $now->copy()->subHours(self::AFTER_HOURS);
        $sent = 0;
        /** @var array<int, array{user: User, items: array<int, array{title: string, body: string, voucher: Voucher}>}> $digest */
        $digest = [];

        $vouchers = Voucher::query()
            ->with(['workflow.steps', 'department', 'requester'])
            ->withMax('approvals', 'created_at')
            ->whereIn('status', [Voucher::STATUS_IN_REVIEW, Voucher::STATUS_APPROVED, Voucher::STATUS_CHANGES_REQUESTED])
            ->get();

        foreach ($vouchers as $voucher) {
            $since = $this->waitingSince($voucher);

            if (! $since || $since->greaterThan($cutoff)) {
                continue;
            }

            [$kind, $people] = $this->holders($voucher);

            foreach ($people as $person) {
                if ($person->status !== 'active' || $this->remindedRecently($person, $voucher, $cutoff)) {
                    continue;
                }

                $digest[$person->id]['user'] = $person;
                $digest[$person->id]['items'][] = $this->remind($person, $voucher, $kind, $since, $now);
                $sent++;
            }
        }

        // One email per person, listing everything waiting on them, rather than
        // an email per voucher.
        if (config('vouchflow.reminders.email', true)) {
            foreach ($digest as ['user' => $person, 'items' => $items]) {
                if (! $person->email) {
                    continue;
                }

                try {
                    $person->notify(new VoucherReminderNotification($items, $person->locale === 'sw'));
                } catch (\Throwable $e) {
                    // The in-app reminders stand even when mail is unavailable.
                    report($e);
                }
            }
        }

        return $sent;
    }

    /** When the voucher arrived where it is now. */
    private function waitingSince(Voucher $voucher): ?Carbon
    {
        if ($voucher->status === Voucher::STATUS_APPROVED && $voucher->approved_at) {
            return Carbon::parse($voucher->approved_at);
        }

        $last = $voucher->approvals_max_created_at;

        return $last ? Carbon::parse($last) : ($voucher->submitted_at ? Carbon::parse($voucher->submitted_at) : null);
    }

    /** @return array{0: string, 1: Collection<int, User>} */
    private function holders(Voucher $voucher): array
    {
        if ($voucher->status === Voucher::STATUS_CHANGES_REQUESTED) {
            return ['changes', collect([$voucher->requester])->filter()];
        }

        if ($voucher->status === Voucher::STATUS_APPROVED) {
            $payers = $this->engine->applicableSteps($voucher)
                ->filter(fn (WorkflowStep $step) => (bool) $step->can_pay)
                ->flatMap(fn (WorkflowStep $step) => $this->engine->assigneesFor($voucher, $step))
                ->unique('id')->values();

            return ['payment', $payers->isNotEmpty() ? $payers : $this->admins()];
        }

        $step = $this->engine->stepAt($voucher, $voucher->current_step_position);

        if (! $step) {
            return ['approval', collect()];
        }

        $kind = match (true) {
            $step->can_sign && ! $step->can_approve && $voucher->step_signed_at !== null => 'submit',
            (bool) $step->can_approve => 'approval',
            (bool) $step->can_sign => 'signature',
            default => 'approval',
        };

        $people = $this->engine->assigneesFor($voucher, $step);

        return [$kind, $people->isNotEmpty() ? $people : $this->admins()];
    }

    private function admins(): Collection
    {
        return User::where('role', User::ROLE_COMPANY_ADMIN)->where('status', 'active')->get();
    }

    private function remindedRecently(User $person, Voucher $voucher, Carbon $cutoff): bool
    {
        return AppNotification::query()
            ->where('user_id', $person->id)
            ->where('type', self::TYPE)
            ->where('entity_type', 'Voucher')
            ->where('entity_id', $voucher->id)
            ->where('created_at', '>', $cutoff)
            ->exists();
    }

    /** @return array{title: string, body: string, voucher: Voucher} */
    private function remind(User $person, Voucher $voucher, string $kind, Carbon $since, Carbon $now): array
    {
        $days = max(1, (int) floor($since->diffInHours($now) / 24));
        $en = $days === 1 ? '1 day' : "{$days} days";
        $sw = "siku {$days}";
        $no = $voucher->number;

        [$title, $titleSw, $body, $bodySw] = match ($kind) {
            'signature' => [
                "Reminder: {$no} is waiting for your signature",
                "Kumbusho: {$no} inasubiri sahihi yako",
                "It has been waiting for {$en}. Open it to sign, or request changes.",
                "Imesubiri kwa {$sw}. Ifungue uisaini, au uombe mabadiliko.",
            ],
            'submit' => [
                "Reminder: {$no} is signed but not yet submitted",
                "Kumbusho: {$no} imesainiwa lakini bado haijawasilishwa",
                "You signed it {$en} ago. Submit it to the next approval step.",
                "Uliisaini {$sw} zilizopita. Iwasilishe kwa hatua inayofuata ya idhini.",
            ],
            'payment' => [
                "Reminder: {$no} is approved and waiting for payment",
                "Kumbusho: {$no} imeidhinishwa na inasubiri malipo",
                "It was approved {$en} ago. Record the payment once the money is released.",
                "Iliidhinishwa {$sw} zilizopita. Rekodi malipo fedha zikishatolewa.",
            ],
            'changes' => [
                "Reminder: {$no} is waiting for your changes",
                "Kumbusho: {$no} inasubiri marekebisho yako",
                "Changes were requested {$en} ago. Update the voucher and submit it again.",
                "Mabadiliko yaliombwa {$sw} zilizopita. Rekebisha vocha na uiwasilishe tena.",
            ],
            default => [
                "Reminder: {$no} is waiting for your approval",
                "Kumbusho: {$no} inasubiri idhini yako",
                "It has been waiting for {$en}. Open it to approve, reject or request changes.",
                "Imesubiri kwa {$sw}. Ifungue uidhinishe, ukatae au uombe mabadiliko.",
            ],
        };

        $this->notifier->toUser($person, self::TYPE, $title, $titleSw, $body, $bodySw, $voucher, 'ph-alarm');

        $swahili = $person->locale === 'sw';

        return ['title' => $swahili ? $titleSw : $title, 'body' => $swahili ? $bodySw : $body, 'voucher' => $voucher];
    }
}
