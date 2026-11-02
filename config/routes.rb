Rails.application.routes.draw do
  root "apps#index"
  post "kamal_hooks/post_deploy", to: "kamal_hooks#post_deploy"

  resources :apps, only: %i[index show new create] do
    resources :deploys, only: %i[create show] do
      resource :cancellation, only: :create, controller: "deploy_cancellations"
      resources :lines, only: :index, controller: "deploy_lines"
    end
    resources :rollbacks, only: :create
    resources :lock_releases, only: :create
    resources :stops, only: :create
    resources :starts, only: :create
    resource :ship_preview, only: :show
    resource :ci_check, only: :create
    resources :log_sessions, only: %i[create destroy]
  end
  resource :status_refresh, only: :create
  resources :servers, only: %i[index new create]
  resources :repos, only: :index

  resource :session, only: %i[new create destroy] do
    get  :verify
    post :confirm
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
