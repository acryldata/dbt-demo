-- Staging model for loan payments
-- Source: raw_loan_payments seed table

with source as (
    select * from {{ ref('raw_loan_payments') }}
),

renamed as (
    select
        payment_id,
        loan_id,
        payment_date::date as payment_date,
        payment_amount,
        principal_paid,
        interest_paid,
        payment_status
    from source
)

select * from renamed
