defmodule LoPrice.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :telegram_user_id, :integer
      add :name, :string
      add :city, :string

      timestamps()
    end

    create unique_index(:users, [:telegram_user_id])
  end
end
