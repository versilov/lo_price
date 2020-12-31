defmodule LoPrice.User do
  use Ecto.Schema
  import Ecto.{Changeset, Query}

  alias LoPrice.{User, Repo}

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

  def by_telegram_id(telegram_user_id), do:
    User
    |> where(telegram_user_id: ^telegram_user_id)
    |> Repo.one()

  def by_id(user_id), do:
    User
    |> where(id: ^user_id)
    |> Repo.one()
end
