defmodule LoPrice.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :telegram_user_id, :bigint, null: false
      add :name, :string, null: false
      add :city, :string, null: false
      add :extra, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps()
    end

    create unique_index(:users, [:telegram_user_id])
  end
end
