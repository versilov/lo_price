defmodule LoPrice.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :city, :string
    field :name, :string
    field :telegram_user_id, :integer

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_user_id, :name, :city])
    |> validate_required([:telegram_user_id, :name, :city])
    |> unique_constraint(:telegram_user_id)
  end
end
