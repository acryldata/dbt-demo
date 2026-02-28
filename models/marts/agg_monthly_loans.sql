with 

monthly_originations as (
    select
        date_trunc('month', origination_date) as month_start,
        loan_type_name,
        count(*) as loans_originated,
        sum(principal_amount) as total_amount_originated,
        avg(principal_amount) as avg_loan_amount
    from {{ ref('fct_loan_details') }}
    group by 1, 2
),

monthly_payments as (
    select
        date_trunc('month', payment_date) as month_start,
        count(*) as total_payments,
        sum(payment_amount) as total_payment_amount,
        avg(payment_amount) as avg_payment_amount
    from {{ ref('stg_loan_payments') }}
    group by 1
),

combined as (
    select
        coalesce(orig.month_start, pay.month_start) as month,
        orig.loan_type_name,
        coalesce(orig.loans_originated, 0) as new_loans,
        coalesce(orig.total_amount_originated, 0) as amount_originated,
        coalesce(orig.avg_loan_amount, 0) as avg_loan_size,
        coalesce(pay.total_payments, 0) as payments_received,
        coalesce(pay.total_payment_amount, 0) as payment_amount_received,
        coalesce(pay.avg_payment_amount, 0) as avg_payment_size
    from monthly_originations orig
    full outer join monthly_payments pay
        on orig.month_start = pay.month_start
)

select * from combined
