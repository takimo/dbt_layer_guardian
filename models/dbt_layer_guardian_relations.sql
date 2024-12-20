{{
  config(
    materialized = 'incremental',
    partition_by = {'field': 'created_at', 'data_type': 'date'},
    incremental_strategy = 'insert_overwrite',
    on_schema_change = 'append_new_columns'
  )
}}

{% set target_layer_names = var('target_layer_names', [""]) %}
{% set layering_rules = var('layering_rules', {"": [""]}) %}

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
joined_judge as (
    select
        joined_specs.*,
        case
{% for parent_layer, child_layers in layering_rules.items() %}
    when parent_model_is_private_model is true and parent_model_layering = children_model_layering then true
    when parent_model_layering = "{{ parent_layer }}" and children_model_layering in (
        {% for child_layer in child_layers %}
            "{{ child_layer }}"{% if not loop.last %}, {% endif %}
        {% endfor %}
    ) then true
{% endfor %}
            else false
        end as layering_judge
    from joined_specs
),
final as (
    select
        current_date('Asia/Tokyo') as created_at,
        joined_judge.*
    from joined_judge
)

select *
from final
