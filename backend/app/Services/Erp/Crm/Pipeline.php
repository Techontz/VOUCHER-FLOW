<?php

namespace App\Services\Erp\Crm;

use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Models\Erp\Customer;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The CRM's state changes: a lead converting into a customer and an
 * opportunity, and an opportunity moving between stages. Both run under a
 * row lock so a double click or two people at once cannot do them twice.
 */
class Pipeline
{
    public function __construct(private readonly DocumentNumberer $numbers, private readonly AuditLogger $audit) {}

    /**
     * Converts a qualified lead, exactly once. An existing customer may be
     * named instead of creating a new one (the buyer is already on the books).
     *
     * @param  array{customer_id?: int|null, title?: string|null, value?: numeric|null, expected_close_date?: string|null, stage?: string|null}  $options
     * @return array{lead: Lead, customer: Customer, opportunity: Opportunity}
     */
    public function convert(Lead $lead, array $options, User $actor): array
    {
        return DB::transaction(function () use ($lead, $options, $actor) {
            $locked = Lead::query()->lockForUpdate()->findOrFail($lead->id);

            if ($locked->isConverted()) {
                throw new RuntimeException("{$locked->number} has already been converted.");
            }

            if ($locked->status !== Lead::STATUS_QUALIFIED) {
                throw new RuntimeException("Only a qualified lead can be converted. {$locked->number} is {$locked->status}.");
            }

            $customer = ! empty($options['customer_id'])
                ? Customer::query()->findOrFail($options['customer_id'])
                : Customer::create([
                    'code' => $this->numbers->next('CUS'),
                    'name' => $locked->company_name ?: $locked->contact_name,
                    'contact_person' => $locked->contact_name,
                    'phone' => $locked->phone,
                    'email' => $locked->email,
                    'city' => $locked->region,
                    'created_by' => $actor->id,
                ]);

            $stage = $options['stage'] ?? Opportunity::STAGE_PROSPECTING;
            $opportunity = Opportunity::create([
                'number' => $this->numbers->next('OPP'),
                'title' => $options['title'] ?? ($customer->name.' opportunity'),
                'lead_id' => $locked->id,
                'customer_id' => $customer->id,
                'stage' => $stage,
                'value' => $options['value'] ?? $locked->estimated_value,
                'probability' => Opportunity::DEFAULT_PROBABILITY[$stage],
                'expected_close_date' => $options['expected_close_date'] ?? now()->addDays(30)->toDateString(),
                'owner_id' => $locked->owner_id ?? $actor->id,
                'stage_changed_at' => now(),
                'created_by' => $actor->id,
            ]);

            $locked->update([
                'status' => Lead::STATUS_CONVERTED,
                'customer_id' => $customer->id,
                'opportunity_id' => $opportunity->id,
                'converted_at' => now(),
                'converted_by' => $actor->id,
            ]);

            $this->audit->log('crm.lead_converted', "Converted {$locked->number} into customer {$customer->code} and {$opportunity->number}", $locked,
                ['status' => Lead::STATUS_QUALIFIED], ['status' => Lead::STATUS_CONVERTED], actor: $actor);

            return ['lead' => $locked, 'customer' => $customer, 'opportunity' => $opportunity];
        });
    }

    /** Moves a deal to another stage; closing it as won or lost records why. */
    public function moveStage(Opportunity $opportunity, string $stage, ?string $reason, ?string $note, User $actor): Opportunity
    {
        if (! in_array($stage, Opportunity::STAGES, true)) {
            throw new RuntimeException("{$stage} is not a pipeline stage.");
        }

        return DB::transaction(function () use ($opportunity, $stage, $reason, $note, $actor) {
            $locked = Opportunity::query()->lockForUpdate()->findOrFail($opportunity->id);
            $from = $locked->stage;

            if ($from === $stage) {
                return $locked;
            }

            $closing = in_array($stage, [Opportunity::STAGE_WON, Opportunity::STAGE_LOST], true);
            $reasons = $stage === Opportunity::STAGE_WON ? Opportunity::WIN_REASONS : Opportunity::LOSS_REASONS;

            if ($stage === Opportunity::STAGE_LOST && ! $reason) {
                throw new RuntimeException('Say why the deal was lost before closing it.');
            }

            if ($closing && $reason && ! in_array($reason, $reasons, true)) {
                throw new RuntimeException("{$reason} is not a recognised reason for a {$stage} deal.");
            }

            $locked->update([
                'stage' => $stage,
                // Each stage carries its usual probability; the owner may refine it afterwards.
                'probability' => Opportunity::DEFAULT_PROBABILITY[$stage],
                'close_reason' => $closing ? $reason : null,
                'close_note' => $closing ? $note : null,
                'closed_at' => $closing ? now() : null,
                'stage_changed_at' => now(),
            ]);

            $this->audit->log('crm.opportunity_stage_changed', "Moved {$locked->number} from {$from} to {$stage}", $locked,
                ['stage' => $from], ['stage' => $stage], actor: $actor);

            return $locked;
        });
    }
}
