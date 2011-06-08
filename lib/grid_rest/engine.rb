module GridRest
  class Railtie < Rails::Engine
    #rake_tasks do
    #  load "tasks/tiny_mce.rake"
    #end
    config.grid_rest = GridRest

    initializer "grid_rest.load_config" do
      ActiveSupport.on_load(:application_controller) do
        GridRest.include_in(self)
      end
    end
  end
end
