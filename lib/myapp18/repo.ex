defmodule Myapp18.Repo do
  use Ecto.Repo,
    otp_app: :myapp18,
    adapter: Ecto.Adapters.Postgres
end
