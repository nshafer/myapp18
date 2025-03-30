defmodule Myapp18Web.UserSessionHTML do
  use Myapp18Web, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:myapp18, Myapp18.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
