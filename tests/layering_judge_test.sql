{{ config(severity='warn') }}

select *
from {{ ref('dbt_layer_guardian_relations') }}
where layering_judge = false
    and created_at = current_date('Asia/Tokyo')
