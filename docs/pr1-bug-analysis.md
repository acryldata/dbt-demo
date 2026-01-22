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
monthly_originations as (
    select
        date_trunc('month', loan_start_date)::date as month_start,
        max(loan_type_name) as loan_type_name,      -- ✗ Using MAX() on text field
        count(distinct loan_id) as loans_originated,
        sum(loan_amount) as total_amount_originated,
        avg(loan_amount) as avg_loan_amount,
        avg(interest_rate) as avg_interest_rate
    from loans
    group by 1                                       -- ✗ Removed loan_type_name from GROUP BY
),
```

### What Changed

1. **Removed `loan_type_name` from GROUP BY clause** - Now grouping only by month
2. **Added `MAX(loan_type_name)`** - Using aggregate function on text field to avoid SQL error

## Why This Is Wrong

### The SQL Anti-Pattern

Using `MAX()` on a text/varchar field is a common SQL anti-pattern that:
- **Compiles successfully** - No SQL errors thrown
- **Produces incorrect results** - Silently corrupts data
- **Hides multiple values** - Picks one arbitrary value (alphabetically highest)

### What Happens

When multiple loan types exist in the same month:
1. SQL groups ALL loans together by month (ignoring loan type)
2. Calculates aggregates across ALL loan types combined
3. Picks the alphabetically "highest" loan type name via `MAX()`
4. Attributes the combined totals to that one loan type
5. Other loan types **completely disappear** from the output

## Data Impact

### Affected Months

**March 2023:**
- ✓ **Correct:** 1 Home Equity ($75K) + 1 Personal ($15K) = 2 separate rows
- ✗ **Buggy:** 1 Personal ($90K) = 1 combined row
- **Impact:** Home Equity loan completely missing, Personal inflated

**June 2023:**
- ✓ **Correct:** 1 Mortgage ($280K) + 1 Personal ($25K) = 2 separate rows
- ✗ **Buggy:** 1 Personal ($305K) = 1 combined row
- **Impact:** Mortgage loan completely missing, Personal inflated

### Summary Statistics

| Metric | Impact |
|--------|--------|
| **Rows Lost** | 2 out of 10 (20% data loss) |
| **Accuracy Rate** | 60% (only 6/10 rows correct) |
| **Loan Types Erased** | Mortgage (June), Home Equity (March) |
| **Misattributed Amount** | $355,000 assigned to wrong loan type |
| **Personal Loans Inflated** | +100% in 2 months (showing 2 instead of 1) |

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
- `MAX()` or `MIN()` on text/varchar fields in GROUP BY queries
- Fields in SELECT that aren't in GROUP BY (and aren't aggregated properly)
- CTEs that reduce dimensionality unexpectedly

### Data Quality Tests

```sql
-- Test: Count of loan types per month should match source
with source_count as (
    select
        date_trunc('month', loan_start_date)::date as month,
        count(distinct loan_type_id) as distinct_types
    from {{ ref('stg_loans') }}
    group by 1
),
agg_count as (
    select
        month,
        count(distinct loan_type_name) as distinct_types
    from {{ ref('agg_monthly_loans') }}
    where new_loans > 0
    group by 1
)
select *
from source_count s
join agg_count a on s.month = a.month
where s.distinct_types != a.distinct_types
```

## The Fix

Simply restore the original GROUP BY:

```sql
monthly_originations as (
    select
        date_trunc('month', loan_start_date)::date as month_start,
        loan_type_name,                              -- Remove MAX()
        count(distinct loan_id) as loans_originated,
        sum(loan_amount) as total_amount_originated,
        avg(loan_amount) as avg_loan_amount,
        avg(interest_rate) as avg_interest_rate
    from loans
    group by 1, 2                                    -- Restore loan_type_name to GROUP BY
),
```

## Lessons Learned

1. **Never use MAX/MIN on categorical text fields** to "fix" GROUP BY errors
2. **All non-aggregated SELECT fields must be in GROUP BY** (or be constants)
3. **SQL that compiles is not the same as SQL that's correct**
4. **Data quality tests are essential** for catching aggregation bugs
5. **Silent data corruption is more dangerous than errors** - queries should fail loudly

## Related Patterns

This is an example of the **"Lossy Aggregation"** anti-pattern, related to:
- Using `ANY_VALUE()` inappropriately
- Using `DISTINCT` to hide duplicates instead of fixing joins
- Grouping at wrong grain and losing detail

## References

- [SQL Anti-Patterns: Avoiding the Pitfalls of Database Programming](https://pragprog.com/titles/bksqla/sql-antipatterns/)
- [dbt Best Practices: Testing](https://docs.getdbt.com/docs/build/tests)
