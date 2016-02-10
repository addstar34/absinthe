defmodule Absinthe.Type.BuiltIns.Introspection do
  use Absinthe.Schema.TypeModule

  alias Absinthe.Schema
  alias Absinthe.Flag
  alias Absinthe.Language
  alias Absinthe.Type

  @doc "Represents a schema"
  object :__schema, [
    fields: [
      types: [
        type: list_of(:__type),
        resolve: fn
          _, %{schema: schema} ->
            Schema.types(schema)
          |> Flag.as(:ok)
        end
      ],
      query_type: [
        type: :__type,
        resolve: fn
          _, %{schema: schema} ->
            {:ok, Schema.lookup_type(schema, :query)}
        end
      ],
      mutation_type: [
        type: :__type,
        resolve: fn
          _, %{schema: schema} ->
            {:ok, Schema.lookup_type(schema, :mutation)}
        end
      ],
      directives: [
        type: list_of(:__directive),
        resolve: fn
          _, %{schema: schema} ->
            {:ok, Schema.directives(schema)}
        end
      ]
    ]
  ]

  @doc "Represents a directive"
  object :__directive, [
    fields: [
      name: [type: :string],
      description: [type: :string],
      args: [
        type: list_of(:__inputvalue),
        resolve: fn
          _, %{source: source} ->
            structs = source.args |> Map.values
          {:ok, structs}
        end
      ],
      on_operation: [
        type: :boolean,
        resolve: fn
          _, %{source: source} ->
            {:ok, Enum.member?(source.on, Language.OperationDefinition)}
        end
      ],
      on_fragment: [
        type: :boolean,
        resolve: fn
          _, %{source: source} ->
            {:ok, Enum.member?(source.on, Language.FragmentSpread)}
        end
      ],
      on_field: [
        type: :boolean,
        resolve: fn
          _, %{source: source} ->
            {:ok, Enum.member?(source.on, Language.Field)}
        end
      ]
    ]
  ]

  @doc "Represents scalars, interfaces, object types, unions, enums in the system"
  object :__type, [
    fields: [
      kind: [
        type: :string,
        resolve: fn
          _, %{source: %{__struct__: type}} ->
            {:ok, type.kind}
        end
      ],
      name: [type: :string],
      description: [type: :string],
      fields: [
        type: list_of(:__field),
        args: [
          include_deprecated: [
            type: :boolean,
            default_value: false
          ]
        ],
        resolve: fn
          %{include_deprecated: show_deprecated}, %{source: %{__struct__: str, fields: fields}} when str in [Type.Object, Type.Interface] ->
            fields
          |> Enum.flat_map(fn
            {_, %{deprecation: is_deprecated} = field} ->
            if !is_deprecated || (is_deprecated && show_deprecated) do
              [field]
            else
              []
            end
          end)
          |> Flag.as(:ok)
          _, _ ->
            {:ok, nil}
        end
      ],
      interfaces: [
        type: list_of(:__type),
        resolve: fn
          _, %{schema: schema, source: %{interfaces: interfaces}} ->
            structs = interfaces
          |> Enum.map(fn
            ident ->
              Absinthe.Schema.lookup_type(schema, ident)
          end)
          {:ok, structs}
          _, _ ->
            {:ok, nil}
        end
      ],
      possible_types: [
        type: list_of(:__type),
        resolve: fn
          _, %{schema: schema, source: %{types: types}} ->
            structs = types |> Enum.map(&(Absinthe.Schema.lookup_type(schema, &1)))
          {:ok, structs}
          _, %{schema: schema, source: %Type.Interface{reference: %{identifier: ident}}} ->
            {:ok, Absinthe.Schema.implementors(schema, ident)}
          _, _ ->
            {:ok, nil}
        end
      ],
      enum_values: [
        type: list_of(:__enumvalue),
        args: [
          include_deprecated: [
            type: :boolean,
            default_value: false
          ]
        ],
        resolve: fn
          %{include_deprecated: show_deprecated}, %{source: %Type.Enum{values: values}} ->
            values
          |> Enum.flat_map(fn
            {_, %{deprecation: is_deprecated} = value} ->
            if !is_deprecated || (is_deprecated && show_deprecated) do
              [value]
            else
              []
            end
          end)
          |> Flag.as(:ok)
          _, _ ->
            {:ok, nil}
        end
      ],
      input_fields: [
        type: list_of(:__inputvalue),
        resolve: fn
          _, %{source: %Type.InputObject{fields: fields}} ->
            structs = fields |> Map.values
          {:ok, structs}
          _, _ ->
            {:ok, nil}
        end
      ],
      of_type: [
        type: :__type,
        resolve: fn
          _, %{schema: schema, source: %{of_type: type}} ->
            Absinthe.Schema.lookup_type(schema, type, unwrap: false)
          |> Flag.as(:ok)
          _, _ ->
            {:ok, nil}
        end
      ]
    ]
  ]

  object :__field, [
    fields: [
      name: [
        type: :string,
        resolve: fn
          _, %{adapter: adapter, source: source} ->
            source.name
            |> adapter.to_external_name(:field)
            |> Flag.as(:ok)
        end
      ],
      description: [type: :string],
      args: [
        type: list_of(:__inputvalue),
        resolve: fn
          _, %{source: source} ->
            {:ok, Map.values(source.args)}
        end
      ],
      type: [
        type: :__type,
        resolve: fn
          _, %{schema: schema, source: source} ->
            case source.type do
              type when is_atom(type) ->
                Absinthe.Schema.lookup_type(schema, source.type)
              type ->
                type
            end
            |> Flag.as(:ok)
        end
      ],
      is_deprecated: [
        type: :boolean,
        resolve: fn
          _, %{source: %{deprecation: nil}} ->
            {:ok, false}
          _, _ ->
            {:ok, true}
        end
      ],
      deprecation_reason: [
        type: :string,
        resolve: fn
          _, %{source: %{deprecation: nil}} ->
            {:ok, nil}
          _, %{source: %{deprecation: dep}} ->
            {:ok, dep.reason}
        end
      ]
    ]
  ]

  object [__inputvalue: "__InputValue"], [
    fields: [
      name: [
        type: :string,
        resolve: fn
          _, %{adapter: adapter, source: source} ->
            source.name
            |> adapter.to_external_name(:field)
            |> Flag.as(:ok)
        end
      ],
      description: [type: :string],
      type: [
        type: :__type,
        resolve: fn
          _, %{schema: schema, source: %{type: ident}} ->
            type = Absinthe.Schema.lookup_type(schema, ident, unwrap: false)
            {:ok, type}
        end
      ],
      default_value: [
        type: :string,
        resolve: fn
          _, %{source: %{default_value: nil}} ->
            {:ok, nil}
          _, %{source: %{default_value: value}} ->
            {:ok, value |> to_string}
          _, %{source: _} ->
            {:ok, nil}
        end
      ]
    ]
  ]

  object [__enumvalue: "__EnumValue"], [
    fields: [
      name: [type: :string],
      description: [type: :string],
      is_deprecated: [
        type: :boolean,
        resolve: fn
          _, %{source: %{deprecation: nil}} ->
            {:ok, false}
          _, _ ->
            {:ok, true}
        end
      ],
      deprecation_reason: [
        type: :string,
        resolve: fn
          _, %{source: %{deprecation: nil}} ->
            {:ok, nil}
          _, %{source: %{deprecation: dep}} ->
            {:ok, dep.reason}
        end
      ]
    ]
  ]


end
