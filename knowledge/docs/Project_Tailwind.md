# Project Tailwind

Owner: Revenue Cycle Operations
Status: Active

## Background

Project Tailwind is the revenue cycle team's initiative to get claims out the door faster
after discharge. It started with the facilities in our Accountable Care Organization,
where shared-savings payments depend on timely, complete claims, and that's still the
program's scope today.

The project name is internal. You won't find it in any table or column.

## The Tailwind Rate

**Definition.** The share of in-scope claims submitted within **24 hours** of the
patient's discharge:

```
within 24 hours:  DATEDIFF('hour', ENCOUNTERS.discharge_date, CLAIMS.submitted_date) <= 24
```

```
Tailwind Rate = in-scope claims submitted within 24 hours / all in-scope claims
```

## Scope

A claim is in scope only when all of these are true:

1. The encounter is at an **ACO-participating facility**:
   `FACILITIES.is_aco_participant = TRUE`. Facilities outside the ACO are not part of
   Tailwind and must not be included, even in a system-wide view.
2. The encounter is complete: `ENCOUNTERS.status = 'Completed'`.
3. The encounter has a discharge timestamp: `ENCOUNTERS.discharge_date IS NOT NULL`.

Report Tailwind over **all available history** unless someone asks for a specific period.

Including non-ACO facilities is the most common error, and it makes the program look far
worse than it is. Those facilities haven't adopted the Tailwind workflow.

## Targets

| Level | Tailwind Rate |
|---|---|
| Target | 80% |
| Stretch | 90% |

## Reference implementation

The saved query `tailwind_rate_by_month.sql` calculates the rate by month and overall.
