<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\Shift;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Daily attendance: recorded by hand or imported from a biometric export, one
 * row per person per day (a second import of the same day replaces the first),
 * and summed by month for payroll: absences, overtime and days worked.
 */
class AttendanceService
{
    public const IMPORT_COLUMNS = ['employee_number', 'date', 'time_in', 'time_out'];

    public function __construct(private readonly AuditLogger $audit) {}

    /** @param  array{date: string, check_in?: ?string, check_out?: ?string, status?: ?string, note?: ?string}  $data */
    public function record(Employee $employee, array $data, User $actor, string $source = 'manual'): Attendance
    {
        $date = Carbon::parse($data['date'])->toDateString();
        $in = $this->time($data['check_in'] ?? null);
        $out = $this->time($data['check_out'] ?? null);
        $status = $data['status'] ?? null;
        $shift = $this->shiftFor($employee);
        $settings = HrSetting::current();

        if (! $status) {
            $status = ! $in ? 'absent' : ($shift && $this->minutes($in) > $this->minutes($shift->start_time) + $shift->grace_minutes ? 'late' : 'present');
        }

        $hours = 0.0;
        $overtime = 0.0;

        if ($in && $out && in_array($status, ['present', 'late'], true)) {
            $span = $this->minutes($out) - $this->minutes($in);
            $hours = round(($span <= 0 ? $span + 1440 : $span) / 60, 2);
            $scheduled = $shift ? $shift->hours() : (float) $settings->hours_per_day;
            $overtime = round(max(0, $hours - $scheduled), 2);
        }

        return Attendance::updateOrCreate(
            ['employee_id' => $employee->id, 'date' => $date],
            [
                'check_in' => in_array($status, ['present', 'late'], true) ? $in : null,
                'check_out' => in_array($status, ['present', 'late'], true) ? $out : null,
                'status' => $status,
                'hours_worked' => $hours,
                'overtime_hours' => $overtime,
                'source' => $source,
                'note' => $data['note'] ?? null,
                'recorded_by' => $actor->id,
            ],
        );
    }

    /**
     * Reads a biometric CSV export (employee_number, date, time_in, time_out)
     * and records each line. Lines that cannot be read are reported by number
     * and skipped; the rest are kept.
     *
     * @return array{imported: int, errors: list<array{line: int, message: string}>}
     */
    public function import(UploadedFile $file, User $actor): array
    {
        $handle = fopen($file->getRealPath(), 'r');

        if (! $handle) {
            throw new RuntimeException('The file could not be read.');
        }

        $header = fgetcsv($handle, escape: '\\');
        $columns = array_map(fn ($c) => strtolower(trim((string) preg_replace('/^\xEF\xBB\xBF/', '', (string) $c))), $header ?: []);
        $missing = array_diff(self::IMPORT_COLUMNS, $columns);

        if ($missing) {
            fclose($handle);
            throw new RuntimeException('The file needs a header row with the columns: '.implode(', ', self::IMPORT_COLUMNS).'. Missing: '.implode(', ', $missing).'.');
        }

        $index = array_flip($columns);
        $employees = Employee::query()->pluck('id', 'employee_number')->all();
        $imported = 0;
        $errors = [];
        $line = 1;

        DB::transaction(function () use ($handle, $index, $employees, $actor, &$imported, &$errors, &$line) {
            while (($row = fgetcsv($handle, escape: '\\')) !== false) {
                $line++;

                if ($row === [null] || ! array_filter($row, fn ($v) => trim((string) $v) !== '')) {
                    continue;
                }

                $value = fn (string $column) => trim((string) ($row[$index[$column]] ?? ''));
                $number = $value('employee_number');

                if (! isset($employees[$number])) {
                    $errors[] = ['line' => $line, 'message' => "No employee has the number '{$number}'."];

                    continue;
                }

                $date = $this->date($value('date'));

                if (! $date) {
                    $errors[] = ['line' => $line, 'message' => "'{$value('date')}' is not a date (use YYYY-MM-DD or DD/MM/YYYY)."];

                    continue;
                }

                if ($date->isFuture()) {
                    $errors[] = ['line' => $line, 'message' => "{$date->toDateString()} is in the future."];

                    continue;
                }

                foreach (['time_in', 'time_out'] as $column) {
                    if ($value($column) !== '' && ! $this->time($value($column))) {
                        $errors[] = ['line' => $line, 'message' => "'{$value($column)}' in {$column} is not a time (use HH:MM)."];

                        continue 2;
                    }
                }

                $this->record(Employee::query()->find($employees[$number]), [
                    'date' => $date->toDateString(),
                    'check_in' => $value('time_in') ?: null,
                    'check_out' => $value('time_out') ?: null,
                ], $actor, 'import');
                $imported++;
            }
        });

        fclose($handle);

        $this->audit->log('hr.attendance.imported', "Imported {$imported} attendance lines from {$file->getClientOriginalName()}".($errors ? ', '.count($errors).' skipped' : ''), actor: $actor);

        return ['imported' => $imported, 'errors' => $errors];
    }

    /**
     * Per employee, what the month's attendance adds up to.
     *
     * @return array<int, array{present: int, late: int, absent: int, leave: int, off: int, hours: float, overtime: float}>
     */
    public function summary(Carbon $from, Carbon $to, ?array $employeeIds = null): array
    {
        $rows = Attendance::query()
            ->whereDate('date', '>=', $from)->whereDate('date', '<=', $to)
            ->when($employeeIds !== null, fn ($q) => $q->whereIn('employee_id', $employeeIds ?: [0]))
            ->select('employee_id', 'status', DB::raw('count(*) as days'), DB::raw('sum(hours_worked) as hours'), DB::raw('sum(overtime_hours) as overtime'))
            ->groupBy('employee_id', 'status')
            ->get();

        $summary = [];

        foreach ($rows as $row) {
            $s = $summary[$row->employee_id] ??= ['present' => 0, 'late' => 0, 'absent' => 0, 'leave' => 0, 'off' => 0, 'hours' => 0.0, 'overtime' => 0.0];
            $s[$row->status] = (int) $row->days;
            $s['hours'] = round($s['hours'] + (float) $row->hours, 2);
            $s['overtime'] = round($s['overtime'] + (float) $row->overtime, 2);
            $summary[$row->employee_id] = $s;
        }

        return $summary;
    }

    public function shiftFor(Employee $employee): ?Shift
    {
        return $employee->shift ?? Shift::query()->where('is_default', true)->first();
    }

    private function time(?string $value): ?string
    {
        if ($value === null || trim($value) === '') {
            return null;
        }

        if (! preg_match('/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/', trim($value), $m) || (int) $m[1] > 23 || (int) $m[2] > 59) {
            return null;
        }

        return sprintf('%02d:%02d:00', $m[1], $m[2]);
    }

    private function minutes(string $time): int
    {
        [$h, $m] = array_map('intval', explode(':', $time));

        return $h * 60 + $m;
    }

    private function date(string $value): ?Carbon
    {
        foreach (['Y-m-d', 'd/m/Y', 'd-m-Y', 'Y/m/d'] as $format) {
            try {
                $date = Carbon::createFromFormat('!'.$format, $value);
            } catch (\Throwable) {
                continue;
            }

            if ($date && $date->format($format) === $value) {
                return $date;
            }
        }

        return null;
    }
}
