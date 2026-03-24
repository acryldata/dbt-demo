with source as (
    select * from {{ ref('raw_loan_payments') }}
),

renamed as (
    select
        payment_id,
        loan_id,
        cast(payment_date as date) as payment_date,
        payment_amount,
        principal_paid,
        interest_paid,
        payment_status
    from source
)

select * from renamed
