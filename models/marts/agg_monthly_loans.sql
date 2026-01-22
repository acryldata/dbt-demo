-- Monthly aggregation of loan metrics
-- Provides month-by-month totals and statistics

with loans as (
    select * from {{ ref('fct_loan_details') }}
),

payments as (
    select * from {{ ref('stg_loan_payments') }}
),

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

monthly_payments as (
    select
        date_trunc('month', payment_date)::date as month_start,
        count(distinct payment_id) as total_payments,
        sum(payment_amount) as total_payment_amount,
        sum(principal_paid) as total_principal_paid,
        sum(interest_paid) as total_interest_paid
    from payments
    group by 1
),

combined as (
    select
        coalesce(orig.month_start, pay.month_start) as month,
        orig.loan_type_name,
        coalesce(orig.loans_originated, 0) as new_loans,
        coalesce(orig.total_amount_originated, 0) as amount_originated,
        coalesce(orig.avg_loan_amount, 0) as avg_loan_size,
        coalesce(orig.avg_interest_rate, 0) as avg_rate,
        coalesce(pay.total_payments, 0) as payments_received,
        coalesce(pay.total_payment_amount, 0) as payment_volume,
        coalesce(pay.total_principal_paid, 0) as principal_collected,
        coalesce(pay.total_interest_paid, 0) as interest_collected
    from monthly_originations orig
    full outer join monthly_payments pay
        on orig.month_start = pay.month_start
)

select * from combined
order by month desc, loan_type_name
