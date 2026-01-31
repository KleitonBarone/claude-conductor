defmodule ClaudeConductorWeb.Router do
  use ClaudeConductorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ClaudeConductorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ClaudeConductorWeb do
    pipe_through :browser

    live "/", ProjectLive.Index, :index
    live "/projects/:id", ProjectLive.Show, :show
  end
end
