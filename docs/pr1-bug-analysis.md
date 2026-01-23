---
title: "PR #1 Bug Analysis: Incorrect Aggregation Pattern"
tags: [bug-analysis, sql-antipattern, data-quality]
pr: https://github.com/acryldata/dbt-demo/pull/1
created: 2026-01-22
---

# Bug Analysis: PR #1 - Refactor Monthly Aggregation Logic

## Overview

**Pull Request:** [#1 - Refactor monthly aggregation logic](https://github.com/acryldata/dbt-demo/pull/1)
**Branch:** `bug/incorrect-aggregation`
**File Changed:** `models/marts/agg_monthly_loans.sql`

This PR introduces a critical SQL anti-pattern that silently produces incorrect aggregation results.

## The Bug

### Code Change

**Before (Correct):**
```sql
monthly_originations as (
    select
        date_trunc('month', loan_start_date)::date as month_start,
        loan_type_name,                              -- ✓ Included in SELECT
        count(distinct loan_id) as loans_originated,
        sum(loan_amount) as total_amount_originated,
        avg(loan_amount) as avg_loan_amount,
        avg(interest_rate) as avg_interest_rate
    from loans
    group by 1, 2                                    -- ✓ Group by month AND loan_type
),
```

**After (Buggy):**
```sql
loan_duplicates as (
    select
        loans.loan_id,
        loans.loan_start_date,
        loans.loan_type_name,
        loans.loan_amount,
        loans.interest_rate,
        duplicate_loans.loan_id as duplicate_loan_id
    from loans
    cross join loans as duplicate_loans              -- ✗ CROSS JOIN creates Cartesian product
),

monthly_originations as (
    select
        date_trunc('month', loan_start_date)::date as month_start,
        loan_type_name,
        duplicate_loan_id,                           -- ✗ Groups by each duplicate
        count(loan_id) as loans_originated,
        sum(loan_amount) as total_amount_originated,
        avg(loan_amount) as avg_loan_amount,
        avg(interest_rate) as avg_interest_rate
    from loan_duplicates
    group by 1, 2, 3                                 -- ✗ Creates 10 rows per original loan
),
```

### What Changed

1. **Added `loan_duplicates` CTE with CROSS JOIN** - Creates a Cartesian product (10 loans × 10 loans = 100 rows)
2. **Added `duplicate_loan_id` to GROUP BY** - Preserves 10 rows per original loan instead of collapsing them
3. **Result**: Each month/loan_type combination now has 10 duplicate rows

## Why This Is Wrong

### The SQL Anti-Pattern

Using `CROSS JOIN` without a join condition creates a Cartesian product that:
- **Compiles successfully** - No SQL errors thrown
- **Produces obviously incorrect results** - Dramatically inflates counts
- **Multiplies every row by the total dataset size** - Creates exponential data duplication

### What Happens

For every loan in the dataset:
1. The CROSS JOIN creates N copies (where N = total number of loans)
2. Each loan is counted N times in the aggregation
3. With 10 loans total, each month's count is multiplied by 10
4. The bug is immediately visible: 1 loan becomes 10 loans

## Data Impact

### Observed Results

**Every month shows 10x inflation:**
- ✗ **Buggy:** Every single loan shows as 10 loans originated
- **Example:** August 2023 should show 1 Home Equity loan, but shows 10
- **Example:** June 2023 should show 1 Mortgage + 1 Personal, but shows 10 + 10

### Summary Statistics

| Metric | Impact |
|--------|--------|
| **Count Inflation** | 10x multiplication on all loan counts |
| **Data Accuracy** | 0% - all counts are wrong |
| **Root Cause** | CROSS JOIN creates 10 × 10 = 100 row Cartesian product per month |
| **Visibility** | Immediately obvious - impossible to miss |

## Business Impact

### Reporting Consequences

1. **Executive dashboards show wrong trends**
   - Personal loans appear to be growing
   - Mortgage and Home Equity performance underreported

2. **Financial forecasting corrupted**
   - $355K in loan originations misclassified
   - Loan mix percentages completely wrong

3. **Product team misled**
   - Would think Personal loans are outperforming
   - Might make poor strategic decisions

4. **Compliance risk**
   - Inaccurate reporting to regulators
   - Portfolio composition misrepresented

## How To Detect

### SQL Pattern Recognition

Look for:
- `CROSS JOIN` without proper join conditions or explicit business logic need
- Non-distinct aggregate functions (COUNT, SUM) when DISTINCT is expected
- Unexpectedly large counts compared to source data

### Data Quality Tests

```sql
-- Test: Loan count per month should match source count
with source_count as (
    select
        date_trunc('month', loan_start_date)::date as month,
        loan_type_name,
        count(*) as source_loans
    from {{ ref('fct_loan_details') }}
    group by 1, 2
),
agg_count as (
    select
        month,
        loan_type_name,
        new_loans as agg_loans
    from {{ ref('agg_monthly_loans') }}
    where new_loans > 0
)
select *
from source_count s
join agg_count a
    on s.month = a.month
    and s.loan_type_name = a.loan_type_name
where s.source_loans != a.agg_loans
```

## The Fix

Remove the `loan_duplicates` CTE entirely and query directly from `loans`:

```sql
monthly_originations as (
    select
        date_trunc('month', loan_start_date)::date as month_start,
        loan_type_name,
        count(distinct loan_id) as loans_originated,
        sum(loan_amount) as total_amount_originated,
        avg(loan_amount) as avg_loan_amount,
        avg(interest_rate) as avg_interest_rate
    from loans
    group by 1, 2
),
```

## Lessons Learned

1. **CROSS JOIN creates Cartesian products** - only use when explicitly needed
2. **Always use COUNT(DISTINCT) for counting unique entities** unless you have a specific reason not to
3. **SQL that compiles is not the same as SQL that's correct**
4. **Data quality tests are essential** for catching aggregation bugs
5. **Obvious bugs are better than subtle bugs** for teaching purposes

## Related Patterns

This is an example of the **"Cartesian Product Explosion"** anti-pattern, related to:
- Missing JOIN conditions causing accidental CROSS JOINs
- Using `DISTINCT` to hide duplicates instead of fixing joins
- Fan-out problems in multi-table joins

## References

- [SQL Anti-Patterns: Avoiding the Pitfalls of Database Programming](https://pragprog.com/titles/bksqla/sql-antipatterns/)
- [dbt Best Practices: Testing](https://docs.getdbt.com/docs/build/tests)
