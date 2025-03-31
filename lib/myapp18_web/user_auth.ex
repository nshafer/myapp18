defmodule Myapp18Web.UserAuth do
  use Myapp18Web, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Myapp18.Accounts
  alias Myapp18.Accounts.UserToken
  alias Myapp18.Accounts.Scope

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_session_age_in_days 60

  # How old the session token should be before it is refreshed. You can reduce this so that
  # the session token is refreshed more often by an active user, but it will also cause more
  # database writes. This might be desirable if you want to track more precisely the last time
  # a given token was used. You may also increase this to reduce the number of database writes.
  # If you increase it to a value greater than the session token expiry, the session token will
  # never be refreshed, effectively disabling token refreshing.
  @session_refresh_age_in_hours 24

  # The remember-me cookie is a signed Phoenix.Token, and the browser is instructed to
  # only keep it for the duration of the session token, and only send it when the request
  # is made to the same site. Setting `same_site` to `Strict` may cause users to not be
  # remembered when they follow links from other sites or emails.
  @remember_me_cookie "_myapp18_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_session_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.

  In case the user re-authenticates for sudo mode,
  the existing remember_me setting is kept, writing a new remember_me cookie.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      Myapp18Web.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.

  Will refresh the session token if it is older than the configured refresh age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    {token, conn} = ensure_user_token(conn)

    if token do
      {user, user_token} = Accounts.get_user_by_session_token(token) || {nil, nil}

      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_refresh_user_session_token(user_token)
    else
      assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        {nil, conn}
      end
    end
  end

  # Refresh the session token if it is older than the configured refresh age.
  defp maybe_refresh_user_session_token(conn, nil), do: conn

  defp maybe_refresh_user_session_token(conn, user_token) do
    if UserToken.seconds_since_refresh(user_token) > @session_refresh_age_in_hours * 60 * 60 do
      Accounts.refresh_user_session_token(user_token.token)
      maybe_refresh_remember_me_cookie(conn, user_token.token)
    else
      conn
    end
  end

  # Refresh the remember me cookie if it is set and it is the same as the session token.
  # This is to ensure the remember me cookie has the same expiration time as the session token.
  defp maybe_refresh_remember_me_cookie(conn, token) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    if conn.cookies[@remember_me_cookie] == token do
      put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
    else
      conn
    end
  end

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule Myapp18Web.PageLive do
        use Myapp18Web, :live_view

        on_mount {Myapp18Web.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{Myapp18Web.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must re-authenticate to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      if user_token = session["user_token"] do
        {user, _user_token} = Accounts.get_user_by_session_token(user_token) || {nil, nil}
        Scope.for_user(user)
      else
        Scope.for_user(nil)
      end
    end)
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      Myapp18Web.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc "Returns the path to redirect to after log in."
  # the user was already logged in, redirect to settings
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}}) do
    ~p"/users/settings"
  end

  def signed_in_path(_), do: ~p"/"
end
