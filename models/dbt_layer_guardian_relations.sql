{% set target_layer_names = var('target_layer_names', [""]) %}

with
model_specs as (
    select * from {{ ref('dbt_layer_guardian_model_specs') }}
    where created_at = current_date('Asia/Tokyo')
),
relations as (
  select * from unnest(array<struct<parent_model string, children_model string>>
    [
{% set values = graph.nodes.values() if graph else [] %}
{% for model in values if model.resource_type == 'model' %}
{% for ref_model in model.depends_on.nodes %}
      ("{{ ref_model }}", "{{ model.unique_id }}"),
{% endfor %}
{% endfor %}
    ("", "")
    ]
  )
),
joined_specs as (
    select
      relations.*,
      parent_model_spec.layer_name as parent_model_layering,
      children_model_spec.layer_name as children_model_layering,
      parent_model_spec.is_private_model as parent_model_is_private_model,
      children_model_spec.is_private_model as children_model_is_private_model
    from relations
    left join model_specs as parent_model_spec
      on relations.parent_model = parent_model_spec.model_unique_id
    left join model_specs as children_model_spec
      on relations.children_model = children_model_spec.model_unique_id
    where
      parent_model_spec.layer_name in ({% for layering_name in target_layer_names %}"{{ layering_name }}"{% if not loop.last %}, {% endif %}{% endfor %})
      and children_model_spec.layer_name in ({% for layering_name in target_layer_names %}"{{ layering_name }}"{% if not loop.last %}, {% endif %}{% endfor %})
),
final as (
    select
        joined_specs.*
    from joined_specs
)

select *
from final
