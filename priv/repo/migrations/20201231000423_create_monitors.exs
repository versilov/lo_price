defmodule LoPrice.Repo.Migrations.CreateMonitors do
  use Ecto.Migration

  def change do
    create table(:monitors) do
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :product_id, references(:products, on_delete: :nothing), null: false
      add :target_price, :integer, null: false
      add :target_price_message_id, :integer, null: true
      add :price_history, {:array, :integer}, null: false, default: []

      timestamps()
    end

    create index(:monitors, [:user_id])
    create index(:monitors, [:product_id])
  end
end
