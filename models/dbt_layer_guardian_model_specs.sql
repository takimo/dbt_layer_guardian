
{% set layer_definitions = var('layer_definitions', []) %}

with base_specs as (
    select * from unnest(array<struct<model_name string, model_unique_id string, original_file_path string>>
        [
{% set values = graph.nodes.values() if graph else [] %}
{% for model in values if model.resource_type == 'model' %}
          ("{{ model.name }}", "{{ model.unique_id }}", "{{ model.original_file_path }}"){% if not loop.last %},{% endif %}
{% endfor %}
        ]
    )
),
layer_mapping as (
    select
        path,
        layer_name,
        concat("models/", path, "/") as folder_path
    from unnest(array<struct<path string, layer_name string>>
        [
        {% for layer in layer_definitions %}
            ("{{ layer.path }}", "{{ layer.layer_name }}"){% if not loop.last %},{% endif %}
        {% endfor %}
        ]
    )
),
joined_base_layering as (
    select
        base_specs.*,
        ifnull(layer_mapping.layer_name, "unknown") as layer_name,
        array_length(split(replace(base_specs.original_file_path, layer_mapping.folder_path, ""), "/")) as depth_from_layer_base_dir,
        (
            -- プライベートモデルのフラグを決定
            -- モデルパスにおける「レイヤーパス+1階層」以降の存在をチェック
            case
                when 
                    array_length(split(replace(base_specs.original_file_path, layer_mapping.folder_path, ""), "/")) > 1
                then true
                else false
            end
        ) as is_private_model
    from base_specs
    left join layer_mapping on starts_with(base_specs.original_file_path, layer_mapping.folder_path)
),
final as (
    select
        current_date('Asia/Tokyo') as created_at,
        joined_base_layering.*
    from joined_base_layering
)

select *
from final
