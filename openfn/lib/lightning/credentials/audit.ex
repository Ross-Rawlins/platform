defmodule Lightning.Credentials.Audit do
  @moduledoc """
  Model for storing changes to Credentials
  """
  use Lightning.Auditing.Model,
    repo: Lightning.Repo,
    schema: __MODULE__,
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted"
    ]

  defmodule Metadata do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :before, :map
      field :after, :map
    end

    @doc false
    def changeset(metadata, attrs \\ %{}) do
      metadata
      |> cast(attrs, [:before, :after])
      |> update_change(:before, &encrypt_body/1)
      |> update_change(:after, &encrypt_body/1)
    end

    defp encrypt_body(changes) when is_map(changes) do
      if Map.has_key?(changes, :body) do
        changes
        |> Map.update(:body, nil, fn val ->
          {:ok, val} = Lightning.Encrypted.Map.dump(val)
          val |> Base.encode64()
        end)
      else
        changes
      end
    end
  end

  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials_audit" do
    field :event, :string
    field :row_id, Ecto.UUID
    embeds_one :metadata, Metadata
    belongs_to :actor, User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(%__MODULE__{} = audit, attrs) do
    audit
    |> cast(attrs, [:event, :row_id, :actor_id])
    |> cast_embed(:metadata)
    |> validate_required([:event, :actor_id])
  end
end
